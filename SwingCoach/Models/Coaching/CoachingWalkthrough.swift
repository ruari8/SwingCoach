//
//  CoachingWalkthrough.swift
//  SwingCoach
//
//  The order the player walks a golfer through a swing's coaching, and the
//  club-head trail drawn under it. Both are worked out from a stored report
//  and evidence; neither changes what is measured or said.
//
//  The walkthrough starts on the verdict: the one pointer, "Good swing",
//  "That's better", or why the swing isn't judged. After it come the other
//  faults on the swing, one step each, in swing order.
//

import Foundation

/// One stop in the walkthrough: a frame, what is drawn on it, one sentence.
nonisolated struct CoachingStep: Equatable, Identifiable {
    enum Kind: Equatable {
        /// The swing's one pointer.
        case pointer
        /// Another fault on the swing, after the pointer.
        case finding
        /// "Good swing": the checks in zone at one position, drawn green.
        case good
        /// "That's better": the theme's checks back in zone.
        case better
        /// Measured but not judged; nothing is drawn.
        case notJudged(CoachingExclusion)
    }

    let kind: Kind
    /// 1...10.
    let position: Int
    /// Where the frame is on the clip.
    let clipTime: Double
    /// Drawn on this step, the lead check first. All measured at `position`.
    let metrics: [CoachingMetricID]
    /// The step's one sentence.
    let text: String

    var lead: CoachingMetricID? { metrics.first }
    var id: String { "\(position)-\(metrics.map(\.rawValue).joined(separator: "+"))-\(text)" }
}

nonisolated enum CoachingWalkthrough {
    /// The verdict first, then every other fault on the swing in swing
    /// order. A swing that isn't judged has one step and draws nothing.
    static func steps(for report: SwingCoachingReport, verdict: CoachingVerdict) -> [CoachingStep] {
        let findings = CoachingFeedback.findings(in: report)
        var steps: [CoachingStep] = []
        var shownFault: CoachingFault?

        switch verdict {
        case .notJudged(let exclusion):
            let first = report.metrics.min { $0.clipTime < $1.clipTime }
            return [CoachingStep(kind: .notJudged(exclusion), position: first?.position ?? 1,
                                 clipTime: first?.clipTime ?? 0, metrics: [], text: verdict.headline)]
        case .focus(let finding):
            if let lead = report.metric(finding.metric) {
                steps.append(step(.pointer, lead: lead, others: finding.supporting, in: report, text: finding.text))
                shownFault = finding.fault
            }
        case .good:
            if let picture = goodPicture(in: report, among: nil) {
                steps.append(CoachingStep(kind: .good, position: picture.position, clipTime: picture.clipTime,
                                          metrics: picture.metrics, text: verdict.headline))
            }
        case .better(let fault):
            if let picture = goodPicture(in: report, among: Set(fault.metrics)) {
                steps.append(CoachingStep(kind: .better, position: picture.position, clipTime: picture.clipTime,
                                          metrics: picture.metrics, text: verdict.headline))
            }
            shownFault = fault
        }

        let rest = findings
            .filter { $0.fault != shownFault }
            .sorted { ($0.position, -$0.score) < ($1.position, -$1.score) }
        for finding in rest {
            guard let lead = report.metric(finding.metric) else { continue }
            steps.append(step(.finding, lead: lead, others: finding.supporting, in: report, text: finding.text))
        }
        return steps
    }

    private static func step(_ kind: CoachingStep.Kind, lead: CoachingMetricResult, others: [CoachingMetricID],
                             in report: SwingCoachingReport, text: String) -> CoachingStep {
        // Supporting checks measured on another frame are left to the list:
        // a drawing only belongs on the frame it was measured on.
        let together = others.filter { report.metric($0)?.position == lead.position }
        return CoachingStep(kind: kind, position: lead.position, clipTime: lead.clipTime,
                            metrics: [lead.id] + together, text: text)
    }

    /// The position to show what went right: impact when it was measured,
    /// otherwise the position with the most judged checks in zone. Only
    /// `among` is considered when given.
    private static func goodPicture(in report: SwingCoachingReport, among: Set<CoachingMetricID>?)
        -> (position: Int, clipTime: Double, metrics: [CoachingMetricID])? {
        let inZone = report.metrics.filter { $0.definition.scored && $0.inZone && (among?.contains($0.id) ?? true) }
        let byPosition = Dictionary(grouping: inZone, by: \.position)
        let position = byPosition[7] != nil && among == nil ? 7
            : byPosition.max { ($0.value.count, -$0.key) < ($1.value.count, -$1.key) }?.key
        guard let position, let results = byPosition[position], let first = results.first else { return nil }
        let ordered = results.sorted { $0.definition.weight > $1.definition.weight }
        return (position, first.clipTime, ordered.map(\.id))
    }

    /// The position in plain words, for the step card and the list.
    static func place(_ position: Int) -> String {
        switch position {
        case 1: "At address"
        case 2: "In the takeaway"
        case 3: "Halfway back"
        case 4: "At the top"
        case 5: "Halfway down"
        case 6: "Just before impact"
        case 7: "At impact"
        case 8: "Just after impact"
        case 9: "Halfway through"
        default: "At the finish"
        }
    }
}

