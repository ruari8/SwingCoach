import Foundation

/// Runtime budgets and physical timing for SwingDetectorV3. Durations are real
/// movement seconds; exported slow-motion timestamps are converted at the edge.
nonisolated struct SwingDetectorV3Configuration: Equatable {
    var name: String
    var sourceTimeScale: Double
    var allowsPracticeSwings: Bool
    var recordsDebugTrace: Bool
    var lowSampleFPS: Double
    var burstSampleFPS: Double
    var startupBurstDuration: Double
    var burstMaxDuration: Double
    var clubEvidenceWindowDuration: Double
    var swingTimeout: Double
    var extendedSwingTimeout: Double
    var impactConfirmationDuration: Double
    var minDepartureAbsentSamples: Int
    var scorer: SwingScorer
    var impactPreRoll: Double
    var impactPostRoll: Double
    var minImpactGap: Double

    var lowSampleInterval: Double { lowSampleFPS > 0 ? 1 / lowSampleFPS : .greatestFiniteMagnitude }
    var burstSampleInterval: Double { burstSampleFPS > 0 ? 1 / burstSampleFPS : .greatestFiniteMagnitude }

    func sourceInterval(forRealInterval value: Double) -> Double { value * sourceTimeScale }
    func realTime(fromSource value: Double) -> Double { sourceTimeScale > 0 ? value / sourceTimeScale : value }
    func sourceTime(fromReal value: Double) -> Double { value * sourceTimeScale }

    static func live(
        sourceTimeScale: Double = 1,
        lowSampleFPS: Double = 8,
        burstSampleFPS: Double = 16,
        allowsPracticeSwings: Bool = false,
        recordsDebugTrace: Bool = false
    ) -> Self {
        let scale = min(12, max(1, sourceTimeScale))
        let low = min(24, max(1, lowSampleFPS))
        let burst = min(24, max(low, burstSampleFPS))
        return Self(
            name: "v3 \(format(low))->\(format(burst))fps / \(format(scale))x",
            sourceTimeScale: scale,
            allowsPracticeSwings: allowsPracticeSwings,
            recordsDebugTrace: recordsDebugTrace,
            lowSampleFPS: low,
            burstSampleFPS: burst,
            startupBurstDuration: 2,
            burstMaxDuration: 1.5,
            clubEvidenceWindowDuration: 1.6,
            swingTimeout: 2.2,
            extendedSwingTimeout: 4,
            impactConfirmationDuration: 0.55,
            minDepartureAbsentSamples: 5,
            scorer: SwingScorer(),
            impactPreRoll: 1.6,
            impactPostRoll: 0.8,
            minImpactGap: 1.5
        )
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}
