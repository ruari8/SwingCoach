//
//  SwingTempo.swift
//  SwingCoach
//
//  Backswing time, downswing time, and their ratio for a down-the-line swing,
//  plus the session-level tempo trend.
//
//  Takeaway start is the first sustained club movement after P1 (address), not
//  P1 itself, found from the club track between P1 and P2 and stored on
//  `SwingPositions.takeawayStartClipTime`. Times are converted from the clip's
//  slow-motion timeline to real milliseconds using the capture's real time
//  scale (e.g. 8 for 240 fps exported at 30 fps, 4 for 120 fps at 30 fps).
//

import Foundation

/// Tempo measurements for one down-the-line swing, in real time.
nonisolated struct SwingTempo: Codable, Equatable {
    /// Real-time backswing duration in milliseconds: takeaway start to top (P4).
    let backswingMilliseconds: Double
    /// Real-time downswing duration in milliseconds: top (P4) to impact (P7).
    let downswingMilliseconds: Double
    /// True when P1, P4, or P7 had low model confidence (< `SwingPosition.lowConfidence`).
    let isLowConfidence: Bool
    /// Clip time of takeaway start (first movement after P1), on the clip's timeline.
    let takeawayStartClipTime: Double

    /// Backswing divided by downswing (tour swings are often near 3.0:1).
    var ratio: Double { backswingMilliseconds / downswingMilliseconds }

    /// Total time from takeaway start to impact, in milliseconds.
    var totalMilliseconds: Double { backswingMilliseconds + downswingMilliseconds }

    /// Share of the swing spent in the backswing, 0...1.
    var backswingShare: Double { totalMilliseconds > 0 ? backswingMilliseconds / totalMilliseconds : 0 }

    /// Rounded whole milliseconds for display.
    var backswingMS: Int { Int(backswingMilliseconds.rounded()) }
    var downswingMS: Int { Int(downswingMilliseconds.rounded()) }

    /// Ratio to one decimal ("2.8:1").
    var ratioText: String { String(format: "%.1f:1", ratio) }
    var backswingText: String { "\(backswingMS) ms" }
    var downswingText: String { "\(downswingMS) ms" }
    /// Compact one-line summary ("2.8:1 · 731 / 272 ms").
    var summaryText: String { "\(ratioText) · \(backswingMS) / \(downswingMS) ms" }

    /// Tour reference ratio shown as a neutral guide line in the session chart.
    static let referenceRatio: Double = 3.0

    /// Measures tempo from stored positions and the clip's slow-motion time scale
    /// (how many times slower than real time the clip plays: 8 for 240 fps at 30 fps,
    /// 4 for 120 fps at 30 fps, 1 for real-time 30 fps).
    ///
    /// Returns nil when `timeScale` is missing/non-positive, when P1, P4, P7, or
    /// `takeawayStartClipTime` is missing, or when the times are not strictly ordered
    /// (`P1 < takeawayStart < P4 < P7`). Never assumes a frame rate or invents a number.
    static func measure(positions: SwingPositions, timeScale: Double) -> SwingTempo? {
        guard timeScale.isFinite, timeScale > 0,
              let takeawayStart = positions.takeawayStartClipTime,
              takeawayStart.isFinite
        else { return nil }

        guard let p1 = positions.positions.first(where: { $0.number == 1 }),
              let p4 = positions.positions.first(where: { $0.number == 4 }),
              let p7 = positions.positions.first(where: { $0.number == 7 })
        else { return nil }

        guard p1.clipTime.isFinite, p4.clipTime.isFinite, p7.clipTime.isFinite,
              takeawayStart > p1.clipTime,
              p4.clipTime > takeawayStart,
              p7.clipTime > p4.clipTime
        else { return nil }

        let backswingMs = (p4.clipTime - takeawayStart) / timeScale * 1000.0
        let downswingMs = (p7.clipTime - p4.clipTime) / timeScale * 1000.0
        guard backswingMs.isFinite, downswingMs.isFinite, backswingMs > 0, downswingMs > 0 else {
            return nil
        }

        let lowConfidence = p1.isLowConfidence || p4.isLowConfidence || p7.isLowConfidence
        return SwingTempo(
            backswingMilliseconds: backswingMs,
            downswingMilliseconds: downswingMs,
            isLowConfidence: lowConfidence,
            takeawayStartClipTime: takeawayStart
        )
    }

    /// Convenience overload from capture frame rate and clip playback frame rate
    /// (e.g. `sourceFPS: 240, playbackFPS: 30` -> time scale 8;
    /// `sourceFPS: 120, playbackFPS: 30` -> time scale 4).
    static func measure(
        positions: SwingPositions,
        sourceFPS: Double,
        playbackFPS: Double = 30.0
    ) -> SwingTempo? {
        guard sourceFPS.isFinite, sourceFPS > 0, playbackFPS.isFinite, playbackFPS > 0 else {
            return nil
        }
        return measure(positions: positions, timeScale: sourceFPS / playbackFPS)
    }
}

