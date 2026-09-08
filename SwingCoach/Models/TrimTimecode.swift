import Foundation
import CoreMedia

/// Trim previews fresh high-FPS captures at their slow-motion export rate.
/// Observe at a steady wall-clock cadence, then map source time to that timeline.
nonisolated enum TrimTimecode {
    static func observationInterval(playbackRate: Float) -> CMTime {
        CMTime(seconds: 0.1 * Double(playbackRate), preferredTimescale: 60000)
    }

    static func format(_ time: CMTime, scale: Double = 1) -> String {
        guard time.isNumeric, time >= .zero else { return "00.0" }
        let tenths = CMTimeConvertScale(CMTimeMultiplyByFloat64(time, multiplier: scale), timescale: 10, method: .roundTowardZero).value
        return String(format: "%02lld.%lld", tenths / 10, tenths % 10)
    }
}
