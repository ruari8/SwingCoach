//
//  LiveSwingDetector.swift
//  SwingCoach
//
//  Created by Codex on 18/05/2026.
//

import AVFoundation
import CoreVideo
import Vision

enum LiveSwingDetectionStatus: Equatable {
    case idle
    case searchingBall
    case ballLocked
    case swingInProgress
    case hitDetected
    case swingDetected
    case unavailable
}

struct LiveSwingDetectionSnapshot: Equatable {
    var status: LiveSwingDetectionStatus = .idle
    var primaryMessage: String = "Auto detect ready"
    var detailMessage: String = "Looking for setup once recording starts."
    var detectedSwingCount: Int = 0
    var hasBallLock = false
    var hasBallMovement = false

    static let idle = LiveSwingDetectionSnapshot()
}

final class LiveSwingDetector {
    private enum SwingState {
        case waitingForSetup
        case swinging
    }

    private struct PoseFrame {
        let time: Double
        let hands: NormalizedPoint
        let relativeHands: NormalizedPoint
        let bodyCenter: NormalizedPoint
        let leftAnkle: NormalizedPoint?
        let rightAnkle: NormalizedPoint?
        let validJointCount: Int
        let bodyHeight: Double
    }

    private struct BallLock {
        let center: NormalizedPoint
        let radiusPixels: Double
        let baselineLuma: Double
    }

    private struct BrightBlob {
        let centerX: Double
        let centerY: Double
        let area: Int
        let width: Int
        let height: Int
        let meanLuma: Double
        let score: Double

        var center: CGPoint {
            CGPoint(x: centerX, y: centerY)
        }

        var radiusPixels: Double {
            sqrt(Double(area) / .pi)
        }
    }

    private struct ActiveSwing {
        let startTime: Double
        let motionStartTime: Double
        var endTime: Double
        var peakSpeed: Double
        var lastMotionTime: Double
        var quietStartedAt: Double?
        var ballMoved = false
        var ballMissingFrames = 0
        var checkedImpactWindow = false
    }

    private let setupSpeedThreshold = 0.34
    private let swingStartSpeedThreshold = 0.92
    private let swingMotionThreshold = 0.55
    private let minimumPeakSpeed = 1.25
    private let minimumSwingDuration = 0.9
    private let maximumSwingDuration = 3.3
    private let impactWindowStartOffset = 0.55
    private let impactWindowEndOffset = 1.45

    private var state: SwingState = .waitingForSetup
    private var previousPose: PoseFrame?
    private var lockedBall: BallLock?
    private var stableBallCandidate: BrightBlob?
    private var stableBallFrameCount = 0
    private var activeSwing: ActiveSwing?
    private var detections: [DetectedSwing] = []
    private var lastSnapshot = LiveSwingDetectionSnapshot.idle

    func reset() {
        state = .waitingForSetup
        previousPose = nil
        lockedBall = nil
        stableBallCandidate = nil
        stableBallFrameCount = 0
        activeSwing = nil
        detections = []
        lastSnapshot = .idle
    }

    func process(
        sampleBuffer: CMSampleBuffer,
        observation: VNHumanBodyPoseObservation?,
        recordingTime: Double
    ) -> LiveSwingDetectionSnapshot {
        guard let observation,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let pose = Self.poseFrame(from: observation, at: recordingTime)
        else {
            lastSnapshot = snapshot(
                status: .unavailable,
                primary: "Auto detect unavailable",
                detail: "Keep the golfer visible so pose and ball search can run."
            )
            return lastSnapshot
        }

        let speed = handSpeed(current: pose, previous: previousPose)
        updateBallLockIfNeeded(pixelBuffer: pixelBuffer, pose: pose, speed: speed)
        updateSwingState(pixelBuffer: pixelBuffer, pose: pose, speed: speed)
        previousPose = pose

        return lastSnapshot
    }

