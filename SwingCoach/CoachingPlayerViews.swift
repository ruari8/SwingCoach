//
//  CoachingPlayerViews.swift
//  SwingCoach
//
//  Coaching inside the swing player, shared by Library and Auto review:
//  the drawings over the video, the step card that walks through the
//  swing's findings, the marks on the pose strip, the Layers tool and
//  the list of every check.
//
//  A swing opens paused on its first step (the verdict) with that step's
//  drawing up. Next walks the other faults in swing order. Playing the
//  swing holds each step's drawing from its frame until the next step's.
//

import AVFoundation
import SwiftUI
import UIKit

// MARK: - Which drawings are on

/// What the player draws over a swing, chosen with the player's Drawings
/// tool. It lasts for one review and covers every swing in it; the video
/// says when it differs from the coach's choice.
struct CoachingLayers: Equatable {
    /// Each step's drawing.
    var coach = true
    /// The club head's path while the swing plays.
    var clubPath = true
    /// Every check measured on the paused frame, in-zone ones too.
    var everyCheck = false

    static let coachsChoice = CoachingLayers()
    var isCoachsChoice: Bool { self == .coachsChoice }
}

/// How close the playhead has to be to a step's frame to be on it.
private let stopTolerance = 0.02

// MARK: - Words and numbers

extension CoachingUnit {
    /// One decimal where the number has one, as zone edges do.
    func formatEdge(_ value: Double) -> String {
        if value == 0 { return self == .degrees ? "0°" : "0%" }
        let whole = value.rounded() == value
        let number = whole ? String(format: "%+.0f", value) : String(format: "%+.1f", value)
        let signed = number.replacingOccurrences(of: "-", with: "−")
        switch self {
        case .bodyPercent: return signed + "%"
        case .degrees: return signed + "°"
        }
    }
}

enum CoachingWords {
    static func value(_ result: CoachingMetricResult) -> String {
        result.definition.unit.formatEdge(result.value.rounded())
    }

    static func zone(_ definition: CoachingMetricDefinition) -> String {
        "\(definition.unit.formatEdge(definition.zone.lowerBound)) to \(definition.unit.formatEdge(definition.zone.upperBound))"
    }

    /// "You: +4%. Good players: −3.5% to +3%."
    static func numbers(_ result: CoachingMetricResult) -> String {
        let definition = result.definition
        guard definition.scored else { return "You: \(value(result)). A guide, not judged." }
        return "You: \(value(result)). Good players: \(zone(definition))."
    }

    /// A level spelled out, the one wording everywhere: "2 steps out",
    /// "In zone", "Not judged".
    static func level(_ result: CoachingMetricResult, neutral: Bool = false) -> String {
        guard result.definition.scored, !neutral else { return "Not judged" }
        return steps(result.level)
    }

    /// "2 steps out", "1 step out", or "In zone".
    static func steps(_ level: Int) -> String {
        let steps = abs(level)
        return steps == 0 ? "In zone" : "\(steps) step\(steps == 1 ? "" : "s") out"
    }

    /// Why a check isn't judged, short enough for a row: "a guide",
    /// "short swing".
    static func notJudgedReason(_ result: CoachingMetricResult, exclusion: CoachingExclusion?) -> String {
        if let exclusion { return reason(exclusion) }
        return result.definition.scored ? "" : "a guide"
    }

    /// Why a swing isn't judged, as a caption says it after "Not judged ·".
    static func reason(_ exclusion: CoachingExclusion) -> String {
        switch exclusion {
        case .shortSwing: "short swing"
        case .cameraMoved: "camera moved"
        case .positionsUnclear: "positions unclear"
        }
    }

    /// Why a swing has no level on a theme: its exclusion, or no reading
    /// of the theme's check on it (or no reading yet).
    static func reason(notJudged report: SwingCoachingReport?) -> String {
        guard let exclusion = report?.exclusion else { return "no reading" }
        return reason(exclusion)
    }

    /// "Not judged", with its reason when known: "Not judged · camera
    /// moved". The one caption for a swing or check without a level.
    static func notJudged(_ reason: String) -> String {
        reason.isEmpty ? "Not judged" : "Not judged · \(reason)"
    }

    /// The key's word for a number in a level badge, said one way
    /// wherever a row of badges is keyed (the session review, a recap,
    /// All checks).
    static let numberKey = "Number = steps out"

    /// A club reading's caveat, the one line everywhere it is shown: the
    /// club checks move with where the camera stands.
    static let cameraCaveat = "Depends on camera position"

    /// What to do about it, said only where there is room for the detail
    /// (All checks).
    static let cameraAdvice = "Check it with the camera on your hand line."

    /// The word beside a level badge: "steps out" after a 4, "In zone"
    /// after a tick, so the badge never reads as a count. "N steps out" is
    /// the one phrase for a distance outside the zone, everywhere.
    static func badgeWord(level: Int, scored: Bool = true, neutral: Bool = false) -> String {
        if neutral || !scored { return "Not judged" }
        let steps = abs(level)
        guard steps > 0 else { return "In zone" }
        return steps == 1 ? "step out" : "steps out"
    }

    /// What a step is, said once where the marks are keyed. A level counts
    /// steps outside good players' zone, and each check has its own step
    /// (docs/COACHING.md, Metrics).
    static let stepDefinition = "1 step = a set distance past good players' zone, per check."

    /// Which side of good players' zone a reading is on.
    static func side(_ result: CoachingMetricResult) -> String {
        let zone = result.definition.zone
        if result.value > zone.upperBound { return "Above zone" }
        if result.value < zone.lowerBound { return "Below zone" }
        return "In zone"
    }

    /// Which swings showed a theme, said as what happened, naming the
    /// check its level is read on and the denominator: "On 4 of 8 swings
    /// with a takeaway (P2) reading", "On all 4 swings with a shaft
    /// halfway back (P3) reading", or "On 4 of 8 swings with a reading"
    /// beside a position tag that already names it.
    static func themeShare(_ theme: CoachingTheme, namingPosition: Bool = true) -> String {
        let count = swingCount(theme.swings, of: theme.measured)
        guard namingPosition else { return "On \(count) with a reading" }
        let check = CoachingMetricDefinition.definition(theme.metric).title.lowercased()
        let article = check.first.map { "aeiou".contains($0) } == true ? "an" : "a"
        return "On \(count) with \(article) \(check) (P\(theme.position)) reading"
    }

    /// A recap's theme counted over the swings that were judged: "On all
    /// 4 judged swings", "On 3 of 5 judged swings". Where the theme's
    /// check couldn't be read on every judged swing, the reading count.
    static func recapShare(_ theme: CoachingTheme, judged: Int) -> String {
        guard theme.measured == judged else { return themeShare(theme) }
        return "On \(swingCount(theme.swings, of: judged, noun: "judged swing"))"
    }

    private static func swingCount(_ swings: Int, of total: Int, noun: String = "swing") -> String {
        switch total {
        case 1: "the 1 \(noun)"
        case swings where swings > 1: "all \(total) \(noun)s"
        default: "\(swings) of \(total) \(noun)s"
        }
    }

    /// What a check says, in or out of its zone.
    static func headline(_ result: CoachingMetricResult) -> String {
        result.finding ?? (result.definition.scored ? "\(result.definition.title): in zone" : result.definition.title)
    }

    static func exclusion(_ exclusion: CoachingExclusion) -> String {
        switch exclusion {
        case .shortSwing: "A chip or pitch. The zones come from full swings, so it is measured but not judged."
        case .cameraMoved: "The camera moved during the swing, so nothing can be compared with address."
        case .positionsUnclear: "Address or impact couldn't be found clearly on this video."
        }
    }

    static func unit(_ unit: CoachingUnit) -> String {
        switch unit {
        case .bodyPercent: "percent of body height"
        case .degrees: "degrees"
        }
    }
}

// MARK: - What the player needs

extension SwingCoachingStore {
    /// The frames the player stops on: each step's, and a picked check's.
    func walkthroughStops(for swing: SavedSwing, highlighted: CoachingMetricID?) -> [PlayerWalkthroughStop] {
        guard Self.canCoach(swing) else { return [] }
        var stops = steps(for: swing).map { PlayerWalkthroughStop(clipTime: $0.clipTime, position: $0.position) }
        if let highlighted, let result = report(for: swing)?.metric(highlighted) {
            stops.append(PlayerWalkthroughStop(clipTime: result.clipTime, position: result.position))
        }
        return stops
    }

    /// Top to bottom (0...1) of the step's own finding at a stop (or the
    /// picked check), and down to the club head on that frame (at the ball
    /// around impact), so the player can keep both clear of the step card.
    func focusRange(for swing: SavedSwing, at time: Double, highlighted: CoachingMetricID?) -> ClosedRange<Double>? {
        guard let report = report(for: swing) else { return nil }
        var ids: [CoachingMetricID] = []
        if let highlighted, let result = report.metric(highlighted), abs(result.clipTime - time) <= stopTolerance {
            ids = [highlighted]
        } else if let step = steps(for: swing).first(where: { abs($0.clipTime - time) <= stopTolerance }) {
            ids = step.lead.map { [$0] } ?? []
        }
        var ys: [Double] = []
        for result in ids.compactMap(report.metric) {
            for shape in result.drawings {
                let size = shape.size ?? 0
                ys += shape.points.flatMap { [$0.y - size, $0.y + size] }
            }
        }
        guard let low = ys.min(), var high = ys.max() else { return nil }
        // The club head only pushes the bottom down: a club high in the
        // backswing must not stop the frame lifting.
        if let head = clubTrail(for: swing)?.points.min(by: { abs($0.clipTime - time) < abs($1.clipTime - time) }),
           abs(head.clipTime - time) <= 0.05 {
            high = max(high, head.y + 0.03)
        }
        return max(0, low)...min(1, high)
    }

