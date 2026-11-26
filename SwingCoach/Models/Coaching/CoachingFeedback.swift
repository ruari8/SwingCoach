//
//  CoachingFeedback.swift
//  SwingCoach
//
//  Decides what to tell the golfer, and when to say nothing.
//
//  A report can hold several out-of-zone metrics. The golfer hears at most
//  one, and only when it is worth a thought: a decent swing gets "good
//  swing" and no pointers. Across a session, the faults that keep repeating
//  become themes, and per-swing feedback stays on the top theme instead of
//  jumping between faults.
//

import Foundation

/// Metrics that describe the same fault, so it is mentioned once.
nonisolated enum CoachingFault: String, Codable, CaseIterable {
    case setup
    case takeaway
    case backswingPlane
    case topPosition
    case backswingPosture
    case steepTransition
    case flatTransition
    case earlyExtension
    case headAtImpact
    case handsAtImpact

    var title: String {
        switch self {
        case .setup: "Setup"
        case .takeaway: "Takeaway"
        case .backswingPlane: "Backswing plane"
        case .topPosition: "Top of the swing"
        case .backswingPosture: "Posture going back"
        case .steepTransition: "Steep coming down"
        case .flatTransition: "Under the plane coming down"
        case .earlyExtension: "Standing up through impact"
        case .headAtImpact: "Head at impact"
        case .handsAtImpact: "Hands at impact"
        }
    }

    /// True for a fault whose metrics all say the same thing in one
    /// direction, so swings showing any of them show the same fault. The
    /// others hold opposite faults (clubhead inside or outside the hands),
    /// which are only the same fault per metric and direction.
    var isOneDirection: Bool {
        switch self {
        case .steepTransition, .flatTransition, .earlyExtension: true
        default: false
        }
    }

    /// The fault a metric shows when it is over or under its zone, or nil
    /// when that side is not a fault.
    static func fault(for metric: CoachingMetricID, over: Bool) -> CoachingFault? {
        guard CoachingMetricDefinition.definition(metric).scored else { return nil }
        switch metric {
        case .setupPosture, .setupHands: return .setup
        case .takeawayClub, .planeTakeaway: return .takeaway
        case .shaftHalfwayBack: return .backswingPlane
        case .leadArmTop, .handDepthTop: return .topPosition
        case .hipDepthTop, .headHeightTop, .headDepthTop, .postureTop: return .backswingPosture
        case .transition: return over ? .steepTransition : .flatTransition
        case .shaftHalfwayDown: return over ? .flatTransition : .steepTransition
        case .planeDelivery: return over ? .steepTransition : .flatTransition
        case .hipDepthImpact: return over ? .earlyExtension : nil
        case .postureImpact: return over ? nil : .earlyExtension
        case .headHeightImpact: return over ? .earlyExtension : .headAtImpact
        case .handsHeightImpact: return over ? .earlyExtension : .handsAtImpact
        case .headDepthImpact: return .headAtImpact
        case .handsOutImpact: return .handsAtImpact
        case .trailKneeImpact: return over ? .earlyExtension : nil
        }
    }

    /// The fault a result belongs to, or nil for a result that is in zone.
    static func fault(for result: CoachingMetricResult) -> CoachingFault? {
        result.level == 0 ? nil : fault(for: result.id, over: result.level > 0)
    }

    /// Every metric that can show this fault.
    var metrics: [CoachingMetricID] {
        CoachingMetricID.allCases.filter { metric in
            Self.fault(for: metric, over: true) == self || Self.fault(for: metric, over: false) == self
        }
    }
}

/// One thing worth saying about a swing.
nonisolated struct CoachingFinding: Codable, Equatable {
    let fault: CoachingFault
    /// The metric that shows it best; its drawing is the one to display.
    let metric: CoachingMetricID
    let position: Int
    let level: Int
    /// The finding in a few words, e.g. "Shaft steepened coming down".
    let text: String
    /// Other out-of-zone metrics of the same fault on this swing.
    let supporting: [CoachingMetricID]
    let score: Double
}