    func finish(recordingTime: Double?) -> [DetectedSwing] {
        if let activeSwing {
            finishActiveSwing(at: recordingTime ?? activeSwing.endTime)
        }

        activeSwing = nil
        state = .waitingForSetup
        return detections
    }

    private func updateBallLockIfNeeded(pixelBuffer: CVPixelBuffer, pose: PoseFrame, speed: Double) {
        guard lockedBall == nil, speed <= setupSpeedThreshold else { return }
        guard let roi = ballSearchROI(for: pose),
              let candidate = Self.bestBallBlob(in: roi, pixelBuffer: pixelBuffer, expectedCenter: pose.hands)
        else {
            stableBallCandidate = nil
            stableBallFrameCount = 0
            lastSnapshot = snapshot(
                status: .searchingBall,
                primary: "Finding ball",
                detail: "Searching near hands and feet while setup is still."
            )
            return
        }

        if let stableBallCandidate,
           stableBallCandidate.center.distance(to: candidate.center) <= max(18, candidate.radiusPixels * 2.8) {
            stableBallFrameCount += 1
        } else {
            stableBallCandidate = candidate
            stableBallFrameCount = 1
        }

        guard stableBallFrameCount >= 3 else {
            lastSnapshot = snapshot(
                status: .searchingBall,
                primary: "Finding ball",
                detail: "Checking for a stable bright ball near address."
            )
            return
        }

        let width = Double(CVPixelBufferGetWidthOfPlane(pixelBuffer, 0))
        let height = Double(CVPixelBufferGetHeightOfPlane(pixelBuffer, 0))
        let normalizedCenter = NormalizedPoint(
            x: candidate.centerX / width,
            y: 1 - candidate.centerY / height
        )
        lockedBall = BallLock(
            center: normalizedCenter,
            radiusPixels: max(5, candidate.radiusPixels),
            baselineLuma: candidate.meanLuma
        )
        lastSnapshot = snapshot(
            status: .ballLocked,
            primary: "Ball locked",
            detail: "Watching for takeaway and ball movement."
        )
    }

    private func updateSwingState(pixelBuffer: CVPixelBuffer, pose: PoseFrame, speed: Double) {
        switch state {
        case .waitingForSetup:
            guard speed >= swingStartSpeedThreshold, pose.validJointCount >= 8 else {
                if lockedBall != nil {
                    lastSnapshot = snapshot(
                        status: .ballLocked,
                        primary: "Ball locked",
                        detail: "Waiting for takeaway."
                    )
                }
                return
            }

            activeSwing = ActiveSwing(
                startTime: max(0, pose.time - 0.35),
                motionStartTime: pose.time,
                endTime: min(pose.time + 2.2, pose.time + maximumSwingDuration),
                peakSpeed: speed,
                lastMotionTime: pose.time
            )
            state = .swinging
            lastSnapshot = snapshot(
                status: .swingInProgress,
                primary: "Swing started",
                detail: lockedBall == nil ? "No ball lock yet; using pose timing only." : "Checking ball movement near impact."
            )

        case .swinging:
            guard var swing = activeSwing else {
                state = .waitingForSetup
                return
            }

            swing.peakSpeed = max(swing.peakSpeed, speed)

            if speed >= swingMotionThreshold {
                swing.lastMotionTime = pose.time
                swing.quietStartedAt = nil
            } else if swing.quietStartedAt == nil, pose.time - swing.motionStartTime > 1.0 {
                swing.quietStartedAt = pose.time
            }

            let elapsed = pose.time - swing.motionStartTime
            if elapsed >= impactWindowStartOffset, elapsed <= impactWindowEndOffset {
                swing.checkedImpactWindow = true
                if ballMoved(pixelBuffer: pixelBuffer, swing: &swing) {
                    swing.ballMoved = true
                    lastSnapshot = snapshot(
                        status: .hitDetected,
                        primary: "Impact detected",
                        detail: "Ball moved during the predicted impact window."
                    )
                }
            }

            let quietLongEnough = swing.quietStartedAt.map { pose.time - $0 >= 0.45 } ?? false
            let tooLong = elapsed >= maximumSwingDuration

            if quietLongEnough || tooLong {
                swing.endTime = min(pose.time + 0.45, swing.motionStartTime + maximumSwingDuration)
                activeSwing = swing
                finishActiveSwing(at: swing.endTime)
                return
            }

            swing.endTime = min(max(swing.endTime, swing.lastMotionTime + 0.65), swing.motionStartTime + maximumSwingDuration)
            activeSwing = swing
        }
    }