    func stripMarks(for swing: SavedSwing) -> [Int: SwingPositionMark] {
        guard Self.canCoach(swing) else { return [:] }
        return CoachingStripMarks.marks(for: report(for: swing), steps: steps(for: swing))
    }
}

// MARK: - Marks on the pose strip

enum CoachingStripMarks {
    /// A mark on each position with a judged check: the furthest level out
    /// of zone there, or a tick when every check there is in zone. The
    /// walkthrough's first stop says so to VoiceOver.
    static func marks(for report: SwingCoachingReport?, steps: [CoachingStep]) -> [Int: SwingPositionMark] {
        guard let report, report.exclusion == nil else { return [:] }
        var marks: [Int: SwingPositionMark] = [:]
        let judged = Dictionary(grouping: report.metrics.filter(\.definition.scored), by: \.position)
        for (position, results) in judged {
            let worst = results.max { abs($0.level) < abs($1.level) }
            let isStart = steps.first?.position == position
            if let worst, worst.level != 0 {
                let out = results.filter { $0.level != 0 }.count
                marks[position] = SwingPositionMark(
                    shape: .level(abs(worst.level)), colour: .coachingLevel(worst.level), isStart: isStart,
                    accessibilityText: "\(out) check\(out == 1 ? "" : "s") out of zone, up to \(CoachingWords.steps(worst.level))"
                        + (isStart ? ", the coach starts here" : ""))
            } else {
                marks[position] = SwingPositionMark(
                    shape: .tick, colour: .coachingLevel(0), isStart: isStart,
                    accessibilityText: "\(results.count) check\(results.count == 1 ? "" : "s") in zone"
                        + (isStart ? ", the coach starts here" : ""))
            }
        }
        return marks
    }
}

// MARK: - Drawings

/// One or more checks' drawings on a frame. White is address or a fixed
/// guide, shaded green with an edge is where good players are, and the
/// swing now is in its level's colour. A guide that isn't judged, and any
/// check on a swing that isn't judged, is drawn in the neutral guide
/// style instead: grey, never green, so it never reads as in zone.
/// `revealed` draws them in that order: 1 address, 2 adds the zone, 3 adds
/// the swing.
struct CoachingDrawingLayer: View {
    let results: [CoachingMetricResult]
    /// The video's displayed rectangle in this view.
    let rect: CGRect
    var still = false
    var revealed = 3
    /// Not judged: the swing is drawn grey, not in a level's colour.
    var neutral = false

    var body: some View {
        ZStack {
            canvas(.zone).opacity(revealed >= 2 ? 1 : 0)
            canvas(.reference).opacity(revealed >= 1 ? 1 : 0)
            canvas(.subject).opacity(revealed >= 3 ? 1 : 0)
        }
        .allowsHitTesting(false)
    }

    private func canvas(_ role: CoachingDrawing.Role) -> some View {
        Canvas { context, _ in
            for result in results {
                var layer = context
                var lineWeight = weight
                // Address is where the swing is measured from, not the
                // point: thinner and dimmer, so where it meets the swing's
                // mark and the zone the three never stack into one blob.
                if role == .reference {
                    lineWeight *= Self.referenceWeight
                    layer.opacity *= Self.referenceOpacity
                }
                let ringed = Self.isRinged(result)
                for shape in result.drawings where shape.role == role {
                    draw(shape, of: result, weight: lineWeight, ringed: ringed, context: &layer)
                }
            }
        }
    }

    private var weight: CGFloat { still ? max(1.5, min(3, rect.height / 110)) : 4 }

    /// The swing's line on a swing that isn't judged, and on a guide.
    static let neutralColour = Color(white: 0.82)
    /// The address reference against the swing's own line.
    static let referenceWeight: CGFloat = 0.55
    static let referenceOpacity = 0.7
    /// The swing's ring (the head now) against the drawing's weight: one
    /// solid outline, the strongest mark on the head.
    static let ringWeight: CGFloat = 0.6
    /// The address ring: thin and dashed, so it reads as where the head
    /// was, never as a second reading.
    static let referenceRingWeight: CGFloat = 0.38
    /// The reading's dot, against the drawing's weight: the largest mark.
    static let dotRadius: CGFloat = 2.2
    /// The dark edge round every line, ring and zone edge, so each holds
    /// on sky, grass and mat: this much wider than the line it edges.
    static let haloExtra: CGFloat = 2.5
    static let haloColour = Color.black.opacity(0.55)
    /// A zone's edge against the drawing's weight, with the measured
    /// line's dark halo, so the zone holds its shape on green turf.
    static let zoneEdgeWeight: CGFloat = 0.5
    static let zoneEdgeExtra: CGFloat = 0.75
    static let zoneEdgeMinimum: CGFloat = 2
    static let zoneFillOpacity = 0.38
    /// The dashes of the address ring, against its line width.
    static func ringDash(_ width: CGFloat) -> [CGFloat] { [width * 2.6, width * 2] }

    /// A check drawn round a ring (the head now and at address).
    static func isRinged(_ result: CoachingMetricResult) -> Bool {
        result.drawings.contains { $0.kind == .circle && $0.role != .zone }
    }

    /// Drawn in the neutral guide style: a guide, or any check on a swing
    /// that isn't judged.
    static func isNeutral(_ result: CoachingMetricResult, swingNeutral: Bool) -> Bool {
        swingNeutral || !result.definition.scored
    }

    /// The colour of the swing's own line (and its tag and legend key).
    static func subjectColour(_ result: CoachingMetricResult, swingNeutral: Bool) -> Color {
        isNeutral(result, swingNeutral: swingNeutral) ? neutralColour : .coachingLevel(result.level)
    }

    /// Good players' zone: green, except on a guide, which isn't judged.
    static func zoneColour(_ result: CoachingMetricResult) -> Color {
        result.definition.scored ? .coachingLevel(0) : .white
    }

    private func draw(_ shape: CoachingDrawing, of result: CoachingMetricResult, weight: CGFloat,
                      ringed: Bool, context: inout GraphicsContext) {
        let colour: Color = switch shape.role {
        case .reference: .white
        case .zone: Self.zoneColour(result)
        case .subject: Self.subjectColour(result, swingNeutral: neutral)
        }
        let points = shape.points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        let size = CGFloat(shape.size ?? 0) * rect.height
        let dash: [CGFloat] = shape.dashed ? [weight * 2.2, weight * 1.6] : []
        let stroke = StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round, dash: dash)
        // A dark edge keeps lines readable on sky and grass.
        let edge = StrokeStyle(lineWidth: weight + Self.haloExtra, lineCap: .round, lineJoin: .round, dash: dash)
        let edgeColour = Self.haloColour

