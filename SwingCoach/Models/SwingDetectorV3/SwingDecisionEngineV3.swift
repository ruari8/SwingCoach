//
//  SwingDecisionEngineV3.swift
//  SwingCoach
//
//  Owns swing timing and the adaptive sample rate. High-rate bursts exist only
//  while Swinging / unresolved ImpactCandidate, armed by address-lock + takeaway
//  and bounded by a hard time budget.
//
//      Idle -> Addressed -> Swinging -> ImpactCandidate -> Confirmed -> Cooldown
//
//  The machine decides WHEN an impact is ready to be scored. The driver then
//  assembles the evidence vector and runs the scorer. De-duplication is by time.
//
//  First implementation target: address -> swing -> persistent post-sweep
//  departure before scoring a candidate.
//

import Foundation

nonisolated enum ContactOutcomeV3: String, Encodable, Equatable {
    case strikeSupported
    case nonContactSupported
    case unresolved
}

nonisolated struct SwingDecisionTraceV3: Encodable, Equatable {
    let candidateID: Int
    let targetID: Int?
    let impactSourceTime: Double
    let declaredSourceTime: Double?
    let outcome: ContactOutcomeV3
    let poseStrokeMotionScore: Double?
    let score: Double
}

nonisolated enum SwingMachineStateV3: String, Equatable {
    case idle
    case addressed
    case swinging
    case impactCandidate
    case cooldown
}

nonisolated struct ResolvedSwingCandidateV3: Equatable {
    let impactRealTime: Double
    let lock: TargetLockV3?
    let swingDuration: Double
    let bestSweep: Double
    let bestArc: Double
    let bestSequence: Double
}