nonisolated enum CoachingVerdict: Equatable {
    /// Measured but not judged: a chip or pitch, a moved camera, or
    /// positions that couldn't be found.
    case notJudged(CoachingExclusion)
    /// Nothing worth a thought. Say "good swing" or stay quiet.
    case good
    /// The session's theme was back in zone on this swing.
    case better(CoachingFault)
    case focus(CoachingFinding)

    var headline: String {
        switch self {
        case .notJudged(.shortSwing): "Short swing, not judged"
        case .notJudged(.cameraMoved): "Camera moved, not judged"
        case .notJudged(.positionsUnclear): "Swing positions unclear, not judged"
        case .good: "Good swing"
        case .better(let fault): "That's better: \(fault.title.lowercased())"
        case .focus(let finding): finding.text
        }
    }
}

/// A fault that keeps showing up across a session.
nonisolated struct CoachingTheme: Equatable, Identifiable {
    let fault: CoachingFault
    /// The metric that stands for it; its drawing is the one to display.
    let metric: CoachingMetricID
    /// +1 when the metric is over its zone, -1 under.
    let direction: Int
    let position: Int
    let text: String
    /// Swings that showed the fault, out of the judged swings where it
    /// could have been seen.
    let swings: Int
    let measured: Int
    /// Middle level of the swings that showed it, signed by `direction`.
    let medianLevel: Int
    let score: Double

    var id: String { "\(fault.rawValue)-\(metric.rawValue)-\(direction)" }
    var share: Double { measured > 0 ? Double(swings) / Double(measured) : 0 }
}

/// What a few swings in a row had in common: the recap shown during Auto.
nonisolated struct CoachingRecap: Equatable {
    /// The fault most of them shared, or nil when nothing kept repeating.
    let theme: CoachingTheme?
    /// How each swing stands on the theme, oldest first. Empty without a
    /// theme.
    let swings: [CoachingThemeShowing]
    /// Swings that were judged, and how many of those needed no pointer.
    let judged: Int
    let good: Int
}

/// How one swing stands on a theme.
nonisolated enum CoachingThemeShowing: Equatable {
    /// Not judged, or the theme couldn't be seen on it.
    case notJudged
    /// The check that shows the theme is in its zone.
    case inZone
    /// Shows the theme, this many levels out.
    case shows(Int)
    /// The theme's check is out of its zone the other way, this many
    /// levels: a different fault, not the theme and not in zone.
    case otherWay(Int)

    /// Spelled out as the player says a level: "2 steps out", "In zone",
    /// "Not judged".
    var label: String {
        switch self {
        case .notJudged: "Not judged"
        case .inZone: "In zone"
        case .shows(let level): Self.stepsOut(level)
        case .otherWay(let level): "Other way, \(Self.stepsOut(level))"
        }
    }

    private static func stepsOut(_ level: Int) -> String {
        let steps = abs(level)
        return "\(steps) step\(steps == 1 ? "" : "s") out"
    }
}

/// When the coach speaks during Auto. Swings are measured either way.
nonisolated enum CoachingCadence: String, CaseIterable, Identifiable {
    case everySwing, everyFive, everyTen, onRequest

    static let key = "coaching.cadence"
    /// A golfer overthinks enough: a recap, not a pointer after every ball.
    static let standard = CoachingCadence.everyFive
    /// Swings in a recap asked for by hand.
    static let requestedRecapSize = 5

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everySwing: "Every swing"
        case .everyFive: "Every 5 swings"
        case .everyTen: "Every 10 swings"
        case .onRequest: "Only when I ask"
        }
    }

    /// The cadence in the camera's compact chip ("Recap: 5"): the swings
    /// a recap covers, "1" for a verdict after every swing, "ask" when
    /// only asked for.
    var shortTitle: String {
        switch self {
        case .everySwing: "1"
        case .everyFive: "5"
        case .everyTen: "10"
        case .onRequest: "ask"
        }
    }

    /// How many swings a recap covers, or nil when none is shown unasked.
    var recapSize: Int? {
        switch self {
        case .everyFive: 5
        case .everyTen: 10
        case .everySwing, .onRequest: nil
        }
    }
}