// MARK: - Club-head trail

/// The club head followed through the swing, cleaned for drawing: one point
/// per track sample where the club could be followed, with short gaps
/// filled in a straight line and marked as filled. Built from the clip's
/// evidence; a first reading from Auto's copies has no track, so no trail.
nonisolated struct CoachingClubTrail: Equatable {
    struct Point: Equatable {
        /// Seconds on the clip.
        let clipTime: Double
        /// Normalized to the displayed frame, like the drawings.
        let x: Double
        let y: Double
        /// False where the point was filled in between two seen ones.
        let seen: Bool
        /// True where the trail starts again after a gap too long to fill.
        var startsSegment = false
    }

    let points: [Point]

    /// Detections below this are not used.
    static let minimumConfidence = 0.25
    /// A trail needs this many seen points to be worth drawing.
    static let minimumSeen = 8
    /// Gaps longer than this, in real seconds, are left open.
    static let longestFill = 0.12

    /// Nil when the evidence has no track or the club couldn't be
    /// followed through enough of it.
    static func make(from evidence: SwingCoachingEvidence) -> CoachingClubTrail? {
        let samples = evidence.track.sorted { $0.clipTime < $1.clipTime }
        guard samples.count >= minimumSeen else { return nil }
        let aspect = evidence.aspect
        let timeScale = max(evidence.timeScale, 1)

        // A "club head" that sits still in most samples is a bag or a
        // spare club, not the swinging one.
        let all = samples.flatMap { $0.clubheads.filter { $0.confidence >= minimumConfidence } }
        func isStill(_ box: CoachingBox) -> Bool {
            let near = all.filter { abs($0.center.x - box.center.x) < 0.012 && abs($0.center.y - box.center.y) < 0.012 }
            return Double(near.count) > Double(samples.count) * 0.5
        }

        func distance(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
            // In frame heights, so a step across reads the same as one down.
            hypot((a.x - b.x) * aspect, a.y - b.y)
        }

        var chosen: [(time: Double, x: Double, y: Double)] = []
        for sample in samples {
            let candidates = sample.clubheads
                .filter { $0.confidence >= minimumConfidence && !isStill($0) }
                .map { (x: $0.center.x, y: $0.center.y, confidence: $0.confidence) }
            guard !candidates.isEmpty else { continue }
            if let last = chosen.last {
                let realGap = (sample.clipTime - last.time) / timeScale
                // A club head moves up to about 15 frame heights a second
                // through impact; anything further is another detection.
                let reach = 0.08 + 15 * max(realGap, 0)
                let nearest = candidates.min { distance(($0.x, $0.y), (last.x, last.y)) < distance(($1.x, $1.y), (last.x, last.y)) }!
                if distance((nearest.x, nearest.y), (last.x, last.y)) <= reach {
                    chosen.append((sample.clipTime, nearest.x, nearest.y))
                }
            } else {
                let best = candidates.max { $0.confidence < $1.confidence }!
                chosen.append((sample.clipTime, best.x, best.y))
            }
        }
        guard chosen.count >= minimumSeen else { return nil }

        // Fill short gaps between seen points at the samples' own times.
        let sampleTimes = samples.map(\.clipTime)
        var points: [Point] = []
        for (index, point) in chosen.enumerated() {
            if index > 0 {
                let previous = chosen[index - 1]
                let gap = (point.time - previous.time) / timeScale
                let missing = sampleTimes.filter { $0 > previous.time && $0 < point.time }
                if !missing.isEmpty, gap <= longestFill {
                    for time in missing {
                        let t = (time - previous.time) / (point.time - previous.time)
                        points.append(Point(clipTime: time, x: previous.x + (point.x - previous.x) * t,
                                            y: previous.y + (point.y - previous.y) * t, seen: false))
                    }
                    points.append(Point(clipTime: point.time, x: point.x, y: point.y, seen: true))
                    continue
                }
                if !missing.isEmpty {
                    points.append(Point(clipTime: point.time, x: point.x, y: point.y, seen: true, startsSegment: true))
                    continue
                }
            }
            points.append(Point(clipTime: point.time, x: point.x, y: point.y, seen: true))
        }
        return CoachingClubTrail(points: points)
    }
}
