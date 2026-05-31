//
//  evaluate_swing_detector_v2.swift
//
//  Offline evaluator for SwingDetectorV2. Reads a video, drives the v2 core, and
//  emits JSON with accepted swings AND the full per-candidate debug traces.
//
//  Unlike the legacy evaluator, it passes SOURCE timestamps straight through:
//  SwingDetectorV2 converts to/from real-time via its configuration's
//  sourceTimeScale, so detection times come back already on the source timeline.
//
//  Build (from repo root):
//    xcrun swiftc -parse-as-library \
//      -framework AVFoundation -framework CoreML -framework Vision \
//      -framework CoreGraphics -framework CoreVideo -framework ImageIO \
//      SwingCoach/Models/OnDeviceSwingDetector.swift \
//      SwingCoach/Models/LiveSwingDetector.swift \
//      SwingCoach/Models/LiveSwingDetecting.swift \
//      SwingCoach/Models/GolfObjectDetector.swift \
//      SwingCoach/Models/SwingDetectorV2/*.swift \
//      detector_workbench/validation/evaluate_swing_detector_v2.swift \
//      -o .videos/bin/evaluate_swing_detector_v2
//

import AVFoundation
import CoreGraphics
import CoreMedia
import CoreML
import CoreVideo
import Foundation

private struct V2DetectionOut: Encodable {
    let start: Double
    let end: Double
    let impactTime: Double?
    let confidence: Double
    let declaredAt: Double?
}

private struct V2Output: Encodable {
    let video: String
    let model: String
    let computeUnits: String
    let configuration: String
    let duration: Double
    let sourceTimeScale: Double
    let lowSampleFPS: Double
    let burstSampleFPS: Double
    let decodedFrames: Int
    let processedFrames: Int
    let averageProcessingTimeMS: Double
    let wallClockElapsedSeconds: Double
    let detections: [V2DetectionOut]
    let traces: [SwingCandidateTrace]
    let sampling: [SwingSamplingTrace]
}

private enum EvaluationErrorV2: Error {
    case invalidDuration
    case noVideoTrack
    case readerSetupFailed
    case modelUnavailable(String)
    case noProcessedFrames
}

@main
struct EvaluateSwingDetectorV2 {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard let videoPath = args.first else {
                fputs("usage: evaluate_swing_detector_v2 <video-path> [model-path] [low-fps] [source-time-scale] [max-frames] [burst-fps] [compute-units]\n", stderr)
                exit(2)
            }

            let modelPath = args.count > 1 && !args[1].isEmpty ? args[1] : "SwingCoach/MLModels/SwingObjectsYOLO11n.mlpackage"
            let lowFPS = args.count > 2 ? Double(args[2]) ?? 8.0 : 8.0
            let sourceTimeScale = args.count > 3 ? Double(args[3]) ?? 1.0 : 1.0
            let maxFrames = args.count > 4 ? Int(args[4]) ?? 200_000 : 200_000
            let burstFPS = args.count > 5 ? Double(args[5]) ?? 16.0 : 16.0
            let computeUnits = args.count > 6 ? computeUnits(named: args[6]) : .all

            let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            guard durationSeconds.isFinite, durationSeconds > 0 else { throw EvaluationErrorV2.invalidDuration }

            let result = try await run(
                asset: asset,
                videoPath: videoPath,
                modelPath: modelPath,
                durationSeconds: durationSeconds,
                lowFPS: lowFPS,
                burstFPS: burstFPS,
                sourceTimeScale: sourceTimeScale,
                maxFrames: maxFrames,
                computeUnits: computeUnits
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(result))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            fputs("swing detector v2 evaluation failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run(
        asset: AVAsset,
        videoPath: String,
        modelPath: String,
        durationSeconds: Double,
        lowFPS: Double,
        burstFPS: Double,
        sourceTimeScale: Double,
        maxFrames: Int,
        computeUnits: MLComputeUnits
    ) async throws -> V2Output {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw EvaluationErrorV2.noVideoTrack
        }

