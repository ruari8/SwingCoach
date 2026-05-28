//
//  ModelBackedSwingDetector.swift
//  SwingCoach
//
//  Created by Codex on 28/05/2026.
//

import AVFoundation
import CoreGraphics
import ImageIO

actor ModelBackedSwingDetector {
    enum DetectionError: Error {
        case invalidDuration
        case noVideoTrack
        case readerSetupFailed
    }

    private let targetSampleInterval: Double
    private let maxProcessedFrames: Int
    private let motionThreshold: Double
    private let minWindowDuration: Double
    private let maxWindowDuration: Double
    private let acceptanceMinPeakMotion: Double
    private let minBallAnchorY: Double
    private let impactPreRoll: Double
    private let impactPostRoll: Double

    init(
        targetSampleInterval: Double = 0.50,
        maxProcessedFrames: Int = 12_000,
        motionThreshold: Double = 0.55,
        minWindowDuration: Double = 10.0,
        maxWindowDuration: Double = 24.0,
        acceptanceMinPeakMotion: Double = 1.10,
        minBallAnchorY: Double = 0.66,
        impactPreRoll: Double = 13.0,
        impactPostRoll: Double = 4.5
    ) {
        self.targetSampleInterval = targetSampleInterval
        self.maxProcessedFrames = max(12, maxProcessedFrames)
        self.motionThreshold = motionThreshold
        self.minWindowDuration = minWindowDuration
        self.maxWindowDuration = maxWindowDuration
        self.acceptanceMinPeakMotion = acceptanceMinPeakMotion
        self.minBallAnchorY = minBallAnchorY
        self.impactPreRoll = impactPreRoll
        self.impactPostRoll = impactPostRoll
    }

    func detectSwings(in asset: AVAsset) async throws -> [DetectedSwing] {
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw DetectionError.invalidDuration
        }

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw DetectionError.noVideoTrack
        }

        let transform = try await videoTrack.load(.preferredTransform)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let orientation = Self.orientation(for: transform)
        let orientedSize = Self.orientedSize(naturalSize: naturalSize, orientation: orientation)
        let sampleInterval = max(targetSampleInterval, durationSeconds / Double(maxProcessedFrames))
        let detector = try GolfObjectDetector()
        let features = try readObjectFeatures(
            from: asset,
            track: videoTrack,
            orientation: orientation,
            orientedSize: orientedSize,
            sampleInterval: sampleInterval,
            detector: detector
        )

        return detections(from: features, videoDuration: durationSeconds)
    }

    private func readObjectFeatures(
        from asset: AVAsset,
        track: AVAssetTrack,
        orientation: CGImagePropertyOrientation,
        orientedSize: CGSize,
        sampleInterval: Double,
        detector: GolfObjectDetector
    ) throws -> [ObjectFrameFeature] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
        )
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw DetectionError.readerSetupFailed
        }

        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? DetectionError.readerSetupFailed
        }

        var previousGray: [UInt8]?
        var previousClubPoint: CGPoint?
        var lastProcessedTime = -Double.greatestFiniteMagnitude
        var features: [ObjectFrameFeature] = []

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()

            let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            guard time.isFinite, time - lastProcessedTime >= sampleInterval else { continue }
            lastProcessedTime = time

            let gray = Self.downsampledLuma(from: sampleBuffer)
            let visualMotion = Self.visualMotion(current: gray, previous: previousGray)
            previousGray = gray

            let detections = try detector.detect(
                in: sampleBuffer,
                orientation: orientation,
                orientedImageSize: orientedSize
            )
            let feature = ObjectFrameFeature(
                time: time,
                detections: detections,
                visualMotion: visualMotion,
                clubMotion: Self.clubMotion(detections: detections, previousClubPoint: previousClubPoint)
            )
            if let point = feature.bestClubPoint {
                previousClubPoint = point
            }
            features.append(feature)
        }

        if reader.status == .failed {
            throw reader.error ?? DetectionError.readerSetupFailed
        }

        return features
    }

    private func detections(from features: [ObjectFrameFeature], videoDuration: Double) -> [DetectedSwing] {
        let proposals = proposeWindows(from: features)
        var detections: [DetectedSwing] = []

        for proposal in proposals {
            guard let evidence = validate(proposal, features: features) else {
                continue
            }

            var start = proposal.start
            var end = proposal.end
            if let impactTime = evidence.impactTime {
                start = max(0, min(start, impactTime - impactPreRoll))
                end = max(start, min(end, impactTime + impactPostRoll))
            }

            end = min(videoDuration, end)
            guard end > start else { continue }

            if let last = detections.last,
               CMTimeGetSeconds(last.endTime) + 0.8 >= start {
                continue
            }

            detections.append(
                DetectedSwing(
                    startTime: CMTime(seconds: start, preferredTimescale: 600),
                    endTime: CMTime(seconds: end, preferredTimescale: 600),
                    confidence: evidence.confidence
                )
            )
        }

        return detections
            .sorted { CMTimeCompare($0.startTime, $1.startTime) < 0 }
            .prefix(24)
            .map { $0 }
    }

    private func proposeWindows(from features: [ObjectFrameFeature]) -> [ObjectCandidateWindow] {
        guard !features.isEmpty else { return [] }

        let motion = smoothedMotion(features)
        var candidates: [ObjectCandidateWindow] = []
        var activeStart: Int?
        var lastActiveIndex: Int?
        let gapTolerance = 1.8

        for index in features.indices {
            let isActive = motion[index] >= motionThreshold && features[index].clubScore >= 0.35
            if isActive {
                if activeStart == nil {
                    activeStart = index
                }
                lastActiveIndex = index
                continue
            }

            if let startIndex = activeStart, let endIndex = lastActiveIndex {
                if features[index].time - features[endIndex].time <= gapTolerance {
                    continue
                }

                appendCandidate(
                    startIndex: startIndex,
                    endIndex: endIndex,
                    motion: motion,
                    features: features,
                    candidates: &candidates
                )
                activeStart = nil
                lastActiveIndex = nil
            }
        }

        if let startIndex = activeStart, let endIndex = lastActiveIndex {
            appendCandidate(
                startIndex: startIndex,
                endIndex: endIndex,
                motion: motion,
                features: features,
                candidates: &candidates
            )
        }

        return merge(candidates)
            .filter { $0.end - $0.start >= minWindowDuration }
    }

    private func appendCandidate(
        startIndex: Int,
        endIndex: Int,
        motion: [Double],
        features: [ObjectFrameFeature],
        candidates: inout [ObjectCandidateWindow]
    ) {
        let start = max(0, features[startIndex].time - 2.2)
        let end = features[endIndex].time + 2.0
        guard end - start <= maxWindowDuration else { return }

        candidates.append(
            ObjectCandidateWindow(
                start: start,
                end: end,
                peakMotion: motion[startIndex...endIndex].max() ?? 0
            )
        )
    }

    private func validate(_ window: ObjectCandidateWindow, features: [ObjectFrameFeature]) -> ObjectWindowEvidence? {
        let windowDuration = window.end - window.start
        let preStart = max(0, window.start - 4.5)
        let preEnd = window.start + windowDuration * 0.45
        let postStart = window.start + windowDuration * 0.58
        let postEnd = window.end + 2.2
        let anchors = ballAnchors(features: features, start: preStart, end: preEnd)
        guard !anchors.isEmpty else { return nil }

        let anchorEvidence = anchors
            .map { anchor in
                let pre = anchorPresenceRatio(features: features, start: preStart, end: preEnd, anchor: anchor)
                let post = anchorPresenceRatio(features: features, start: postStart, end: postEnd, anchor: anchor)
                let clubhead = clubheadEvidence(features: features, start: max(0, window.start - 2.5), end: window.start + 3.0, anchor: anchor)
                return ObjectAnchorEvidence(anchor: anchor, pre: pre, post: post, clubhead: clubhead)
            }
            .sorted {
                if $0.clubhead.near != $1.clubhead.near {
                    return $0.clubhead.near && !$1.clubhead.near
                }
                if $0.drop != $1.drop {
                    return $0.drop > $1.drop
                }
                return $0.pre > $1.pre
            }

        guard let best = anchorEvidence.first else { return nil }

        let inWindow = features.filter { $0.time >= window.start && $0.time <= window.end }
        let peakMotion = smoothedMotion(inWindow).max() ?? 0
        let ballDisappearance = best.pre >= 0.18 && best.post <= max(0.12, best.pre * 0.45)
        guard ballDisappearance, peakMotion >= acceptanceMinPeakMotion else { return nil }

        let impactAnchor = anchorEvidence
            .sorted {
                if $0.clubhead.nearRatio != $1.clubhead.nearRatio {
                    return $0.clubhead.nearRatio > $1.clubhead.nearRatio
                }
                return $0.clubhead.minDistance < $1.clubhead.minDistance
            }
            .first { evidence in
                let closeEnough = evidence.clubhead.nearRatio >= 0.35 || evidence.clubhead.minDistance <= 0.08
                return closeEnough && estimateDisappearanceTime(features: features, start: window.start, end: postEnd, anchor: evidence.anchor) != nil
            }

        let impactTime = impactAnchor
            .flatMap { estimateDisappearanceTime(features: features, start: window.start, end: postEnd, anchor: $0.anchor) }
            ?? estimateDisappearanceTime(features: features, start: window.start, end: postEnd, anchor: best.anchor)

        let confidence = min(
            0.96,
            0.22
            + min(0.32, peakMotion * 0.22)
            + 0.22
            + 0.28
            + (best.clubhead.near ? 0.08 : 0)
        )

        return ObjectWindowEvidence(confidence: confidence, impactTime: impactTime)
    }

    private func ballAnchors(features: [ObjectFrameFeature], start: Double, end: Double) -> [CGPoint] {
        var points: [(point: CGPoint, confidence: Double)] = []

        for feature in features where feature.time >= start && feature.time <= end {
            for ball in feature.foregroundBalls where ball.confidence >= 0.35 && Double(ball.center.y) >= minBallAnchorY {
                points.append((ball.center, ball.confidence))
            }
        }

        guard !points.isEmpty else { return [] }

        var buckets: [ObjectBallBucket: [(point: CGPoint, confidence: Double)]] = [:]
        for item in points {
            let bucket = ObjectBallBucket(x: Int((item.point.x * 18).rounded()), y: Int((item.point.y * 18).rounded()))
            buckets[bucket, default: []].append(item)
        }

        return buckets
            .sorted { lhs, rhs in lhs.value.count > rhs.value.count }
            .prefix(5)
            .compactMap { _, bucketPoints in
                let totalWeight = bucketPoints.reduce(0) { $0 + $1.confidence }
                guard totalWeight > 0 else { return nil }
                let x = bucketPoints.reduce(0) { $0 + $1.point.x * $1.confidence } / totalWeight
                let y = bucketPoints.reduce(0) { $0 + $1.point.y * $1.confidence } / totalWeight
                return CGPoint(x: x, y: y)
            }
    }

    private func anchorPresenceRatio(features: [ObjectFrameFeature], start: Double, end: Double, anchor: CGPoint) -> Double {
        let window = features.filter { $0.time >= start && $0.time <= end }
        guard !window.isEmpty else { return 0 }

        let present = window.filter { feature in
            feature.foregroundBalls.contains { $0.center.distance(to: anchor) <= 0.055 }
        }.count

        return Double(present) / Double(window.count)
    }

    private func clubheadEvidence(features: [ObjectFrameFeature], start: Double, end: Double, anchor: CGPoint) -> ObjectClubheadEvidence {
        let window = features.filter { $0.time >= start && $0.time <= end }
        guard !window.isEmpty else { return ObjectClubheadEvidence(minDistance: .greatestFiniteMagnitude, nearRatio: 0) }

        var minDistance = Double.greatestFiniteMagnitude
        var nearCount = 0

        for feature in window {
            let clubheads = feature.detections.filter { $0.objectClass == .clubhead && $0.confidence >= 0.30 }
            guard !clubheads.isEmpty else { continue }

            let frameMin = clubheads.map { $0.center.distance(to: anchor) }.min() ?? .greatestFiniteMagnitude
            minDistance = min(minDistance, frameMin)
            if frameMin <= 0.18 {
                nearCount += 1
            }
        }

        return ObjectClubheadEvidence(
            minDistance: minDistance,
            nearRatio: Double(nearCount) / Double(window.count)
        )
    }

    private func estimateDisappearanceTime(features: [ObjectFrameFeature], start: Double, end: Double, anchor: CGPoint) -> Double? {
        let timeline = features
            .filter { $0.time >= start && $0.time <= end }
            .map { feature in
                (
                    time: feature.time,
                    present: feature.foregroundBalls.contains { $0.center.distance(to: anchor) <= 0.055 }
                )
            }

        guard timeline.count >= 4 else { return nil }

        for index in timeline.indices where !timeline[index].present {
            let previous = timeline[max(0, index - 6)..<index]
            let following = timeline[index..<min(timeline.count, index + 4)]
            let previousPresent = previous.filter { $0.present }.count
            let followingAbsent = following.filter { !$0.present }.count

            if previousPresent >= 2, followingAbsent >= 2 {
                return timeline[index].time
            }
        }

        return nil
    }

    private func smoothedMotion(_ features: [ObjectFrameFeature]) -> [Double] {
        let raw = features.map { feature in
            (feature.visualMotion * 8.0)
            + (feature.clubMotion * 5.5)
            + (feature.clubScore >= 0.60 ? 0.35 : 0.0)
        }

        return raw.indices.map { index in
            let lower = max(0, index - 2)
            let upper = min(raw.count, index + 3)
            return raw[lower..<upper].reduce(0, +) / Double(max(1, upper - lower))
        }
    }

    private func merge(_ windows: [ObjectCandidateWindow]) -> [ObjectCandidateWindow] {
        var merged: [ObjectCandidateWindow] = []

        for window in windows.sorted(by: { $0.start < $1.start }) {
            guard let last = merged.last else {
                merged.append(window)
                continue
            }

            if window.start > last.end + 2.4 {
                merged.append(window)
            } else {
                merged[merged.count - 1] = ObjectCandidateWindow(
                    start: last.start,
                    end: max(last.end, window.end),
                    peakMotion: max(last.peakMotion, window.peakMotion)
                )
            }
        }

        return merged
    }

    private static func clubMotion(detections: [GolfObjectDetection], previousClubPoint: CGPoint?) -> Double {
        guard let previousClubPoint else { return 0 }
        let clubBoxes = detections
            .filter { $0.objectClass == .clubhead || $0.objectClass == .clubShaft }
            .sorted { $0.confidence > $1.confidence }
        guard let best = clubBoxes.first else { return 0 }
        return best.center.distance(to: previousClubPoint)
    }

    private static func downsampledLuma(from sampleBuffer: CMSampleBuffer) -> [UInt8]? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }

        let sourceWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let sourceHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
        let width = 80
        let height = 120

        return (0..<(width * height)).map { index in
            let x = index % width
            let y = index / width
            let sourceX = min(sourceWidth - 1, x * sourceWidth / width)
            let sourceY = min(sourceHeight - 1, y * sourceHeight / height)
            return pixels[sourceY * bytesPerRow + sourceX]
        }
    }

    private static func visualMotion(current: [UInt8]?, previous: [UInt8]?) -> Double {
        guard let current, let previous, current.count == previous.count else { return 0 }

        let total = zip(current, previous).reduce(0) { partial, pair in
            partial + abs(Int(pair.0) - Int(pair.1))
        }

        return Double(total) / Double(current.count) / 255.0
    }

    private static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let epsilon = 0.001

        func equals(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
            abs(lhs - rhs) < epsilon
        }

        if equals(transform.a, 0), equals(transform.b, 1), equals(transform.c, -1), equals(transform.d, 0) {
            return .right
        }

        if equals(transform.a, 0), equals(transform.b, -1), equals(transform.c, 1), equals(transform.d, 0) {
            return .left
        }

        if equals(transform.a, -1), equals(transform.d, -1) {
            return .down
        }

        return .up
    }

    private static func orientedSize(naturalSize: CGSize, orientation: CGImagePropertyOrientation) -> CGSize {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: naturalSize.height, height: naturalSize.width)
        default:
            return naturalSize
        }
    }
}