    private func finishActiveSwing(at endTime: Double) {
        guard let swing = activeSwing else { return }

        let duration = endTime - swing.startTime
        let hasBallEvidence = lockedBall != nil
        let isConfirmedHit = swing.ballMoved
        let strongPoseOnlySwing = !hasBallEvidence && swing.peakSpeed >= 1.85

        guard duration >= minimumSwingDuration,
              duration <= maximumSwingDuration + 0.6,
              swing.peakSpeed >= minimumPeakSpeed,
              isConfirmedHit || strongPoseOnlySwing
        else {
            activeSwing = nil
            state = .waitingForSetup
            lastSnapshot = snapshot(
                status: lockedBall == nil ? .searchingBall : .ballLocked,
                primary: lockedBall == nil ? "Finding ball" : "Ball locked",
                detail: "Rejected motion without enough hit evidence."
            )
            return
        }

        let confidence = isConfirmedHit ? min(0.95, 0.72 + (swing.peakSpeed - minimumPeakSpeed) * 0.08) : 0.6
        let detection = DetectedSwing(
            startTime: CMTime(seconds: swing.startTime, preferredTimescale: 600),
            endTime: CMTime(seconds: max(endTime, swing.startTime + minimumSwingDuration), preferredTimescale: 600),
            confidence: confidence
        )

        if detections.last.map({ CMTimeGetSeconds($0.endTime) + 0.8 < swing.startTime }) ?? true {
            detections.append(detection)
        }

        activeSwing = nil
        state = .waitingForSetup
        lastSnapshot = snapshot(
            status: .swingDetected,
            primary: isConfirmedHit ? "Swing detected" : "Likely swing detected",
            detail: isConfirmedHit ? "Ball movement confirmed this hit." : "No ball lock; saved high-motion swing only."
        )
    }

    private func ballMoved(pixelBuffer: CVPixelBuffer, swing: inout ActiveSwing) -> Bool {
        guard let lockedBall else { return false }

        if Self.ballStillPresent(lockedBall, pixelBuffer: pixelBuffer) {
            swing.ballMissingFrames = 0
            return false
        }

        swing.ballMissingFrames += 1
        return swing.ballMissingFrames >= 2
    }

    private func handSpeed(current: PoseFrame, previous: PoseFrame?) -> Double {
        guard let previous else { return 0 }
        let dt = current.time - previous.time
        guard dt > 0.02, dt < 0.6 else { return 0 }
        return current.relativeHands.distance(to: previous.relativeHands) / dt
    }

    private func ballSearchROI(for pose: PoseFrame) -> NormalizedRect? {
        let anklePoints = [pose.leftAnkle, pose.rightAnkle].compactMap { $0 }
        guard !anklePoints.isEmpty else { return nil }

        let ankleMinX = anklePoints.map(\.x).min() ?? pose.hands.x
        let ankleMaxX = anklePoints.map(\.x).max() ?? pose.hands.x
        let ankleMinY = anklePoints.map(\.y).min() ?? pose.hands.y
        let ankleMaxY = anklePoints.map(\.y).max() ?? pose.hands.y

        let minX = min(pose.hands.x, ankleMinX) - 0.12
        let maxX = max(pose.hands.x, ankleMaxX) + 0.34
        let minY = min(ankleMinY, pose.hands.y) - 0.08
        let maxY = max(ankleMaxY, pose.hands.y) + 0.12

        return NormalizedRect(
            minX: max(0, minX),
            maxX: min(1, maxX),
            minY: max(0, minY),
            maxY: min(1, maxY)
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
            hasBallLock: lockedBall != nil,
            hasBallMovement: activeSwing?.ballMoved ?? false
        )
    }