        func zoneFill(_ path: Path) {
            // A translucent fill, and an edge with the measured line's
            // dark halo, so it holds its shape on green turf and mat.
            let zoneEdge = max(Self.zoneEdgeMinimum, weight * Self.zoneEdgeWeight + Self.zoneEdgeExtra)
            context.fill(path, with: .color(colour.opacity(Self.zoneFillOpacity)))
            context.stroke(path, with: .color(edgeColour),
                           style: StrokeStyle(lineWidth: zoneEdge + Self.haloExtra, lineJoin: .round))
            context.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: zoneEdge, lineJoin: .round))
        }

        switch shape.kind {
        case .line:
            guard points.count == 2 else { return }
            var path = Path()
            path.move(to: points[0])
            path.addLine(to: points[1])
            context.stroke(path, with: .color(edgeColour), style: edge)
            context.stroke(path, with: .color(colour), style: stroke)
        case .area:
            guard points.count >= 3 else { return }
            var path = Path()
            path.addLines(points)
            path.closeSubpath()
            zoneFill(path)
        case .band:
            guard points.count == 2 else { return }
            let delta = CGPoint(x: points[1].x - points[0].x, y: points[1].y - points[0].y)
            let length = max(hypot(delta.x, delta.y), 0.001)
            let normal = CGPoint(x: -delta.y / length * size, y: delta.x / length * size)
            var path = Path()
            path.move(to: CGPoint(x: points[0].x + normal.x, y: points[0].y + normal.y))
            path.addLine(to: CGPoint(x: points[1].x + normal.x, y: points[1].y + normal.y))
            path.addLine(to: CGPoint(x: points[1].x - normal.x, y: points[1].y - normal.y))
            path.addLine(to: CGPoint(x: points[0].x - normal.x, y: points[0].y - normal.y))
            path.closeSubpath()
            zoneFill(path)
        case .circle:
            guard let centre = points.first else { return }
            let path = Path(ellipseIn: CGRect(x: centre.x - size, y: centre.y - size, width: size * 2, height: size * 2))
            if shape.role == .zone {
                zoneFill(path)
            } else {
                // A ring (the head) is only an outline with the line's dark
                // halo: the address ring thin and dashed, this swing's one
                // solid ring, so the two never stack into one blob with
                // the zone and the face shows through both.
                let isAddress = shape.role == .reference
                let ring = max(isAddress ? 1.25 : 2, weight * (isAddress ? Self.referenceRingWeight : Self.ringWeight))
                let ringDash = isAddress ? Self.ringDash(ring) : []
                context.stroke(path, with: .color(edgeColour),
                               style: StrokeStyle(lineWidth: ring + Self.haloExtra, lineCap: .round, dash: ringDash))
                context.stroke(path, with: .color(colour),
                               style: StrokeStyle(lineWidth: ring, lineCap: .round, dash: ringDash))
            }
        case .dot:
            // The reading itself: the strongest mark on the frame. A head
            // check's reading is its ring, so no dot is drawn inside it.
            guard !ringed, let centre = points.first else { return }
            let radius = weight * Self.dotRadius
            let path = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
            context.fill(path, with: .color(colour))
            context.stroke(path, with: .color(.black.opacity(0.75)), lineWidth: 2)
        case .label:
            guard let anchor = points.first, let text = shape.text else { return }
            context.draw(Text(text).font(FixedType.readout).foregroundColor(colour), at: anchor, anchor: .leading)
        }
    }

    /// Where a check's tag sits: the end of the swing's own line, or its
    /// dot, in view points.
    static func anchor(of result: CoachingMetricResult, in rect: CGRect) -> CGPoint? {
        let shapes = result.drawings.filter { $0.role == .subject && $0.kind != .label }
            + result.drawings.filter { $0.role != .subject && $0.kind != .label }
        guard let shape = shapes.first else { return nil }
        let point: CoachingPoint
        switch shape.kind {
        case .line, .band: point = shape.points.last ?? shape.points[0]
        case .circle:
            guard let centre = shape.points.first else { return nil }
            point = CoachingPoint(x: centre.x, y: centre.y + (shape.size ?? 0))
        default:
            guard let first = shape.points.first else { return nil }
            point = first
        }
        return CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }
}

/// The club head's path up to the playhead: the accent lime, the colour of
/// the clubs on the pose strip, never a level's colour. Filled-in stretches
/// are dashed.
struct CoachingTrailLayer: View {
    let trail: CoachingClubTrail
    let rect: CGRect
    let upTo: Double

    static let colour = Color.accentLime