/// Session-level tempo summary and swing-by-swing trend (oldest swing first).
nonisolated struct SwingTempoTrend: Equatable {
    struct Sample: Equatable, Identifiable {
        /// 1-based position among the session's swings (oldest first).
        let swingNumber: Int
        let swingID: UUID
        let tempo: SwingTempo

        var id: UUID { swingID }
    }

    enum Direction: Equatable {
        case steady
        /// Ratio rose in the second half of the session (longer backswing relative to downswing).
        case slowerBackswing
        /// Ratio fell in the second half of the session (quicker backswing relative to downswing).
        case quickerBackswing

        var label: String {
            switch self {
            case .steady: "Steady"
            case .slowerBackswing: "Longer backswing"
            case .quickerBackswing: "Quicker backswing"
            }
        }
    }

    /// Confident, non-excluded full-swing tempos in chronological order.
    let samples: [Sample]
    /// Total swings in the session, for x-axis positioning.
    let totalSwings: Int

    /// Minimum samples needed to draw a trend line.
    static let minimumTrendSamples = 2
    /// Minimum samples needed to call a first-half vs second-half direction.
    static let minimumDirectionSamples = 4
    /// Minimum ratio shift between the first and second half to leave "Steady".
    static let directionThreshold = 0.2

    var medianRatio: Double? { Self.median(samples.map(\.tempo.ratio)) }
    var medianBackswingMilliseconds: Double? { Self.median(samples.map(\.tempo.backswingMilliseconds)) }
    var medianDownswingMilliseconds: Double? { Self.median(samples.map(\.tempo.downswingMilliseconds)) }

    var medianRatioText: String? { medianRatio.map { String(format: "%.1f:1", $0) } }
    var medianBackswingMS: Int? { medianBackswingMilliseconds.map { Int($0.rounded()) } }
    var medianDownswingMS: Int? { medianDownswingMilliseconds.map { Int($0.rounded()) } }

    /// Compact summary of the session's median times ("731 / 272 ms").
    var medianTimesText: String? {
        guard let back = medianBackswingMS, let down = medianDownswingMS else { return nil }
        return "\(back) / \(down) ms"
    }

    /// Compact one-line summary for a recap ("2.8:1 · 731 / 272 ms").
    var summaryText: String? {
        guard let ratio = medianRatioText, let times = medianTimesText else { return nil }
        return "\(ratio) · \(times)"
    }

    /// Compares the median ratio of the first half of samples against the second half.
    var direction: Direction? {
        guard samples.count >= Self.minimumDirectionSamples else { return nil }
        let half = samples.count / 2
        guard let early = Self.median(samples.prefix(half).map(\.tempo.ratio)),
              let late = Self.median(samples.suffix(half).map(\.tempo.ratio))
        else { return nil }
        let delta = late - early
        if delta >= Self.directionThreshold { return .slowerBackswing }
        if delta <= -Self.directionThreshold { return .quickerBackswing }
        return .steady
    }

    /// Builds a trend from chronologically ordered swings. Drops swings with missing
    /// tempo, low-confidence tempo, or coaching exclusions (short swings, moved camera,
    /// unclear positions).
    static func build(from swings: [(id: UUID, tempo: SwingTempo?, excluded: Bool)]) -> SwingTempoTrend {
        let samples: [Sample] = swings.enumerated().compactMap { index, entry in
            guard !entry.excluded, let tempo = entry.tempo, !tempo.isLowConfidence else { return nil }
            return Sample(swingNumber: index + 1, swingID: entry.id, tempo: tempo)
        }
        return SwingTempoTrend(samples: samples, totalSwings: swings.count)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}