    private static func poseFrame(from observation: VNHumanBodyPoseObservation, at time: Double) -> PoseFrame? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }

        func point(_ joint: VNHumanBodyPoseObservation.JointName, minimumConfidence: Float = 0.28) -> NormalizedPoint? {
            guard let recognizedPoint = points[joint],
                  recognizedPoint.confidence >= minimumConfidence else {
                return nil
            }

            return NormalizedPoint(
                x: Double(recognizedPoint.location.x),
                y: Double(recognizedPoint.location.y)
            )
        }

        let confidentPoints = points.values
            .filter { $0.confidence >= 0.28 }
            .map {
                NormalizedPoint(
                    x: Double($0.location.x),
                    y: Double($0.location.y)
                )
            }

        guard confidentPoints.count >= 6 else { return nil }

        let bounds = NormalizedRect(points: confidentPoints)
        guard bounds.height >= 0.16 else { return nil }

        let wrists = [point(.leftWrist), point(.rightWrist)].compactMap { $0 }
        guard let hands = NormalizedPoint.average(wrists) else { return nil }

        let shoulders = [point(.leftShoulder), point(.rightShoulder)].compactMap { $0 }
        let hips = [point(.leftHip), point(.rightHip)].compactMap { $0 }

        let bodyCenter: NormalizedPoint
        if let shoulderCenter = NormalizedPoint.average(shoulders),
           let hipCenter = NormalizedPoint.average(hips) {
            bodyCenter = NormalizedPoint(
                x: (shoulderCenter.x + hipCenter.x) / 2,
                y: (shoulderCenter.y + hipCenter.y) / 2
            )
        } else {
            bodyCenter = NormalizedPoint(x: bounds.midX, y: bounds.midY)
        }

        let relativeHands = NormalizedPoint(
            x: (hands.x - bodyCenter.x) / bounds.height,
            y: (hands.y - bodyCenter.y) / bounds.height
        )

        return PoseFrame(
            time: time,
            hands: hands,
            relativeHands: relativeHands,
            bodyCenter: bodyCenter,
            leftAnkle: point(.leftAnkle),
            rightAnkle: point(.rightAnkle),
            validJointCount: confidentPoints.count,
            bodyHeight: bounds.height
        )
    }

    private static func bestBallBlob(
        in roi: NormalizedRect,
        pixelBuffer: CVPixelBuffer,
        expectedCenter: NormalizedPoint
    ) -> BrightBlob? {
        brightBlobs(in: roi, pixelBuffer: pixelBuffer, expectedCenter: expectedCenter)
            .max { $0.score < $1.score }
    }

    private static func ballStillPresent(_ ball: BallLock, pixelBuffer: CVPixelBuffer) -> Bool {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let centerX = ball.center.x * Double(width)
        let centerY = (1 - ball.center.y) * Double(height)
        let searchRadius = max(18, ball.radiusPixels * 3.2)
        let roi = PixelRect(
            minX: max(0, Int((centerX - searchRadius).rounded(.down))),
            maxX: min(width - 1, Int((centerX + searchRadius).rounded(.up))),
            minY: max(0, Int((centerY - searchRadius).rounded(.down))),
            maxY: min(height - 1, Int((centerY + searchRadius).rounded(.up)))
        )
        let normalizedROI = NormalizedRect(pixelRect: roi, width: width, height: height)
        let blobs = brightBlobs(in: normalizedROI, pixelBuffer: pixelBuffer, expectedCenter: ball.center)

        return blobs.contains { blob in
            blob.center.distance(to: CGPoint(x: centerX, y: centerY)) <= searchRadius &&
            abs(blob.meanLuma - ball.baselineLuma) <= 52
        }
    }

    private static func brightBlobs(
        in roi: NormalizedRect,
        pixelBuffer: CVPixelBuffer,
        expectedCenter: NormalizedPoint
    ) -> [BrightBlob] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return []
        }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
        let pixelRect = PixelRect(roi: roi, width: width, height: height)

        guard pixelRect.width >= 8, pixelRect.height >= 8 else { return [] }

        let threshold = lumaThreshold(in: pixelRect, pixels: pixels, bytesPerRow: bytesPerRow)
        var visited = Array(repeating: false, count: pixelRect.width * pixelRect.height)
        var blobs: [BrightBlob] = []

        func localIndex(x: Int, y: Int) -> Int {
            (y - pixelRect.minY) * pixelRect.width + (x - pixelRect.minX)
        }

        for y in pixelRect.minY...pixelRect.maxY {
            for x in pixelRect.minX...pixelRect.maxX {
                let index = localIndex(x: x, y: y)
                guard !visited[index], pixels[y * bytesPerRow + x] >= threshold else {
                    visited[index] = true
                    continue
                }

                var stack = [(x, y)]
                visited[index] = true
                var area = 0
                var minX = x
                var maxX = x
                var minY = y
                var maxY = y
                var sumX = 0
                var sumY = 0
                var sumLuma = 0

                while let (currentX, currentY) = stack.popLast() {
                    let luma = Int(pixels[currentY * bytesPerRow + currentX])
                    guard luma >= threshold else { continue }

                    area += 1
                    minX = min(minX, currentX)
                    maxX = max(maxX, currentX)
                    minY = min(minY, currentY)
                    maxY = max(maxY, currentY)
                    sumX += currentX
                    sumY += currentY
                    sumLuma += luma

                    for (nextX, nextY) in [
                        (currentX - 1, currentY),
                        (currentX + 1, currentY),
                        (currentX, currentY - 1),
                        (currentX, currentY + 1)
                    ] where pixelRect.contains(x: nextX, y: nextY) {
                        let nextIndex = localIndex(x: nextX, y: nextY)
                        guard !visited[nextIndex] else { continue }
                        visited[nextIndex] = true
                        if pixels[nextY * bytesPerRow + nextX] >= threshold {
                            stack.append((nextX, nextY))
                        }
                    }
                }

                guard area >= 8, area <= 1_600 else { continue }

                let blobWidth = maxX - minX + 1
                let blobHeight = maxY - minY + 1
                guard blobWidth >= 3, blobHeight >= 3, blobWidth <= 64, blobHeight <= 64 else { continue }

                let aspect = Double(blobWidth) / Double(blobHeight)
                guard aspect >= 0.35, aspect <= 2.8 else { continue }

                let fill = Double(area) / Double(blobWidth * blobHeight)
                guard fill >= 0.24 else { continue }

                let centerX = Double(sumX) / Double(area)
                let centerY = Double(sumY) / Double(area)
                let normalizedCenter = NormalizedPoint(
                    x: centerX / Double(width),
                    y: 1 - centerY / Double(height)
                )
                let centerScore = max(0, 1 - normalizedCenter.distance(to: expectedCenter) / 0.55)
                let compactScore = min(1, fill * 1.7)
                let areaScore = max(0, 1 - abs(Double(area) - 90) / 250)
                let brightnessScore = Double(sumLuma) / Double(area) / 255
                let score = 0.34 * brightnessScore + 0.28 * compactScore + 0.22 * centerScore + 0.16 * areaScore

                blobs.append(
                    BrightBlob(
                        centerX: centerX,
                        centerY: centerY,
                        area: area,
                        width: blobWidth,
                        height: blobHeight,
                        meanLuma: Double(sumLuma) / Double(area),
                        score: score
                    )
                )
            }
        }

        return blobs
    }

    private static func lumaThreshold(
        in rect: PixelRect,
        pixels: UnsafePointer<UInt8>,
        bytesPerRow: Int
    ) -> UInt8 {
        var values: [Double] = []
        values.reserveCapacity(max(1, rect.width * rect.height / 16))

        stride(from: rect.minY, through: rect.maxY, by: 4).forEach { y in
            stride(from: rect.minX, through: rect.maxX, by: 4).forEach { x in
                values.append(Double(pixels[y * bytesPerRow + x]))
            }
        }

        guard !values.isEmpty else { return 210 }

        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { partial, value in
            let delta = value - mean
            return partial + delta * delta
        } / Double(values.count)
        let threshold = max(188, min(245, mean + sqrt(variance) * 1.45))
        return UInt8(threshold.rounded())
    }
}

