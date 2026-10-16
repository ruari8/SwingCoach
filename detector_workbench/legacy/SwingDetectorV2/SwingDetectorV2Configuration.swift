//
//  SwingDetectorV2Configuration.swift
//  SwingCoach
//
//  Tunables for the v2 swing detector. All durations are expressed in REAL
//  swing-time (seconds of wall-clock golfer motion). The source video may be a
//  slow-motion export, so `sourceTimeScale` maps between the two timelines:
//
//      realTime   = sourceTime / sourceTimeScale
//      sourceTime = realTime   * sourceTimeScale
//
//  The state machine and every component run entirely in real-time seconds.
//  Only inputs (incoming timestamps) and outputs (DetectedSwing ranges) are
//  converted to/from the source timeline.
//

import Foundation

nonisolated struct SwingDetectorV2Configuration: Equatable {
    var name: String

    /// Playback-vs-real-time scale of the source. 1.0 = real-time camera,
    /// 8.0 = 240fps captured exported at 8x slow motion, 4.0 = 120fps @ 4x.
    var sourceTimeScale: Double
    /// Accept club-motion-only swing sequences when no ball departs. This is
    /// intended for explicit practice/testing sessions and is off by default.
    var allowsPracticeSwings: Bool

    // MARK: Sampling (real-time fps)

    /// Sampling rate while idle or merely addressed (cheap, most of the time).
    var lowSampleFPS: Double
    /// Sampling rate during an armed swing burst (downswing -> follow-through).
    var burstSampleFPS: Double
    /// Sample at burst rate immediately after recording starts. Startup clips
    /// may begin already addressed or mid-swing, before address can mature.
    var startupBurstDuration: Double
    /// Maximum real-time seconds a high-rate burst may run before decaying.
    var burstMaxDuration: Double
    /// Recent real-time window used for state-machine club evidence. This must
    /// stay local; long-session history should not make current waggles look
    /// like a swing.
    var clubEvidenceWindowDuration: Double

    // MARK: State timing (real seconds)

    /// Maximum time to wait for impact after a swing has been armed.
    var swingTimeout: Double
    /// Extended timeout for slow-tempo/drill swings where the ball remains
    /// present and strong swing evidence is still active.
    var extendedSwingTimeout: Double
    /// Minimum post-departure confirmation time before scoring a candidate.
    var impactConfirmationDuration: Double
    /// Minimum absent samples after a sweep before scoring a candidate.
    var minDepartureAbsentSamples: Int

    // MARK: Scoring

    var scorer: SwingScorer

    // MARK: Window padding (real seconds, mapped to source on output)

    var impactPreRoll: Double
    var impactPostRoll: Double

    /// Minimum real-time gap between two accepted impacts. De-duplication is by
    /// time only, never by screen location.
    var minImpactGap: Double

    var lowSampleInterval: Double { lowSampleFPS > 0 ? 1.0 / lowSampleFPS : .greatestFiniteMagnitude }
    var burstSampleInterval: Double { burstSampleFPS > 0 ? 1.0 / burstSampleFPS : .greatestFiniteMagnitude }

    /// Convert a real-time interval to the source timeline the evaluator/camera
    /// timestamps live in.
    func sourceInterval(forRealInterval realInterval: Double) -> Double {
        realInterval * sourceTimeScale
    }

    func realTime(fromSource sourceTime: Double) -> Double {
        guard sourceTimeScale > 0 else { return sourceTime }
        return sourceTime / sourceTimeScale
    }

    func sourceTime(fromReal realTime: Double) -> Double {
        realTime * sourceTimeScale
    }

    static func live(
        sourceTimeScale: Double = 1.0,
        lowSampleFPS: Double = 8.0,
        burstSampleFPS: Double = 16.0,
        allowsPracticeSwings: Bool = false
    ) -> SwingDetectorV2Configuration {
        let clampedScale = min(12.0, max(1.0, sourceTimeScale))
        let clampedLow = min(24.0, max(1.0, lowSampleFPS))
        let clampedBurst = min(24.0, max(clampedLow, burstSampleFPS))
        return SwingDetectorV2Configuration(
            name: "v2 \(formatted(clampedLow))->\(formatted(clampedBurst))fps / \(formatted(clampedScale))x",
            sourceTimeScale: clampedScale,
            allowsPracticeSwings: allowsPracticeSwings,
            lowSampleFPS: clampedLow,
            burstSampleFPS: clampedBurst,
            startupBurstDuration: 2.0,
            burstMaxDuration: 1.5,
            clubEvidenceWindowDuration: 1.6,
            swingTimeout: 2.2,
            extendedSwingTimeout: 4.0,
            impactConfirmationDuration: 0.55,
            minDepartureAbsentSamples: 5,
            scorer: SwingScorer(),
            impactPreRoll: 1.6,
            impactPostRoll: 0.8,
            minImpactGap: 1.5
        )
    }

    private static func formatted(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}
