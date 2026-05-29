//
//  ModelBackedSwingDetector.swift
//  SwingCoach
//
//  Created by Codex on 28/05/2026.
//

import AVFoundation
import CoreGraphics
import CoreML
import ImageIO
import Vision

nonisolated struct ObjectSwingDetectorConfiguration: Equatable {
    var name: String
    var targetSampleInterval: Double
    var maxProcessedFrames: Int
    var motionThreshold: Double
    var acceptanceMinPeakMotion: Double
    var acceptanceMinStrongMotionFrames: Int
    var acceptanceMinMeanClubMotion: Double
    var acceptanceMinClubPathSpan: Double
    var acceptanceMaxClubTopY: Double
    var minBallAnchorY: Double
    var featureRetentionLimit: Int
    var timelineScale: Double
    var minWindowDuration: Double
    var maxWindowDuration: Double
    var impactPreRoll: Double
    var impactPostRoll: Double
    var impactConfirmationPostRoll: Double
    var candidatePreRoll: Double
    var candidatePostRoll: Double
    var proposalGapTolerance: Double
    var mergeMaxGap: Double
    var validationPreRoll: Double
    var validationPostRoll: Double
    var addressPreRoll: Double
    var addressPostOffset: Double

    var targetSampleFPS: Double {
        guard targetSampleInterval > 0 else { return 0 }
        return 1 / targetSampleInterval
    }

    static func liveObjectModel(
        sampleFPS: Double = 16.0,
        timelineScale: Double = 8.0,
        impactConfirmationPostRoll: Double = 0.20
    ) -> ObjectSwingDetectorConfiguration {
        let clampedSampleFPS = min(24.0, max(1.0, sampleFPS))
        let clampedTimelineScale = min(12.0, max(1.0, timelineScale))
        let clampedImpactConfirmationPostRoll = min(0.80, max(0.18, impactConfirmationPostRoll))
        let scale = { (seconds: Double) in seconds / clampedTimelineScale }
        return ObjectSwingDetectorConfiguration(
            name: "YOLO \(Self.formatFPS(clampedSampleFPS))fps / \(Self.formatScale(clampedTimelineScale))x",
            targetSampleInterval: 1 / clampedSampleFPS,
            maxProcessedFrames: 18_000,
            motionThreshold: 0.55,
            acceptanceMinPeakMotion: 1.10,
            acceptanceMinStrongMotionFrames: 2,
            acceptanceMinMeanClubMotion: 0.05,
            acceptanceMinClubPathSpan: 0.32,
            acceptanceMaxClubTopY: 0.58,
            minBallAnchorY: 0.66,
            featureRetentionLimit: 2_400,
            timelineScale: clampedTimelineScale,
            minWindowDuration: scale(10.0),
            maxWindowDuration: scale(24.0),
            impactPreRoll: scale(13.0),
            impactPostRoll: scale(4.5),
            impactConfirmationPostRoll: clampedImpactConfirmationPostRoll,
            candidatePreRoll: scale(2.2),
            candidatePostRoll: scale(2.0),
            proposalGapTolerance: scale(1.8),
            mergeMaxGap: scale(2.4),
            validationPreRoll: scale(4.5),
            validationPostRoll: scale(2.2),
            addressPreRoll: scale(2.5),
            addressPostOffset: scale(3.0)
        )
    }

    static func sourceTimelineObjectModel(sampleFPS: Double = 2.0) -> ObjectSwingDetectorConfiguration {
        liveObjectModel(sampleFPS: sampleFPS, timelineScale: 1.0)
    }

    private static func formatFPS(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func formatScale(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

nonisolated struct ObjectSwingWindowDiagnostics: Encodable, Equatable {
    let start: Double
    let end: Double
    let peakMotion: Double
    let strongMotionFrameCount: Int
    let meanClubMotion: Double
    let clubPathSpan: Double
    let clubTopY: Double
    let clubFrameRatio: Double
    let ballFrameRatio: Double
}

nonisolated struct ObjectSwingFeatureSummary: Encodable, Equatable {
    let frameCount: Int
    let clubFrameCount: Int
    let ballFrameCount: Int
    let maxClubScore: Double
    let maxBallScore: Double
    let maxMotion: Double
    let maxClubMotion: Double
}

nonisolated struct ObjectSwingImpactDebugReport: Encodable, Equatable {
    let anchorX: Double?
    let anchorY: Double?
    let result: String
    let disappearanceTime: Double?
    let preFeatureCount: Int
    let postFeatureCount: Int
    let prePresence: Double?
    let postPresence: Double?
    let clubMinDistance: Double?
    let clubNearRatio: Double?
    let localPeakMotion: Double?
    let localMeanClubMotion: Double?
    let windowPeakMotion: Double?
    let windowMeanClubMotion: Double?
    let clubPathSpan: Double?
}

nonisolated struct ObjectSwingImpactCandidate: Encodable, Equatable {
    let start: Double
    let end: Double
    let impactTime: Double
    let declaredAt: Double
    let confidence: Double
    let diagnostics: ObjectSwingWindowDiagnostics
}

nonisolated struct ObjectSwingPoseFeature: Equatable {
    let time: Double
    let relativeHands: CGPoint
    let bodyCenter: CGPoint
    let bodyHeight: Double
    let validJointCount: Int
}

nonisolated struct ObjectSwingPoseWindowMetrics: Equatable {
    let attemptedCount: Int
    let validCount: Int
    let coverage: Double
    let handTravel: Double
    let peakHandSpeed: Double
    let addressToFinishDistance: Double
    let bodyDrift: Double
}

nonisolated enum ObjectSwingImpactSelector {
    static func poseGatedImpactCandidates(
        _ detections: [ObjectSwingImpactCandidate],
        attemptTimes: [Double],
        poseFeatures: [ObjectSwingPoseFeature]
    ) -> [ObjectSwingImpactCandidate] {
        detections.filter { detection in
            passesPoseGate(
                detection: detection,
                attemptTimes: attemptTimes,
                poseFeatures: poseFeatures
            )
        }
    }

    static func hybridImpactCandidates(
        _ detections: [ObjectSwingImpactCandidate],
        attemptTimes: [Double],
        poseFeatures: [ObjectSwingPoseFeature]
    ) -> [ObjectSwingImpactCandidate] {
        var accepted: [(candidate: ObjectSwingImpactCandidate, reason: String)] = []
        var lastCoreImpactTime: Double?

        for detection in detections {
            guard detection.impactTime >= 1.15 else { continue }

            if passesPoseGate(
                detection: detection,
                attemptTimes: attemptTimes,
                poseFeatures: poseFeatures
            ) {
                accepted.append((detection, "pose"))
                lastCoreImpactTime = detection.impactTime
            } else if passesLowPoseCadenceFallback(
                detection: detection,
                lastCoreImpactTime: lastCoreImpactTime,
                attemptTimes: attemptTimes,
                poseFeatures: poseFeatures
            ) {
                accepted.append((detection, "lowPoseCadence"))
                lastCoreImpactTime = detection.impactTime
            }
        }

        var keep = Array(repeating: true, count: accepted.count)
        for index in accepted.indices {
            let detection = accepted[index]
            for nextIndex in accepted.indices.dropFirst(index + 1) {
                let nextDetection = accepted[nextIndex]
                let impactGap = nextDetection.candidate.impactTime - detection.candidate.impactTime
                if impactGap > 8.0 {
                    break
                }
                let laterIsCleanerPoseSwing = detection.reason == "pose"
                    && nextDetection.reason == "pose"
                    && poseQuality(
                        detection: nextDetection.candidate,
                        attemptTimes: attemptTimes,
                        poseFeatures: poseFeatures
                    ) - poseQuality(
                        detection: detection.candidate,
                        attemptTimes: attemptTimes,
                        poseFeatures: poseFeatures
                    ) >= 0.45
                if laterIsCleanerPoseSwing {
                    keep[index] = false
                    break
                }
            }
        }

        return accepted.enumerated().compactMap { index, item in
            keep[index] ? item.candidate : nil
        }
    }

    static func poseFeature(
        from sampleBuffer: CMSampleBuffer,
        at time: Double,
        orientation: CGImagePropertyOrientation,
        request: VNDetectHumanBodyPoseRequest
    ) -> ObjectSwingPoseFeature? {
        let handler = VNImageRequestHandler(
            cmSampleBuffer: sampleBuffer,
            orientation: orientation,
            options: [:]
        )

        do {
            try handler.perform([request])
            let features = try (request.results ?? []).compactMap { observation in
                try poseFeature(from: observation, at: time)
            }
            return features.max { lhs, rhs in
                poseScore(lhs) < poseScore(rhs)
            }
        } catch {
            return nil
        }
    }

    static func poseFeature(
        from observation: VNHumanBodyPoseObservation,
        at time: Double
    ) throws -> ObjectSwingPoseFeature? {
        let points = try observation.recognizedPoints(.all)

        func point(_ joint: VNHumanBodyPoseObservation.JointName, minimumConfidence: Float = 0.25) -> CGPoint? {
            guard let recognizedPoint = points[joint],
                  recognizedPoint.confidence >= minimumConfidence else {
                return nil
            }
            return recognizedPoint.location
        }

        let confidentPoints = points.values
            .filter { $0.confidence >= 0.25 }
            .map(\.location)
        guard confidentPoints.count >= 6 else { return nil }

        let bodyBounds = imageBounds(for: confidentPoints)
        let bodyHeight = Double(bodyBounds.height)
        guard bodyHeight >= 0.16 else { return nil }

        let wrists = [point(.leftWrist), point(.rightWrist)].compactMap { $0 }
        guard let hands = averagePoint(wrists) else { return nil }

        let shoulders = [point(.leftShoulder), point(.rightShoulder)].compactMap { $0 }
        let hips = [point(.leftHip), point(.rightHip)].compactMap { $0 }
        let center: CGPoint
        if let shoulderCenter = averagePoint(shoulders), let hipCenter = averagePoint(hips) {
            center = CGPoint(
                x: (shoulderCenter.x + hipCenter.x) / 2,
                y: (shoulderCenter.y + hipCenter.y) / 2
            )
        } else {
            center = CGPoint(x: bodyBounds.midX, y: bodyBounds.midY)
        }

        return ObjectSwingPoseFeature(
            time: time,
            relativeHands: CGPoint(
                x: Double(hands.x - center.x) / bodyHeight,
                y: Double(hands.y - center.y) / bodyHeight
            ),
            bodyCenter: center,
            bodyHeight: bodyHeight,
            validJointCount: confidentPoints.count
        )
    }

    private static func passesPoseGate(
        detection: ObjectSwingImpactCandidate,
        attemptTimes: [Double],
        poseFeatures: [ObjectSwingPoseFeature]
    ) -> Bool {
        guard let metrics = poseWindowMetrics(
            detection: detection,
            attemptTimes: attemptTimes,
            poseFeatures: poseFeatures
        ) else {
            return false
        }

        guard metrics.validCount >= 3, metrics.coverage >= 0.40 else { return false }
        guard metrics.bodyDrift <= 0.18 else { return false }

        let sustainedHandMotion = metrics.handTravel >= 0.22 && metrics.peakHandSpeed >= 0.70
        let addressToFinishChange = metrics.addressToFinishDistance >= 0.38 && metrics.peakHandSpeed >= 0.50
        let largeSwingShape = metrics.handTravel >= 0.65 && metrics.addressToFinishDistance >= 0.45
        return sustainedHandMotion || addressToFinishChange || largeSwingShape
    }

    private static func passesLowPoseCadenceFallback(
        detection: ObjectSwingImpactCandidate,
        lastCoreImpactTime: Double?,
        attemptTimes: [Double],
        poseFeatures: [ObjectSwingPoseFeature]
    ) -> Bool {
        guard let lastCoreImpactTime,
              detection.impactTime - lastCoreImpactTime >= 14.0,
              let metrics = poseWindowMetrics(
                detection: detection,
                attemptTimes: attemptTimes,
                poseFeatures: poseFeatures
              )
        else {
            return false
        }

        let diagnostics = detection.diagnostics
        return metrics.coverage >= 0.80
            && metrics.validCount >= 8
            && metrics.handTravel <= 0.08
            && metrics.peakHandSpeed <= 0.15
            && metrics.bodyDrift <= 0.03
            && diagnostics.peakMotion >= 1.0
            && diagnostics.strongMotionFrameCount >= 3
            && diagnostics.meanClubMotion >= 0.045
            && diagnostics.clubFrameRatio >= 0.90
    }

    private static func poseQuality(
        detection: ObjectSwingImpactCandidate,
        attemptTimes: [Double],
        poseFeatures: [ObjectSwingPoseFeature]
    ) -> Double {
        guard let metrics = poseWindowMetrics(
            detection: detection,
            attemptTimes: attemptTimes,
            poseFeatures: poseFeatures
        ) else {
            return 0
        }

        return metrics.handTravel + metrics.addressToFinishDistance + metrics.peakHandSpeed * 0.10
    }

    private static func poseWindowMetrics(
        detection: ObjectSwingImpactCandidate,
        attemptTimes: [Double],
        poseFeatures: [ObjectSwingPoseFeature]
    ) -> ObjectSwingPoseWindowMetrics? {
        let attemptedCount = attemptTimes.filter { $0 >= detection.start && $0 <= detection.end }.count
        guard attemptedCount > 0 else { return nil }

        let windowFeatures = poseFeatures.filter { $0.time >= detection.start && $0.time <= detection.end }
        guard !windowFeatures.isEmpty else { return nil }

        let handBounds = pointBounds(windowFeatures.map(\.relativeHands))
        let bodyBounds = pointBounds(windowFeatures.map(\.bodyCenter))
        return ObjectSwingPoseWindowMetrics(
            attemptedCount: attemptedCount,
            validCount: windowFeatures.count,
            coverage: Double(windowFeatures.count) / Double(attemptedCount),
            handTravel: handBounds.diagonal,
            peakHandSpeed: peakHandSpeed(windowFeatures),
            addressToFinishDistance: addressToFinishHandDistance(windowFeatures),
            bodyDrift: bodyBounds.diagonal
        )
    }

    private static func poseScore(_ feature: ObjectSwingPoseFeature) -> Double {
        Double(feature.validJointCount) * 0.08 + feature.bodyHeight * 2.8
    }

    private static func peakHandSpeed(_ features: [ObjectSwingPoseFeature]) -> Double {
        guard features.count >= 2 else { return 0 }

        var peak = 0.0
        for index in 1..<features.count {
            let dt = features[index].time - features[index - 1].time
            guard dt > 0, dt <= 0.6 else { continue }
            peak = max(peak, distance(features[index].relativeHands, features[index - 1].relativeHands) / dt)
        }
        return peak
    }

    private static func addressToFinishHandDistance(_ features: [ObjectSwingPoseFeature]) -> Double {
        guard features.count >= 2 else { return 0 }

        let sampleCount = max(1, min(3, features.count / 3))
        guard let addressPoint = averagePoint(Array(features.prefix(sampleCount)).map(\.relativeHands)),
              let finishPoint = averagePoint(Array(features.suffix(sampleCount)).map(\.relativeHands))
        else {
            return 0
        }

        return distance(addressPoint, finishPoint)
    }

    private static func pointBounds(_ points: [CGPoint]) -> (width: Double, height: Double, diagonal: Double) {
        guard !points.isEmpty else { return (0, 0, 0) }

        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let width = Double((xs.max() ?? 0) - (xs.min() ?? 0))
        let height = Double((ys.max() ?? 0) - (ys.min() ?? 0))
        return (width, height, sqrt(width * width + height * height))
    }

    private static func imageBounds(for points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        return CGRect(
            x: minX,
            y: minY,
            width: max(0.001, maxX - minX),
            height: max(0.001, maxY - minY)
        )
    }

    private static func averagePoint(_ points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }

        let sum = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }

        return CGPoint(
            x: sum.x / CGFloat(points.count),
            y: sum.y / CGFloat(points.count)
        )
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        let dx = Double(lhs.x - rhs.x)
        let dy = Double(lhs.y - rhs.y)
        return sqrt(dx * dx + dy * dy)
    }
}

actor ModelBackedSwingDetector {
    enum DetectionError: Error {
        case invalidDuration
        case noVideoTrack
        case readerSetupFailed
        case modelUnavailable
    }

    private let configuration: ObjectSwingDetectorConfiguration

    init(
        targetSampleInterval: Double = 0.50,
        maxProcessedFrames: Int = 12_000,
        motionThreshold: Double = 0.55,
        minWindowDuration: Double = 10.0,
        maxWindowDuration: Double = 24.0,
        acceptanceMinPeakMotion: Double = 1.10,
        minBallAnchorY: Double = 0.66,
        impactPreRoll: Double = 13.0,
        impactPostRoll: Double = 4.5,
        impactConfirmationPostRoll: Double = 0.20
    ) {
        self.configuration = ObjectSwingDetectorConfiguration(
            name: "YOLO source timeline",
            targetSampleInterval: targetSampleInterval,
            maxProcessedFrames: max(12, maxProcessedFrames),
            motionThreshold: motionThreshold,
            acceptanceMinPeakMotion: acceptanceMinPeakMotion,
            acceptanceMinStrongMotionFrames: 2,
            acceptanceMinMeanClubMotion: 0.05,
            acceptanceMinClubPathSpan: 0.32,
            acceptanceMaxClubTopY: 0.58,
            minBallAnchorY: minBallAnchorY,
            featureRetentionLimit: 12_000,
            timelineScale: 1.0,
            minWindowDuration: minWindowDuration,
            maxWindowDuration: maxWindowDuration,
            impactPreRoll: impactPreRoll,
            impactPostRoll: impactPostRoll,
            impactConfirmationPostRoll: impactConfirmationPostRoll,
            candidatePreRoll: 2.2,
            candidatePostRoll: 2.0,
            proposalGapTolerance: 1.8,
            mergeMaxGap: 2.4,
            validationPreRoll: 4.5,
            validationPostRoll: 2.2,
            addressPreRoll: 2.5,
            addressPostOffset: 3.0
        )
    }

    init(configuration: ObjectSwingDetectorConfiguration) {
        self.configuration = configuration
    }

    func detectImpactSwings(in asset: AVAsset, usesHybridGate: Bool) async throws -> [DetectedSwing] {
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
        let sampleInterval = max(configuration.targetSampleInterval, durationSeconds / Double(configuration.maxProcessedFrames))
        let poseSampleInterval = max(0.12, sampleInterval * 2.0)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
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

        let detector = LiveModelSwingDetector(configuration: configuration)
        detector.reset(enabled: true, configuration: configuration)
        guard detector.currentSnapshot().status != .unavailable else {
            throw DetectionError.modelUnavailable
        }
        let poseRequest = VNDetectHumanBodyPoseRequest()
        var poseAttemptTimes: [Double] = []
        var poseFeatures: [ObjectSwingPoseFeature] = []
        var lastSubmittedTime = -Double.greatestFiniteMagnitude
        var lastPoseTime = -Double.greatestFiniteMagnitude
        var lastDetectorTime = 0.0

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()

            let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            guard time.isFinite, time - lastSubmittedTime >= sampleInterval else { continue }

            lastSubmittedTime = time
            lastDetectorTime = time
            _ = detector.process(
                sampleBuffer: sampleBuffer,
                recordingTime: time,
                orientation: orientation,
                orientedImageSize: orientedSize
            )

            if time - lastPoseTime >= poseSampleInterval {
                lastPoseTime = time
                poseAttemptTimes.append(time)
                if let poseFeature = ObjectSwingImpactSelector.poseFeature(
                    from: sampleBuffer,
                    at: time,
                    orientation: orientation,
                    request: poseRequest
                ) {
                    poseFeatures.append(poseFeature)
                }
            }
        }

        if reader.status == .failed {
            throw reader.error ?? DetectionError.readerSetupFailed
        }

        let candidates = detector.currentImpactCenteredDetections(
            videoDuration: durationSeconds,
            declaredAt: lastDetectorTime
        )
        let selected = usesHybridGate
            ? ObjectSwingImpactSelector.hybridImpactCandidates(
                candidates,
                attemptTimes: poseAttemptTimes,
                poseFeatures: poseFeatures
            )
            : candidates

        return selected
            .prefix(32)
            .map { candidate in
                DetectedSwing(
                    startTime: CMTime(seconds: candidate.start, preferredTimescale: 600),
                    endTime: CMTime(seconds: candidate.end, preferredTimescale: 600),
                    confidence: candidate.confidence,
                    impactTime: candidate.impactTime,
                    declaredAt: candidate.declaredAt
                )
            }
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
        let sampleInterval = max(configuration.targetSampleInterval, durationSeconds / Double(configuration.maxProcessedFrames))
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
                start = max(0, min(start, impactTime - configuration.impactPreRoll))
                end = max(start, min(end, impactTime + configuration.impactPostRoll))
            }

            end = min(videoDuration, end)
            guard end > start else { continue }
            guard finalWindowMeetsAcceptance(start: start, end: end, features: features) else { continue }

            if let last = detections.last,
               CMTimeGetSeconds(last.endTime) + 0.8 >= start {
                continue
            }

            detections.append(
                DetectedSwing(
                    startTime: CMTime(seconds: start, preferredTimescale: 600),
                    endTime: CMTime(seconds: end, preferredTimescale: 600),
                    confidence: evidence.confidence,
                    impactTime: evidence.impactTime,
                    declaredAt: features.last?.time
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
        let gapTolerance = configuration.proposalGapTolerance

        for index in features.indices {
            let isActive = motion[index] >= configuration.motionThreshold && features[index].clubScore >= 0.35
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
            .filter { $0.end - $0.start >= configuration.minWindowDuration }
    }

    private func appendCandidate(
        startIndex: Int,
        endIndex: Int,
        motion: [Double],
        features: [ObjectFrameFeature],
        candidates: inout [ObjectCandidateWindow]
    ) {
        let start = max(0, features[startIndex].time - configuration.candidatePreRoll)
        let end = features[endIndex].time + configuration.candidatePostRoll
        guard end - start <= configuration.maxWindowDuration else { return }

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
        let preStart = max(0, window.start - configuration.validationPreRoll)
        let preEnd = window.start + windowDuration * 0.45
        let postStart = window.start + windowDuration * 0.58
        let postEnd = window.end + configuration.validationPostRoll
        let anchors = ballAnchors(features: features, start: preStart, end: preEnd)
        guard !anchors.isEmpty else { return nil }

        let anchorEvidence = anchors
            .map { anchor in
                let pre = anchorPresenceRatio(features: features, start: preStart, end: preEnd, anchor: anchor)
                let post = anchorPresenceRatio(features: features, start: postStart, end: postEnd, anchor: anchor)
                let clubhead = clubheadEvidence(
                    features: features,
                    start: max(0, window.start - configuration.addressPreRoll),
                    end: window.start + configuration.addressPostOffset,
                    anchor: anchor
                )
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
        let motionSeries = smoothedMotion(inWindow)
        let peakMotion = motionSeries.max() ?? 0
        let strongMotionFrameCount = motionSeries.filter { $0 >= configuration.acceptanceMinPeakMotion }.count
        let meanClubMotion = inWindow.isEmpty
            ? 0
            : inWindow.reduce(0.0) { $0 + $1.clubMotion } / Double(inWindow.count)
        let clubPathSpan = objectClubPathSpan(inWindow)
        let clubTopY = objectClubTopY(inWindow)
        let ballDisappearance = best.pre >= 0.18 && best.post <= max(0.12, best.pre * 0.45)
        guard ballDisappearance,
              peakMotion >= configuration.acceptanceMinPeakMotion,
              strongMotionFrameCount >= configuration.acceptanceMinStrongMotionFrames,
              meanClubMotion >= configuration.acceptanceMinMeanClubMotion,
              clubPathSpan >= configuration.acceptanceMinClubPathSpan,
              clubTopY <= configuration.acceptanceMaxClubTopY
        else { return nil }

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

    private func finalWindowMeetsAcceptance(start: Double, end: Double, features: [ObjectFrameFeature]) -> Bool {
        let inWindow = features.filter { $0.time >= start && $0.time <= end }
        guard !inWindow.isEmpty else { return false }

        let motionSeries = smoothedMotion(inWindow)
        let peakMotion = motionSeries.max() ?? 0
        let strongMotionFrameCount = motionSeries.filter { $0 >= configuration.acceptanceMinPeakMotion }.count
        let meanClubMotion = inWindow.reduce(0.0) { $0 + $1.clubMotion } / Double(inWindow.count)
        return peakMotion >= configuration.acceptanceMinPeakMotion
            && strongMotionFrameCount >= configuration.acceptanceMinStrongMotionFrames
            && meanClubMotion >= configuration.acceptanceMinMeanClubMotion
            && objectClubPathSpan(inWindow) >= configuration.acceptanceMinClubPathSpan
            && objectClubTopY(inWindow) <= configuration.acceptanceMaxClubTopY
    }

    private func ballAnchors(features: [ObjectFrameFeature], start: Double, end: Double) -> [CGPoint] {
        var points: [(point: CGPoint, confidence: Double)] = []

        for feature in features where feature.time >= start && feature.time <= end {
            for ball in feature.foregroundBalls where ball.confidence >= 0.35 && Double(ball.center.y) >= configuration.minBallAnchorY {
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

            if window.start > last.end + configuration.mergeMaxGap {
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

nonisolated final class LiveModelSwingDetector {
    private var configuration: ObjectSwingDetectorConfiguration
    private let modelURL: URL?
    private let computeUnits: MLComputeUnits
    private var detector: GolfObjectDetector?
    private var previousGray: [UInt8]?
    private var previousClubPoint: CGPoint?
    private var features: [ObjectFrameFeature] = []
    private var detections: [DetectedSwing] = []
    private var impactCandidates: [ObjectSwingImpactCandidate] = []
    private var detectionDiagnostics: [ObjectSwingWindowDiagnostics] = []
    private var lastProcessedTime = -Double.greatestFiniteMagnitude
    private var lastImpactCandidateRefreshTime = -Double.greatestFiniteMagnitude
    private var lastSnapshot = LiveSwingDetectionSnapshot.idle
    private var modelLoadError: Error?
    private var processedFrameCount = 0
    private var skippedFrameCount = 0
    private var totalProcessingTimeMS = 0.0
    private var lastProcessingTimeMS = 0.0

    init(
        configuration: ObjectSwingDetectorConfiguration = .liveObjectModel(),
        modelURL: URL? = nil,
        computeUnits: MLComputeUnits = .all
    ) {
        self.configuration = configuration
        self.modelURL = modelURL
        self.computeUnits = computeUnits
    }

    var targetSampleInterval: Double {
        configuration.targetSampleInterval
    }

    func reset(enabled: Bool, configuration: ObjectSwingDetectorConfiguration? = nil) {
        if let configuration {
            self.configuration = configuration
        }
        previousGray = nil
        previousClubPoint = nil
        features = []
        detections = []
        impactCandidates = []
        detectionDiagnostics = []
        lastProcessedTime = -Double.greatestFiniteMagnitude
        lastImpactCandidateRefreshTime = -Double.greatestFiniteMagnitude
        modelLoadError = nil
        processedFrameCount = 0
        skippedFrameCount = 0
        totalProcessingTimeMS = 0
        lastProcessingTimeMS = 0

        guard enabled else {
            detector = nil
            lastSnapshot = LiveSwingDetectionSnapshot(
                status: .disabled,
                primaryMessage: "Auto detect off",
                detailMessage: "Recording normally; trim manually after stop.",
                detectorConfigurationName: self.configuration.name
            )
            return
        }

        do {
            detector = try GolfObjectDetector(modelURL: modelURL, computeUnits: computeUnits)
            lastSnapshot = LiveSwingDetectionSnapshot(
                status: .searchingBall,
                primaryMessage: "Model detector ready",
                detailMessage: "Scanning sampled frames while recording.",
                targetSampleFPS: self.configuration.targetSampleFPS,
                detectorConfigurationName: self.configuration.name
            )
        } catch {
            detector = nil
            modelLoadError = error
            lastSnapshot = LiveSwingDetectionSnapshot(
                status: .unavailable,
                primaryMessage: "Model detector unavailable",
                detailMessage: "The YOLO Core ML model could not be loaded.",
                detectorConfigurationName: self.configuration.name
            )
        }
    }

    func process(
        sampleBuffer: CMSampleBuffer,
        recordingTime: Double,
        orientation: CGImagePropertyOrientation,
        orientedImageSize: CGSize
    ) -> LiveSwingDetectionSnapshot {
        guard recordingTime.isFinite,
              recordingTime - lastProcessedTime + 0.001 >= configuration.targetSampleInterval
        else {
            skippedFrameCount += 1
            return lastSnapshot
        }
        lastProcessedTime = recordingTime

        guard let detector else {
            lastSnapshot = LiveSwingDetectionSnapshot(
                status: .unavailable,
                primaryMessage: "Model detector unavailable",
                detailMessage: modelLoadError == nil ? "Model detector has not been started." : "The YOLO Core ML model could not be loaded.",
                detectedSwingCount: detections.count,
                processedFrameCount: processedFrameCount,
                skippedFrameCount: skippedFrameCount,
                targetSampleFPS: configuration.targetSampleFPS,
                effectiveSampleFPS: effectiveSampleFPS,
                averageProcessingTimeMS: averageProcessingTimeMS,
                lastProcessingTimeMS: lastProcessingTimeMS,
                detectorConfigurationName: configuration.name
            )
            return lastSnapshot
        }

        let processingStartedAt = Date()
        do {
            let gray = Self.downsampledLuma(from: sampleBuffer)
            let visualMotion = Self.visualMotion(current: gray, previous: previousGray)
            previousGray = gray

            let objects = try detector.detect(
                in: sampleBuffer,
                orientation: orientation,
                orientedImageSize: orientedImageSize
            )
            let feature = ObjectFrameFeature(
                time: recordingTime,
                detections: objects,
                visualMotion: visualMotion,
                clubMotion: Self.clubMotion(detections: objects, previousClubPoint: previousClubPoint)
            )
            if let point = feature.bestClubPoint {
                previousClubPoint = point
            }
            features.append(feature)
            if features.count > configuration.featureRetentionLimit {
                features.removeFirst(features.count - configuration.featureRetentionLimit)
            }
            recordProcessingTime(startedAt: processingStartedAt)

            let previousDetections = detections
            let previousDiagnostics = detectionDiagnostics
            let updatedDetections = mergedDetections(
                existing: detections,
                new: buildDetections(videoDuration: recordingTime)
            )
            refreshImpactCandidates(
                videoDuration: recordingTime,
                declaredAt: recordingTime
            )
            let updatedDiagnostics = diagnosticsForUpdatedDetections(
                previousDetections: previousDetections,
                previousDiagnostics: previousDiagnostics,
                updatedDetections: updatedDetections
            )
            if updatedDetections.count > detections.count {
                detections = updatedDetections
                detectionDiagnostics = updatedDiagnostics
                lastSnapshot = snapshot(
                    status: .swingDetected,
                    primary: "\(detections.count) swing\(detections.count == 1 ? "" : "s") detected",
                    detail: "Model confirmed ball disappearance near impact."
                )
            } else {
                detections = updatedDetections
                detectionDiagnostics = updatedDiagnostics
                lastSnapshot = liveSnapshot(for: feature)
            }
        } catch {
            modelLoadError = error
            recordProcessingTime(startedAt: processingStartedAt)
            lastSnapshot = LiveSwingDetectionSnapshot(
                status: .unavailable,
                primaryMessage: "Model detector unavailable",
                detailMessage: "The YOLO model failed on a camera frame.",
                detectedSwingCount: detections.count,
                processedFrameCount: processedFrameCount,
                skippedFrameCount: skippedFrameCount,
                targetSampleFPS: configuration.targetSampleFPS,
                effectiveSampleFPS: effectiveSampleFPS,
                averageProcessingTimeMS: averageProcessingTimeMS,
                lastProcessingTimeMS: lastProcessingTimeMS,
                detectorConfigurationName: configuration.name
            )
        }

        return lastSnapshot
    }

    func finish(recordingTime: Double?) -> [DetectedSwing] {
        if let recordingTime, recordingTime.isFinite {
            let previousDetections = detections
            let previousDiagnostics = detectionDiagnostics
            detections = mergedDetections(
                existing: detections,
                new: buildDetections(videoDuration: recordingTime)
            )
            refreshImpactCandidates(
                videoDuration: recordingTime,
                declaredAt: recordingTime,
                force: true
            )
            detectionDiagnostics = diagnosticsForUpdatedDetections(
                previousDetections: previousDetections,
                previousDiagnostics: previousDiagnostics,
                updatedDetections: detections
            )
        }
        return detections
    }

    func currentDetections() -> [DetectedSwing] {
        detections
    }

    func currentSnapshot() -> LiveSwingDetectionSnapshot {
        lastSnapshot
    }

    func currentDetectionDiagnostics() -> [ObjectSwingWindowDiagnostics] {
        detectionDiagnostics
    }

    func currentFeatureSummary() -> ObjectSwingFeatureSummary {
        let motionSeries = smoothedMotion(features)
        return ObjectSwingFeatureSummary(
            frameCount: features.count,
            clubFrameCount: features.filter { $0.clubScore >= 0.35 }.count,
            ballFrameCount: features.filter { !$0.foregroundBalls.isEmpty }.count,
            maxClubScore: features.map(\.clubScore).max() ?? 0,
            maxBallScore: features.compactMap { $0.foregroundBalls.map(\.confidence).max() }.max() ?? 0,
            maxMotion: motionSeries.max() ?? 0,
            maxClubMotion: features.map(\.clubMotion).max() ?? 0
        )
    }

    func currentCandidateDiagnostics() -> [ObjectSwingWindowDiagnostics] {
        proposeWindows(from: features).map { window in
            windowDiagnostics(start: window.start, end: window.end)
        }
    }

    func currentImpactCenteredDetections(
        videoDuration: Double,
        declaredAt: Double? = nil
    ) -> [ObjectSwingImpactCandidate] {
        refreshImpactCandidates(
            videoDuration: videoDuration,
            declaredAt: declaredAt ?? features.last?.time ?? 0
        )
        return impactCandidates
    }

    func currentImpactDebugReports(
        videoDuration: Double,
        declaredAt: Double
    ) -> [ObjectSwingImpactDebugReport] {
        impactDebugReports(videoDuration: videoDuration, declaredAt: declaredAt)
    }

    func diagnostics(for detections: [DetectedSwing]) -> [ObjectSwingWindowDiagnostics] {
        detections.map { detection in
            windowDiagnostics(
                start: CMTimeGetSeconds(detection.startTime),
                end: CMTimeGetSeconds(detection.endTime)
            )
        }
    }

    private func diagnosticsForUpdatedDetections(
        previousDetections: [DetectedSwing],
        previousDiagnostics: [ObjectSwingWindowDiagnostics],
        updatedDetections: [DetectedSwing]
    ) -> [ObjectSwingWindowDiagnostics] {
        updatedDetections.map { detection in
            let start = CMTimeGetSeconds(detection.startTime)
            let end = CMTimeGetSeconds(detection.endTime)
            if let previousIndex = previousDetections.firstIndex(where: { previous in
                abs(CMTimeGetSeconds(previous.startTime) - start) < 0.01
                && abs(CMTimeGetSeconds(previous.endTime) - end) < 0.01
            }), previousDiagnostics.indices.contains(previousIndex) {
                return previousDiagnostics[previousIndex]
            }
            return windowDiagnostics(start: start, end: end)
        }
    }

    private var averageProcessingTimeMS: Double {
        guard processedFrameCount > 0 else { return 0 }
        return totalProcessingTimeMS / Double(processedFrameCount)
    }

    private func recordProcessingTime(startedAt: Date) {
        lastProcessingTimeMS = Date().timeIntervalSince(startedAt) * 1_000
        totalProcessingTimeMS += lastProcessingTimeMS
        processedFrameCount += 1
    }

    private func windowDiagnostics(start: Double, end: Double) -> ObjectSwingWindowDiagnostics {
        let inWindow = features.filter { $0.time >= start && $0.time <= end }
        let motionSeries = smoothedMotion(inWindow)
        let peakMotion = motionSeries.max() ?? 0
        let strongMotionFrameCount = motionSeries.filter { $0 >= configuration.acceptanceMinPeakMotion }.count
        let meanClubMotion = inWindow.isEmpty
            ? 0
            : inWindow.reduce(0.0) { $0 + $1.clubMotion } / Double(inWindow.count)
        let clubFrames = inWindow.filter { $0.clubScore >= 0.35 }.count
        let ballFrames = inWindow.filter { !$0.foregroundBalls.isEmpty }.count

        return ObjectSwingWindowDiagnostics(
            start: start,
            end: end,
            peakMotion: peakMotion,
            strongMotionFrameCount: strongMotionFrameCount,
            meanClubMotion: meanClubMotion,
            clubPathSpan: objectClubPathSpan(inWindow),
            clubTopY: objectClubTopY(inWindow),
            clubFrameRatio: inWindow.isEmpty ? 0 : Double(clubFrames) / Double(inWindow.count),
            ballFrameRatio: inWindow.isEmpty ? 0 : Double(ballFrames) / Double(inWindow.count)
        )
    }

    private func liveSnapshot(for feature: ObjectFrameFeature) -> LiveSwingDetectionSnapshot {
        let motion = smoothedMotion(Array(features.suffix(5))).last ?? 0
        let hasBall = !feature.foregroundBalls.isEmpty
        let hasClub = feature.clubScore >= 0.35

        if motion >= configuration.motionThreshold, hasClub {
            return snapshot(
                status: .swingInProgress,
                primary: "Model sees swing motion",
                detail: "Waiting for ball disappearance confirmation."
            )
        }

        if hasBall, hasClub {
            return snapshot(
                status: .ballLocked,
                primary: "Model sees ball and club",
                detail: "Scanning for a real strike."
            )
        }

        return snapshot(
            status: .searchingBall,
            primary: "Model scanning",
            detail: hasClub ? "Club visible; looking for strike-area ball." : "Looking for club and ball candidates."
        )
    }

    private func snapshot(
        status: LiveSwingDetectionStatus,
        primary: String,
        detail: String
    ) -> LiveSwingDetectionSnapshot {
        LiveSwingDetectionSnapshot(
            status: status,
            primaryMessage: primary,
            detailMessage: detail,
            detectedSwingCount: detections.count,
            hasBallLock: features.last?.foregroundBalls.isEmpty == false,
            hasBallMovement: status == .swingDetected || status == .hitDetected,
            poseObservationCount: 0,
            handSpeed: features.last?.visualMotion ?? 0,
            peakHandSpeed: smoothedMotion(Array(features.suffix(12))).max() ?? 0,
            handTravel: features.last?.clubMotion ?? 0,
            setupDuration: 0,
            ballCandidateScore: features.last?.foregroundBalls.map(\.confidence).max(),
            ballLumaDelta: nil,
            lastRejectionReason: nil,
            processedFrameCount: processedFrameCount,
            skippedFrameCount: skippedFrameCount,
            targetSampleFPS: configuration.targetSampleFPS,
            effectiveSampleFPS: effectiveSampleFPS,
            averageProcessingTimeMS: averageProcessingTimeMS,
            lastProcessingTimeMS: lastProcessingTimeMS,
            detectorConfigurationName: configuration.name
        )
    }

    private var effectiveSampleFPS: Double {
        guard features.count >= 2,
              let firstTime = features.first?.time,
              let lastTime = features.last?.time
        else { return 0 }

        let duration = lastTime - firstTime
        guard duration > 0 else { return 0 }
        return Double(features.count - 1) / duration
    }

    private func mergedDetections(existing: [DetectedSwing], new: [DetectedSwing]) -> [DetectedSwing] {
        var merged = existing

        for detection in new {
            let detectionStart = CMTimeGetSeconds(detection.startTime)
            let detectionEnd = CMTimeGetSeconds(detection.endTime)
            if let overlapIndex = merged.firstIndex(where: { existingDetection in
                let existingStart = CMTimeGetSeconds(existingDetection.startTime)
                let existingEnd = CMTimeGetSeconds(existingDetection.endTime)
                return detectionStart <= existingEnd + 0.8 && existingStart <= detectionEnd + 0.8
            }) {
                if detection.confidence >= merged[overlapIndex].confidence {
                    let previousDeclaredAt = merged[overlapIndex].declaredAt
                    let nextDeclaredAt = detection.declaredAt
                    let declaredAt = [previousDeclaredAt, nextDeclaredAt]
                        .compactMap { $0 }
                        .min()
                    merged[overlapIndex] = DetectedSwing(
                        startTime: detection.startTime,
                        endTime: detection.endTime,
                        confidence: detection.confidence,
                        impactTime: detection.impactTime ?? merged[overlapIndex].impactTime,
                        declaredAt: declaredAt
                    )
                }
            } else {
                merged.append(detection)
            }
        }

        return merged
            .sorted { CMTimeCompare($0.startTime, $1.startTime) < 0 }
            .prefix(32)
            .map { $0 }
    }

    private func mergedImpactCandidates(
        existing: [ObjectSwingImpactCandidate],
        new: [ObjectSwingImpactCandidate]
    ) -> [ObjectSwingImpactCandidate] {
        var merged = existing
        let sameImpactTolerance = max(1.45, configuration.minWindowDuration * 0.90)
            + configuration.targetSampleInterval * 0.50

        for candidate in new {
            if let index = merged.firstIndex(where: { existingCandidate in
                abs(existingCandidate.impactTime - candidate.impactTime) <= sameImpactTolerance
            }) {
                let previous = merged[index]
                let isSameSampledPeak = abs(previous.impactTime - candidate.impactTime) <= configuration.targetSampleInterval
                let declaredAt = isSameSampledPeak
                    ? min(previous.declaredAt, candidate.declaredAt)
                    : candidate.declaredAt
                let candidateExtendsWindow = isSameSampledPeak
                    && (candidate.end > previous.end + 0.01 || candidate.start < previous.start - 0.01)
                let candidateIsStronger = candidate.confidence > previous.confidence + 0.03
                let candidateIsLaterComparablePeak = candidate.impactTime > previous.impactTime
                    && candidate.confidence + 0.08 >= previous.confidence

                if candidateExtendsWindow || candidateIsStronger || candidateIsLaterComparablePeak {
                    merged[index] = ObjectSwingImpactCandidate(
                        start: candidate.start,
                        end: candidate.end,
                        impactTime: candidate.impactTime,
                        declaredAt: declaredAt,
                        confidence: max(previous.confidence, candidate.confidence),
                        diagnostics: candidate.diagnostics
                    )
                }
            } else {
                merged.append(candidate)
            }
        }

        return merged
            .sorted { $0.impactTime < $1.impactTime }
            .prefix(128)
            .map { $0 }
    }

    private func refreshImpactCandidates(
        videoDuration: Double,
        declaredAt: Double,
        force: Bool = false
    ) {
        let refreshInterval = max(0.35, configuration.targetSampleInterval * 3.0)
        guard force || declaredAt - lastImpactCandidateRefreshTime + 0.001 >= refreshInterval else {
            return
        }

        impactCandidates = mergedImpactCandidates(
            existing: impactCandidates,
            new: buildImpactCenteredDetections(
                videoDuration: videoDuration,
                declaredAt: declaredAt
            )
        )
        lastImpactCandidateRefreshTime = declaredAt
    }

    private func buildDetections(videoDuration: Double) -> [DetectedSwing] {
        let proposals = proposeWindows(from: features)
        var nextDetections: [DetectedSwing] = []

        for proposal in proposals {
            guard let evidence = validate(proposal, features: features) else {
                continue
            }

            var start = proposal.start
            var end = proposal.end
            if let impactTime = evidence.impactTime {
                start = max(0, min(start, impactTime - configuration.impactPreRoll))
                end = max(start, min(end, impactTime + configuration.impactPostRoll))
            }

            end = min(videoDuration, end)
            guard end > start else { continue }
            guard finalWindowMeetsAcceptance(start: start, end: end, features: features) else { continue }

            if let last = nextDetections.last,
               CMTimeGetSeconds(last.endTime) + 0.8 >= start {
                continue
            }

            nextDetections.append(
                DetectedSwing(
                    startTime: CMTime(seconds: start, preferredTimescale: 600),
                    endTime: CMTime(seconds: end, preferredTimescale: 600),
                    confidence: evidence.confidence,
                    impactTime: evidence.impactTime,
                    declaredAt: features.last?.time
                )
            )
        }

        return nextDetections
            .sorted { CMTimeCompare($0.startTime, $1.startTime) < 0 }
            .prefix(24)
            .map { $0 }
    }

    private func buildImpactCenteredDetections(
        videoDuration: Double,
        declaredAt: Double
    ) -> [ObjectSwingImpactCandidate] {
        guard !features.isEmpty else { return [] }

        let confirmationPostRoll = max(0.18, configuration.impactConfirmationPostRoll)
        let minimumImpactGap = max(1.45, configuration.minWindowDuration * 0.90)
        let firstTime = features.first?.time ?? 0
        let anchorLookback = max(
            configuration.maxWindowDuration * 3.0,
            configuration.validationPreRoll + configuration.impactPostRoll + confirmationPostRoll + 1.0
        )
        let anchors = ballAnchors(
            features: features,
            start: max(firstTime, declaredAt - anchorLookback),
            end: declaredAt
        )
        let detections = anchors
            .flatMap { anchor in
                confirmedImpactCandidates(
                    anchor: anchor,
                    videoDuration: videoDuration,
                    declaredAt: declaredAt,
                    confirmationPostRoll: confirmationPostRoll
                )
            }
            .sorted { $0.impactTime < $1.impactTime }

        var separatedDetections: [ObjectSwingImpactCandidate] = []
        for detection in detections {
            if let last = separatedDetections.last,
               detection.impactTime - last.impactTime < minimumImpactGap {
                if detection.confidence > last.confidence {
                    separatedDetections[separatedDetections.count - 1] = detection
                }
                continue
            }

            separatedDetections.append(detection)
        }

        return mergeImpactCandidates(separatedDetections)
            .prefix(32)
            .map { $0 }
    }

    private func impactDebugReports(
        videoDuration: Double,
        declaredAt: Double
    ) -> [ObjectSwingImpactDebugReport] {
        guard !features.isEmpty else {
            return [
                ObjectSwingImpactDebugReport(
                    anchorX: nil,
                    anchorY: nil,
                    result: "no_sampled_features",
                    disappearanceTime: nil,
                    preFeatureCount: 0,
                    postFeatureCount: 0,
                    prePresence: nil,
                    postPresence: nil,
                    clubMinDistance: nil,
                    clubNearRatio: nil,
                    localPeakMotion: nil,
                    localMeanClubMotion: nil,
                    windowPeakMotion: nil,
                    windowMeanClubMotion: nil,
                    clubPathSpan: nil
                )
            ]
        }

        let firstTime = features.first?.time ?? 0
        let anchors = ballAnchors(features: features, start: firstTime, end: declaredAt)
        guard !anchors.isEmpty else {
            return [
                ObjectSwingImpactDebugReport(
                    anchorX: nil,
                    anchorY: nil,
                    result: "no_ball_anchor",
                    disappearanceTime: nil,
                    preFeatureCount: 0,
                    postFeatureCount: 0,
                    prePresence: nil,
                    postPresence: nil,
                    clubMinDistance: nil,
                    clubNearRatio: nil,
                    localPeakMotion: nil,
                    localMeanClubMotion: nil,
                    windowPeakMotion: nil,
                    windowMeanClubMotion: nil,
                    clubPathSpan: nil
                )
            ]
        }

        return anchors.prefix(8).map { anchor in
            impactDebugReport(anchor: anchor, videoDuration: videoDuration, declaredAt: declaredAt)
        }
    }

    private func impactDebugReport(
        anchor: CGPoint,
        videoDuration: Double,
        declaredAt: Double
    ) -> ObjectSwingImpactDebugReport {
        let firstTime = features.first?.time ?? 0
        let confirmationPostRoll = max(0.18, configuration.impactConfirmationPostRoll)
        let disappearanceTimes = estimateDisappearanceTimes(
            features: features,
            start: firstTime,
            end: declaredAt,
            anchor: anchor
        )

        if let confirmed = confirmedImpactCandidate(
            anchor: anchor,
            videoDuration: videoDuration,
            declaredAt: declaredAt,
            confirmationPostRoll: confirmationPostRoll
        ) {
            let disappearedAt = confirmed.impactTime
            let beforeEnd = max(0, disappearedAt - configuration.targetSampleInterval * 0.5)
            let beforeStart = max(0, disappearedAt - max(configuration.validationPreRoll, configuration.targetSampleInterval * 4.0))
            let afterStart = disappearedAt + configuration.targetSampleInterval * 0.5
            let afterDuration = max(
                configuration.validationPostRoll,
                configuration.impactPostRoll,
                configuration.targetSampleInterval * 8.0
            )
            let afterEnd = disappearedAt + afterDuration
            let contactTolerance = max(0.30, configuration.targetSampleInterval * 3.0)
            let club = clubContactEvidence(
                features: features,
                start: disappearedAt - contactTolerance,
                end: disappearedAt + contactTolerance,
                anchor: anchor
            )
            let localDiagnostics = windowDiagnostics(
                start: disappearedAt - contactTolerance,
                end: disappearedAt + contactTolerance
            )

            return impactDebugReport(
                anchor: anchor,
                result: "confirmed",
                disappearanceTime: disappearedAt,
                preFeatureCount: featureCount(start: beforeStart, end: beforeEnd),
                postFeatureCount: featureCount(start: afterStart, end: afterEnd),
                prePresence: anchorPresenceRatio(features: features, start: beforeStart, end: beforeEnd, anchor: anchor),
                postPresence: anchorPresenceRatio(features: features, start: afterStart, end: afterEnd, anchor: anchor),
                clubMinDistance: club.minDistance.isFinite ? club.minDistance : nil,
                clubNearRatio: club.nearRatio,
                localPeakMotion: localDiagnostics.peakMotion,
                localMeanClubMotion: localDiagnostics.meanClubMotion,
                windowPeakMotion: confirmed.diagnostics.peakMotion,
                windowMeanClubMotion: confirmed.diagnostics.meanClubMotion,
                clubPathSpan: confirmed.diagnostics.clubPathSpan
            )
        }

        guard let disappearedAt = disappearanceTimes.first else {
            return impactDebugReport(
                anchor: anchor,
                result: "no_sustained_departure",
                disappearanceTime: nil
            )
        }

        if disappearedAt + confirmationPostRoll > declaredAt {
            return impactDebugReport(
                anchor: anchor,
                result: "pending_confirmation_wait",
                disappearanceTime: disappearedAt
            )
        }

        let beforeEnd = max(0, disappearedAt - configuration.targetSampleInterval * 0.5)
        let beforeStart = max(0, disappearedAt - max(configuration.validationPreRoll, configuration.targetSampleInterval * 4.0))
        let afterStart = disappearedAt + configuration.targetSampleInterval * 0.5
        let afterDuration = max(
            configuration.validationPostRoll,
            configuration.impactPostRoll,
            configuration.targetSampleInterval * 8.0
        )
        let afterEnd = disappearedAt + afterDuration
        let preFeatureCount = featureCount(start: beforeStart, end: beforeEnd)
        let postFeatureCount = featureCount(start: afterStart, end: afterEnd)

        if preFeatureCount < 2 {
            return impactDebugReport(
                anchor: anchor,
                result: "insufficient_pre_frames",
                disappearanceTime: disappearedAt,
                preFeatureCount: preFeatureCount,
                postFeatureCount: postFeatureCount
            )
        }
        if postFeatureCount < 3 {
            return impactDebugReport(
                anchor: anchor,
                result: "insufficient_post_frames",
                disappearanceTime: disappearedAt,
                preFeatureCount: preFeatureCount,
                postFeatureCount: postFeatureCount
            )
        }

        let prePresence = anchorPresenceRatio(features: features, start: beforeStart, end: beforeEnd, anchor: anchor)
        let postPresence = anchorPresenceRatio(features: features, start: afterStart, end: afterEnd, anchor: anchor)
        let ballDeparted = prePresence >= 0.30 && postPresence <= max(0.10, prePresence * 0.40)
        let strongBallDeparture = prePresence >= 0.75 && postPresence <= 0.05
        if !ballDeparted {
            return impactDebugReport(
                anchor: anchor,
                result: "ball_departure_not_confirmed",
                disappearanceTime: disappearedAt,
                preFeatureCount: preFeatureCount,
                postFeatureCount: postFeatureCount,
                prePresence: prePresence,
                postPresence: postPresence
            )
        }

            let contactTolerance = max(0.30, configuration.targetSampleInterval * 3.0)
            let club = clubContactEvidence(
                features: features,
                start: disappearedAt - contactTolerance,
                end: disappearedAt + contactTolerance,
                anchor: anchor
            )
            let localDiagnostics = windowDiagnostics(
                start: disappearedAt - contactTolerance,
                end: disappearedAt + contactTolerance
            )
            let start = max(0, disappearedAt - configuration.impactPreRoll)
            let end = min(videoDuration, disappearedAt + configuration.impactPostRoll)
            let diagnostics = windowDiagnostics(start: start, end: end)
            let directClubAtBall = club.minDistance <= 0.055 || club.nearRatio >= 0.20
            let looseClubAtBall = strongBallDeparture && club.minDistance <= 0.12
            let clubAtBall = directClubAtBall || looseClubAtBall
            let strongSwingMotion = hasStrongImpactSwingMotion(diagnostics)
            let strikeMotion = hasLocalStrikeMotion(localDiagnostics) || strongSwingMotion
            let missedContactStrike = strongBallDeparture && strongSwingMotion

            if !clubAtBall, !missedContactStrike {
                return impactDebugReport(
                    anchor: anchor,
                    result: "no_club_contact_at_anchor",
                    disappearanceTime: disappearedAt,
                    preFeatureCount: preFeatureCount,
                    postFeatureCount: postFeatureCount,
                    prePresence: prePresence,
                    postPresence: postPresence,
                    clubMinDistance: club.minDistance.isFinite ? club.minDistance : nil,
                    clubNearRatio: club.nearRatio,
                    localPeakMotion: localDiagnostics.peakMotion,
                    localMeanClubMotion: localDiagnostics.meanClubMotion,
                    windowPeakMotion: diagnostics.peakMotion,
                    windowMeanClubMotion: diagnostics.meanClubMotion,
                    clubPathSpan: diagnostics.clubPathSpan
                )
            }
            if clubAtBall, !strikeMotion {
                return impactDebugReport(
                    anchor: anchor,
                    result: "low_local_strike_motion",
                disappearanceTime: disappearedAt,
                preFeatureCount: preFeatureCount,
                postFeatureCount: postFeatureCount,
                prePresence: prePresence,
                postPresence: postPresence,
                clubMinDistance: club.minDistance.isFinite ? club.minDistance : nil,
                clubNearRatio: club.nearRatio,
                    localPeakMotion: localDiagnostics.peakMotion,
                    localMeanClubMotion: localDiagnostics.meanClubMotion
                )
            }

            if diagnostics.meanClubMotion < 0.025 || diagnostics.clubPathSpan < 0.20 {
                return impactDebugReport(
                    anchor: anchor,
                result: "low_window_club_motion",
                disappearanceTime: disappearedAt,
                preFeatureCount: preFeatureCount,
                postFeatureCount: postFeatureCount,
                prePresence: prePresence,
                postPresence: postPresence,
                clubMinDistance: club.minDistance.isFinite ? club.minDistance : nil,
                clubNearRatio: club.nearRatio,
                localPeakMotion: localDiagnostics.peakMotion,
                localMeanClubMotion: localDiagnostics.meanClubMotion,
                windowPeakMotion: diagnostics.peakMotion,
                windowMeanClubMotion: diagnostics.meanClubMotion,
                clubPathSpan: diagnostics.clubPathSpan
            )
        }
        if diagnostics.peakMotion < 0.70 && diagnostics.strongMotionFrameCount < 1 {
            return impactDebugReport(
                anchor: anchor,
                result: "low_window_motion",
                disappearanceTime: disappearedAt,
                preFeatureCount: preFeatureCount,
                postFeatureCount: postFeatureCount,
                prePresence: prePresence,
                postPresence: postPresence,
                clubMinDistance: club.minDistance.isFinite ? club.minDistance : nil,
                clubNearRatio: club.nearRatio,
                localPeakMotion: localDiagnostics.peakMotion,
                localMeanClubMotion: localDiagnostics.meanClubMotion,
                windowPeakMotion: diagnostics.peakMotion,
                windowMeanClubMotion: diagnostics.meanClubMotion,
                clubPathSpan: diagnostics.clubPathSpan
            )
        }

        return impactDebugReport(
            anchor: anchor,
            result: "confirmed",
            disappearanceTime: disappearedAt,
            preFeatureCount: preFeatureCount,
            postFeatureCount: postFeatureCount,
            prePresence: prePresence,
            postPresence: postPresence,
            clubMinDistance: club.minDistance.isFinite ? club.minDistance : nil,
            clubNearRatio: club.nearRatio,
            localPeakMotion: localDiagnostics.peakMotion,
            localMeanClubMotion: localDiagnostics.meanClubMotion,
            windowPeakMotion: diagnostics.peakMotion,
            windowMeanClubMotion: diagnostics.meanClubMotion,
            clubPathSpan: diagnostics.clubPathSpan
        )
    }

    private func impactDebugReport(
        anchor: CGPoint,
        result: String,
        disappearanceTime: Double?,
        preFeatureCount: Int = 0,
        postFeatureCount: Int = 0,
        prePresence: Double? = nil,
        postPresence: Double? = nil,
        clubMinDistance: Double? = nil,
        clubNearRatio: Double? = nil,
        localPeakMotion: Double? = nil,
        localMeanClubMotion: Double? = nil,
        windowPeakMotion: Double? = nil,
        windowMeanClubMotion: Double? = nil,
        clubPathSpan: Double? = nil
    ) -> ObjectSwingImpactDebugReport {
        ObjectSwingImpactDebugReport(
            anchorX: Double(anchor.x),
            anchorY: Double(anchor.y),
            result: result,
            disappearanceTime: disappearanceTime,
            preFeatureCount: preFeatureCount,
            postFeatureCount: postFeatureCount,
            prePresence: prePresence,
            postPresence: postPresence,
            clubMinDistance: clubMinDistance,
            clubNearRatio: clubNearRatio,
            localPeakMotion: localPeakMotion,
            localMeanClubMotion: localMeanClubMotion,
            windowPeakMotion: windowPeakMotion,
            windowMeanClubMotion: windowMeanClubMotion,
            clubPathSpan: clubPathSpan
        )
    }

    private func confirmedImpactCandidate(
        anchor: CGPoint,
        videoDuration: Double,
        declaredAt: Double,
        confirmationPostRoll: Double
    ) -> ObjectSwingImpactCandidate? {
        confirmedImpactCandidates(
            anchor: anchor,
            videoDuration: videoDuration,
            declaredAt: declaredAt,
            confirmationPostRoll: confirmationPostRoll
        ).first
    }

    private func confirmedImpactCandidates(
        anchor: CGPoint,
        videoDuration: Double,
        declaredAt: Double,
        confirmationPostRoll: Double
    ) -> [ObjectSwingImpactCandidate] {
        let firstTime = features.first?.time ?? 0
        let searchEnd = max(firstTime, declaredAt - confirmationPostRoll)
        let disappearanceTimes = estimateDisappearanceTimes(
            features: features,
            start: firstTime,
            end: searchEnd,
            anchor: anchor
        )
        var candidates: [ObjectSwingImpactCandidate] = []

        for disappearedAt in disappearanceTimes {
            guard disappearedAt >= 0.55 else { continue }
            guard disappearedAt + confirmationPostRoll <= declaredAt else { continue }

            let beforeEnd = max(0, disappearedAt - configuration.targetSampleInterval * 0.5)
            let beforeStart = max(0, disappearedAt - max(configuration.validationPreRoll, configuration.targetSampleInterval * 4.0))
            let afterStart = disappearedAt + configuration.targetSampleInterval * 0.5
            let afterDuration = max(
                configuration.validationPostRoll,
                configuration.impactPostRoll,
                configuration.targetSampleInterval * 8.0
            )
            let afterEnd = disappearedAt + afterDuration
            guard featureCount(start: beforeStart, end: beforeEnd) >= 2 else { continue }
            guard featureCount(start: afterStart, end: afterEnd) >= 3 else { continue }

            let prePresence = anchorPresenceRatio(features: features, start: beforeStart, end: beforeEnd, anchor: anchor)
            let postPresence = anchorPresenceRatio(features: features, start: afterStart, end: afterEnd, anchor: anchor)
            let ballDeparted = prePresence >= 0.30 && postPresence <= max(0.10, prePresence * 0.40)
            guard ballDeparted else { continue }
            let strongBallDeparture = prePresence >= 0.75 && postPresence <= 0.05

            let start = max(0, disappearedAt - configuration.impactPreRoll)
            let end = min(videoDuration, disappearedAt + configuration.impactPostRoll)
            guard end > start else { continue }

            let diagnostics = windowDiagnostics(start: start, end: end)
            let contactTolerance = max(0.30, configuration.targetSampleInterval * 3.0)
            let club = clubContactEvidence(
                features: features,
                start: disappearedAt - contactTolerance,
                end: disappearedAt + contactTolerance,
                anchor: anchor
            )
            let localDiagnostics = windowDiagnostics(
                start: disappearedAt - contactTolerance,
                end: disappearedAt + contactTolerance
            )
            let directClubAtBall = club.minDistance <= 0.055 || club.nearRatio >= 0.20
            let looseClubAtBall = strongBallDeparture && club.minDistance <= 0.12
            let clubAtBall = directClubAtBall || looseClubAtBall
            let strongSwingMotion = hasStrongImpactSwingMotion(diagnostics)
            let strikeMotion = hasLocalStrikeMotion(localDiagnostics) || strongSwingMotion
            let missedContactStrike = strongBallDeparture && strongSwingMotion
            guard (clubAtBall && strikeMotion) || missedContactStrike else { continue }

            let hasClubMotion = diagnostics.meanClubMotion >= 0.025
                && diagnostics.clubPathSpan >= 0.20
            let hasMotion = diagnostics.peakMotion >= 0.70
                || diagnostics.strongMotionFrameCount >= 1
            guard hasClubMotion, hasMotion else { continue }

            let departureScore = max(0, prePresence - postPresence)
            let contactScore = max(0, 1 - club.minDistance / 0.12)
            let departureComponent = min(0.24, departureScore * 0.36)
            let contactComponent = min(0.20, contactScore * 0.20)
            let motionComponent = min(0.16, diagnostics.peakMotion * 0.08)
            let pathComponent = min(0.10, diagnostics.clubPathSpan * 0.10)
            let confidence = min(0.96, 0.30 + departureComponent + contactComponent + motionComponent + pathComponent)

            candidates.append(
                ObjectSwingImpactCandidate(
                    start: start,
                    end: end,
                    impactTime: disappearedAt,
                    declaredAt: disappearedAt + confirmationPostRoll,
                    confidence: confidence,
                    diagnostics: diagnostics
                )
            )
        }

        return candidates
    }

    private func hasLocalStrikeMotion(_ diagnostics: ObjectSwingWindowDiagnostics) -> Bool {
        diagnostics.peakMotion >= max(1.55, configuration.acceptanceMinPeakMotion * 1.35)
            && diagnostics.meanClubMotion >= max(0.08, configuration.acceptanceMinMeanClubMotion * 1.60)
    }

    private func hasStrongImpactSwingMotion(_ diagnostics: ObjectSwingWindowDiagnostics) -> Bool {
        diagnostics.peakMotion >= max(2.0, configuration.acceptanceMinPeakMotion * 1.80)
            && diagnostics.meanClubMotion >= max(0.12, configuration.acceptanceMinMeanClubMotion * 2.40)
            && diagnostics.clubPathSpan >= max(0.68, configuration.acceptanceMinClubPathSpan * 2.10)
            && diagnostics.clubTopY <= min(0.40, configuration.acceptanceMaxClubTopY * 0.70)
            && diagnostics.clubFrameRatio >= 0.80
            && diagnostics.strongMotionFrameCount >= max(6, configuration.acceptanceMinStrongMotionFrames * 3)
    }

    private func clubContactEvidence(features: [ObjectFrameFeature], start: Double, end: Double, anchor: CGPoint) -> ObjectClubheadEvidence {
        let window = features.filter { $0.time >= start && $0.time <= end }
        guard !window.isEmpty else { return ObjectClubheadEvidence(minDistance: .greatestFiniteMagnitude, nearRatio: 0) }

        var minDistance = Double.greatestFiniteMagnitude
        var nearCount = 0

        for feature in window {
            let clubObjects = feature.detections.filter {
                ($0.objectClass == .clubhead || $0.objectClass == .clubShaft)
                    && $0.confidence >= 0.30
            }
            guard !clubObjects.isEmpty else { continue }

            let frameMin = clubObjects
                .map { Self.distance(from: anchor, to: $0.rect) }
                .min() ?? .greatestFiniteMagnitude
            minDistance = min(minDistance, frameMin)
            if frameMin <= 0.055 {
                nearCount += 1
            }
        }

        return ObjectClubheadEvidence(
            minDistance: minDistance,
            nearRatio: Double(nearCount) / Double(window.count)
        )
    }

    private func mergeImpactCandidates(
        _ detections: [ObjectSwingImpactCandidate]
    ) -> [ObjectSwingImpactCandidate] {
        var merged: [ObjectSwingImpactCandidate] = []
        let nearbyGap = min(1.20, max(0.25, configuration.impactPostRoll * 2.1))

        for detection in detections.sorted(by: { $0.start < $1.start }) {
            guard let last = merged.last else {
                merged.append(detection)
                continue
            }

            if detection.start > last.end + nearbyGap {
                merged.append(detection)
                continue
            }

            let shouldReplace = detection.confidence > last.confidence + 0.08
            if shouldReplace {
                merged[merged.count - 1] = detection
            }
        }

        return merged
    }

    private func proposeWindows(from features: [ObjectFrameFeature]) -> [ObjectCandidateWindow] {
        guard !features.isEmpty else { return [] }

        let motion = smoothedMotion(features)
        var candidates: [ObjectCandidateWindow] = []
        var activeStart: Int?
        var lastActiveIndex: Int?
        let gapTolerance = configuration.proposalGapTolerance

        for index in features.indices {
            let isActive = motion[index] >= configuration.motionThreshold && features[index].clubScore >= 0.35
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
                appendCandidate(startIndex: startIndex, endIndex: endIndex, motion: motion, features: features, candidates: &candidates)
                activeStart = nil
                lastActiveIndex = nil
            }
        }

        if let startIndex = activeStart, let endIndex = lastActiveIndex {
            appendCandidate(startIndex: startIndex, endIndex: endIndex, motion: motion, features: features, candidates: &candidates)
        }

        return merge(candidates)
            .filter { $0.end - $0.start >= configuration.minWindowDuration }
    }

    private func appendCandidate(
        startIndex: Int,
        endIndex: Int,
        motion: [Double],
        features: [ObjectFrameFeature],
        candidates: inout [ObjectCandidateWindow]
    ) {
        let start = max(0, features[startIndex].time - configuration.candidatePreRoll)
        let end = features[endIndex].time + configuration.candidatePostRoll
        guard end - start <= configuration.maxWindowDuration else { return }
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
        let preStart = max(0, window.start - configuration.validationPreRoll)
        let preEnd = window.start + windowDuration * 0.45
        let postStart = window.start + windowDuration * 0.58
        let postEnd = window.end + configuration.validationPostRoll
        let anchors = ballAnchors(features: features, start: preStart, end: preEnd)
        guard !anchors.isEmpty else { return nil }

        let anchorEvidence = anchors
            .map { anchor in
                let pre = anchorPresenceRatio(features: features, start: preStart, end: preEnd, anchor: anchor)
                let post = anchorPresenceRatio(features: features, start: postStart, end: postEnd, anchor: anchor)
                let clubhead = clubheadEvidence(
                    features: features,
                    start: max(0, window.start - configuration.addressPreRoll),
                    end: window.start + configuration.addressPostOffset,
                    anchor: anchor
                )
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
        let motionSeries = smoothedMotion(inWindow)
        let peakMotion = motionSeries.max() ?? 0
        let strongMotionFrameCount = motionSeries.filter { $0 >= configuration.acceptanceMinPeakMotion }.count
        let meanClubMotion = inWindow.isEmpty
            ? 0
            : inWindow.reduce(0.0) { $0 + $1.clubMotion } / Double(inWindow.count)
        let clubPathSpan = objectClubPathSpan(inWindow)
        let clubTopY = objectClubTopY(inWindow)
        let ballDisappearance = best.pre >= 0.18 && best.post <= max(0.12, best.pre * 0.45)
        guard ballDisappearance,
              peakMotion >= configuration.acceptanceMinPeakMotion,
              strongMotionFrameCount >= configuration.acceptanceMinStrongMotionFrames,
              meanClubMotion >= configuration.acceptanceMinMeanClubMotion,
              clubPathSpan >= configuration.acceptanceMinClubPathSpan,
              clubTopY <= configuration.acceptanceMaxClubTopY
        else { return nil }

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

    private func finalWindowMeetsAcceptance(start: Double, end: Double, features: [ObjectFrameFeature]) -> Bool {
        let inWindow = features.filter { $0.time >= start && $0.time <= end }
        guard !inWindow.isEmpty else { return false }

        let motionSeries = smoothedMotion(inWindow)
        let peakMotion = motionSeries.max() ?? 0
        let strongMotionFrameCount = motionSeries.filter { $0 >= configuration.acceptanceMinPeakMotion }.count
        let meanClubMotion = inWindow.reduce(0.0) { $0 + $1.clubMotion } / Double(inWindow.count)
        return peakMotion >= configuration.acceptanceMinPeakMotion
            && strongMotionFrameCount >= configuration.acceptanceMinStrongMotionFrames
            && meanClubMotion >= configuration.acceptanceMinMeanClubMotion
            && objectClubPathSpan(inWindow) >= configuration.acceptanceMinClubPathSpan
            && objectClubTopY(inWindow) <= configuration.acceptanceMaxClubTopY
    }

    private func ballAnchors(features: [ObjectFrameFeature], start: Double, end: Double) -> [CGPoint] {
        var points: [(point: CGPoint, confidence: Double)] = []

        for feature in features where feature.time >= start && feature.time <= end {
            for ball in feature.foregroundBalls where ball.confidence >= 0.35 && Double(ball.center.y) >= configuration.minBallAnchorY {
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
        estimateDisappearanceTimes(features: features, start: start, end: end, anchor: anchor).first
    }

    private func estimateDisappearanceTimes(features: [ObjectFrameFeature], start: Double, end: Double, anchor: CGPoint) -> [Double] {
        let timeline = features
            .filter { $0.time >= start && $0.time <= end }
            .map { feature in
                (
                    time: feature.time,
                    present: feature.foregroundBalls.contains { $0.center.distance(to: anchor) <= 0.055 }
                )
            }

        guard timeline.count >= 4 else { return [] }

        var times: [Double] = []
        for index in timeline.indices where !timeline[index].present {
            let previous = timeline[max(0, index - 6)..<index]
            let following = timeline[index..<min(timeline.count, index + 4)]
            let previousPresent = previous.filter { $0.present }.count
            let followingAbsent = following.filter { !$0.present }.count

            if previousPresent >= 2, followingAbsent >= 2 {
                times.append(timeline[index].time)
            }
        }

        return times
    }

    private func featureCount(start: Double, end: Double) -> Int {
        features.filter { $0.time >= start && $0.time <= end }.count
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

            if window.start > last.end + configuration.mergeMaxGap {
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

    private static func distance(from point: CGPoint, to rect: CGRect) -> Double {
        if rect.contains(point) {
            return 0
        }

        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        return point.distance(to: CGPoint(x: clampedX, y: clampedY))
    }
}

nonisolated private struct ObjectFrameFeature {
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

nonisolated private struct ObjectCandidateWindow {
    let start: Double
    let end: Double
    let peakMotion: Double
}

nonisolated private func objectClubPathSpan(_ features: [ObjectFrameFeature]) -> Double {
    let points = features.compactMap(\.bestClubPoint)
    guard !points.isEmpty else { return 0 }

    let xs = points.map(\.x)
    let ys = points.map(\.y)
    let xSpan = Double((xs.max() ?? 0) - (xs.min() ?? 0))
    let ySpan = Double((ys.max() ?? 0) - (ys.min() ?? 0))
    return sqrt(xSpan * xSpan + ySpan * ySpan)
}

nonisolated private func objectClubTopY(_ features: [ObjectFrameFeature]) -> Double {
    features.compactMap(\.bestClubPoint?.y).min() ?? 1.0
}

nonisolated private struct ObjectWindowEvidence {
    let confidence: Double
    let impactTime: Double?
}

nonisolated private struct ObjectAnchorEvidence {
    let anchor: CGPoint
    let pre: Double
    let post: Double
    let clubhead: ObjectClubheadEvidence

    var drop: Double {
        pre - post
    }
}

nonisolated private struct ObjectClubheadEvidence {
    let minDistance: Double
    let nearRatio: Double

    var near: Bool {
        minDistance <= 0.18 || nearRatio >= 0.08
    }
}

nonisolated private struct ObjectBallBucket: Hashable {
    let x: Int
    let y: Int
}

nonisolated private extension CGPoint {
    func distance(to other: CGPoint) -> Double {
        let dx = Double(x - other.x)
        let dy = Double(y - other.y)
        return sqrt(dx * dx + dy * dy)
    }
}
