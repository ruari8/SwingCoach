//
//  CoachingMetrics.swift
//  SwingCoach
//
//  The measurements coaching makes on a down-the-line swing, and the result
//  types stored for each swing.
//
//  Every metric is one number at one swing position with a zone. Inside the
//  zone the level is 0. Outside, the level counts steps away from the zone,
//  1...10, signed by direction. Lower is better; there is no overall score.
//

import Foundation

nonisolated enum CoachingMetricID: String, Codable, CaseIterable {
    case setupPosture
    case setupHands
    case takeawayClub
    case planeTakeaway
    case shaftHalfwayBack
    case leadArmTop
    case handDepthTop
    case hipDepthTop
    case headHeightTop
    case headDepthTop
    case postureTop
    case transition
    case shaftHalfwayDown
    case planeDelivery
    case hipDepthImpact
    case headHeightImpact
    case headDepthImpact
    case postureImpact
    case handsHeightImpact
    case handsOutImpact
    case trailKneeImpact
}

nonisolated enum CoachingUnit: String, Codable {
    /// Share of the golfer's body scale (shoulder to hip plus hip to ankle).
    case bodyPercent
    case degrees

    func format(_ value: Double) -> String {
        switch self {
        case .bodyPercent: String(format: "%+.0f%%", value)
        case .degrees: String(format: "%+.0f°", value)
        }
    }
}

