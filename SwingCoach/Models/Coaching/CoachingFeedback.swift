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
    /// The finding in a few words, e.g. "Shaft steepens coming down".
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
    /// A swing that isn't judged has none.
    static func findings(in report: SwingCoachingReport) -> [CoachingFinding] {
        guard report.exclusion == nil else { return [] }
        var byFault: [CoachingFault: [CoachingMetricResult]] = [:]
        for result in report.metrics {
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
                let measured = judged.filter { report in metrics.contains { report.metric($0) != nil } }.count
                let shown = judged.compactMap { report in
                    findings(in: report).first { $0.fault == fault && abs($0.level) >= themeLevel }
                }
                // The metric that most often leads stands for the fault.
                let leads = Dictionary(grouping: shown, by: \.metric)
                let lead = leads.max { ($0.value.count, $1.key.rawValue) < ($1.value.count, $0.key.rawValue) }
                guard let lead, let first = lead.value.first else { continue }
                add(fault: fault, metric: lead.key, direction: first.level > 0 ? 1 : -1,
                    levels: shown.map(\.level), measured: measured)
            } else {
                // Opposite directions are opposite faults: count each
                // metric and direction on its own.
                for metric in fault.metrics {
                    for direction in [-1, 1] where CoachingFault.fault(for: metric, over: direction > 0) == fault {
                        let results = judged.compactMap { $0.metric(metric) }
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
        guard let result = report.metric(theme.metric), result.level * theme.direction > 0 else { return nil }
        let sameFault = report.metrics.filter { CoachingFault.fault(for: $0) == theme.fault }
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
            let backInZone = report.metric(theme.metric)?.level == 0
                && !findings.contains { $0.fault == theme.fault }
            if backInZone, findings.allSatisfy({ $0.score < mentionScore }) {
                return .better(theme.fault)
            }
        }

        guard let worst = findings.first, worst.score >= mentionScore else { return .good }
        return .focus(worst)
    }

    /// The verdict for each swing of a session, oldest first, each judged
    /// against the swings before it: what the pills show.
    static func sessionVerdicts(_ reports: [SwingCoachingReport]) -> [CoachingVerdict] {
        reports.indices.map { verdict(for: reports[$0], earlier: Array(reports[..<$0])) }
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
