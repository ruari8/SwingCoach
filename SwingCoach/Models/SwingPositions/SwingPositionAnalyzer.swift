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
        var modelSeconds = 0.0
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
    /// (8 for a 240 fps capture exported at 30 fps).
    func analyze(videoURL: URL, timeScale: Double) async throws -> (SwingPositions, Timing) {
        var timing = Timing()
        let started = Date()
        let (grid, firstTime) = try await poseGrid(videoURL: videoURL, timeScale: timeScale, timing: &timing)
        timing.readAndPoseSeconds = Date().timeIntervalSince(started)
        timing.bodySlots = grid.filter { $0 != nil }.count
        guard Double(timing.bodySlots) >= Self.minimumBodyShare * Double(grid.count) else {
            throw AnalyzerError.noGolfer
        }

        let modelStarted = Date()
        let logits = try predictLogits(SwingPositionFeatures.build(grid), frameCount: grid.count)
        timing.modelSeconds = Date().timeIntervalSince(modelStarted)
        guard let frames = SwingPositionFeatures.decode(logits: logits, frameCount: grid.count) else {
            throw AnalyzerError.tooShort
        }

        let positionCount = SwingPositionFeatures.positionCount
        let positions = frames.enumerated().map { index, frame in
            var slot = Double(frame)
            if index == 0 { slot += Self.firstPositionOffsetFrames }
            if index == positionCount - 1 { slot += Self.lastPositionOffsetFrames }
            let realTime = max(0, slot / SwingPositionFeatures.gridFPS)
            let logit = Double(logits[frame * positionCount + index])
            return SwingPosition(
                number: index + 1,
                clipTime: firstTime + realTime * timeScale,
                confidence: 1 / (1 + exp(-logit))
            )
        }
        return (SwingPositions(model: SwingPositions.currentModel, positions: positions), timing)
    }

    // MARK: - Pose grid

    /// One pose per 30 fps real-time slot, from the decoded frame nearest the
    /// slot (dataset.py resample_indices). Returns the grid and the
    /// presentation time of the clip's first frame, which slot 0 maps to.
    private func poseGrid(
        videoURL: URL,
        timeScale: Double,
        timing: inout Timing
    ) async throws -> ([SwingPositionPose?], Double) {
        let asset = AVURLAsset(url: videoURL)
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
        guard reader.startReading() else { throw AnalyzerError.unreadable }

        var grid: [SwingPositionPose?] = []
        var firstTime: Double?
        var previous: (time: Double, buffer: CMSampleBuffer)?
        var lastPose: (time: Double, pose: SwingPositionPose?)?
        var frameDurations: [Double] = []

        func pose(at frame: (time: Double, buffer: CMSampleBuffer)) -> SwingPositionPose? {
            if let lastPose, lastPose.time == frame.time { return lastPose.pose }
            let result = detectPose(in: frame.buffer, orientation: orientation)
            timing.poseCalls += 1
            lastPose = (frame.time, result)
            return result
        }

        while let buffer = output.copyNextSampleBuffer() {
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
        return (grid, firstTime)
    }

    private func detectPose(in buffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) -> SwingPositionPose? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return nil }
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
