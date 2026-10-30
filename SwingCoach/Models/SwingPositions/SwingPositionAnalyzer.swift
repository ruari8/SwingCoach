//
//  SwingPositionAnalyzer.swift
//  SwingCoach
//
//  Finds P1-P10 in a saved down-the-line clip. Reads the clip once, runs
//  Vision body pose on the frame nearest each 30 fps real-time slot (one
//  call per slot: on the frozen bench this scores the same as pose on every
//  frame), then runs SwingPositionTCN over the whole clip and decodes the
//  positions in order.
//

import AVFoundation
import CoreML
import Vision

/// Not thread-safe: SwingPositionProcessor runs one analysis at a time.
nonisolated final class SwingPositionAnalyzer: @unchecked Sendable {
    enum AnalyzerError: LocalizedError {
        case modelMissing
        case noVideoTrack
        case unreadable
        case tooShort
        case noGolfer
        case unexpectedOutput

        var errorDescription: String? {
            switch self {
            case .modelMissing: "The swing position model is missing from the app."
            case .noVideoTrack: "The clip has no video track."
            case .unreadable: "The clip could not be read."
            case .tooShort: "The clip is too short to find swing positions."
            case .noGolfer: "No golfer was found in enough of the clip."
            case .unexpectedOutput: "The swing position model returned an unexpected output."
            }
        }
    }

    struct Timing {
        var decodedFrames = 0
        var poseCalls = 0
        var bodySlots = 0
        var readAndPoseSeconds = 0.0
        /// Inside readAndPoseSeconds: waiting on the decoder, and in Vision.
        var decodeSeconds = 0.0
        var poseSeconds = 0.0
        var modelSeconds = 0.0
        /// Model slot of each position, P1 first.
        var slots: [Int] = []
    }

    /// Mean decode error of tcn_vision_v2 on the frozen bench's range clips
    /// (P1 +1.4 frames late, P10 -1.8 early at 30 fps), removed from the
    /// reported times. Both come from fuzzy label conventions at the ends of
    /// the swing; the other positions are within half a frame.
    private static let firstPositionOffsetFrames = -1.4
    private static let lastPositionOffsetFrames = 1.8

    /// Below this share of slots with a body, the decoder would still return
    /// ten positions, but they would mean nothing.
    private static let minimumBodyShare = 0.5

    /// Training extractor joint order (vision_pose_extract.swift).
    private static let jointOrder: [VNHumanBodyPoseObservation.JointName] = [
        .nose, .leftEye, .rightEye, .leftEar, .rightEar,
        .neck, .leftShoulder, .rightShoulder,
        .leftElbow, .rightElbow, .leftWrist, .rightWrist,
        .root, .leftHip, .rightHip,
        .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
    ]

    private let model: MLModel
    private let poseRequest = VNDetectHumanBodyPoseRequest()

    init(modelURL: URL, computeUnits: MLComputeUnits = .cpuAndNeuralEngine) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        model = try MLModel(contentsOf: modelURL, configuration: configuration)
    }

    convenience init() throws {
        guard let url = Bundle.main.url(forResource: "SwingPositionTCN", withExtension: "mlmodelc") else {
            throw AnalyzerError.modelMissing
        }
        try self.init(modelURL: url)
    }

    /// `timeScale` is how many times slower than real time the clip plays
    /// (8 for a 240 fps capture exported at 30 fps). `window` limits the
    /// search to part of the clip's timeline, e.g. leaving out extra footage.
    func analyze(videoURL: URL, timeScale: Double, window: ClosedRange<Double>? = nil) async throws -> (SwingPositions, Timing) {
        try await analyze(asset: AVURLAsset(url: videoURL), timeScale: timeScale, window: window)
    }

    func analyze(asset: AVAsset, timeScale: Double, window: ClosedRange<Double>? = nil) async throws -> (SwingPositions, Timing) {
        var timing = Timing()
        let started = Date()
        let (grid, playableTimes) = try await poseGrid(asset: asset, timeScale: timeScale, window: window, timing: &timing)
        timing.readAndPoseSeconds = Date().timeIntervalSince(started)
        let positions = try positions(grid: grid, playable: playableTimes, timeScale: timeScale, timing: &timing)
        return (positions, timing)
    }

    /// P1-P10 from one pose per 30 fps real-time slot. `playable` is the time
    /// of slot 0 and of the last frame, on the timeline the results use.
    func positions(
        grid: [SwingPositionPose?],
        playable playableTimes: ClosedRange<Double>,
        timeScale: Double,
        timing: inout Timing
    ) throws -> SwingPositions {
        timing.bodySlots = grid.filter { $0 != nil }.count
        guard Double(timing.bodySlots) >= Self.minimumBodyShare * Double(grid.count) else {
            throw AnalyzerError.noGolfer
        }
        guard grid.count >= SwingPositionFeatures.positionCount else { throw AnalyzerError.tooShort }

        let modelStarted = Date()
        let logits = try predictLogits(SwingPositionFeatures.build(grid), frameCount: grid.count)
        timing.modelSeconds = Date().timeIntervalSince(modelStarted)
        guard let frames = SwingPositionFeatures.decode(logits: logits, frameCount: grid.count) else {
            throw AnalyzerError.tooShort
        }
        timing.slots = frames

        let positionCount = SwingPositionFeatures.positionCount
        let positions = frames.enumerated().map { index, frame in
            let logit = Double(logits[frame * positionCount + index])
            return SwingPosition(
                number: index + 1,
                clipTime: Self.clipTime(position: index, slot: frame, timeScale: timeScale, playable: playableTimes),
                confidence: 1 / (1 + exp(-logit))
            )
        }
        return SwingPositions(model: SwingPositions.currentModel, positions: positions)
    }

    /// Runs pose and the position model once on blank input, so the first
    /// real swing doesn't pay for loading them.
    func warmUp() {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 1920, 1080, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer)
        if let pixelBuffer {
            try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
                .perform([poseRequest])
        }
        let frameCount = 72
        _ = try? predictLogits([Float](repeating: 0, count: frameCount * SwingPositionFeatures.featureCount),
                               frameCount: frameCount)
    }

    /// Clip time for a decoded slot, with the P1/P10 bias removed. The
    /// correction can push P1 before the first frame or P10 past the last, so
    /// the result is clamped to the clip's first and last frame times.
    static func clipTime(
        position index: Int,
        slot frame: Int,
        timeScale: Double,
        playable: ClosedRange<Double>
    ) -> Double {
        var slot = Double(frame)
        if index == 0 { slot += firstPositionOffsetFrames }
        if index == SwingPositionFeatures.positionCount - 1 { slot += lastPositionOffsetFrames }
        let time = playable.lowerBound + slot / SwingPositionFeatures.gridFPS * timeScale
        return min(max(time, playable.lowerBound), playable.upperBound)
    }

    // MARK: - Pose grid

    /// One pose per 30 fps real-time slot, from the decoded frame nearest the
    /// slot (dataset.py resample_indices). Returns the grid and the
    /// presentation times of the clip's first frame (slot 0) and last frame.
    private func poseGrid(
        asset: AVAsset,
        timeScale: Double,
        window: ClosedRange<Double>?,
        timing: inout Timing
    ) async throws -> ([SwingPositionPose?], ClosedRange<Double>) {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw AnalyzerError.noVideoTrack
        }
        let orientation = Self.orientation(for: try await track.load(.preferredTransform))
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        if let window {
            reader.timeRange = CMTimeRange(start: CMTime(seconds: window.lowerBound, preferredTimescale: 600),
                                           end: CMTime(seconds: window.upperBound, preferredTimescale: 600))
        }
        guard reader.startReading() else { throw AnalyzerError.unreadable }

        var grid: [SwingPositionPose?] = []
        var firstTime: Double?
        var previous: (time: Double, buffer: CMSampleBuffer)?
        var lastPose: (time: Double, pose: SwingPositionPose?)?
        var frameDurations: [Double] = []

        func pose(at frame: (time: Double, buffer: CMSampleBuffer)) -> SwingPositionPose? {
            if let lastPose, lastPose.time == frame.time { return lastPose.pose }
            let poseStarted = Date()
            let result = detectPose(in: frame.buffer, orientation: orientation)
            timing.poseSeconds += Date().timeIntervalSince(poseStarted)
            timing.poseCalls += 1
            lastPose = (frame.time, result)
            return result
        }

        while true {
            let decodeStarted = Date()
            let next = output.copyNextSampleBuffer()
            timing.decodeSeconds += Date().timeIntervalSince(decodeStarted)
            guard let buffer = next else { break }
            guard CMSampleBufferGetImageBuffer(buffer) != nil else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            guard time.isFinite else { continue }
            timing.decodedFrames += 1
            let start = firstTime ?? time
            firstTime = start
            if let previous { frameDurations.append(time - previous.time) }

            // Resolve every slot whose target falls at or before this frame,
            // using whichever of the previous and current frame is nearer.
            while true {
                let target = start + Double(grid.count) / SwingPositionFeatures.gridFPS * timeScale
                guard target <= time else { break }
                if let previous, target - previous.time < time - target {
                    grid.append(pose(at: previous))
                } else {
                    grid.append(pose(at: (time, buffer)))
                }
            }
            previous = (time, buffer)
        }
        guard reader.status != .failed, let firstTime, let previous else {
            throw AnalyzerError.unreadable
        }

        // dataset.py: n_out = floor(real duration * 30), where the duration
        // counts the last frame's own length.
        let frameDuration = SwingPositionFeatures.median(frameDurations.map(Float.init)).map(Double.init) ?? 0
        let realDuration = (previous.time - firstTime + frameDuration) / timeScale
        let slotCount = max(2, Int((realDuration * SwingPositionFeatures.gridFPS).rounded(.down)))
        while grid.count < slotCount {
            grid.append(pose(at: previous))
        }
        if grid.count > slotCount {
            grid.removeLast(grid.count - slotCount)
        }
        guard grid.count >= SwingPositionFeatures.positionCount else { throw AnalyzerError.tooShort }
        return (grid, firstTime...previous.time)
    }

    private func detectPose(in buffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) -> SwingPositionPose? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return nil }
        return pose(in: pixelBuffer, orientation: orientation)
    }

    func pose(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> SwingPositionPose? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        guard (try? handler.perform([poseRequest])) != nil,
              let observation = poseRequest.results?.first,
              let points = try? observation.recognizedPoints(.all)
        else {
            return nil
        }
        var pose = SwingPositionPose(
            xy: Array(repeating: .zero, count: SwingPositionFeatures.jointCount),
            confidence: Array(repeating: 0, count: SwingPositionFeatures.jointCount)
        )
        for (j, name) in Self.jointOrder.enumerated() {
            guard let point = points[name], point.confidence > 0 else { continue }
            pose.xy[j] = SIMD2(Float(point.location.x), Float(1 - point.location.y))
            pose.confidence[j] = point.confidence
        }
        return pose.hasBody ? pose : nil
    }

    /// Same mapping as the training extractor: raw reader buffers are
    /// sensor-oriented, so Vision gets the track's display rotation.
    private static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let degrees = (Int(atan2(transform.b, transform.a) * 180 / .pi) + 360) % 360
        switch degrees {
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
    }

    // MARK: - Model

    private func predictLogits(_ features: [Float], frameCount: Int) throws -> [Float] {
        let featureCount = SwingPositionFeatures.featureCount
        let input = try MLMultiArray(
            shape: [1, NSNumber(value: frameCount), NSNumber(value: featureCount)],
            dataType: .float32
        )
        let inputStrides = input.strides.map(\.intValue)
        let inputPointer = input.dataPointer.bindMemory(to: Float.self, capacity: input.count)
        for t in 0..<frameCount {
            for c in 0..<featureCount {
                inputPointer[t * inputStrides[1] + c * inputStrides[2]] = features[t * featureCount + c]
            }
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: ["features": MLFeatureValue(multiArray: input)])
        guard let output = try model.prediction(from: provider).featureValue(for: "event_logits")?.multiArrayValue,
              output.shape.count == 3,
              output.shape[1].intValue == frameCount,
              output.shape[2].intValue == SwingPositionFeatures.positionCount
        else {
            throw AnalyzerError.unexpectedOutput
        }

        let positions = SwingPositionFeatures.positionCount
        let strides = output.strides.map(\.intValue)
        var logits = [Float](repeating: 0, count: frameCount * positions)
        switch output.dataType {
        case .float32:
            let pointer = output.dataPointer.bindMemory(to: Float.self, capacity: output.count)
            for t in 0..<frameCount {
                for p in 0..<positions {
                    logits[t * positions + p] = pointer[t * strides[1] + p * strides[2]]
                }
            }
        case .float16:
            let pointer = output.dataPointer.bindMemory(to: Float16.self, capacity: output.count)
            for t in 0..<frameCount {
                for p in 0..<positions {
                    logits[t * positions + p] = Float(pointer[t * strides[1] + p * strides[2]])
                }
            }
        default:
            throw AnalyzerError.unexpectedOutput
        }
        return logits
    }
}