nonisolated final class SwingDecisionEngineV3 {
    private(set) var state: SwingMachineStateV3 = .idle
    private(set) var bestStateReached: SwingMachineStateV3 = .idle
    private var burstUntilRealTime = -Double.greatestFiniteMagnitude
    private var lastConfirmedImpactRealTime = -Double.greatestFiniteMagnitude
    private var swingStartedAt: Double?
    private var firstAbsentAt: Double?
    private var absentSampleCount = 0
    private var bestSweepDuringSwing = 0.0
    private var bestArcDuringSwing = 0.0
    private var bestSequenceDuringSwing = 0.0

    private let configuration: SwingDetectorV3Configuration

    init(configuration: SwingDetectorV3Configuration) {
        self.configuration = configuration
    }

    func reset() {
        state = .idle
        bestStateReached = .idle
        burstUntilRealTime = -Double.greatestFiniteMagnitude
        lastConfirmedImpactRealTime = -Double.greatestFiniteMagnitude
        swingStartedAt = nil
        firstAbsentAt = nil
        absentSampleCount = 0
        bestSweepDuringSwing = 0
        bestArcDuringSwing = 0
        bestSequenceDuringSwing = 0
    }

    /// Should the next sample be taken at burst rate?
    func wantsBurst(atRealTime realTime: Double) -> Bool {
        realTime <= burstUntilRealTime + 0.0001
    }

    /// Advance with the newest frame's signals; return a resolved candidate when
    /// an impact instant is ready to be scored, else nil.
    func update(
        frame: SwingObservationV3,
        lock: TargetLockV3?,
        patch: TargetRegionObservationV3?,
        club: ClubEvidenceV3
    ) -> ResolvedSwingCandidateV3? {
        let now = frame.realTime

        if state == .cooldown {
            if now - lastConfirmedImpactRealTime >= configuration.minImpactGap {
                transition(to: .idle)
            } else {
                return nil
            }
        }

        guard let lock, let patch else {
            transition(to: .idle)
            clearSwing()
            return nil
        }

        switch state {
        case .idle:
            transition(to: .addressed)
            return nil

        case .addressed:
            guard patch.isPresent else {
                return nil
            }

            if shouldStartSwing(club: club, frame: frame) {
                transition(to: .swinging)
                swingStartedAt = now
                burstUntilRealTime = now + configuration.burstMaxDuration
                bestSweepDuringSwing = max(bestSweepDuringSwing, club.sweepScore)
                bestArcDuringSwing = max(bestArcDuringSwing, club.arcScore)
                bestSequenceDuringSwing = max(bestSequenceDuringSwing, club.swingSequenceScore)
            }
            return nil

        case .swinging:
            bestSweepDuringSwing = max(bestSweepDuringSwing, club.sweepScore)
            bestArcDuringSwing = max(bestArcDuringSwing, club.arcScore)
            bestSequenceDuringSwing = max(bestSequenceDuringSwing, club.swingSequenceScore)

            if let swingStartedAt,
               now - swingStartedAt > configuration.swingTimeout,
               shouldTimeoutSwing(elapsed: now - swingStartedAt) {
                transition(to: .addressed)
                clearSwing()
                return nil
            }

            if patch.isPresent {
                return nil
            }

            guard bestSweepDuringSwing >= 0.34 || club.sweepScore >= 0.34 else { return nil }
            guard bestArcDuringSwing >= 0.32 || club.arcScore >= 0.32 else { return nil }

            transition(to: .impactCandidate)
            firstAbsentAt = now
            absentSampleCount = patch == .clearAbsent ? 1 : 0
            return maybeResolveImpact(now: now, lock: lock)

        case .impactCandidate:
            if patch.isPresent {
                transition(to: .addressed)
                clearSwing()
                return nil
            }

            if patch == .clearAbsent {
                absentSampleCount += 1
            }
            return maybeResolveImpact(now: now, lock: lock)

        case .cooldown:
            return nil
        }
    }

    /// Called by the driver once a candidate is accepted, to start cooldown and
    /// record the impact time for de-duplication.
    func didConfirm(impactRealTime: Double) {
        lastConfirmedImpactRealTime = impactRealTime
        state = .cooldown
        markBest(.cooldown)
        clearSwing()
    }

    private func shouldStartSwing(club: ClubEvidenceV3, frame: SwingObservationV3) -> Bool {
        (club.takeawayScore >= 0.24 && club.arcScore >= 0.12)
            || (club.sweepScore >= 0.42 && club.arcScore >= 0.18)
            || (club.clubNearPatch >= 0.45 && frame.lumaMotion >= 0.010 && club.arcScore >= 0.18)
    }

    private func shouldTimeoutSwing(
        elapsed: Double
    ) -> Bool {
        guard elapsed <= configuration.extendedSwingTimeout else { return true }
        return !hasSlowDrillSwingEvidence(elapsed: elapsed)
    }

    private func hasSlowDrillSwingEvidence(elapsed: Double) -> Bool {
        elapsed > configuration.swingTimeout
            && configuration.sourceTimeScale > 1.0
            && bestArcDuringSwing >= 0.75
            && bestSequenceDuringSwing < 0.20
    }

    private func maybeResolveImpact(now: Double, lock: TargetLockV3) -> ResolvedSwingCandidateV3? {
        guard let firstAbsentAt else { return nil }

        let confirmedBySamples = absentSampleCount >= configuration.minDepartureAbsentSamples
        guard confirmedBySamples else {
            // Time bounds an unresolved candidate; it cannot make an obscured
            // target become evidence of contact. Do not extend the deadline on
            // every frame, or old rehearsal motion can live indefinitely.
            let deadline = firstAbsentAt + configuration.impactConfirmationDuration
            if now >= deadline {
                transition(to: .addressed)
                clearSwing()
            } else {
                burstUntilRealTime = max(burstUntilRealTime, deadline)
            }
            return nil
        }

        guard firstAbsentAt - lastConfirmedImpactRealTime >= configuration.minImpactGap else {
            transition(to: .cooldown)
            clearSwing()
            return nil
        }

        let candidate = ResolvedSwingCandidateV3(
            impactRealTime: firstAbsentAt,
            lock: lock,
            swingDuration: firstAbsentAt - (swingStartedAt ?? firstAbsentAt),
            bestSweep: bestSweepDuringSwing,
            bestArc: bestArcDuringSwing,
            bestSequence: bestSequenceDuringSwing
        )
        transition(to: .cooldown)
        clearSwing()
        return candidate
    }

    private func transition(to next: SwingMachineStateV3) {
        state = next
        markBest(next)
    }

    private func markBest(_ next: SwingMachineStateV3) {
        if rank(next) > rank(bestStateReached) {
            bestStateReached = next
        }
    }

    private func rank(_ state: SwingMachineStateV3) -> Int {
        switch state {
        case .idle: return 0
        case .addressed: return 1
        case .swinging: return 2
        case .impactCandidate: return 3
        case .cooldown: return 4
        }
    }

    private func clearSwing() {
        swingStartedAt = nil
        firstAbsentAt = nil
        absentSampleCount = 0
        bestSweepDuringSwing = 0
        bestArcDuringSwing = 0
        bestSequenceDuringSwing = 0
        burstUntilRealTime = -Double.greatestFiniteMagnitude
    }
}