/// Decides when a recap comes up on the camera screen: once for every
/// `recapSize` swings measured since the last one. Swings already measured
/// when the screen was first looked at, or when the setting changed, are
/// never counted, and deleting a swing doesn't bring an old recap back. A
/// session that is empty at the first look has none to pass over, so its
/// first swing counts.
nonisolated struct CoachingRecapSchedule: Equatable {
    /// Measured swings already recapped or passed over. Nil before the
    /// first look at a session.
    private var counted: Set<UUID>?

    /// Call when the session's measured swings (oldest first) change.
    /// Returns the swings of a recap that has just come due.
    mutating func update(measured: [UUID], cadence: CoachingCadence) -> [UUID]? {
        guard let counted else {
            self.counted = Set(measured)
            return nil
        }
        // Deleted swings are forgotten; the rest stay counted.
        self.counted = counted.intersection(measured)
        let fresh = measured.filter { !counted.contains($0) }
        guard let size = cadence.recapSize, fresh.count >= size else { return nil }
        let recap = Array(fresh.prefix(size))
        self.counted?.formUnion(recap)
        return recap
    }

    mutating func cadenceChanged(measured: [UUID]) {
        counted = Set(measured)
    }
}

nonisolated enum CoachingFeedback {
    /// A fault scoring this much (level x weight x confidence, more when
    /// its metrics agree) is worth mentioning on its own. Set so that four
    /// in five valid pro swings come out "good"; a level 3 alone is not
    /// enough, a level 4 or two agreeing metrics is.
    static let mentionScore = 3.5
    /// The session's theme is mentioned at a lower score: it is already
    /// what the golfer is working on.
    static let themeMentionScore = 2.5
    /// A fault this far out is mentioned even when it isn't the session's theme.
    static let overrideLevel = 6
    /// A swing shows a theme at this level or more.
    static let themeLevel = 2
    /// A theme needs this many swings showing it, and this share of them.
    static let themeMinimumSwings = 4
    static let themeMinimumShare = 0.5

    private static func score(_ result: CoachingMetricResult) -> Double {
        Double(abs(result.level)) * result.definition.weight * result.confidence
    }

    /// Out-of-zone results grouped into faults, most important first.
    /// A swing that isn't judged has none, and a club check held for the
    /// camera is never one: here and in every rule below, only
    /// `countedMetrics` are read.
    static func findings(in report: SwingCoachingReport) -> [CoachingFinding] {
        guard report.exclusion == nil else { return [] }
        var byFault: [CoachingFault: [CoachingMetricResult]] = [:]
        for result in report.countedMetrics {
            guard let fault = CoachingFault.fault(for: result) else { continue }
            byFault[fault, default: []].append(result)
        }
        return byFault.compactMap { fault, results in
            // Ties go to the earlier metric, so the same report always
            // gives the same finding.
            let lead = results.max { (score($0), -$0.position) < (score($1), -$1.position) }
            return lead.flatMap { finding(fault, lead: $0, among: results) }
        }
        .sorted { ($0.score, -$0.position, $1.fault.rawValue) > ($1.score, -$1.position, $0.fault.rawValue) }
    }

    private static func finding(_ fault: CoachingFault, lead: CoachingMetricResult, among results: [CoachingMetricResult]) -> CoachingFinding? {
        guard let text = lead.finding else { return nil }
        // Agreement between metrics of the same fault counts for more than
        // one metric alone.
        let others = results.filter { $0.id != lead.id }
        return CoachingFinding(
            fault: fault,
            metric: lead.id,
            position: lead.position,
            level: lead.level,
            text: text,
            supporting: others.map(\.id),
            score: score(lead) * (1 + 0.25 * Double(others.count))
        )
    }

    /// Faults seen on at least half of the swings where they could be
    /// seen, strongest first. `minimumSwings` lets a recap of the last few
    /// swings ask for fewer.
    static func themes(in reports: [SwingCoachingReport], minimumSwings: Int = themeMinimumSwings) -> [CoachingTheme] {
        let judged = reports.filter { $0.exclusion == nil }
        var themes: [CoachingTheme] = []

        func add(fault: CoachingFault, metric: CoachingMetricID, direction: Int, levels: [Int], measured: Int) {
            guard levels.count >= minimumSwings, measured > 0,
                  Double(levels.count) >= themeMinimumShare * Double(measured)
            else { return }
            let definition = CoachingMetricDefinition.definition(metric)
            let middle = median(levels.map { Double(abs($0)) })
            themes.append(CoachingTheme(
                fault: fault,
                metric: metric,
                direction: direction,
                position: definition.position,
                text: definition.finding(forLevel: direction) ?? definition.title,
                swings: levels.count,
                measured: measured,
                medianLevel: Int(middle.rounded()) * direction,
                score: Double(levels.count) / Double(measured) * middle * definition.weight
            ))
        }

        for fault in CoachingFault.allCases {
            if fault.isOneDirection {
                // Any of its metrics shows it, so any of them measured
                // counts the swing as one where it could have been seen.
                let metrics = fault.metrics
                let measured = judged.filter { report in metrics.contains { report.countedMetric($0) != nil } }.count
                // A swing shows the fault when any of its metrics is at
                // theme level; the strongest of those stands for the swing.
                // Chosen among those only: a closer-to-zone reading with
                // more confidence must not hide one that qualifies.
                let shown = judged.compactMap { report in
                    report.countedMetrics
                        .filter { CoachingFault.fault(for: $0) == fault && abs($0.level) >= themeLevel }
                        .max { (score($0), -$0.position) < (score($1), -$1.position) }
                }
                // The metric that most often leads stands for the fault.
                let leads = Dictionary(grouping: shown, by: \.id)
                let lead = leads.max { ($0.value.count, $1.key.rawValue) < ($1.value.count, $0.key.rawValue) }
                guard let lead, let first = lead.value.first else { continue }
                add(fault: fault, metric: lead.key, direction: first.level > 0 ? 1 : -1,
                    levels: shown.map(\.level), measured: measured)
            } else {
                // Opposite directions are opposite faults: count each
                // metric and direction on its own.
                for metric in fault.metrics {
                    for direction in [-1, 1] where CoachingFault.fault(for: metric, over: direction > 0) == fault {
                        let results = judged.compactMap { $0.countedMetric(metric) }
                        let levels = results.map(\.level).filter { $0 * direction >= themeLevel }
                        add(fault: fault, metric: metric, direction: direction, levels: levels, measured: results.count)
                    }
                }
            }
        }

        // Half the swings one way and half the other is inconsistency, not
        // a fault in either direction: say neither.
        let both = Dictionary(grouping: themes.filter { !$0.fault.isOneDirection }, by: \.metric).filter { $0.value.count > 1 }
        themes.removeAll { both[$0.metric] != nil && !$0.fault.isOneDirection }

        // Strongest first, in an order that never depends on dictionary
        // order.
        themes.sort { ($0.score, -$0.position, $1.id) > ($1.score, -$1.position, $0.id) }
        // An earlier-in-the-swing fault within a quarter of the strongest
        // leads instead: a backswing fault often causes the downswing one.
        if let strongest = themes.first {
            let close = themes.filter { $0.score >= 0.75 * strongest.score }
            if let earliest = close.min(by: { ($0.position, -$0.score) < ($1.position, -$1.score) }),
               earliest.id != strongest.id,
               let index = themes.firstIndex(where: { $0.id == earliest.id }) {
                themes.insert(themes.remove(at: index), at: 0)
            }
        }
        return themes
    }

    /// The swing's finding for a theme, if the swing shows it.
    private static func finding(
        showing theme: CoachingTheme, in report: SwingCoachingReport, _ findings: [CoachingFinding]
    ) -> CoachingFinding? {
        if theme.fault.isOneDirection {
            return findings.first { $0.fault == theme.fault }
        }
        guard let result = report.countedMetric(theme.metric), result.level * theme.direction > 0 else { return nil }
        let sameFault = report.countedMetrics.filter { CoachingFault.fault(for: $0) == theme.fault }
        return finding(theme.fault, lead: result, among: sameFault)
    }

    /// What to say about one swing. `earlier` is the session so far, oldest
    /// first, without this swing.
    static func verdict(for report: SwingCoachingReport, earlier: [SwingCoachingReport] = []) -> CoachingVerdict {
        if let exclusion = report.exclusion { return .notJudged(exclusion) }
        let findings = findings(in: report)

        if let theme = themes(in: earlier).first {
            if let onTheme = finding(showing: theme, in: report, findings), onTheme.score >= themeMentionScore {
                // Stay on the theme unless something else is far worse.
                if let worst = findings.first, worst.fault != theme.fault, abs(worst.level) >= overrideLevel,
                   worst.score > 2 * onTheme.score {
                    return .focus(worst)
                }
                return .focus(onTheme)
            }
            // "Better" means the theme's own metric is back in its zone,
            // not merely out on the other side, with nothing else to say.
            let backInZone = report.countedMetric(theme.metric)?.level == 0
                && !findings.contains { $0.fault == theme.fault }
            if backInZone, findings.allSatisfy({ $0.score < mentionScore }) {
                return .better(theme.fault)
            }
        }

        guard let worst = findings.first, worst.score >= mentionScore else { return .good }
        return .focus(worst)
    }

    /// What to say about one swing of a session. `earlierInSession` is
    /// every earlier swing that can be coached, oldest first, nil where it
    /// has not been coached yet. The session's themes only apply once all
    /// of them have been: until then the swing is judged on its own, so
    /// the verdict doesn't depend on which swings happen to have been
    /// opened.
    static func verdict(for report: SwingCoachingReport, earlierInSession: [SwingCoachingReport?]) -> CoachingVerdict {
        let known = earlierInSession.compactMap { $0 }
        return verdict(for: report, earlier: known.count == earlierInSession.count ? known : [])
    }

    /// The verdict for each coached swing of a session, oldest first, each
    /// judged against the swings before it: what the pills show. A swing
    /// not coached yet is nil and gets no verdict.
    static func sessionVerdicts(_ reports: [SwingCoachingReport?]) -> [CoachingVerdict] {
        reports.indices.compactMap { index in
            reports[index].map { verdict(for: $0, earlierInSession: Array(reports[..<index])) }
        }
    }

    /// What `reports`, a few swings in a row, had in common. A fault is
    /// the recap's theme when at least three of them, and half of those
    /// where it could be seen, show it.
    static func recap(of reports: [SwingCoachingReport]) -> CoachingRecap {
        let judged = reports.filter { $0.exclusion == nil }
        let theme = themes(in: reports, minimumSwings: 3).first
        return CoachingRecap(
            theme: theme,
            swings: theme.map { theme in reports.map { showing(of: theme, in: $0) } } ?? [],
            judged: judged.count,
            good: judged.filter { verdict(for: $0) == .good }.count
        )
    }

    /// How far out a swing is on a theme: 0 when it doesn't show it, nil
    /// when the swing wasn't judged or the theme couldn't be seen on it.
    static func level(of theme: CoachingTheme, in report: SwingCoachingReport) -> Int? {
        guard report.exclusion == nil else { return nil }
        if theme.fault.isOneDirection {
            let measured = theme.fault.metrics.compactMap { report.countedMetric($0) }
            guard !measured.isEmpty else { return nil }
            return measured.filter { CoachingFault.fault(for: $0) == theme.fault }.map { abs($0.level) }.max() ?? 0
        }
        guard let result = report.countedMetric(theme.metric) else { return nil }
        return result.level * theme.direction > 0 ? abs(result.level) : 0
    }

    /// How a swing stands on a theme as a whole, for its bar in a recap:
    /// how far out its strongest reading of the fault is. A swing that
    /// doesn't show the theme is only "in zone" when every check of the
    /// fault is; out the other way on any of them is said as that.
    static func showing(of theme: CoachingTheme, in report: SwingCoachingReport) -> CoachingThemeShowing {
        guard let level = level(of: theme, in: report) else { return .notJudged }
        if level > 0 { return .shows(level) }
        guard let drawn = metric(showing: theme, in: report).flatMap({ report.countedMetric($0) }) else { return .notJudged }
        return drawn.level == 0 ? .inZone : .otherWay(abs(drawn.level))
    }

    /// How the one check drawn for a theme on a swing stands on it, for
    /// the label beside its picture: always that check's own level.
    static func showing(of theme: CoachingTheme, drawnIn report: SwingCoachingReport) -> CoachingThemeShowing {
        guard report.exclusion == nil,
              let drawn = metric(showing: theme, in: report).flatMap({ report.countedMetric($0) })
        else { return .notJudged }
        if shows(theme, drawn) { return .shows(abs(drawn.level)) }
        return drawn.level == 0 ? .inZone : .otherWay(abs(drawn.level))
    }

    /// True when this result is the theme's fault: any metric of the
    /// fault for a fault several metrics can show, otherwise the theme's
    /// own metric out in the theme's direction.
    private static func shows(_ theme: CoachingTheme, _ result: CoachingMetricResult) -> Bool {
        theme.fault.isOneDirection
            ? CoachingFault.fault(for: result) == theme.fault
            : result.id == theme.metric && result.level * theme.direction > 0
    }

    /// The metric whose drawing shows a theme on one swing. Where the
    /// swing shows the theme: the theme's own metric if it shows it there,
    /// otherwise the swing's strongest metric of the same fault. Where it
    /// doesn't: for a fault several metrics can show, whichever of them is
    /// furthest out of its zone (the other way), the theme's own on a tie;
    /// otherwise the theme's own metric.
    static func metric(showing theme: CoachingTheme, in report: SwingCoachingReport) -> CoachingMetricID? {
        if let own = report.countedMetric(theme.metric), shows(theme, own) { return own.id }
        guard theme.fault.isOneDirection else { return report.countedMetric(theme.metric)?.id }
        let family = theme.fault.metrics.compactMap { report.countedMetric($0) }
        if let other = family.filter({ shows(theme, $0) })
            .max(by: { (score($0), -$0.position) < (score($1), -$1.position) }) {
            return other.id
        }
        func rank(_ result: CoachingMetricResult) -> (Int, Int, Int) {
            (abs(result.level), result.id == theme.metric ? 1 : 0, -result.position)
        }
        return family.max { rank($0) < rank($1) }?.id
    }

    /// Two swings to picture a theme with, as places in `reports`: the one
    /// that shows it most, and the best one that doesn't (the theme's own
    /// metric nearest the middle of its zone). Either can be missing.
    static func examples(of theme: CoachingTheme, in reports: [SwingCoachingReport]) -> (most: Int?, best: Int?) {
        let levels = reports.map { level(of: theme, in: $0) }
        let most = levels.indices.filter { (levels[$0] ?? 0) > 0 }.max { (levels[$0] ?? 0, -$0) < (levels[$1] ?? 0, -$1) }
        let zone = CoachingMetricDefinition.definition(theme.metric).zone
        let middle = (zone.lowerBound + zone.upperBound) / 2
        func distance(_ index: Int) -> Double {
            reports[index].countedMetric(theme.metric).map { abs($0.value - middle) } ?? .infinity
        }
        let best = levels.indices.filter { levels[$0] == 0 && distance($0).isFinite }
            .min { (distance($0), $0) < (distance($1), $1) }
        return (most, best)
    }

    /// How many swings show both themes at theme level.
    static func swingsShowingBoth(_ first: CoachingTheme, _ second: CoachingTheme, in reports: [SwingCoachingReport]) -> Int {
        reports.filter { report in
            (level(of: first, in: report) ?? 0) >= themeLevel && (level(of: second, in: report) ?? 0) >= themeLevel
        }.count
    }

    /// The checks the coach draws without being asked: the verdict's one
    /// fault, by every metric that shows it. Nothing on a good swing.
    static func picks(for verdict: CoachingVerdict) -> Set<CoachingMetricID> {
        guard case .focus(let finding) = verdict else { return [] }
        return Set([finding.metric] + finding.supporting)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}
