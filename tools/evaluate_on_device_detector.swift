import AVFoundation
import CoreMedia
import Darwin
import Foundation

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
struct EvaluateOnDeviceDetector {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let videoPath = arguments.first else {
                fputs("usage: evaluate_on_device_detector <video-path> [sample-interval] [max-frames] [confidence-threshold] [peak-threshold] [motion-threshold]\n", stderr)
                exit(2)
            }

            let sampleInterval = arguments.count > 1 ? Double(arguments[1]) ?? 0.12 : 0.12
            let maxFrames = arguments.count > 2 ? Int(arguments[2]) ?? 900 : 900
            let confidenceThreshold = arguments.count > 3 ? Double(arguments[3]) ?? 0.50 : 0.50
            let peakThreshold = arguments.count > 4 ? Double(arguments[4]) ?? 1.65 : 1.65
            let motionThreshold = arguments.count > 5 ? Double(arguments[5]) ?? 0.85 : 0.85
            let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)

            let detector = OnDeviceSwingDetector(
                targetSampleInterval: sampleInterval,
                maxProcessedFrames: maxFrames,
                peakSpeedThreshold: peakThreshold,
                motionThreshold: motionThreshold,
                confidenceThreshold: confidenceThreshold
            )
            let detections = try await detector.detectSwings(in: asset)
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
            fputs("detector evaluation failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
