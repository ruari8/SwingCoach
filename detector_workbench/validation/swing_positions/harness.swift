// Runs the app's SwingPositionAnalyzer on saved clips on a Mac and prints the
// positions and timings. Writes one SwingPositions JSON per clip for parity.py.
// See docs/SWING_POSITIONS.md for the build command.
//
// Usage: harness <SwingPositionTCN.mlmodelc> <timeScale> <out-dir> <clip.mp4>...
import Foundation
import CoreML

@main
struct Harness {
    static func main() async throws {
        let args = CommandLine.arguments
        let analyzer = try SwingPositionAnalyzer(modelURL: URL(fileURLWithPath: args[1]))
        let timeScale = Double(args[2])!
        let outDir = URL(fileURLWithPath: args[3])
        for path in args.dropFirst(4) {
            let url = URL(fileURLWithPath: path)
            let (positions, timing) = try await analyzer.analyze(videoURL: url, timeScale: timeScale)
            let summary = positions.positions.map { String(format: "%@ %.2fs %.2f", $0.label, $0.clipTime, $0.confidence) }.joined(separator: " | ")
            print(url.lastPathComponent, String(format: "frames %d pose %d body %d read+pose %.2fs model %.3fs", timing.decodedFrames, timing.poseCalls, timing.bodySlots, timing.readAndPoseSeconds, timing.modelSeconds))
            print("  ", summary)
            let data = try JSONEncoder().encode(positions)
            try data.write(to: outDir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".json"))
        }
    }
}
