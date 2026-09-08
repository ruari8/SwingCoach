import Foundation
import CoreMedia

/// Extra real movement time around an accepted detection, independent of scoring.
nonisolated struct SwingClipContext: Equatable, Sendable {
    static let beforeKey = "capture.extraSecondsBeforeSwing"
    static let afterKey = "capture.extraSecondsAfterSwing"
    static let maximumSeconds = 30.0

    let before: Double
    let after: Double

    init(before: Double = 0, after: Double = 0) {
        self.before = Self.validSeconds(before)
        self.after = Self.validSeconds(after)
    }

    static func validSeconds(_ value: Double) -> Double {
        value.isFinite ? min(maximumSeconds, max(0, value)) : 0
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(before: defaults.double(forKey: beforeKey), after: defaults.double(forKey: afterKey))
    }

    func range(for detection: DetectedSwing, sourceTimeScale: Double = 1) -> CMTimeRange {
        let start = max(0, detection.startTime.seconds - before * sourceTimeScale)
        let end = detection.endTime.seconds + after * sourceTimeScale
        return CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                           end: CMTime(seconds: end, preferredTimescale: 600))
    }
}