private struct NormalizedPoint {
    let x: Double
    let y: Double

    nonisolated func distance(to other: NormalizedPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }

    nonisolated static func average(_ points: [NormalizedPoint]) -> NormalizedPoint? {
        guard !points.isEmpty else { return nil }

        let sum = points.reduce(NormalizedPoint(x: 0, y: 0)) { partial, point in
            NormalizedPoint(x: partial.x + point.x, y: partial.y + point.y)
        }

        return NormalizedPoint(x: sum.x / Double(points.count), y: sum.y / Double(points.count))
    }
}

private struct NormalizedRect {
    let minX: Double
    let maxX: Double
    let minY: Double
    let maxY: Double

    init(minX: Double, maxX: Double, minY: Double, maxY: Double) {
        self.minX = min(minX, maxX)
        self.maxX = max(minX, maxX)
        self.minY = min(minY, maxY)
        self.maxY = max(minY, maxY)
    }

    init(points: [NormalizedPoint]) {
        minX = points.map(\.x).min() ?? 0
        maxX = points.map(\.x).max() ?? 0
        minY = points.map(\.y).min() ?? 0
        maxY = points.map(\.y).max() ?? 0
    }

    init(pixelRect: PixelRect, width: Int, height: Int) {
        minX = Double(pixelRect.minX) / Double(width)
        maxX = Double(pixelRect.maxX) / Double(width)
        minY = 1 - Double(pixelRect.maxY) / Double(height)
        maxY = 1 - Double(pixelRect.minY) / Double(height)
    }

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var midX: Double { (minX + maxX) / 2 }
    var midY: Double { (minY + maxY) / 2 }
}

private struct PixelRect {
    let minX: Int
    let maxX: Int
    let minY: Int
    let maxY: Int

    init(minX: Int, maxX: Int, minY: Int, maxY: Int) {
        self.minX = min(minX, maxX)
        self.maxX = max(minX, maxX)
        self.minY = min(minY, maxY)
        self.maxY = max(minY, maxY)
    }

    init(roi: NormalizedRect, width: Int, height: Int) {
        minX = max(0, min(width - 1, Int((roi.minX * Double(width)).rounded(.down))))
        maxX = max(0, min(width - 1, Int((roi.maxX * Double(width)).rounded(.up))))
        minY = max(0, min(height - 1, Int(((1 - roi.maxY) * Double(height)).rounded(.down))))
        maxY = max(0, min(height - 1, Int(((1 - roi.minY) * Double(height)).rounded(.up))))
    }

    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }

    nonisolated func contains(x: Int, y: Int) -> Bool {
        x >= minX && x <= maxX && y >= minY && y <= maxY
    }
}

private extension CGPoint {
    nonisolated func distance(to other: CGPoint) -> Double {
        let dx = Double(x - other.x)
        let dy = Double(y - other.y)
        return sqrt(dx * dx + dy * dy)
    }
}