nonisolated struct CoachingMetricDefinition {
    let id: CoachingMetricID
    /// Short name for chips and lists.
    let title: String
    /// Swing position the metric is read and drawn at, 1...10.
    let position: Int
    let unit: CoachingUnit
    let zone: ClosedRange<Double>
    /// Size of one level outside the zone, in `unit`.
    let step: Double
    /// What the golfer is doing when the value is under / over the zone.
    let below: String
    let above: String
    /// One line on what is measured, for the detail view.
    let measures: String
    /// How much an out-of-zone level matters when picking what to mention.
    let weight: Double
    /// False for a guide that is drawn but never judged: its level is 0.
    var scored = true
    /// True for a reading of where the club points or sits. From down the
    /// line that picture changes with where the camera stands relative to
    /// the target line, so these readings moved between sessions (and
    /// within one when the tripod moved) while the body readings held.
    var dependsOnCamera = false

    /// True for a check only made from the saved clip, never from the
    /// small copies Auto holds in memory: every club reading. At 30 frames
    /// a second the level-shaft frames can't be placed and the fast frames
    /// land a little off, enough to move takeaway by a step and transition
    /// by 2 degrees and make themes the clip didn't have. The body
    /// readings came out the same.
    var needsClip: Bool { dependsOnCamera }

    func level(for value: Double) -> Int {
        if !scored || zone.contains(value) { return 0 }
        let outside = value < zone.lowerBound ? value - zone.lowerBound : value - zone.upperBound
        let steps = min(10, Int((abs(outside) / step).rounded(.up)))
        return outside < 0 ? -steps : steps
    }

    /// A reading more than ten steps outside the zone is a measurement slip
    /// (a wrong shaft end, another person in the outline), not a swing.
    func isBelievable(_ value: Double) -> Bool {
        guard scored else { return true }
        return value >= zone.lowerBound - 10 * step && value <= zone.upperBound + 10 * step
    }

    func finding(forLevel level: Int) -> String? {
        level == 0 ? nil : (level < 0 ? below : above)
    }

    static func definition(_ id: CoachingMetricID) -> CoachingMetricDefinition {
        all.first { $0.id == id }!
    }

    /// In swing order. Zones are the middle 70% (15th to 85th percentile,
    /// rounded) of the 96 tour-pro swings that pass the same checks a swing
    /// here has to pass to be judged; see docs/COACHING.md. A level counts
    /// steps outside what good players do. The address plane is a guide.
    static let all: [CoachingMetricDefinition] = [
        // Setup depends on the club, and the pro swings behind these zones
        // are mostly drivers: guides until there are zones per club.
        .init(id: .setupPosture, title: "Posture", position: 1, unit: .degrees, zone: 29...39, step: 3,
              below: "Standing tall at address", above: "Bent over a lot at address",
              measures: "Forward bend from hips to neck at address. A guide, not judged.", weight: 0, scored: false),
        .init(id: .setupHands, title: "Hands at address", position: 1, unit: .bodyPercent, zone: 5...13, step: 2.5,
              below: "Hands tucked in close", above: "Reaching for the ball",
              measures: "Hands against a line straight down from the trail shoulder. A guide, not judged.",
              weight: 0, scored: false),
        .init(id: .takeawayClub, title: "Takeaway", position: 2, unit: .bodyPercent, zone: 4...26, step: 5,
              below: "Clubhead inside the hands", above: "Clubhead well outside the hands",
              measures: "Clubhead against the hands when the shaft is level going back.", weight: 1.0, dependsOnCamera: true),
        .init(id: .planeTakeaway, title: "Address plane going back", position: 2, unit: .bodyPercent, zone: -40...25, step: 8,
              below: "Club under the address plane", above: "Club above the address plane",
              measures: "Clubhead against the line from the address clubhead through the trail forearm. A guide, not judged.",
              weight: 0, scored: false, dependsOnCamera: true),
        .init(id: .shaftHalfwayBack, title: "Shaft halfway back", position: 3, unit: .bodyPercent, zone: -29...3, step: 6,
              below: "Shaft steep: points well inside the ball", above: "Shaft flat: points outside the ball",
              measures: "Where the butt of the club points on the ground, against the ball, with the lead arm level.",
              weight: 1.0, dependsOnCamera: true),
        .init(id: .leadArmTop, title: "Lead arm at the top", position: 4, unit: .degrees, zone: 8...20, step: 4,
              below: "Lead arm flat across the shoulders", above: "Lead arm high above the shoulder plane",
              measures: "Lead arm angle against the line through the shoulders at the top.", weight: 0.9),
        .init(id: .handDepthTop, title: "Hand depth at the top", position: 4, unit: .bodyPercent, zone: 0...10, step: 3,
              below: "Hands very deep behind the heels", above: "Hands out over the toes",
              measures: "Hands against a line straight up from the trail heel at the top.", weight: 0.8),
        .init(id: .hipDepthTop, title: "Hip depth at the top", position: 4, unit: .bodyPercent, zone: -3...1.5, step: 1.5,
              below: "Hips backed away a lot", above: "Hips moved toward the ball",
              measures: "Backside against its address line at the top.", weight: 1.0),
        .init(id: .headHeightTop, title: "Head height at the top", position: 4, unit: .bodyPercent, zone: -6...0, step: 1.5,
              below: "Head dropped a lot going back", above: "Head lifted going back",
              measures: "Head height against address at the top.", weight: 0.7),
        .init(id: .headDepthTop, title: "Head at the top", position: 4, unit: .bodyPercent, zone: -1.5...3, step: 1.5,
              below: "Head backed away from the ball", above: "Head moved toward the ball",
              measures: "Head toward or away from the ball against address, at the top.", weight: 0.7),
        .init(id: .postureTop, title: "Posture at the top", position: 4, unit: .degrees, zone: -7...2, step: 3,
              below: "Standing up going back", above: "Bending over more going back",
              measures: "Forward bend against address at the top.", weight: 0.8),
        .init(id: .transition, title: "Transition", position: 5, unit: .degrees, zone: -16...6, step: 3,
              below: "Shaft drops very flat coming down", above: "Shaft steepens coming down",
              measures: "Shaft angle with the lead arm level coming down, against the same point going back.",
              weight: 1.2, dependsOnCamera: true),
        .init(id: .shaftHalfwayDown, title: "Shaft halfway down", position: 5, unit: .bodyPercent, zone: -25...26, step: 8,
              below: "Shaft steep: points inside the ball", above: "Shaft flat: points well outside the ball",
              measures: "Where the butt of the club points on the ground, against the ball, coming down.", weight: 1.0, dependsOnCamera: true),
        .init(id: .planeDelivery, title: "Address plane coming down", position: 6, unit: .bodyPercent, zone: -45...20, step: 8,
              below: "Club under the address plane", above: "Club above the address plane",
              measures: "Clubhead against the address plane line when the shaft is level coming down. A guide, not judged.",
              weight: 0, scored: false, dependsOnCamera: true),
        .init(id: .hipDepthImpact, title: "Hip depth at impact", position: 7, unit: .bodyPercent, zone: -3.5...3, step: 1.5,
              below: "Hips backed away a lot", above: "Hips moved toward the ball",
              measures: "Backside against its address line at impact.", weight: 1.3),
        .init(id: .headHeightImpact, title: "Head height at impact", position: 7, unit: .bodyPercent, zone: -12...(-3), step: 2,
              below: "Head dropped a lot into impact", above: "Head stays up through impact",
              measures: "Head height against address at impact. Good players lower it.", weight: 0.9),
        .init(id: .headDepthImpact, title: "Head at impact", position: 7, unit: .bodyPercent, zone: -5.5...2, step: 2,
              below: "Head backed away from the ball", above: "Head moved toward the ball",
              measures: "Head toward or away from the ball against address, at impact.", weight: 0.9),
        .init(id: .postureImpact, title: "Posture at impact", position: 7, unit: .degrees, zone: -6...6, step: 3,
              below: "Standing up through impact", above: "Bending over more at impact",
              measures: "Forward bend against address at impact.", weight: 1.1),
        .init(id: .handsHeightImpact, title: "Hands height at impact", position: 7, unit: .bodyPercent, zone: 2.5...10.5, step: 2,
              below: "Hands lower than address at impact", above: "Hands high at impact",
              measures: "Hands height against address at impact.", weight: 1.0),
        .init(id: .handsOutImpact, title: "Hands at impact", position: 7, unit: .bodyPercent, zone: 0.5...7, step: 2,
              below: "Hands closer to the body than address", above: "Hands far from the body at impact",
              measures: "Hands toward or away from the ball against address, at impact.", weight: 0.9),
        .init(id: .trailKneeImpact, title: "Trail knee at impact", position: 7, unit: .bodyPercent, zone: -1...8, step: 1.5,
              below: "Trail knee pulled back from the ball", above: "Trail knee moves out toward the ball",
              measures: "Trail knee toward or away from the ball against address, at impact.", weight: 0.9),
    ]
}