        let transform = try await videoTrack.load(.preferredTransform)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let orientation = orientation(for: transform)
        let orientedSize = orientedSize(naturalSize: naturalSize, orientation: orientation)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw EvaluationErrorV2.readerSetupFailed }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? EvaluationErrorV2.readerSetupFailed }

        let configuration = SwingDetectorV2Configuration.live(
            sourceTimeScale: sourceTimeScale,
            lowSampleFPS: lowFPS,
            burstSampleFPS: burstFPS
        )
        let detector = SwingDetectorV2(
            configuration: configuration,
            modelURL: URL(fileURLWithPath: modelPath),
            computeUnits: computeUnits
        )
        detector.reset(enabled: true)
        let startupSnapshot = detector.currentSnapshot()
        if startupSnapshot.status == .unavailable {
            throw EvaluationErrorV2.modelUnavailable(startupSnapshot.detailMessage)
        }

        var firstSampleTime: CMTime?
        var lastSubmittedSourceTime = -Double.greatestFiniteMagnitude
        var lastSourceTime = 0.0
        var decodedFrames = 0
        let startedAt = Date()

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            decodedFrames += 1
            if decodedFrames > maxFrames { break }

            let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if firstSampleTime == nil { firstSampleTime = sampleTime }
            guard let firstSampleTime else { continue }
            let sourceTime = CMTimeGetSeconds(CMTimeSubtract(sampleTime, firstSampleTime))
            guard sourceTime.isFinite else { continue }

            let sampleInterval = detector.currentSampleInterval(recordingTime: sourceTime)
            guard sourceTime - lastSubmittedSourceTime + 0.001 >= sampleInterval else { continue }
            lastSubmittedSourceTime = sourceTime
            lastSourceTime = sourceTime

            _ = detector.process(
                sampleBuffer: sampleBuffer,
                recordingTime: sourceTime,
                orientation: orientation,
                orientedImageSize: orientedSize
            )
        }

        if reader.status == .failed { throw reader.error ?? EvaluationErrorV2.readerSetupFailed }

        let detections = detector.finish(recordingTime: lastSourceTime)
        if decodedFrames > 0, detector.processedFrames == 0 {
            let snapshot = detector.currentSnapshot()
            if snapshot.status == .unavailable {
                throw EvaluationErrorV2.modelUnavailable(snapshot.detailMessage)
            }
            throw EvaluationErrorV2.noProcessedFrames
        }
        let elapsed = Date().timeIntervalSince(startedAt)

        return V2Output(
            video: videoPath,
            model: modelPath,
            computeUnits: computeUnitsDescription(computeUnits),
            configuration: detector.configurationName,
            duration: durationSeconds,
            sourceTimeScale: sourceTimeScale,
            lowSampleFPS: lowFPS,
            burstSampleFPS: burstFPS,
            decodedFrames: decodedFrames,
            processedFrames: detector.processedFrames,
            averageProcessingTimeMS: detector.averageProcessingMS,
            wallClockElapsedSeconds: elapsed,
            detections: detections.map { detection in
                V2DetectionOut(
                    start: CMTimeGetSeconds(detection.startTime),
                    end: CMTimeGetSeconds(detection.endTime),
                    impactTime: detection.impactTime,
                    confidence: detection.confidence,
                    declaredAt: detection.declaredAt
                )
            },
            traces: detector.currentTraces(),
            sampling: detector.currentSamplingTrace()
        )
    }

    private static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let epsilon = 0.001
        func equals(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool { abs(lhs - rhs) < epsilon }
        if equals(transform.a, 0), equals(transform.b, 1), equals(transform.c, -1), equals(transform.d, 0) { return .right }
        if equals(transform.a, 0), equals(transform.b, -1), equals(transform.c, 1), equals(transform.d, 0) { return .left }
        if equals(transform.a, -1), equals(transform.d, -1) { return .down }
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

    private static func computeUnits(named value: String) -> MLComputeUnits {
        switch value.lowercased() {
        case "cpu", "cpuonly": return .cpuOnly
        case "cpuandgpu", "cpu+gpu", "gpu": return .cpuAndGPU
        case "cpuandneuralengine", "cpu+ne", "ne", "neuralengine": return .cpuAndNeuralEngine
        default: return .all
        }
    }

    private static func computeUnitsDescription(_ computeUnits: MLComputeUnits) -> String {
        switch computeUnits {
        case .cpuOnly: return "cpuOnly"
        case .cpuAndGPU: return "cpuAndGPU"
        case .cpuAndNeuralEngine: return "cpuAndNeuralEngine"
        case .all: return "all"
        @unknown default: return "unknown"
        }
    }
}
