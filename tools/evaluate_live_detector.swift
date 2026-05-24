import AVFoundation
import CoreMedia
import Darwin
import Foundation
import ImageIO
import Vision

private struct DetectionOutput: Encodable {
    let start: Double
    let end: Double
    let confidence: Double
}

private struct EvaluationOutput: Encodable {
    let video: String
    let duration: Double
    let detections: [DetectionOutput]
}

@main
struct EvaluateLiveDetector {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let videoPath = arguments.first else {
                fputs("usage: evaluate_live_detector <video-path> [sample-interval] [max-frames]\n", stderr)
                exit(2)
            }

            let sampleInterval = arguments.count > 1 ? Double(arguments[1]) ?? 0.08 : 0.08
            let maxFrames = arguments.count > 2 ? Int(arguments[2]) ?? 2_000 : 2_000
            let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            guard durationSeconds.isFinite, durationSeconds > 0 else {
                throw EvaluationError.invalidDuration
            }

            let detections = try await detectSwings(
                in: asset,
                durationSeconds: durationSeconds,
                sampleInterval: max(sampleInterval, durationSeconds / Double(max(12, maxFrames)))
            )
            let output = EvaluationOutput(
                video: videoPath,
                duration: durationSeconds,
                detections: detections.map {
                    DetectionOutput(
                        start: CMTimeGetSeconds($0.startTime),
                        end: CMTimeGetSeconds($0.endTime),
                        confidence: $0.confidence
                    )
                }
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(output))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            fputs("live detector evaluation failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func detectSwings(
        in asset: AVAsset,
        durationSeconds: Double,
        sampleInterval: Double
    ) async throws -> [DetectedSwing] {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw EvaluationError.noVideoTrack
        }

        let transform = try await videoTrack.load(.preferredTransform)
        let orientation = orientation(for: transform)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
        )
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw EvaluationError.readerSetupFailed
        }
        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? EvaluationError.readerSetupFailed
        }

        let detector = LiveSwingDetector()
        let request = VNDetectHumanBodyPoseRequest()
        var lastProcessedTime = -Double.greatestFiniteMagnitude
        var lastSampleTime: Double?

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()

            let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            guard time.isFinite, time - lastProcessedTime >= sampleInterval else { continue }
            lastProcessedTime = time
            lastSampleTime = time

            let observations = try poseObservations(
                from: sampleBuffer,
                orientation: orientation,
                request: request
            )
            _ = detector.process(
                sampleBuffer: sampleBuffer,
                observations: observations,
                recordingTime: time
            )
        }

        if reader.status == .failed {
            throw reader.error ?? EvaluationError.readerSetupFailed
        }

        return detector.finish(recordingTime: lastSampleTime ?? durationSeconds)
    }

    private static func poseObservations(
        from sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation,
        request: VNDetectHumanBodyPoseRequest
    ) throws -> [VNHumanBodyPoseObservation] {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: orientation, options: [:])
        try handler.perform([request])
        return request.results ?? []
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

private enum EvaluationError: Error {
    case invalidDuration
    case noVideoTrack
    case readerSetupFailed
}