/// One shape of a metric's drawing, in normalized frame coordinates.
/// `size` (a circle's radius, a band's half-width) is a share of frame height.
nonisolated struct CoachingDrawing: Codable, Equatable {
    enum Kind: String, Codable {
        /// `area` is a filled outline through its points.
        case line, band, area, circle, dot, label
    }

    enum Role: String, Codable {
        /// Where the golfer was at address, or a fixed guide.
        case reference
        /// The allowed zone.
        case zone
        /// What is being judged now; drawn in the result's colour.
        case subject
    }

    var kind: Kind
    var role: Role
    var points: [CoachingPoint]
    var size: Double? = nil
    var text: String? = nil
    var dashed: Bool = false
}

nonisolated struct CoachingMetricResult: Codable, Equatable {
    let id: CoachingMetricID
    let position: Int
    /// Clip time of the frame it was measured on, where its drawing belongs.
    let clipTime: Double
    /// In the metric's unit; see CoachingMetricDefinition.
    let value: Double
    /// 0 in zone; otherwise 1...10 steps outside, negative under the zone.
    let level: Int
    /// 0...1: how sure the evidence behind this number is.
    let confidence: Double
    var drawings: [CoachingDrawing]

    var definition: CoachingMetricDefinition { .definition(id) }
    var inZone: Bool { level == 0 }
    var finding: String? { definition.finding(forLevel: level) }
}

nonisolated enum CoachingSwingLength: String, Codable {
    case full
    /// A chip or pitch: the hands stay under the trail shoulder at the top.
    /// The zones come from full swings, so a short swing is measured but
    /// not judged.
    case short
}

/// Why a swing is measured but not judged, if it isn't.
nonisolated enum CoachingExclusion: String, Codable {
    case shortSwing
    /// The feet appear to move before the top: the camera moved or zoomed,
    /// so nothing can be compared with address.
    case cameraMoved
    /// Address or impact doesn't look like one, so the positions are off.
    case positionsUnclear
}

nonisolated struct SwingCoachingReport: Codable, Equatable {
    /// Bumped when metric maths or zones change, so stored reports can be
    /// recomputed from stored evidence.
    var version: Int = SwingCoachingReport.currentVersion
    var rightHanded: Bool
    var swingLength: CoachingSwingLength = .full
    var cameraMoved = false
    var positionsUnclear = false
    /// True for a first reading made during Auto from the small copies of
    /// the camera's frames. The saved clip gives a fuller one later, which
    /// replaces it.
    var fromLiveCopies = false

    /// Nil when the swing is judged.
    var exclusion: CoachingExclusion? {
        if positionsUnclear { return .positionsUnclear }
        if cameraMoved { return .cameraMoved }
        return swingLength == .short ? .shortSwing : nil
    }
    var metrics: [CoachingMetricResult]
    /// Metrics that could not be measured on this swing.
    var unavailable: [CoachingMetricID]

    static let currentVersion = 8

    /// Feet shifting more than this share of body scale by the top means
    /// the camera moved. A tripod clip's ankle joints wander about 5%, and
    /// 90% stay under 7%.
    static let steadyFootShift = 0.10

    func metric(_ id: CoachingMetricID) -> CoachingMetricResult? {
        metrics.first { $0.id == id }
    }
}