private struct ObjectFrameFeature {
    let time: Double
    let detections: [GolfObjectDetection]
    let visualMotion: Double
    let clubMotion: Double

    var clubBoxes: [GolfObjectDetection] {
        detections.filter { $0.objectClass == .clubhead || $0.objectClass == .clubShaft }
    }

    var foregroundBalls: [GolfObjectDetection] {
        detections.filter {
            $0.objectClass == .golfBallCandidate
            && $0.confidence >= 0.35
            && $0.center.y >= 0.50
        }
    }

    var clubScore: Double {
        clubBoxes.map(\.confidence).max() ?? 0
    }

    var bestClubPoint: CGPoint? {
        clubBoxes.max { $0.confidence < $1.confidence }?.center
    }
}

private struct ObjectCandidateWindow {
    let start: Double
    let end: Double
    let peakMotion: Double
}

private struct ObjectWindowEvidence {
    let confidence: Double
    let impactTime: Double?
}

private struct ObjectAnchorEvidence {
    let anchor: CGPoint
    let pre: Double
    let post: Double
    let clubhead: ObjectClubheadEvidence

    var drop: Double {
        pre - post
    }
}

private struct ObjectClubheadEvidence {
    let minDistance: Double
    let nearRatio: Double

    var near: Bool {
        minDistance <= 0.18 || nearRatio >= 0.08
    }
}

private struct ObjectBallBucket: Hashable {
    let x: Int
    let y: Int
}

private extension CGPoint {
    func distance(to other: CGPoint) -> Double {
        let dx = Double(x - other.x)
        let dy = Double(y - other.y)
        return sqrt(dx * dx + dy * dy)
    }
}
