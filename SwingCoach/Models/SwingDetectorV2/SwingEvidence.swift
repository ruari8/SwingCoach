//
//  SwingEvidence.swift
//  SwingCoach
//
//  The flat evidence vector and the single scorer that replace the legacy
//  detector's tangle of interacting boolean OR-branches.
//
//  Rule: every component emits CONTINUOUS scores in [0, 1]. Only the scorer
//  thresholds. Missing corroborators (audio/pose) are NEUTRAL — excluded from
//  the weighted average, not scored as zero — so a silent clip is not penalised
//  for evidence it could never produce.
//

import Foundation

nonisolated struct EvidenceVector: Encodable, Equatable {
    /// How cleanly the addressed ball was locked and stationary at address.
    var anchorStability: Double
    /// Ball gone from the locked patch AND stayed gone after the club left it.
    var disappearancePersistence: Double
    /// Club passed through / very near the patch at strike speed.
    var clubSweptThrough: Double
    /// Takeaway + downswing + follow-through shape and path span.
    var swingArc: Double
    /// Sharp audio transient near candidate impact. nil when audio unavailable.
    var audioTransient: Double?
    /// Primary golfer present with plausible address->finish change. nil when pose unavailable.
    var poseConsistency: Double?

    static let zero = EvidenceVector(
        anchorStability: 0,
        disappearancePersistence: 0,
        clubSweptThrough: 0,
        swingArc: 0,
        audioTransient: nil,
        poseConsistency: nil
    )
}

nonisolated struct SwingScorer: Equatable {
    var weightAnchorStability = 0.22
    var weightDisappearancePersistence = 0.26
    var weightClubSweptThrough = 0.34
    var weightSwingArc = 0.10
    var weightAudioTransient = 0.04
    var weightPoseConsistency = 0.04

    /// Single operating threshold. Strictness is this one knob, not dozens of
    /// interacting gates.
    var threshold = 0.74

    /// Weighted average over the evidence that is actually present. Audio and
    /// pose drop out of both numerator and denominator when nil.
    func score(_ evidence: EvidenceVector) -> Double {
        var numerator = 0.0
        var denominator = 0.0

        func add(_ value: Double?, _ weight: Double) {
            guard let value else { return }
            numerator += weight * value
            denominator += weight
        }

        add(evidence.anchorStability, weightAnchorStability)
        add(evidence.disappearancePersistence, weightDisappearancePersistence)
        add(evidence.clubSweptThrough, weightClubSweptThrough)
        add(evidence.swingArc, weightSwingArc)
        add(evidence.audioTransient, weightAudioTransient)
        add(evidence.poseConsistency, weightPoseConsistency)

        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }

    func accepts(_ evidence: EvidenceVector) -> Bool {
        score(evidence) >= threshold
    }
}
