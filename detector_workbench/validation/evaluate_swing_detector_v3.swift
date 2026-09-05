//
//  evaluate_swing_detector_v3.swift
//
//  Offline evaluator for SwingDetectorV3. Reads a video, drives the V3 core, and
//  emits JSON with accepted swings AND the full per-candidate debug traces.
//
//  Unlike the legacy evaluator, it passes SOURCE timestamps straight through:
//  SwingDetectorV3 converts to/from real-time via its configuration's
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
//      SwingCoach/Models/SwingDetectorV3/*.swift \
//      detector_workbench/validation/evaluate_swing_detector_v3.swift \
//      -o .videos/bin/evaluate_swing_detector_v3
//

import AVFoundation
import CoreGraphics
import CoreMedia
import CoreML
import CoreVideo
import Foundation

private struct V3DetectionOut: Encodable {
    let start: Double
    let end: Double
    let impactTime: Double?
    let confidence: Double
    let declaredAt: Double?
}

private struct V3Output: Encodable {
    let video: String
    let model: String
    let computeUnits: String
    let configuration: String
    let duration: Double
    let segmentStart: Double
    let segmentEnd: Double
    let sourceTimeScale: Double
    let allowsPracticeSwings: Bool
    let lowSampleFPS: Double
    let burstSampleFPS: Double
    let decodedFrames: Int
    let processedFrames: Int
    let averageProcessingTimeMS: Double
    let wallClockElapsedSeconds: Double
    let sampleReadSeconds: Double
    let sampleProcessingSeconds: Double
    let modelSetupSeconds: Double
    let detections: [V3DetectionOut]
    let traces: [SwingCandidateTrace]
    let sampling: [SwingSamplingTrace]
    let observations: [FrameObservationTraceV3]
    let decisions: [SwingDecisionTraceV3]
}

private enum EvaluationErrorV3: Error {
    case invalidDuration
    case noVideoTrack
    case readerSetupFailed
    case modelUnavailable(String)
    case noProcessedFrames
}

@main
struct EvaluateSwingDetectorV3 {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            let allowsPracticeSwings = arguments.contains("--practice-swings")
            let args = arguments.filter { $0 != "--practice-swings" }
            guard let videoPath = args.first else {
                fputs("usage: evaluate_swing_detector_v3 <video-path> [model-path] [low-fps] [source-time-scale] [max-frames] [burst-fps] [compute-units] [segment-start] [segment-end] [--practice-swings]\n", stderr)
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
            guard durationSeconds.isFinite, durationSeconds > 0 else { throw EvaluationErrorV3.invalidDuration }
            let segmentStart = args.count > 7 ? Double(args[7]) ?? 0 : 0
            let segmentEnd = args.count > 8 ? Double(args[8]) ?? durationSeconds : durationSeconds
            guard segmentStart >= 0, segmentEnd > segmentStart, segmentEnd <= durationSeconds + 0.05 else {
                throw EvaluationErrorV3.invalidDuration
            }

            let result = try await run(
                asset: asset,
                videoPath: videoPath,
                modelPath: modelPath,
                segmentStart: segmentStart,
                segmentEnd: min(segmentEnd, durationSeconds),
                lowFPS: lowFPS,
                burstFPS: burstFPS,
                sourceTimeScale: sourceTimeScale,
                maxFrames: maxFrames,
                computeUnits: computeUnits,
                allowsPracticeSwings: allowsPracticeSwings
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(result))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            fputs("swing detector V3 evaluation failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run(
        asset: AVAsset,
        videoPath: String,
        modelPath: String,
        segmentStart: Double,
        segmentEnd: Double,
        lowFPS: Double,
        burstFPS: Double,
        sourceTimeScale: Double,
        maxFrames: Int,
        computeUnits: MLComputeUnits,
        allowsPracticeSwings: Bool
    ) async throws -> V3Output {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw EvaluationErrorV3.noVideoTrack
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
        guard reader.canAdd(output) else { throw EvaluationErrorV3.readerSetupFailed }
        reader.add(output)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: segmentStart, preferredTimescale: 2_400),
            duration: CMTime(seconds: segmentEnd - segmentStart, preferredTimescale: 2_400)
        )
        guard reader.startReading() else { throw reader.error ?? EvaluationErrorV3.readerSetupFailed }

