import Foundation
import AVFoundation

@main struct TrimPlaybackClockProbe {
    @MainActor static func main() async throws {
        let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        for _ in 0..<50 where player.currentItem?.status != .readyToPlay {
            try await Task.sleep(for: .milliseconds(50))
        }
        var times: [Double] = []
        let interval = CommandLine.arguments.contains("--legacy-interval")
            ? CMTime(seconds: 0.1, preferredTimescale: 600)
            : TrimTimecode.observationInterval(playbackRate: 0.125)
        let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            times.append(time.seconds * 8)
        }
        player.playImmediately(atRate: 0.125)
        try await Task.sleep(for: .seconds(2.5))
        player.pause()
        player.removeTimeObserver(token)
        let gaps = zip(times, times.dropFirst()).map { $1 - $0 }.filter { $0 > 0.01 }
        print("DISPLAYED CLOCK", times.map { String(format: "%.2f", $0) }.joined(separator: ", "))
        print("MAX JUMP", gaps.max() ?? -1, "UPDATES", gaps.count)
        guard gaps.count >= 15, (gaps.max() ?? 100) < 0.25 else { exit(1) }
    }
}