    var body: some View {
        Canvas { context, _ in
            let shown = trail.points.filter { $0.clipTime <= upTo + stopTolerance }
            guard shown.count >= 2 else { return }
            func place(_ point: CoachingClubTrail.Point) -> CGPoint {
                CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
            }
            var seen = Path(), filled = Path()
            for (previous, point) in zip(shown, shown.dropFirst()) where !point.startsSegment {
                if previous.seen && point.seen {
                    seen.move(to: place(previous))
                    seen.addLine(to: place(point))
                } else {
                    filled.move(to: place(previous))
                    filled.addLine(to: place(point))
                }
            }
            let round = StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            context.stroke(seen, with: .color(.black.opacity(0.45)), style: round)
            context.stroke(seen, with: .color(Self.colour), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            let dashed = StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [4, 5])
            context.stroke(filled, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [4, 5]))
            context.stroke(filled, with: .color(Self.colour), style: dashed)
            if let head = shown.last {
                let centre = place(head)
                let dot = Path(ellipseIn: CGRect(x: centre.x - 4, y: centre.y - 4, width: 8, height: 8))
                context.fill(dot, with: .color(Self.colour))
                context.stroke(dot, with: .color(.black.opacity(0.6)), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Coaching over the playing video. Paused on a step's frame, that step's
/// drawing builds up: address, then the zone, then the swing, each with a
/// tag of its number on the drawing. Playing, each step's drawing holds,
/// faded, from its frame until the next step's, under the club's path.
/// Paused anywhere else, only checks measured on that frame are drawn,
/// and only with "Every check at this frame" on.
struct SwingCoachingOverlay: View {
    let report: SwingCoachingReport?
    let steps: [CoachingStep]
    let trail: CoachingClubTrail?
    let layers: CoachingLayers
    let aspectRatio: Double?
    let currentTime: CMTime
    /// A check picked from the list or a comparison: drawn on its own frame.
    let highlighted: CoachingMetricID?

    @Environment(\.playerIsPlaying) private var isPlaying
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = 3
    @State private var revealKey: String?

    private struct Shown {
        var results: [CoachingMetricResult] = []
        /// Drawn past its own frame while the swing plays.
        var held = false
        /// Identifies a paused stop, so its drawing builds up once.
        var stopKey: String?
        var showsTrail = false
        /// The checks that get a name tag; every one drawn when nil.
        var tagged: Set<CoachingMetricID>?
    }

    /// A step draws only its own finding, so the eye goes to one place on
    /// the body; the checks supporting it are drawn only with "Every check
    /// on the frame".
    private func leadOnly(_ shown: inout Shown) {
        guard let lead = shown.results.first else { return }
        shown.results = [lead]
        shown.tagged = [lead.id]
    }

    private func shown(at now: Double) -> Shown {
        guard let report else { return Shown() }
        let neutral = report.exclusion != nil
        func atFrame() -> [CoachingMetricResult] {
            report.metrics.filter { abs($0.clipTime - now) <= stopTolerance }
        }
        if isPlaying {
            guard layers.coach, !neutral, let step = steps.last(where: { $0.clipTime <= now + stopTolerance }) else {
                return Shown(showsTrail: layers.clubPath)
            }
            let results = step.metrics.compactMap(report.metric)
            var shown = Shown(results: results, held: now - step.clipTime > stopTolerance, showsTrail: layers.clubPath)
            leadOnly(&shown)
            return shown
        }
        var shown = Shown()
        if let highlighted, let result = report.metric(highlighted), abs(result.clipTime - now) <= stopTolerance {
            shown.results = [result]
            shown.stopKey = "check-\(highlighted.rawValue)"
        } else if let step = steps.first(where: { abs($0.clipTime - now) <= stopTolerance }) {
            shown.results = layers.coach ? step.metrics.compactMap(report.metric) : []
            shown.stopKey = step.id
            // "Every check on the frame" keeps a tag on every drawing.
            if !layers.everyCheck { leadOnly(&shown) }
        } else {
            shown.showsTrail = layers.clubPath
        }
        if layers.everyCheck {
            let ids = Set(shown.results.map(\.id))
            shown.results += atFrame().filter { !ids.contains($0.id) }
        }
        return shown
    }

    var body: some View {
        let now = CMTimeGetSeconds(currentTime)
        let shown = now.isFinite ? shown(at: now) : Shown()
        GeometryReader { geometry in
            if let aspectRatio {
                let rect = VideoDisplayGeometry.contentRect(in: geometry.size, aspectRatio: aspectRatio)
                ZStack(alignment: .topLeading) {
                    if shown.showsTrail, let trail {
                        CoachingTrailLayer(trail: trail, rect: rect, upTo: now)
                    }
                    if !shown.results.isEmpty {
                        CoachingDrawingLayer(results: shown.results, rect: rect,
                                             revealed: shown.stopKey == nil ? 3 : (revealKey == shown.stopKey ? revealed : 0),
                                             neutral: report?.exclusion != nil)
                            .opacity(shown.held ? 0.55 : 1)
                        if !shown.held {
                            tags(shown.results, tagged: shown.tagged, in: rect,
                                 bounds: CGRect(origin: .zero, size: geometry.size))
                                .opacity(shown.stopKey == nil || (revealKey == shown.stopKey && revealed >= 3) ? 1 : 0)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: shown.stopKey, initial: true) { _, key in
            reveal(key)
        }
    }

    /// Address, then the zone, then the swing; all at once with Reduce Motion.
    private func reveal(_ key: String?) {
        guard let key else {
            revealKey = nil
            return
        }
        guard key != revealKey else { return }
        revealKey = key
        if reduceMotion {
            revealed = 0
            withAnimation(.easeOut(duration: 0.25)) { revealed = 3 }
            return
        }
        revealed = 0
        Task { @MainActor in
            for stage in 1...3 {
                guard revealKey == key else { return }
                withAnimation(.easeOut(duration: 0.18)) { revealed = stage }
                try? await Task.sleep(nanoseconds: 260_000_000)
            }
        }
    }

    /// A footnote bold character is about 8 pt wide, plus the padding.
    private static func tagWidth(_ result: CoachingMetricResult) -> CGFloat {
        CGFloat(result.definition.title.count) * 8 + 16
    }

    private static let tagHeight: CGFloat = 26

    /// Where each name tag sits: beside its drawing, moved down a row when
    /// it would cover a tag already placed, so two checks on one frame
    /// never print over each other.
    private func tagCentres(_ results: [CoachingMetricResult], in rect: CGRect) -> [CoachingMetricID: CGPoint] {
        let rowHeight: CGFloat = 30
        var placed: [CGRect] = []
        var centres: [CoachingMetricID: CGPoint] = [:]
        let anchored = results.compactMap { result in
            CoachingDrawingLayer.anchor(of: result, in: rect).map { (result, $0) }
        }.sorted { $0.1.y < $1.1.y }
        for (result, anchor) in anchored {
            let width = Self.tagWidth(result)
            var centre = CGPoint(x: min(max(anchor.x + 34, rect.minX + width / 2 + 6), rect.maxX - width / 2 - 6),
                                 y: min(max(anchor.y - 16, rect.minY + 14), rect.maxY - 14))
            func frame(_ point: CGPoint) -> CGRect {
                CGRect(x: point.x - width / 2, y: point.y - rowHeight / 2, width: width, height: rowHeight)
            }
            while let hit = placed.first(where: { $0.intersects(frame(centre)) }) {
                centre.y = hit.maxY + rowHeight / 2 + 2
            }
            placed.append(frame(centre))
            centres[result.id] = centre
        }
        return centres
    }

    /// One tag on the frame: beside everything drawn there, at the height
    /// of its own line, so it sits next to the golfer rather than on the
    /// head. Right of the drawing, else left, else above, else below; clear
    /// of the tool rail on either side and the header over the video. A
    /// head check's tag goes above first, a further ring's height up, so
    /// it sits in clear space over the hat, never touching it.
    private func besideCentre(of result: CoachingMetricResult, among results: [CoachingMetricResult],
                              in rect: CGRect, bounds: CGRect) -> CGPoint? {
        guard let anchor = CoachingDrawingLayer.anchor(of: result, in: rect) else { return nil }
        var drawn = CGRect.null
        for shape in results.flatMap(\.drawings) where shape.kind != .label {
            let size = CGFloat(shape.size ?? 0) * rect.height
            for point in shape.points {
                let x = rect.minX + point.x * rect.width, y = rect.minY + point.y * rect.height
                drawn = drawn.union(CGRect(x: x - size, y: y - size, width: size * 2, height: size * 2))
            }
        }
        if drawn.isNull { drawn = CGRect(origin: anchor, size: .zero) }
        let width = Self.tagWidth(result), height = Self.tagHeight, gap: CGFloat = 10
        // The head's ring is drawn round the face; the top of the head and
        // a hat sit up to a ring's height above it.
        let headRing = CoachingDrawingLayer.isRinged(result)
            ? result.drawings.filter { $0.kind == .circle && $0.role != .zone }
                .map { CGFloat($0.size ?? 0) * rect.height }.max() ?? 0
            : 0
        var safe = rect.intersection(bounds).inset(by: UIEdgeInsets(top: 64, left: 56, bottom: 12, right: 56))
        if safe.isNull || safe.width < width || safe.height < height { safe = rect.intersection(bounds) }
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, safe.minX + width / 2), safe.maxX - width / 2) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, safe.minY + height / 2), safe.maxY - height / 2) }
        let above = CGPoint(x: clampX(drawn.midX), y: drawn.minY - headRing - gap - height / 2)
        let beside = [
            CGPoint(x: drawn.maxX + gap + width / 2, y: clampY(anchor.y)),
            CGPoint(x: drawn.minX - gap - width / 2, y: clampY(anchor.y)),
        ]
        let below = CGPoint(x: clampX(drawn.midX), y: drawn.maxY + gap + height / 2)
        let candidates = headRing > 0 ? [above] + beside + [below] : beside + [above, below]
        return candidates.first { centre in
            safe.contains(CGRect(x: centre.x - width / 2, y: centre.y - height / 2, width: width, height: height))
        } ?? CGPoint(x: clampX(drawn.maxX + gap + width / 2), y: clampY(anchor.y))
    }

    private func tags(_ results: [CoachingMetricResult], tagged: Set<CoachingMetricID>?, in rect: CGRect,
                      bounds: CGRect) -> some View {
        let named = results.filter { tagged?.contains($0.id) ?? true }
        var centres: [CoachingMetricID: CGPoint]
        if named.count == 1, let only = named.first {
            centres = [:]
            centres[only.id] = besideCentre(of: only, among: results, in: rect, bounds: bounds)
        } else {
            centres = tagCentres(named, in: rect)
        }
        let swingNeutral = report?.exclusion != nil
        return ForEach(named, id: \.id) { result in
            if let centre = centres[result.id] {
                // A name, not a number: the numbers are in All checks.
                Text(result.definition.title)
                    .font(.appCaptionLabel.monospacedDigit())
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(
                        CoachingDrawingLayer.subjectColour(result, swingNeutral: swingNeutral)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.black.opacity(0.5), lineWidth: 1))
                    .fixedSize()
                    .position(centre)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(CoachingWords.headline(result)), \(CoachingWords.value(result))")
                    .accessibilityIdentifier("coaching-caption-\(result.id.rawValue)")
            }
        }
    }
}

// MARK: - The step card

/// A level as a shape and a number: a tick in zone, the number of steps
/// out in the level's colour, a dash for a guide that isn't judged.
/// Outlined (a ring and the number in the level's colour, no fill) for a
/// swing out the other way on a recap: out, but not the theme.
struct CoachingLevelBadge: View {
    let level: Int
    var scored = true
    var neutral = false
    var size: CGFloat = 24
    var outlined = false

    /// One swing's mark in a row of swings: the session review's dots and
    /// the recap's slots, big enough to read from the tripod.
    static let markSize: CGFloat = 26

    var body: some View {
        let colour: Color = neutral || !scored ? .notJudged : .coachingLevel(level)
        ZStack {
            if outlined {
                Circle().strokeBorder(colour, lineWidth: max(1.5, size * 0.09))
            } else {
                Circle().fill(colour)
            }
            if !scored || neutral {
                Image(systemName: "minus").font(.system(size: size * 0.45, weight: .heavy))
            } else if level == 0 {
                Image(systemName: "checkmark").font(.system(size: size * 0.45, weight: .heavy))
            } else {
                Text("\(abs(level))").font(.system(size: size * 0.55, weight: .heavy).monospacedDigit())
            }
        }
        .foregroundStyle(outlined ? colour : .black)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// What a row of level badges means, said the same way wherever badges
/// are keyed (the session review, All checks): a tick, a number for steps
/// out, a dash for not judged, each beside one badge of one size. Only
/// the marks the row can have are keyed. Font and colour come from the
/// caller.
struct CoachingMarkKey: View {
    /// The tick's word, or nil to leave it out: "Good" for a swing's
    /// verdict, "In zone" for a check.
    var tick: String? = nil
    var number = true
    var dash = false
    /// What the dash means here.
    var dashWord = "Not judged"

    static let badgeSize: CGFloat = 16

    var body: some View {
        FlowLayout(spacing: 12, lineSpacing: 4) {
            if let tick {
                entry(CoachingLevelBadge(level: 0, size: Self.badgeSize), tick)
            }
            if number {
                entry(CoachingLevelBadge(level: 2, size: Self.badgeSize), CoachingWords.numberKey)
            }
            if dash {
                entry(CoachingLevelBadge(level: 0, neutral: true, size: Self.badgeSize), dashWord)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("coaching-mark-key")
    }

    private var spoken: String {
        var parts: [String] = []
        if let tick { parts.append("a tick is \(tick.lowercased())") }
        if number { parts.append("a number is steps out") }
        if dash { parts.append("a dash is \(dashWord.lowercased())") }
        return "Key: " + parts.joined(separator: ", ")
    }

    private func entry(_ badge: CoachingLevelBadge, _ word: String) -> some View {
        HStack(spacing: 4) {
            badge
            Text(word).fixedSize()
        }
    }
}

/// A club reading's caveat, the one wording everywhere
/// (`CoachingWords.cameraCaveat`), with a camera glyph so it reads as a
/// note on the reading, never as part of its level. On the player it is
/// near-white on the dark panel; on lists and sheets the help grey.
struct CoachingCameraCaveat: View {
    var onPlayer = false
    /// Adds what to do about it, where there is room (All checks).
    var advice = false

    var body: some View {
        Label {
            Text(CoachingWords.cameraCaveat + (advice ? ". " + CoachingWords.cameraAdvice : ""))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "camera.viewfinder")
        }
        .labelStyle(CaveatLabelStyle())
        .font(.appCaption)
        .foregroundStyle(onPlayer ? PlayerChrome.secondaryText : Color.helpText)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coaching-camera-caveat")
    }

    private struct CaveatLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                configuration.icon
                configuration.title
            }
        }
    }
}

/// One reading against good players' zone: a track with the zone as a
/// green band and this swing as a marker in its level's colour, and under
/// it the reading, the zone and which side of it the swing is, as
/// tabular numbers in columns that line up from row to row. A guide, or a
/// swing that isn't judged, is drawn in the neutral guide style.
struct CoachingZoneTrack: View {
    let result: CoachingMetricResult
    /// The swing isn't judged.
    var neutral = false

    private var judged: Bool { result.definition.scored && !neutral }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            track.frame(height: 14)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                column("You", CoachingWords.value(result),
                       colour: judged ? .coachingLevelText(result.level) : .primary, alignment: .leading,
                       swatch: AnyView(youSwatch))
                // Its natural width, so "Good players" never truncates; the
                // outer columns split the rest evenly, so it stays centred.
                column("Good players", CoachingWords.zone(result.definition), colour: .primary, alignment: .center,
                       swatch: AnyView(zoneSwatch))
                    .fixedSize(horizontal: true, vertical: false)
                // Not judged says so on the row's first line; no side here.
                column("", judged ? CoachingWords.side(result) : "",
                       colour: .coachingLevelText(result.level), alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(judged ? "\(CoachingWords.numbers(result)) \(CoachingWords.side(result))."
                            : result.definition.scored ? "\(CoachingWords.numbers(result)) Not judged." : CoachingWords.numbers(result))
        .accessibilityIdentifier("coaching-zone-track")
    }

    /// A column under the track: its name beside a swatch of its mark on
    /// the track (the dot, the band), in the heading grey, and the value in
    /// the label size, tabular.
    private func column(_ title: String, _ value: String, colour: Color, alignment: HorizontalAlignment,
                        swatch: AnyView? = nil) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            HStack(spacing: 4) {
                if let swatch { swatch }
                Text(title.isEmpty ? " " : title)
                    .font(.appCaptionLabel)
                    .foregroundStyle(Color.sectionHeading)
                    .lineLimit(1)
            }
            Text(value)
                .font(.appLabel.monospacedDigit())
                .foregroundStyle(colour)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    private static let swatchSize: CGFloat = 9

    /// The swing's marker as on the track: a solid dot in its level's
    /// colour, or a hollow ring when not judged.
    private var youSwatch: some View {
        let marker: Color = judged ? .coachingLevel(result.level) : CoachingDrawingLayer.neutralColour
        return ZStack {
            if judged {
                Circle().fill(marker)
                Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1)
            } else {
                Circle().strokeBorder(marker, lineWidth: 2)
            }
        }
        .frame(width: Self.swatchSize, height: Self.swatchSize)
        .accessibilityHidden(true)
    }

    /// Good players' zone as on the track: a green band, or a dashed
    /// outline when not judged.
    private var zoneSwatch: some View {
        let shape = RoundedRectangle(cornerRadius: 2)
        return ZStack {
            if judged {
                shape.fill(Color.coachingLevel(0).opacity(0.4))
                shape.strokeBorder(Color.coachingLevel(0), lineWidth: 1.5)
            } else {
                shape.strokeBorder(CoachingDrawingLayer.neutralColour.opacity(0.8),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            }
        }
        .frame(width: Self.swatchSize * 1.8, height: Self.swatchSize)
        .accessibilityHidden(true)
    }

    private var track: some View {
        let definition = result.definition
        let zone = definition.zone
        let low = min(zone.lowerBound, result.value), high = max(zone.upperBound, result.value)
        let margin = max((high - low) * 0.15, definition.step * 0.5)
        let bottom = low - margin, top = high + margin
        let marker: Color = judged ? .coachingLevel(result.level) : CoachingDrawingLayer.neutralColour
        let isJudged = judged
        return Canvas { context, size in
            let inset: CGFloat = 7
            func x(_ value: Double) -> CGFloat {
                inset + (size.width - 2 * inset) * CGFloat((value - bottom) / max(top - bottom, 0.001))
            }
            let mid = size.height / 2
            let rail = Path(roundedRect: CGRect(x: 0, y: mid - 2, width: size.width, height: 4), cornerRadius: 2)
            context.fill(rail, with: .color(.secondary.opacity(0.35)))
            let zoneRect = CGRect(x: x(zone.lowerBound), y: 1, width: max(x(zone.upperBound) - x(zone.lowerBound), 3),
                                  height: size.height - 2)
            let zonePath = Path(roundedRect: zoneRect, cornerRadius: 3)
            let centre = CGPoint(x: x(result.value), y: mid)
            let dot = Path(ellipseIn: CGRect(x: centre.x - 6, y: centre.y - 6, width: 12, height: 12))
            if isJudged {
                // Good players' zone as a green band, the swing as a solid
                // marker in its level's colour.
                context.fill(zonePath, with: .color(Color.coachingLevel(0).opacity(0.4)))
                context.stroke(zonePath, with: .color(Color.coachingLevel(0)), lineWidth: 1.5)
                context.fill(dot, with: .color(marker))
                context.stroke(dot, with: .color(.black.opacity(0.6)), lineWidth: 1.5)
            } else {
                // The neutral guide style: the zone as a dashed outline with
                // no fill and the swing as a hollow ring, so a reading inside
                // it never looks like a pass.
                context.stroke(zonePath, with: .color(marker.opacity(0.8)),
                               style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                let ring = Path(ellipseIn: CGRect(x: centre.x - 5, y: centre.y - 5, width: 10, height: 10))
                context.fill(ring, with: .color(.black.opacity(0.5)))
                context.stroke(ring, with: .color(marker), lineWidth: 2.5)
            }
        }
    }
}

/// The badge with a word after it ("4 steps out", "✓ In zone"), where the
/// bare badge could read as a count: the step card and the session
/// review's themes ("5 steps out, typical"). Strips and lists of marks keep
/// the bare badge. The word is the level's text ink, so it reads on the
/// dark player and on light Library sheets alike.
struct CoachingLevelPill: View {
    let level: Int
    var scored = true
    var neutral = false
    /// Said after the word: "typical" gives "5 steps out, typical".
    var note: String? = nil

    var body: some View {
        let judged = scored && !neutral
        let colour: Color = judged ? .coachingLevel(level) : .notJudged
        let word = CoachingWords.badgeWord(level: level, scored: scored, neutral: neutral)
            + (note.map { ", \($0)" } ?? "")
        HStack(spacing: 6) {
            CoachingLevelBadge(level: level, scored: scored, neutral: neutral, size: 20)
            Text(word)
                .font(.appLabel)
                .foregroundStyle(judged ? Color.coachingLevelText(level) : Color.helpText)
        }
        .padding(.leading, 3)
        .padding(.trailing, 10)
        .padding(.vertical, 2)
        .background(Capsule().fill(colour.opacity(0.16)))
        .overlay(Capsule().strokeBorder(colour.opacity(0.55), lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(judged && level != 0 ? "\(abs(level)) \(word)" : word)
        .accessibilityIdentifier("coaching-level-pill")
    }
}

/// The card under the video that walks through a swing's coaching. Paused
/// on a step it shows where in the swing, the one sentence, the numbers,
/// what the drawing's colours mean, and Back / Play / Next. Anywhere else
/// it folds to one line that brings the walkthrough back.
struct SwingCoachingPanel: View {
    let swing: SavedSwing
    let context: PlayerPanelContext
    @Binding var highlighted: CoachingMetricID?
    let onShowChecks: () -> Void
    /// The golfer moved through the walkthrough, so a new reading
    /// shouldn't move the frame under them.
    let onInteract: () -> Void

    @ObservedObject private var store = SwingCoachingStore.shared

    var body: some View {
        Group {
            if let report = store.report(for: swing) {
                coached(report)
            } else if store.failed.contains(swing.id) {
                failed
            } else {
                reading
            }
        }
        .foregroundStyle(.white)
        // A dark panel whatever the system appearance, so level inks and
        // help text resolve to their dark values.
        .environment(\.colorScheme, .dark)
        // Large text grows the card, not past the point where it hides the swing.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    // MARK: States without a report

    private var reading: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView().tint(.white).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Reading this swing")
                    .font(.appLabel)
                Text(readingDetail)
                    .font(.appBody)
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("swing-coaching-pending")
    }

    private var readingDetail: String {
        if store.isWaitingForAuto { return "It starts when Auto pauses. The video plays meanwhile." }
        switch store.swingsAhead(of: swing) {
        case let ahead? where ahead > 0:
            return "\(ahead) swing\(ahead == 1 ? "" : "s") ahead of it, about 10 seconds each on the phone. The video plays meanwhile."
        default: return "About 10 seconds on the phone. The video plays meanwhile."
        }
    }

    private var failed: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Couldn't read this swing")
                .font(.appLabel)
            Text(store.failureReasons[swing.id] ?? "The video couldn't be read.")
                .font(.appBody)
                .foregroundStyle(.white.opacity(0.82))
            Button {
                store.retry(swing)
            } label: {
                Text("Try again")
                    .font(.appLabel)
                    .frame(maxWidth: .infinity, minHeight: Self.buttonHeight)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coaching-retry")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("swing-coaching-failed")
    }

    // MARK: With a report

    @ViewBuilder
    private func coached(_ report: SwingCoachingReport) -> some View {
        let steps = store.steps(for: swing)
        let now = context.currentTime
        let atStep = context.isPlaying ? nil : steps.firstIndex { abs($0.clipTime - now) <= stopTolerance }
        let picked = context.isPlaying ? nil : highlighted.flatMap(report.metric).flatMap { abs($0.clipTime - now) <= stopTolerance ? $0 : nil }
        if let picked, atStep.map({ !steps[$0].metrics.contains(picked.id) }) ?? true {
            checkCard(picked, report: report, steps: steps)
        } else if let atStep {
            stepCard(steps[atStep], index: atStep, of: steps, report: report)
        } else if let first = steps.first {
            foldedLine(first, steps: steps)
        }
    }

    private func stepCard(_ step: CoachingStep, index: Int, of steps: [CoachingStep], report: SwingCoachingReport) -> some View {
        let lead = step.lead.flatMap(report.metric)
        let notJudged: CoachingExclusion? = if case .notJudged(let exclusion) = step.kind { exclusion } else { nil }
        // The legend keys what is drawn: the step's own finding only.
        let results = lead.map { [$0] } ?? []
        return VStack(alignment: .leading, spacing: Self.rowGap) {
            readingNote(report)
            HStack(alignment: .center) {
                // "Finding", not "step": "steps out" is the level's word.
                Text(placeLine(step) + (steps.count > 1 ? ", finding \(index + 1) of \(steps.count)" : ""))
                    .font(.appLabel)
                    .foregroundStyle(.white.opacity(0.82))
                    .accessibilityIdentifier("coaching-step-count")
                Spacer(minLength: 8)
                allChecksButton
            }
            // The All checks capsule stands taller than this row's text:
            // take its overhang out of the gap, so the text-to-text gaps
            // match the card's other rows.
            .padding(.bottom, -Self.rowGap)
            Text(step.text)
                .font(.appTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("coaching-step-title")
            levelRow(pill(step, lead: lead), dependsOnCamera: lead?.definition.dependsOnCamera == true,
                     legend: results.isEmpty ? nil : CoachingLegend(results: results))
            if notJudged != nil || step.kind == .good || step.kind == .better {
                detail(step, lead: lead, notJudged: notJudged, report: report)
            }
            buttons(index: index, of: steps)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Self.cardPadding)
        .background(cardBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coaching-step-card")
        .onChange(of: step.id) { _, _ in
            UIAccessibility.post(notification: .layoutChanged, argument: nil)
        }
    }

    private func placeLine(_ step: CoachingStep) -> String {
        if case .notJudged = step.kind { return "Measured only" }
        return CoachingWalkthrough.place(step.position)
    }

    @ViewBuilder
    private func badge(_ step: CoachingStep, lead: CoachingMetricResult?) -> some View {
        switch step.kind {
        case .notJudged: CoachingLevelBadge(level: 0, neutral: true)
        case .good, .better: CoachingLevelBadge(level: 0)
        case .pointer, .finding: CoachingLevelBadge(level: lead?.level ?? 0)
        }
    }

    @ViewBuilder
    private func pill(_ step: CoachingStep, lead: CoachingMetricResult?) -> some View {
        switch step.kind {
        case .notJudged: CoachingLevelPill(level: 0, neutral: true)
        case .good, .better: CoachingLevelPill(level: 0)
        case .pointer, .finding: CoachingLevelPill(level: lead?.level ?? 0)
        }
    }

    /// The level, then for a club reading the one caveat (the detail is in
    /// All checks), then what the drawing's marks mean, each beside the one
    /// before while the row has room and on its own line when it is full,
    /// so the card never grows a row it doesn't need.
    private func levelRow(_ pill: some View, dependsOnCamera: Bool, legend: CoachingLegend?) -> some View {
        FlowLayout(spacing: 12, lineSpacing: Self.rowGap) {
            pill
            if dependsOnCamera {
                CoachingCameraCaveat(onPlayer: true)
            }
            if let legend { legend }
        }
    }

    @ViewBuilder
    private func detail(_ step: CoachingStep, lead: CoachingMetricResult?, notJudged: CoachingExclusion?,
                        report: SwingCoachingReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let notJudged {
                Text(CoachingWords.exclusion(notJudged))
            } else if step.kind == .good {
                Text("Nothing worth changing on this one.")
            } else if step.kind == .better {
                // Numbers stay in All checks: on the card the drawing says it.
                Text("Back in zone.")
            }
        }
        .font(.appBody)
        .foregroundStyle(PlayerChrome.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    /// The first reading has the body checks only; say what is coming, or
    /// what the clip's reading changed.
    @ViewBuilder
    private func readingNote(_ report: SwingCoachingReport) -> some View {
        if let before = store.replacedFirstReadings[swing.id] {
            let now = store.verdict(for: swing, report: report).headline
            note(before == now ? "Club checks added. The pointer is the same."
                 : "Club checks added. On the body checks alone it was: \(before).", busy: false)
        } else if report.fromLiveCopies {
            if store.pending.contains(swing.id), !store.isWaitingForAuto {
                note("Body checks only. Adding the club checks now.", busy: true)
            } else if store.failed.contains(swing.id) {
                note("Body checks only. The club checks couldn't be read.", busy: false)
            } else {
                note("Body checks only. The club checks come when Auto pauses.", busy: false)
            }
        }
    }

    private func note(_ text: String, busy: Bool) -> some View {
        HStack(spacing: 8) {
            if busy { ProgressView().controlSize(.small).tint(.white) }
            Text(text)
                .font(.appCaptionLabel)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coaching-reading-note")
    }

    private func buttons(index: Int, of steps: [CoachingStep]) -> some View {
        let isLast = index == steps.count - 1
        return HStack(spacing: 10) {
            if index > 0 {
                Button {
                    go(to: steps[index - 1])
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.appLabel)
                        .frame(width: Self.buttonHeight, height: Self.buttonHeight)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to \(steps[index - 1].text)")
                .accessibilityIdentifier("coaching-back")
            }
            Button {
                play()
            } label: {
                // "Play" alone when large text leaves no room for "Play swing".
                ViewThatFits(in: .horizontal) {
                    Label("Play swing", systemImage: "play.fill").fixedSize()
                    Label("Play", systemImage: "play.fill").fixedSize()
                    Image(systemName: "play.fill")
                }
                    .font(.appLabel)
                    .frame(maxWidth: .infinity, minHeight: Self.buttonHeight)
                    .background(RoundedRectangle(cornerRadius: 14).fill(isLast ? Color.white : Color.white.opacity(0.16)))
                    .foregroundStyle(isLast ? Color.black : Color.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play swing")
            .accessibilityIdentifier("coaching-play")
            if !isLast {
                Button {
                    go(to: steps[index + 1])
                } label: {
                    HStack(spacing: 6) {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .font(.appLabel)
                    .frame(maxWidth: .infinity, minHeight: Self.buttonHeight)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                    .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next: \(steps[index + 1].text)")
                .accessibilityIdentifier("coaching-next")
            }
        }
    }

    /// Every check on the swing, from the card's top row.
    private var allChecksButton: some View {
        Button(action: showChecks) {
            HStack(spacing: 3) {
                Text("All checks")
                Image(systemName: "chevron.right").font(.appCaptionLabel)
            }
            .font(.appLabel)
            .padding(.horizontal, 10)
            .frame(minHeight: Self.allChecksHeight)
            .background(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            // 44 points to tap, without making the row taller.
            .padding(.vertical, (Self.buttonHeight - Self.allChecksHeight) / 2)
            .contentShape(Rectangle())
            .padding(.vertical, -(Self.buttonHeight - Self.allChecksHeight) / 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("All checks on this swing")
        .accessibilityIdentifier("coaching-all-checks")
    }

    /// A check picked from the list, on its own frame.
    private func checkCard(_ result: CoachingMetricResult, report: SwingCoachingReport, steps: [CoachingStep]) -> some View {
        VStack(alignment: .leading, spacing: Self.rowGap) {
            Text(CoachingWalkthrough.place(result.position))
                .font(.appLabel)
                .foregroundStyle(.white.opacity(0.82))
            Text(CoachingWords.headline(result))
                .font(.appTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("coaching-step-title")
            levelRow(CoachingLevelPill(level: result.level, scored: result.definition.scored,
                                       neutral: report.exclusion != nil),
                     dependsOnCamera: result.definition.dependsOnCamera,
                     legend: CoachingLegend(results: [result], neutral: report.exclusion != nil))
            HStack(spacing: 10) {
                Button {
                    highlighted = nil
                    if let first = steps.first { go(to: first) }
                } label: {
                    Text("Back to the coach")
                        .font(.appLabel)
                        .frame(maxWidth: .infinity, minHeight: Self.buttonHeight)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coaching-back-to-steps")
                Button(action: showChecks) {
                    Text("All checks")
                        .font(.appLabel)
                        .frame(maxWidth: .infinity, minHeight: Self.buttonHeight)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coaching-all-checks")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Self.cardPadding)
        .background(cardBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coaching-step-card")
    }

    /// Playing, or paused off the walkthrough: the verdict on one line.
    /// Tapping it always goes back to the first step.
    private func foldedLine(_ first: CoachingStep, steps: [CoachingStep]) -> some View {
        let report = store.report(for: swing)
        let lead = first.lead.flatMap { report?.metric($0) }
        return Button {
            go(to: first)
        } label: {
            HStack(spacing: 10) {
                badge(first, lead: lead)
                VStack(alignment: .leading, spacing: 1) {
                    // Which finding this is and where, so it never reads
                    // as a verdict on the frame on screen.
                    if let caption = foldedCaption(first) {
                        Text(caption)
                            .font(.appCaptionLabel)
                            .foregroundStyle(PlayerChrome.secondaryText)
                            .lineLimit(1)
                    }
                    // One line: shrinks a little, then truncates; the
                    // whole finding is one tap away.
                    Text(first.text)
                        .font(.appLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                // A chevron only, so the finding's title gets the width;
                // "Findings" is its name to VoiceOver and Voice Control.
                Image(systemName: "chevron.up")
                    .font(.appLabel)
                    .foregroundStyle(PlayerChrome.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.white.opacity(0.12)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, Self.foldedPadding)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(cardBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Coaching: \(first.text)")
        .accessibilityInputLabels([steps.count > 1 ? "Findings" : "Show", "Coaching"])
        .accessibilityHint(steps.count > 1 ? "Findings: pauses on the coach's first finding"
                           : "Pauses on the coach's finding")
        .accessibilityIdentifier("swing-coaching-pill")
    }

    /// "Swing's top finding · at impact": off the walkthrough the line says
    /// it is the whole swing's first finding, not the frame on screen, and
    /// where in the swing that is.
    private func foldedCaption(_ step: CoachingStep) -> String? {
        let place = CoachingWalkthrough.place(step.position)
        let at = place.prefix(1).lowercased() + place.dropFirst()
        switch step.kind {
        case .pointer, .finding: return "Swing's top finding · \(at)"
        case .better: return "Back in zone · \(at)"
        case .good, .notJudged: return nil
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: PlayerChrome.panelRadius)
            .fill(PlayerChrome.panel)
            .overlay(RoundedRectangle(cornerRadius: PlayerChrome.panelRadius).strokeBorder(PlayerChrome.panelEdge, lineWidth: 0.5))
    }

    /// The gap between the card's rows. With each row's own leading and
    /// the pill's edge it gives one even 8-point gap between the rows'
    /// text, and keeps the card as short as it was, so it covers as little
    /// of the swing as it can.
    private static let rowGap: CGFloat = 5
    /// The card's top and bottom padding, as tight as its rounded corners allow.
    private static let cardPadding: CGFloat = 7
    /// The folded line's top and bottom padding: clear of the capsule's
    /// rounded edge.
    private static let foldedPadding: CGFloat = 10
    /// The All checks capsule: drawn shorter than its row's text needs
    /// room for, and still 44 points to tap.
    private static let allChecksHeight: CGFloat = 28
    /// The card's buttons: the 44 pt minimum, no taller.
    private static let buttonHeight: CGFloat = 44

    // MARK: Actions

    private func go(to step: CoachingStep) {
        onInteract()
        store.acknowledgeUpdate(swing.id)
        if let highlighted, !step.metrics.contains(highlighted) { self.highlighted = nil }
        context.seek(step.clipTime)
    }

    private func play() {
        onInteract()
        store.acknowledgeUpdate(swing.id)
        // From address, so each drawing comes up at its own frame.
        let start = store.report(for: swing)?.metrics.map(\.clipTime).min()
        let positionsStart = swing.swingPositions?.positions.first?.clipTime
        let from = [start, positionsStart].compactMap { $0 }.min() ?? 0
        context.play(max(0, from - 0.3))
    }

    private func showChecks() {
        onInteract()
        onShowChecks()
    }
}

/// What the colours on the frame mean, for the parts this drawing has.
/// Each swatch is the shape drawn: a line (dashed where the line is), a
/// ring, a dot or a band, in the drawing's colours.
struct CoachingLegend: View {
    let results: [CoachingMetricResult]
    /// Several swings side by side: every colour their lines are drawn
    /// in, so the key matches each picture.
    var subjectColours: [Color]? = nil
    /// The swing isn't judged: its line is drawn grey.
    var neutral = false

    /// The shape a swatch draws.
    enum Swatch: Equatable {
        case line(dashed: Bool)
        case ring(dashed: Bool)
        case dot
        case band
    }

    var body: some View {
        let roles = Set(results.flatMap { $0.drawings.map(\.role) })
        // One row when it fits; at large text sizes it wraps onto as few
        // lines as it needs, never one item a line.
        FlowLayout(spacing: 12, lineSpacing: 4) { items(roles) }
        .font(.appCaption)
        .foregroundStyle(.white.opacity(0.88))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(roles))
        .accessibilityIdentifier("coaching-legend")
    }

    @ViewBuilder
    private func items(_ roles: Set<CoachingDrawing.Role>) -> some View {
        if roles.contains(.reference) { item(.reference, "Address") }
        if roles.contains(.zone) { item(.zone, "Good players") }
        if roles.contains(.subject) { item(.subject, "This swing") }
    }

    /// The shape this role is drawn as on the first result: a head check's
    /// address and swing are rings, a club check's swing a line, a guide's
    /// address a line and a dot.
    static func swatch(for role: CoachingDrawing.Role, in result: CoachingMetricResult?) -> Swatch {
        guard role != .zone else { return .band }
        let shapes = result?.drawings.filter { $0.role == role && $0.kind != .label } ?? []
        if let ring = shapes.first(where: { $0.kind == .circle }) {
            return .ring(dashed: role == .reference || ring.dashed && role != .subject)
        }
        if let line = shapes.first(where: { $0.kind == .line || $0.kind == .band }) {
            return .line(dashed: line.dashed)
        }
        if shapes.contains(where: { $0.kind == .dot }) { return .dot }
        return .line(dashed: false)
    }

    private func item(_ role: CoachingDrawing.Role, _ title: String) -> some View {
        let first = results.first
        let zone = first.map { CoachingDrawingLayer.zoneColour($0) } ?? .coachingLevel(0)
        let subject = first.map { CoachingDrawingLayer.subjectColour($0, swingNeutral: neutral) } ?? .coachingLevel(0)
        let colours: [Color] = switch role {
        case .reference: [.white.opacity(CoachingDrawingLayer.referenceOpacity)]
        case .zone: [zone]
        case .subject: subjectColours ?? [subject]
        }
        let swatch = Self.swatch(for: role, in: first)
        let wide = role == .subject && colours.count > 1 && swatch != .dot
        return HStack(spacing: 5) {
            Canvas { context, size in
                Self.draw(swatch, colours: colours, role: role, in: CGRect(origin: .zero, size: size), context: context)
            }
            .frame(width: wide ? 9 * CGFloat(colours.count) : (swatch == .dot ? 10 : 18), height: 10)
            Text(title).fixedSize()
        }
    }

    /// One swatch, drawn as the video draws its shape, with the same dark
    /// halo.
    private static func draw(_ swatch: Swatch, colours: [Color], role: CoachingDrawing.Role, in rect: CGRect,
                             context: GraphicsContext) {
        let halo = CoachingDrawingLayer.haloColour
        switch swatch {
        case .band:
            let path = Path(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 2)
            let colour = colours.first ?? .coachingLevel(0)
            context.fill(path, with: .color(colour.opacity(0.45)))
            context.stroke(path, with: .color(halo), lineWidth: 2.5)
            context.stroke(path, with: .color(colour), lineWidth: 1.5)
        case .line(let dashed):
            let width: CGFloat = role == .reference ? 2 : 3
            let dash: [CGFloat] = dashed ? [3, 2.5] : []
            let step = rect.width / CGFloat(max(colours.count, 1))
            for (index, colour) in colours.enumerated() {
                var line = Path()
                line.move(to: CGPoint(x: step * CGFloat(index) + 1, y: rect.midY))
                line.addLine(to: CGPoint(x: step * CGFloat(index + 1) - 1, y: rect.midY))
                context.stroke(line, with: .color(halo), style: StrokeStyle(lineWidth: width + 1.5, lineCap: .butt, dash: dash))
                context.stroke(line, with: .color(colour), style: StrokeStyle(lineWidth: width, lineCap: .butt, dash: dash))
            }
        case .ring(let dashed):
            // One ring; several swings' colours share it as arcs.
            let side = min(rect.width, rect.height) - 2
            let circle = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
            let width: CGFloat = dashed ? 1.25 : 2
            let dash: [CGFloat] = dashed ? CoachingDrawingLayer.ringDash(width) : []
            context.stroke(Path(ellipseIn: circle), with: .color(halo),
                           style: StrokeStyle(lineWidth: width + 1.5, dash: dash))
            let share = 360 / Double(max(colours.count, 1))
            for (index, colour) in colours.enumerated() {
                var arc = Path()
                arc.addArc(center: CGPoint(x: circle.midX, y: circle.midY), radius: side / 2,
                           startAngle: .degrees(share * Double(index) - 90),
                           endAngle: .degrees(share * Double(index + 1) - 90), clockwise: false)
                context.stroke(arc, with: .color(colour), style: StrokeStyle(lineWidth: width, dash: dash))
            }
        case .dot:
            let side = min(rect.width, rect.height) - 2
            let dot = Path(ellipseIn: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
            context.fill(dot, with: .color(colours.first ?? .white))
            context.stroke(dot, with: .color(.black.opacity(0.75)), lineWidth: 1)
        }
    }

    private func accessibilityText(_ roles: Set<CoachingDrawing.Role>) -> String {
        let first = results.first
        func shape(_ role: CoachingDrawing.Role) -> String {
            switch Self.swatch(for: role, in: first) {
            case .ring(let dashed): dashed ? "the dashed ring" : "the ring"
            case .line(let dashed): dashed ? "the dashed line" : "the line"
            case .dot: "the dot"
            case .band: "the shading"
            }
        }
        var parts: [String] = []
        if roles.contains(.reference) { parts.append("\(shape(.reference)) in white is where you were at address") }
        if roles.contains(.zone) { parts.append("\(shape(.zone)) is where good players are") }
        if roles.contains(.subject) { parts.append("\(shape(.subject)) in colour is this swing") }
        return "Drawing: " + parts.joined(separator: ", ")
    }
}

// MARK: - Opening on the first step

/// Opens the swing paused on its first step, or on `focus` when it came
/// from a comparison. Queues the swing's reading. When a new reading moves
/// the first step and the golfer hasn't moved through the steps, the
/// player moves with it.
struct SwingCoachingOpening: ViewModifier {
    let swing: SavedSwing
    let isActive: Bool
    var focus: CoachingMetricID?
    @Binding var seek: Double?
    @Binding var interacted: Bool
    @Binding var highlighted: CoachingMetricID?

    @ObservedObject private var store = SwingCoachingStore.shared

    private var openingTime: Double? {
        if let focus, let result = store.report(for: swing)?.metric(focus) { return result.clipTime }
        return store.steps(for: swing).first?.clipTime
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                if SwingCoachingStore.canCoach(swing) { store.coachWithSession(swing) }
                open()
            }
            .onChange(of: isActive) { _, active in
                guard active else { return }
                interacted = false
                open()
            }
            .onChange(of: swing.id) { _, _ in
                interacted = false
                open()
            }
            .onChange(of: openingTime) { _, _ in
                if !interacted { open() }
            }
            .onChange(of: swing.swingPositions) { _, _ in
                if SwingCoachingStore.canCoach(swing) { store.coachWithSession(swing) }
            }
    }

    private func open() {
        guard isActive, let time = openingTime else { return }
        if let focus, store.report(for: swing)?.metric(focus) != nil { highlighted = focus }
        seek = time
    }
}

extension View {
    func swingCoachingOpening(swing: SavedSwing, isActive: Bool, focus: CoachingMetricID? = nil,
                              seek: Binding<Double?>, interacted: Binding<Bool>,
                              highlighted: Binding<CoachingMetricID?>) -> some View {
        modifier(SwingCoachingOpening(swing: swing, isActive: isActive, focus: focus, seek: seek,
                                      interacted: interacted, highlighted: highlighted))
    }
}

// MARK: - Layers tool

/// The player's Layers tool: what is drawn over the swing, in golf words,
/// and one way back to the coach's choice. Draw (adding your own marks) is
/// a separate tool.
struct CoachingLayersSheet: View {
    @Binding var layers: CoachingLayers
    let hasTrail: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $layers.coach) {
                        row("Coaching overlays", "The lines for each finding on the swing.")
                    }
                    .accessibilityIdentifier("coaching-layer-coach")
                    Toggle(isOn: $layers.clubPath) {
                        row("Club head path", hasTrail ? "Drawn while the swing plays, dashed where the club was lost."
                            : "Not on this swing: it comes with the full reading of the video.")
                    }
                    .accessibilityIdentifier("coaching-layer-club")
                    Toggle(isOn: $layers.everyCheck) {
                        row("Every check on the frame", "Checks in zone too, drawn green, on any position you pause on.")
                    }
                    .accessibilityIdentifier("coaching-layer-every")
                } footer: {
                    Text("For every swing until you close this review.")
                }
                if !layers.isCoachsChoice {
                    Section {
                        Button("Back to the coach's choice") { layers = .coachsChoice }
                            .accessibilityIdentifier("coaching-reset-choices")
                    }
                }
            }
            .navigationTitle("Layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .playerSheetStyle()
    }

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.appCaption).foregroundStyle(Color.helpText)
        }
    }
}

/// On the video while the layers differ from the coach's choice.
struct CoachingLayersChangedTag: View {
    @Binding var layers: CoachingLayers

    var body: some View {
        HStack(spacing: 10) {
            Text("Your layers")
                .font(.appLabel)
            Button { layers = .coachsChoice } label: {
                Text("Reset")
                    .font(.appLabel)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(Capsule().fill(Color.white))
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
                .accessibilityLabel("Reset layers to the coach's choice")
                .accessibilityIdentifier("coaching-layers-reset")
        }
        .foregroundStyle(.white)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.07).opacity(0.88)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coaching-layers-custom")
    }
}

extension PlayerTool {
    static func coachingDrawings(changed: Bool, action: @escaping () -> Void) -> PlayerTool {
        PlayerTool(id: "drawings", title: "Layers", caption: "Layers", accessibilityLabel: "Choose layers",
                   accessibilityValue: changed ? "Changed" : "Coach's choice", isOn: changed,
                   icon: .system("square.3.layers.3d"), action: action)
    }
}

// MARK: - Every check

/// Every check on a swing, by position in swing order: a picture of each
/// on its frame, the sentence, the numbers against good players and what
/// the level means. Picking one shows it on the video.
struct SwingCoachingChecks: View {
    let swing: SavedSwing
    let report: SwingCoachingReport
    let verdict: CoachingVerdict
    let onSelect: (CoachingMetricResult) -> Void
    @Environment(\.dismiss) private var dismiss

    private var positions: [Int] {
        Array(Set(report.metrics.map(\.position))).sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryCard
                }
                ForEach(positions, id: \.self) { position in
                    Section {
                        ForEach(report.metrics.filter { $0.position == position }, id: \.id) { result in
                            Button { onSelect(result) } label: { row(result) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("coaching-metric-\(result.id.rawValue)")
                        }
                    } header: {
                        SectionHeading(SwingPosition.title(position))
                    }
                }
                if !report.unavailable.isEmpty {
                    Section {
                        Text(report.unavailable.map { CoachingMetricDefinition.definition($0).title }.joined(separator: ", "))
                            .font(.appCaption)
                            .foregroundStyle(Color.helpText)
                    } header: {
                        SectionHeading("Not measured on this swing")
                    }
                }
            }
            .navigationTitle("All checks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .playerSheetStyle()
    }

    /// The whole swing first ("11 of 16 checks in zone"), then the coach's
    /// verdict, labelled "Top finding" when it is one, then what the
    /// numbers mean. A swing that isn't judged leads with its verdict.
    private var summaryCard: some View {
        let judged = report.metrics.filter(\.definition.scored)
        let guides = report.metrics.count - judged.count
        let inZone = judged.filter(\.inZone).count
        // Says what it counts: judged checks, not the guides listed too.
        let count = "\(inZone) of \(judged.count) judged checks in zone"
        let label: String? = if case .focus = verdict { "Top finding" } else { nil }
        let keyed = report.exclusion == nil && { if case .focus = verdict { true } else { false } }()
        let guideNote = guides > 0 ? " Guides are shown, not counted." : ""
        let note: String = if let exclusion = report.exclusion {
            CoachingWords.exclusion(exclusion)
        } else if keyed {
            CoachingWords.stepDefinition + guideNote
        } else {
            "None of the others is far enough out to work on." + guideNote
        }
        return VStack(alignment: .leading, spacing: 6) {
            if report.exclusion == nil {
                // A headline number: proportional digits, so "11" never
                // reads as "1 1".
                Text(count).font(.appTitle)
            }
            VStack(alignment: .leading, spacing: 1) {
                if let label {
                    Text(label)
                        .font(.appCaptionLabel)
                        .foregroundStyle(Color.helpText)
                }
                Text(verdict.headline).font(.appLabel)
            }
            VStack(alignment: .leading, spacing: 2) {
                if keyed {
                    CoachingMarkKey(dash: guides > 0)
                }
                Text(note)
            }
            .font(.appCaption)
            .foregroundStyle(Color.helpText)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(report.exclusion == nil
            ? "\(count). \(label.map { "\($0): " } ?? "")\(verdict.headline). \(keyed ? CoachingWords.numberKey + ". " : "")\(note)"
            : "\(verdict.headline). \(note)")
        .accessibilityIdentifier("coaching-summary")
    }

    private func row(_ result: CoachingMetricResult) -> some View {
        let neutral = report.exclusion != nil
        let judged = result.definition.scored && !neutral
        let reason = CoachingWords.notJudgedReason(result, exclusion: report.exclusion)
        return HStack(spacing: 12) {
            CoachingFrameView(swing: swing, report: report, metric: result.id)
                .frame(width: 44, height: 78)
                .clipShape(.rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CoachingLevelBadge(level: result.level, scored: result.definition.scored,
                                       neutral: neutral, size: 18)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                    // Not judged: the check's name alone, never "in zone".
                    Text(judged ? CoachingWords.headline(result) : result.definition.title)
                        .font(.appLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    if !judged {
                        Text(CoachingWords.notJudged(reason))
                            .font(.appCaptionLabel)
                            .foregroundStyle(Color.helpText)
                            .fixedSize()
                    }
                }
                CoachingZoneTrack(result: result, neutral: neutral)
                    .padding(.vertical, 2)
                if judged && !result.inZone {
                    Text(CoachingWords.level(result) + ".")
                        .font(.appCaption)
                        .foregroundStyle(Color.helpText)
                }
                if result.definition.dependsOnCamera {
                    CoachingCameraCaveat(advice: true)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(CoachingWords.level(result, neutral: report.exclusion != nil))
    }
}