        let modelStartedAt = Date()
        let configuration = SwingDetectorV3Configuration.live(
            sourceTimeScale: sourceTimeScale,
            lowSampleFPS: lowFPS,
            burstSampleFPS: burstFPS,
            allowsPracticeSwings: allowsPracticeSwings,
            recordsDebugTrace: true
        )
        let detector = SwingDetectorV3(
            configuration: configuration,
            modelURL: URL(fileURLWithPath: modelPath),
            computeUnits: computeUnits
        )
        detector.reset(enabled: true)
        let startupSnapshot = detector.currentSnapshot()
        if startupSnapshot.status == .unavailable {
            throw EvaluationErrorV3.modelUnavailable(startupSnapshot.detailMessage)
        }

        let modelSetupSeconds = Date().timeIntervalSince(modelStartedAt)
        var sampleReadSeconds = 0.0
        var sampleProcessingSeconds = 0.0
        var firstSampleTime: CMTime?
        var lastSubmittedSourceTime = -Double.greatestFiniteMagnitude
        var lastSourceTime = 0.0
        var decodedFrames = 0
        let startedAt = Date()

        while reader.status == .reading {
            let readStartedAt = Date()
            let nextSample = output.copyNextSampleBuffer()
            sampleReadSeconds += Date().timeIntervalSince(readStartedAt)
            guard let sampleBuffer = nextSample else { break }
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

            let processingStartedAt = Date()
            _ = detector.process(
                sampleBuffer: sampleBuffer,
                recordingTime: sourceTime,
                orientation: orientation,
                orientedImageSize: orientedSize
            )
            sampleProcessingSeconds += Date().timeIntervalSince(processingStartedAt)
        }

        if reader.status == .failed { throw reader.error ?? EvaluationErrorV3.readerSetupFailed }

        let detections = detector.finish(recordingTime: lastSourceTime)
        if decodedFrames > 0, detector.processedFrames == 0 {
            let snapshot = detector.currentSnapshot()
            if snapshot.status == .unavailable {
                throw EvaluationErrorV3.modelUnavailable(snapshot.detailMessage)
            }
            throw EvaluationErrorV3.noProcessedFrames
        }
        let elapsed = Date().timeIntervalSince(startedAt)
        let sourceOffset = firstSampleTime.map(CMTimeGetSeconds) ?? segmentStart

        return V3Output(
            video: videoPath,
            model: modelPath,
            computeUnits: computeUnitsDescription(computeUnits),
            configuration: detector.configurationName,
            duration: segmentEnd - segmentStart,
            segmentStart: sourceOffset,
            segmentEnd: segmentEnd,
            sourceTimeScale: sourceTimeScale,
            allowsPracticeSwings: allowsPracticeSwings,
            lowSampleFPS: lowFPS,
            burstSampleFPS: burstFPS,
            decodedFrames: decodedFrames,
            processedFrames: detector.processedFrames,
            averageProcessingTimeMS: detector.averageProcessingMS,
            wallClockElapsedSeconds: elapsed,
            sampleReadSeconds: sampleReadSeconds,
            sampleProcessingSeconds: sampleProcessingSeconds,
            modelSetupSeconds: modelSetupSeconds,
            detections: detections.map { detection in
                V3DetectionOut(
                    start: CMTimeGetSeconds(detection.startTime) + sourceOffset,
                    end: CMTimeGetSeconds(detection.endTime) + sourceOffset,
                    impactTime: detection.impactTime.map { $0 + sourceOffset },
                    confidence: detection.confidence,
                    declaredAt: detection.declaredAt.map { $0 + sourceOffset }
                )
            },
            traces: detector.currentTraces(),
            sampling: detector.currentSamplingTrace(),
            observations: detector.currentObservationTrace(),
            decisions: detector.currentDecisionTrace()
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
