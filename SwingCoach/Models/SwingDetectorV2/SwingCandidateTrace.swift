//
//  SwingCandidateTrace.swift
//  SwingCoach
//
//  Debug-only artifact. "Candidate" is an internal concept (a thing being
//  evaluated before accept) and is never surfaced on the phone. Each evaluated
//  candidate, accepted or rejected, emits one trace. Read alongside the contact
//  sheet for the same window: the numbers say what the detector believed, the
//  frames say what was actually true.
//

import Foundation

nonisolated enum SwingPrimaryFailure: String, Encodable {
    case none
    case noAddressLock = "no_address_lock"
    case addressLost = "address_lost"
    case temporaryOcclusion = "temporary_occlusion"
    case ballReappeared = "ball_reappeared"
    case noBallDeparture = "no_ball_departure"
    case noClubSweep = "no_club_sweep"
    case noSwingSequence = "no_swing_sequence"
    case lowSwingArc = "low_swing_arc"
    case belowThreshold = "below_threshold"
    case duplicate
    case timedOut = "timed_out"
}

nonisolated struct SwingAddressLockTrace: Encodable, Equatable {
    let lockedAtReal: Double
    let lockedAtSource: Double
    let centerX: Double
    let centerY: Double
    let stabilityScore: Double
    let clubAssociationScore: Double
    let revision: Int
    let selectionReason: String
    let currentClubheadAssociationScore: Double
    let ballConfidence: Double
    let addressBallCount: Int
}

nonisolated struct SwingCandidateTrace: Encodable, Equatable {
    let candidateId: Int
    let stateReached: String
    /// nil while no impact instant was estimated.
    let impactRealTime: Double?
    let impactSourceTime: Double?
    let addressLock: SwingAddressLockTrace?
    let departure: SwingDepartureTrace?
    let evidence: EvidenceVector
    let score: Double
    let accepted: Bool
    let primaryFailure: SwingPrimaryFailure
}

nonisolated struct SwingDepartureTrace: Encodable, Equatable {
    let preTargetPresenceRatio: Double
    let postTargetAbsenceRatio: Double
    let preBallInventory: Double
    let postBallInventory: Double
    let ballInventoryDropScore: Double
    let ballInventoryDropFrameRatio: Double
    let longestBallInventoryDropRun: Int
}

nonisolated struct SwingSamplingTrace: Encodable, Equatable {
    let sourceTime: Double
    let realTime: Double
    let targetFPS: Double
    let burstActive: Bool
    let stateBeforeFrame: String
    let lockCenterX: Double?
    let lockCenterY: Double?
    let lockRevision: Int?
    let lockSelectionReason: String?
    let lockCurrentClubheadAssociationScore: Double?
    let lockBallConfidence: Double?
    let addressBallCount: Int?
}
