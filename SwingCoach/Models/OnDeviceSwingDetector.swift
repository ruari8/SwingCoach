//
//  OnDeviceSwingDetector.swift
//  SwingCoach
//
//  Created by Codex on 18/05/2026.
//

import AVFoundation
import CoreGraphics
import ImageIO
import Vision

nonisolated struct DetectedSwing: Identifiable {
    let id = UUID()
    let startTime: CMTime
    let endTime: CMTime
    let confidence: Double
}

actor OnDeviceSwingDetector {
    enum DetectionError: Error {
        case invalidDuration
        case noVideoTrack
        case readerSetupFailed
    }

    private let targetSampleInterval: Double
    private let maxProcessedFrames: Int
    private let peakSpeedThreshold: Double
    private let motionThreshold: Double
    private let quietThreshold: Double
    private let confidenceThreshold: Double

    init(
        targetSampleInterval: Double = 0.12,
        maxProcessedFrames: Int = 900,
        peakSpeedThreshold: Double = 1.65,
        motionThreshold: Double = 0.85,
        quietThreshold: Double = 0.28,
        confidenceThreshold: Double = 0.50
    ) {
        self.targetSampleInterval = targetSampleInterval
        self.maxProcessedFrames = max(12, maxProcessedFrames)
        self.peakSpeedThreshold = peakSpeedThreshold
        self.motionThreshold = motionThreshold
        self.quietThreshold = quietThreshold
        self.confidenceThreshold = confidenceThreshold
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
        let orientation = Self.orientation(for: transform)
        let sampleInterval = max(targetSampleInterval, durationSeconds / Double(maxProcessedFrames))
        let samples = try readPoseSamples(
            from: asset,
            track: videoTrack,
            orientation: orientation,
            sampleInterval: sampleInterval
        )

        return buildDetections(from: samples, videoDuration: durationSeconds)
    }

    private func readPoseSamples(
        from asset: AVAsset,
        track: AVAssetTrack,
        orientation: CGImagePropertyOrientation,
        sampleInterval: Double
    ) throws -> [PoseSample] {
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

        let request = VNDetectHumanBodyPoseRequest()
        var lastProcessedTime = -Double.greatestFiniteMagnitude
        var samples: [PoseSample] = []

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()

            let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            guard time.isFinite, time - lastProcessedTime >= sampleInterval else { continue }

            lastProcessedTime = time

            if let sample = Self.poseSample(
                from: sampleBuffer,
                at: time,
                orientation: orientation,
                request: request,
                previousSample: samples.last
            ) {
                samples.append(sample)
            }
        }

        if reader.status == .failed {
            throw reader.error ?? DetectionError.readerSetupFailed
        }

        return samples
    }

    private func buildDetections(from samples: [PoseSample], videoDuration: Double) -> [DetectedSwing] {
        guard samples.count >= 6 else { return [] }

        let speeds = smoothedHandSpeeds(for: samples)
        let adaptivePeakThreshold = adaptivePeakSpeedThreshold(from: speeds)
        let peakIndices = candidatePeakIndices(from: speeds, samples: samples, peakThreshold: adaptivePeakThreshold)
        var candidates: [SwingCandidate] = []

        for peakIndex in peakIndices {
            let peakTime = samples[peakIndex].time
            let isAlreadyCovered = candidates.contains { candidate in
                peakTime >= candidate.startTime && peakTime <= candidate.endTime
            }
            guard !isAlreadyCovered else { continue }

            let bounds = candidateBounds(around: peakIndex, samples: samples, speeds: speeds, videoDuration: videoDuration)
            if let candidate = evaluateCandidate(
                startIndex: bounds.startIndex,
                endIndex: bounds.endIndex,
                startTime: bounds.startTime,
                endTime: bounds.endTime,
                peakIndex: peakIndex,
                peakThreshold: adaptivePeakThreshold,
                samples: samples,
                speeds: speeds
            ) {
                candidates.append(candidate)
            }
        }

        return merged(candidates)
            .sorted { $0.startTime < $1.startTime }
            .prefix(12)
            .map {
                DetectedSwing(
                    startTime: CMTime(seconds: $0.startTime, preferredTimescale: 600),
                    endTime: CMTime(seconds: $0.endTime, preferredTimescale: 600),
                    confidence: $0.confidence
                )
            }
    }

    private func smoothedHandSpeeds(for samples: [PoseSample]) -> [Double] {
        var raw = Array(repeating: 0.0, count: samples.count)

        for index in 1..<samples.count {
            let dt = samples[index].time - samples[index - 1].time
            guard dt > 0, dt <= 0.6 else { continue }
            raw[index] = samples[index].relativeHands.distance(to: samples[index - 1].relativeHands) / dt
        }

        guard raw.count >= 3 else { return raw }

        return raw.indices.map { index in
            let lower = max(0, index - 1)
            let upper = min(raw.count - 1, index + 1)
            let values = raw[lower...upper]
            return values.reduce(0, +) / Double(values.count)
        }
    }

    private func adaptivePeakSpeedThreshold(from speeds: [Double]) -> Double {
        let movingSpeeds = speeds
            .filter { $0.isFinite && $0 > 0.05 }
            .sorted()

        guard movingSpeeds.count >= 8 else { return peakSpeedThreshold }

        func percentile(_ fraction: Double) -> Double {
            let index = min(movingSpeeds.count - 1, max(0, Int((Double(movingSpeeds.count - 1) * fraction).rounded())))
            return movingSpeeds[index]
        }

        let p85 = percentile(0.85)
        let p95 = percentile(0.95)
        let distributionThreshold = max(0.65, max(p85 * 0.85, p95 * 0.52))

        return min(peakSpeedThreshold, distributionThreshold)
    }

    private func candidatePeakIndices(from speeds: [Double], samples: [PoseSample], peakThreshold: Double) -> [Int] {
        let sorted = speeds.enumerated()
            .filter { index, speed in
                index > 1 && index < speeds.count - 2 && speed >= peakThreshold
            }
            .sorted { $0.element > $1.element }

        var selected: [Int] = []

        for entry in sorted {
            let peakTime = samples[entry.offset].time
            let isNearSelectedPeak = selected.contains { existingIndex in
                abs(samples[existingIndex].time - peakTime) < 1.4
            }
            guard !isNearSelectedPeak else { continue }
            selected.append(entry.offset)
        }

        return selected
    }

    private func candidateBounds(
        around peakIndex: Int,
        samples: [PoseSample],
        speeds: [Double],
        videoDuration: Double
    ) -> (startIndex: Int, endIndex: Int, startTime: Double, endTime: Double) {
        let peakTime = samples[peakIndex].time
        let leadLimit = peakTime - 2.8
        let followLimit = peakTime + 3.2
        let activeThreshold = motionThreshold * 0.42

        var startIndex = peakIndex
        var index = peakIndex
        while index >= 0, samples[index].time >= leadLimit {
            if speeds[index] >= activeThreshold {
                startIndex = index
            }
            index -= 1
        }

        var quietExtension = 0
        while startIndex > 0,
              samples[peakIndex].time - samples[startIndex - 1].time <= 3.1,
              speeds[startIndex - 1] <= quietThreshold,
              quietExtension < 2 {
            startIndex -= 1
            quietExtension += 1
        }

        var endIndex = peakIndex
        index = peakIndex
        while index < samples.count, samples[index].time <= followLimit {
            if speeds[index] >= activeThreshold {
                endIndex = index
            }
            index += 1
        }

        quietExtension = 0
        while endIndex < samples.count - 1,
              samples[endIndex + 1].time - samples[peakIndex].time <= 3.5,
              speeds[endIndex + 1] <= quietThreshold,
              quietExtension < 3 {
            endIndex += 1
            quietExtension += 1
        }

        let startTime = max(0, samples[startIndex].time - 0.35)
        let endTime = min(videoDuration, samples[endIndex].time + 0.65)

        return (startIndex, endIndex, startTime, endTime)
    }

    private func evaluateCandidate(
        startIndex: Int,
        endIndex: Int,
        startTime: Double,
        endTime: Double,
        peakIndex: Int,
        peakThreshold: Double,
        samples: [PoseSample],
        speeds: [Double]
    ) -> SwingCandidate? {
        guard startIndex < endIndex else { return nil }

        let duration = endTime - startTime
        guard duration >= 0.75, duration <= 5.6 else { return nil }

        let windowSamples = Array(samples[startIndex...endIndex])
        guard windowSamples.count >= 5 else { return nil }

        let windowSpeeds = Array(speeds[startIndex...endIndex])
        let peakSpeed = speeds[peakIndex]
        let handBounds = bounds(for: windowSamples.map(\.relativeHands))
        let bodyBounds = bounds(for: windowSamples.map(\.normalizedBodyCenter))
        let handTravel = handBounds.diagonal
        let verticalTravel = handBounds.height
        let horizontalTravel = handBounds.width
        let bodyDrift = bodyBounds.diagonal
        let coverage = Double(windowSamples.filter { $0.validJointCount >= 8 }.count) / Double(windowSamples.count)
        let preStillness = averageSpeed(
            from: max(0, startIndex - 5),
            to: max(0, startIndex - 1),
            speeds: speeds
        )
        let postStillness = averageSpeed(
            from: min(speeds.count - 1, endIndex + 1),
            to: min(speeds.count - 1, endIndex + 5),
            speeds: speeds
        )

        guard peakSpeed >= peakThreshold else { return nil }
        guard handTravel >= 0.52 else { return nil }
        guard verticalTravel >= 0.20 || horizontalTravel >= 0.34 else { return nil }
        guard bodyDrift <= 0.7 else { return nil }
        guard coverage >= 0.45 else { return nil }

        let peakScore = clamp((peakSpeed - peakThreshold) / 1.7)
        let travelScore = clamp((handTravel - 0.42) / 0.62)
        let verticalScore = clamp(verticalTravel / 0.55)
        let coverageScore = clamp((coverage - 0.45) / 0.45)
        let durationScore = clamp(1 - abs(duration - 2.4) / 2.6)
        let stillnessScore = clamp(1 - min(preStillness, postStillness) / 0.9)
        let sustainedMotionScore = clamp(Double(windowSpeeds.filter { $0 >= motionThreshold }.count) / 4.0)

        let confidence =
            0.24 * peakScore +
            0.22 * travelScore +
            0.16 * verticalScore +
            0.14 * coverageScore +
            0.10 * durationScore +
            0.08 * stillnessScore +
            0.06 * sustainedMotionScore

        guard confidence >= confidenceThreshold else { return nil }

        return SwingCandidate(
            startTime: startTime,
            endTime: endTime,
            confidence: confidence,
            peakSpeed: peakSpeed
        )
    }

    private func averageSpeed(from startIndex: Int, to endIndex: Int, speeds: [Double]) -> Double {
        guard startIndex <= endIndex, speeds.indices.contains(startIndex), speeds.indices.contains(endIndex) else {
            return 0
        }

        let values = speeds[startIndex...endIndex]
        guard !values.isEmpty else { return 0 }

        return values.reduce(0, +) / Double(values.count)
    }

    private func merged(_ candidates: [SwingCandidate]) -> [SwingCandidate] {
        let sorted = candidates.sorted { $0.startTime < $1.startTime }
        var result: [SwingCandidate] = []

        for candidate in sorted {
            guard let last = result.last else {
                result.append(candidate)
                continue
            }

            if candidate.startTime <= last.endTime + 0.65 {
                if candidate.confidence > last.confidence {
                    result[result.count - 1] = candidate
                }
            } else {
                result.append(candidate)
            }
        }

        return result
    }

    private func bounds(for points: [NormalizedPoint]) -> PointBounds {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0

        return PointBounds(width: maxX - minX, height: maxY - minY)
    }

    private func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static func poseSample(
        from sampleBuffer: CMSampleBuffer,
        at time: Double,
        orientation: CGImagePropertyOrientation,
        request: VNDetectHumanBodyPoseRequest,
        previousSample: PoseSample?
    ) -> PoseSample? {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: orientation, options: [:])

        do {
            try handler.perform([request])
            return try primaryPoseSample(
                from: request.results ?? [],
                at: time,
                previousSample: previousSample
            )
        } catch {
            return nil
        }
    }

    private static func primaryPoseSample(
        from observations: [VNHumanBodyPoseObservation],
        at time: Double,
        previousSample: PoseSample?
    ) throws -> PoseSample? {
        let samples = try observations.compactMap { observation in
            try poseSample(from: observation, at: time)
        }

        guard !samples.isEmpty else { return nil }

        return samples.max { lhs, rhs in
            primaryGolferScore(lhs, previousSample: previousSample) < primaryGolferScore(rhs, previousSample: previousSample)
        }
    }

    private static func primaryGolferScore(_ sample: PoseSample, previousSample: PoseSample?) -> Double {
        var score = Double(sample.validJointCount) * 0.08 + sample.bodyHeight * 2.8

        if let previousSample {
            let continuity = max(0, 1 - sample.imageBodyCenter.distance(to: previousSample.imageBodyCenter) / 0.55)
            score += continuity * 3.0
        }

        return score
    }

    private static func poseSample(from observation: VNHumanBodyPoseObservation, at time: Double) throws -> PoseSample? {
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

        let wrists = [
            point(.leftWrist),
            point(.rightWrist)
        ].compactMap { $0 }
        guard let hands = average(wrists) else { return nil }

        let shoulders = [
            point(.leftShoulder),
            point(.rightShoulder)
        ].compactMap { $0 }
        let hips = [
            point(.leftHip),
            point(.rightHip)
        ].compactMap { $0 }

        let center: CGPoint
        if let shoulderCenter = average(shoulders), let hipCenter = average(hips) {
            center = CGPoint(
                x: (shoulderCenter.x + hipCenter.x) / 2,
                y: (shoulderCenter.y + hipCenter.y) / 2
            )
        } else {
            center = CGPoint(x: bodyBounds.midX, y: bodyBounds.midY)
        }

        let relativeHands = NormalizedPoint(
            x: Double(hands.x - center.x) / bodyHeight,
            y: Double(hands.y - center.y) / bodyHeight
        )
        let normalizedBodyCenter = NormalizedPoint(
            x: Double(center.x) / bodyHeight,
            y: Double(center.y) / bodyHeight
        )
        let imageBodyCenter = NormalizedPoint(
            x: Double(center.x),
            y: Double(center.y)
        )

        return PoseSample(
            time: time,
            relativeHands: relativeHands,
            normalizedBodyCenter: normalizedBodyCenter,
            imageBodyCenter: imageBodyCenter,
            bodyHeight: bodyHeight,
            validJointCount: confidentPoints.count
        )
    }

    private static func imageBounds(for points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func average(_ points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }

        let sum = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }

        return CGPoint(
            x: sum.x / CGFloat(points.count),
            y: sum.y / CGFloat(points.count)
        )
    }

    private static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let epsilon: CGFloat = 0.001

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
}

private struct PoseSample {
    let time: Double
    let relativeHands: NormalizedPoint
    let normalizedBodyCenter: NormalizedPoint
    let imageBodyCenter: NormalizedPoint
    let bodyHeight: Double
    let validJointCount: Int
}

private struct SwingCandidate {
    let startTime: Double
    let endTime: Double
    let confidence: Double
    let peakSpeed: Double
}

private struct NormalizedPoint {
    let x: Double
    let y: Double

    nonisolated func distance(to other: NormalizedPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}

private struct PointBounds {
    let width: Double
    let height: Double

    nonisolated var diagonal: Double {
        sqrt(width * width + height * height)
    }
}
