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

/// What the player draws over a swing, chosen with the player's Layers
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

    /// The range a reading is drawn against, named one way wherever a
    /// range is named (rows, keys, the session's charts): "Good zone". A
    /// guide's range keeps the name; the guide itself says
    /// `referenceOnly`, and its range is drawn dashed and grey.
    static let zoneName = "Good zone"

    /// "You: +4%. Good zone: −3.5% to +3%."
    static func numbers(_ result: CoachingMetricResult) -> String {
        let definition = result.definition
        guard definition.scored else { return "You: \(value(result)). A guide, not judged." }
        return "You: \(value(result)). \(zoneName): \(zone(definition))."
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

    /// A guide's word beside its name and in the key for the dashed
    /// range it is drawn against: drawn for reference, never judged.
    static let referenceOnly = "Reference only"

    /// Why a check isn't judged, short enough for a row: "short swing";
    /// nil for a guide, which says `referenceOnly` instead.
    static func notJudgedReason(_ result: CoachingMetricResult, exclusion: CoachingExclusion?) -> String? {
        if let exclusion { return reason(exclusion) }
        return result.definition.scored ? "" : nil
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

    /// How far out a level is, in plain words for a beginner beside the
    /// badge on a finding (the step card, a picked check): the level's
    /// `CoachingSeverity` word, "A little out" in amber or "Well out" in
    /// red. Nil in zone.
    static func severity(_ level: Int) -> String? {
        level == 0 ? nil : CoachingSeverity(level: level).word
    }

    /// A club reading's caveat, the one line everywhere it is shown: the
    /// club checks move with where the camera stands.
    static let cameraCaveat = "Depends on camera position"

    /// What to do about it, said only where there is room for the detail
    /// (All checks).
    static let cameraAdvice = "Check it with the camera on your hand line."

    /// The word beside a level badge, wherever a word sits beside one: its
    /// `CoachingSeverity` word ("A little out", "Well out", "In zone"), or
    /// "Not judged". "N steps out" is said only in All checks' rows.
    static func badgeWord(level: Int, scored: Bool = true, neutral: Bool = false) -> String {
        if neutral || !scored { return "Not judged" }
        return CoachingSeverity(level: level).word
    }

    /// Which side of good players' zone a reading is on.
    static func side(_ result: CoachingMetricResult) -> String {
        let zone = result.definition.zone
        if result.value > zone.upperBound { return "Above zone" }
        if result.value < zone.lowerBound { return "Below zone" }
        return "In zone"
    }

    /// Which swings showed a theme, in one caption: how many of the swings
    /// with a reading of its check showed it, then the check ("4 of 8
    /// measured · takeaway"), or the count alone beside a position tag that
    /// already names it ("4 of 8 measured").
    static func themeShare(_ theme: CoachingTheme, namingPosition: Bool = true) -> String {
        let count = "\(theme.swings) of \(theme.measured) measured"
        guard namingPosition else { return count }
        return "\(count) · \(CoachingMetricDefinition.definition(theme.metric).title.lowercased())"
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

    /// What a number's unit is of, where the sign alone doesn't say:
    /// "% of body height". Nil for degrees.
    static func measure(_ unit: CoachingUnit) -> String? {
        switch unit {
        case .bodyPercent: "% of body height"
        case .degrees: nil
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
    /// The dashed address ring round the head. Off on a walkthrough stop,
    /// where the head's own ring and its zone are the whole story; on with
    /// "Show all drawings here", while playing and in pictures.
    var showsAddressRing = true

    var body: some View {
        ZStack {
            canvas(.zone, ringed: false).opacity(revealed >= 2 ? 1 : 0)
            canvas(.reference).opacity(revealed >= 1 ? 1 : 0)
            canvas(.subject).opacity(revealed >= 3 ? 1 : 0)
            // A head check's zone over the rings, cut away round them, so
            // the clear gap between ring and band reads.
            canvas(.zone, ringed: true).opacity(revealed >= 2 ? 1 : 0)
        }
        .allowsHitTesting(false)
    }

    /// One role's shapes. For the zone, `ringed` picks the head checks'
    /// zones (true) or every other check's (false).
    private func canvas(_ role: CoachingDrawing.Role, ringed onlyRinged: Bool? = nil) -> some View {
        Canvas { context, _ in
            for result in results {
                var layer = context
                var lineWeight = weight
                // Address is where the swing is measured from, not the
                // point: thinner and dimmer, so where it meets the swing's
                // mark and the zone the three never stack into one blob.
                let ringed = Self.isRinged(result)
                if let onlyRinged, onlyRinged != ringed { continue }
                if role == .reference {
                    lineWeight *= Self.referenceWeight
                    layer.opacity *= ringed ? Self.referenceRingOpacity : Self.referenceOpacity
                }
                // A head check's zone sits behind both rings: cut away
                // under each ring and its halo, with a gap, so the rings
                // and the zone never meet over the face.
                if role == .zone, ringed {
                    layer.clip(to: ringKnockout(result), options: .inverse)
                }
                for shape in result.drawings where shape.role == role {
                    if shape.role == .reference, shape.kind == .circle, !showsAddressRing { continue }
                    draw(shape, of: result, weight: lineWeight, ringed: ringed, context: &layer)
                }
            }
        }
    }

    private var weight: CGFloat { still ? max(1.5, min(3, rect.height / 110)) : 4 }

    /// A ring's stroke: the address ring thin, this swing's ring solid.
    /// `weight` is the canvas's, already thinned for address.
    private static func ringWidth(address: Bool, weight: CGFloat) -> CGFloat {
        address ? referenceRingWidth : max(2, weight * ringWeight)
    }

    /// The rings' outlines with their halos and a gap, which the zone
    /// is cut away under.
    private func ringKnockout(_ result: CoachingMetricResult) -> Path {
        var knockout = Path()
        for shape in result.drawings where shape.kind == .circle && shape.role != .zone {
            // While the drawing builds up, only the rings already shown.
            guard let centre = shape.points.first, shape.role == .reference || revealed >= 3 else { continue }
            if shape.role == .reference, !showsAddressRing { continue }
            let address = shape.role == .reference
            let size = CGFloat(shape.size ?? 0) * rect.height
            let x = rect.minX + centre.x * rect.width, y = rect.minY + centre.y * rect.height
            let ring = Path(ellipseIn: CGRect(x: x - size, y: y - size, width: size * 2, height: size * 2))
            let width = Self.ringWidth(address: address, weight: address ? weight * Self.referenceWeight : weight)
                + (address ? Self.referenceHaloExtra : Self.haloExtra) + 2 * Self.ringKnockoutGap
            knockout.addPath(ring.strokedPath(StrokeStyle(lineWidth: width)))
        }
        return knockout
    }

    /// The swing's line on a swing that isn't judged, and on a guide.
    static let neutralColour = Color(white: 0.82)
    /// The address reference against the swing's own line.
    static let referenceWeight: CGFloat = 0.55
    static let referenceOpacity = 0.7
    /// The swing's ring (the head now) against the drawing's weight: one
    /// solid outline, the strongest mark on the head.
    static let ringWeight: CGFloat = 0.6
    /// The address ring: 1 point, dashed, at 25% opacity, with a narrow
    /// halo, so it reads as where the head was, never as a second reading
    /// competing with the solid ring and the zone's edge at phone size.
    static let referenceRingWidth: CGFloat = 1
    static let referenceRingOpacity = 0.25
    static let referenceHaloExtra: CGFloat = 1
    /// The clear space between a ring's halo and the zone behind it.
    static let ringKnockoutGap: CGFloat = 1.5
    /// The reading's dot, against the drawing's weight: the largest mark.
    static let dotRadius: CGFloat = 2.2
    /// The dark edge round every line, ring and zone edge, so each holds
    /// on sky, grass and mat: this much wider than the line it edges.
    static let haloExtra: CGFloat = 2.5
    static let haloColour = Color.black.opacity(0.55)
    /// A zone's edge against the drawing's weight: about 3 points on the
    /// player, in the shared drawing style, with the same dark halo as the
    /// shaft line (`haloExtra`), so the zone's green edge holds on green
    /// turf and the mat. Its fill stays light (16 to 20%), so a wedge over
    /// the leg and mat tints them less than the measured line it sits
    /// behind.
    static let zoneEdgeWeight: CGFloat = 0.75
    static let zoneEdgeMinimum: CGFloat = 1.5
    static let zoneFillOpacity = 0.16
    /// A head check's zone: an outlined band a little stronger than other
    /// zones, so it reads as a place beside the solid ring.
    static let ringedZoneFillOpacity = 0.2
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
            // A light fill, and an edge with the measured line's dark
            // halo, so it holds its shape on green turf and mat.
            let zoneEdge = max(Self.zoneEdgeMinimum, weight * Self.zoneEdgeWeight)
            context.fill(path, with: .color(colour.opacity(ringed ? Self.ringedZoneFillOpacity : Self.zoneFillOpacity)))
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
            if shape.role == .zone, ringed, let ring = headRingRadius(result) {
                // The head's zone is where its centre should be; drawn as
                // where the ring itself fits, a ring's radius wider each
                // side, so it shows past both sides of the head rings.
                let xs = points.map(\.x), ys = points.map(\.y)
                let box = CGRect(x: xs.min()! - ring, y: ys.min()!, width: xs.max()! - xs.min()! + ring * 2,
                                 height: ys.max()! - ys.min()!)
                zoneFill(Path(roundedRect: box, cornerRadius: min(box.height / 2, ring / 2)))
                return
            }
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
                let ring = Self.ringWidth(address: isAddress, weight: weight)
                let ringDash = isAddress ? Self.ringDash(ring) : []
                let halo = isAddress ? Self.referenceHaloExtra : Self.haloExtra
                context.stroke(path, with: .color(edgeColour),
                               style: StrokeStyle(lineWidth: ring + halo, lineCap: .round, dash: ringDash))
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

    /// The head ring's radius in view points, for a check drawn round it.
    private func headRingRadius(_ result: CoachingMetricResult) -> CGFloat? {
        result.drawings.first { $0.kind == .circle && $0.role != .zone }
            .map { CGFloat($0.size ?? 0) * rect.height }
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
/// drawing builds up: address, then the zone, then the swing, then a tag
/// with the check's name unless the card under the video names it.
/// Playing, each step's drawing holds, faded, from its frame until the
/// next step's, under the club's path. Paused anywhere else, only checks
/// measured on that frame are drawn, and only with "Show all drawings
/// here" on.
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
    @Environment(\.playerPanelIsShown) private var panelIsShown
    @Environment(\.playerTopRowBottom) private var topRowBottom
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
        /// The card under the video names this stop's check, so its tag
        /// on the frame gives way: one name per finding on screen.
        var namedOnCard = false
    }

    /// A step draws only its own finding, so the eye goes to one place on
    /// the body; the checks supporting it are drawn only with "Show all
    /// drawings here".
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
            shown.namedOnCard = panelIsShown && !layers.everyCheck
        } else if let step = steps.first(where: { abs($0.clipTime - now) <= stopTolerance }) {
            shown.results = layers.coach ? step.metrics.compactMap(report.metric) : []
            shown.stopKey = step.id
            // "Show all drawings here" keeps a tag on every drawing.
            if !layers.everyCheck { leadOnly(&shown) }
            shown.namedOnCard = panelIsShown && !layers.everyCheck
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
                                             neutral: report?.exclusion != nil,
                                             showsAddressRing: shown.stopKey == nil || layers.everyCheck)
                            .opacity(shown.held ? 0.55 : 1)
                        if !shown.held {
                            tags(shown.results, tagged: shown.tagged, visible: !shown.namedOnCard, in: rect,
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
                                 y: min(max(anchor.y - 16, max(rect.minY, topRowBottom) + 14), rect.maxY - 14))
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
    /// of the tool rail on either side and under the row over the video
    /// (`playerTopRowBottom`), wherever the video's own top is. A
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
        let video = rect.intersection(bounds)
        // Under the top row, or 12 points into the video when its top is
        // lower than that.
        let top = max(topRowBottom, video.minY) + 12 - video.minY
        var safe = video.inset(by: UIEdgeInsets(top: top, left: 56, bottom: 12, right: 56))
        if safe.isNull || safe.width < width || safe.height < height {
            safe = video.inset(by: UIEdgeInsets(top: max(0, topRowBottom - video.minY), left: 0, bottom: 0, right: 0))
        }
        if safe.isNull || safe.width < width || safe.height < height { safe = video }
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

    /// The drawings' name tags. Hidden (`visible` false) while the card
    /// under the video names the same check: then each drawing is still
    /// described to VoiceOver at its place on the frame, with no tag drawn.
    private func tags(_ results: [CoachingMetricResult], tagged: Set<CoachingMetricID>?, visible: Bool,
                      in rect: CGRect, bounds: CGRect) -> some View {
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
            if !visible, let anchor = CoachingDrawingLayer.anchor(of: result, in: rect) {
                Color.clear
                    .frame(width: HitArea.minimum, height: HitArea.minimum)
                    .position(anchor)
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isImage)
                    .accessibilityLabel("\(CoachingWords.headline(result)), \(CoachingWords.value(result))")
                    .accessibilityIdentifier("coaching-caption-\(result.id.rawValue)")
            } else if visible, let centre = centres[result.id] {
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

/// The one verdict badge, everywhere a level is marked (the step card,
/// the pose strip, All checks, the comparison, the session review): a
/// glyph in the level's colour, never a number, so it never reads as a
/// count. A tick in zone, "!" a little out (amber), "!!" well out (red)
/// (`CoachingSeverity.markSymbol`, so amber and red differ by shape too),
/// a dash for a guide or a swing that isn't judged. Outlined (a ring and
/// the glyph in the level's colour, no fill) for a swing out the other
/// way on a recap: out, but not the theme. "N steps out" is said only in
/// All checks' rows and to VoiceOver.
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
            } else if let symbol = CoachingSeverity(level: level).markSymbol {
                Image(systemName: symbol).font(.system(size: size * 0.5, weight: .heavy))
            }
        }
        .foregroundStyle(outlined ? colour : .black)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A club reading's caveat, the one wording everywhere
/// (`CoachingWords.cameraCaveat`), with a camera glyph so it reads as a
/// note on the reading, never as part of its level, in the help grey.
struct CoachingCameraCaveat: View {
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
        .foregroundStyle(Color.helpText)
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

/// One reading against good players' zone, in All checks' rows: which
/// side of the zone the swing is and how far ("Above zone · 3 steps out")
/// in the level's ink, then a track with the zone as a green band and
/// this swing as a marker in its level's colour, then the numbers in one
/// caption line with what they measure ("You +19% · Good zone −29% to
/// +3% · % of body height"). The track's key is in the sheet's header,
/// once. A guide, or a swing that isn't judged, is drawn in the neutral
/// guide style, with no side.
struct CoachingZoneTrack: View {
    let result: CoachingMetricResult
    /// The swing isn't judged.
    var neutral = false

    private var judged: Bool { result.definition.scored && !neutral }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if judged {
                Text(sideWords)
                    .font(.appLabel)
                    .foregroundStyle(Color.coachingLevelText(result.level))
            }
            track.frame(height: 14)
            Text(numbers)
                .font(.appCaption.monospacedDigit())
                .foregroundStyle(Color.helpText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(judged ? "\(CoachingWords.numbers(result)) \(sideWords)."
                            : result.definition.scored ? "\(CoachingWords.numbers(result)) Not judged." : CoachingWords.numbers(result))
        .accessibilityIdentifier("coaching-zone-track")
    }

    /// "Above zone · 3 steps out", or "In zone".
    private var sideWords: String {
        result.level == 0 ? CoachingWords.side(result)
            : "\(CoachingWords.side(result)) · \(CoachingWords.steps(result.level))"
    }

    /// "You +19% · Good zone −29% to +3% · % of body height".
    private var numbers: String {
        let definition = result.definition
        var parts = ["You \(CoachingWords.value(result))",
                     "\(CoachingWords.zoneName) \(CoachingWords.zone(definition))"]
        if let measure = CoachingWords.measure(definition.unit) { parts.append(measure) }
        return parts.joined(separator: " · ")
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
                // no fill, so a reading inside it never looks like a pass,
                // and the swing as the same solid marker in the grey.
                context.stroke(zonePath, with: .color(marker.opacity(0.8)),
                               style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                context.fill(dot, with: .color(marker))
                context.stroke(dot, with: .color(.black.opacity(0.6)), lineWidth: 1.5)
            }
        }
    }
}

/// The badge with its severity word after it ("!! Typically well out",
/// "✓ In zone"), where a word goes with a badge across swings: the themes
/// of the session review. The words are the level's text ink, so they
/// read on the dark player and on light Library sheets alike.
struct CoachingLevelPill: View {
    let level: Int
    var scored = true
    var neutral = false
    /// Said before the word: "Typically" gives "Typically well out", so a
    /// theme's level reads as across swings, never as one swing's.
    var lead: String? = nil

    var body: some View {
        let judged = scored && !neutral
        let colour: Color = judged ? .coachingLevel(level) : .notJudged
        let ink: Color = judged ? .coachingLevelText(level) : .helpText
        let badgeWord = CoachingWords.badgeWord(level: level, scored: scored, neutral: neutral)
        // After a lead the word is mid-sentence: "Typically in zone".
        let words = lead.map { "\($0) " + badgeWord.prefix(1).lowercased() + badgeWord.dropFirst() } ?? badgeWord
        HStack(spacing: 6) {
            CoachingLevelBadge(level: level, scored: scored, neutral: neutral, size: 20)
            Text(words)
                .font(.appLabel)
                .foregroundStyle(ink)
        }
        .padding(.leading, 3)
        .padding(.trailing, 10)
        .padding(.vertical, 2)
        .background(Capsule().fill(colour.opacity(0.16)))
        .overlay(Capsule().strokeBorder(colour.opacity(0.55), lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(words)
        .accessibilityIdentifier("coaching-level-pill")
    }
}

/// The card under the video that walks through a swing's coaching. Paused
/// on a step it shows where in the swing, which finding of how many, the
/// one sentence with its level badge, All checks, and Back / Play / Next.
/// The numbers and the key to the drawing's colours are in All checks.
/// Anywhere else it folds to one line that brings the walkthrough back.
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
            Button("Try again") {
                store.retry(swing)
            }
            .buttonStyle(PanelButtonStyle())
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
        return VStack(alignment: .leading, spacing: Self.rowGap) {
            readingNote(report)
            HStack(alignment: .center, spacing: 8) {
                Text(placeLine(step))
                    .font(.appLabel)
                    .foregroundStyle(.white.opacity(0.82))
                    .accessibilityIdentifier("coaching-step-place")
                // "Finding", not "step": "steps out" is the level's word.
                if steps.count > 1 {
                    Text("\(index + 1)/\(steps.count)")
                        .font(.appCaptionLabel.monospacedDigit())
                        .foregroundStyle(PlayerChrome.secondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.14)))
                        .accessibilityLabel("Finding \(index + 1) of \(steps.count)")
                        .accessibilityIdentifier("coaching-step-count")
                }
                Spacer(minLength: 8)
                allChecksButton
            }
            // The All checks capsule stands taller than this row's text:
            // take its overhang out of the gap, so the text-to-text gaps
            // match the card's other rows.
            .padding(.bottom, -Self.rowGap)
            titleRow(badge(step, lead: lead, size: CoachingLevelBadge.markSize), step.text, level: levelWords(step, lead: lead),
                     severity: severityLevel(step, lead: lead))
            // Why a swing isn't judged; a good or better swing's tick and
            // title say it without a line under them.
            if let notJudged {
                Text(CoachingWords.exclusion(notJudged))
                    .font(.appBody)
                    .foregroundStyle(PlayerChrome.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
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

    /// The finding with its level badge before it, read at a glance from
    /// the tripod: out of zone, one plain word over the title says how far
    /// ("Well out"), semibold at the body size, since it carries the
    /// meaning beside the badge's glyph. The drawing's own colours say
    /// which line is the swing, and the key and the camera caveat are in
    /// All checks.
    private func titleRow(_ badge: some View, _ text: String, level: String, severity: Int?) -> some View {
        HStack(alignment: severity == nil ? .firstTextBaseline : .center, spacing: 10) {
            badge
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 7 }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(level)
                .accessibilityIdentifier("coaching-step-level")
            VStack(alignment: .leading, spacing: 0) {
                if let severity, let word = CoachingWords.severity(severity) {
                    Text(word)
                        .font(.appLabel)
                        .foregroundStyle(Color.coachingLevelText(severity))
                        .accessibilityIdentifier("coaching-step-severity")
                }
                Text(text)
                    .font(.appTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("coaching-step-title")
            }
        }
    }

    /// The level a finding's severity word says, or nil when the step has
    /// no distance out (in zone, not judged).
    private func severityLevel(_ step: CoachingStep, lead: CoachingMetricResult?) -> Int? {
        switch step.kind {
        case .pointer, .finding: lead.map(\.level).flatMap { $0 == 0 ? nil : $0 }
        case .notJudged, .good, .better: nil
        }
    }

    /// The step's level in words, for VoiceOver: "4 steps out", "In zone".
    private func levelWords(_ step: CoachingStep, lead: CoachingMetricResult?) -> String {
        switch step.kind {
        case .notJudged: "Not judged"
        case .good, .better: "In zone"
        case .pointer, .finding: CoachingWords.steps(lead?.level ?? 0)
        }
    }

    private func placeLine(_ step: CoachingStep) -> String {
        if case .notJudged = step.kind { return "Measured only" }
        return CoachingWalkthrough.place(step.position)
    }

    private func badge(_ step: CoachingStep, lead: CoachingMetricResult?, size: CGFloat = 24) -> CoachingLevelBadge {
        switch step.kind {
        case .notJudged: CoachingLevelBadge(level: 0, neutral: true, size: size)
        case .good, .better: CoachingLevelBadge(level: 0, size: size)
        case .pointer, .finding: CoachingLevelBadge(level: lead?.level ?? 0, size: size)
        }
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

    /// Back, Play swing and Next. Next is the card's one primary action,
    /// in the accent; on the last step Play swing takes it.
    private func buttons(index: Int, of steps: [CoachingStep]) -> some View {
        let isLast = index == steps.count - 1
        return HStack(spacing: 10) {
            if index > 0 {
                Button {
                    go(to: steps[index - 1])
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: Self.buttonHeight)
                }
                .buttonStyle(PanelButtonStyle(fills: false))
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
            }
            .buttonStyle(PanelButtonStyle(prominent: isLast))
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
                }
                .buttonStyle(PanelButtonStyle(prominent: true))
                .accessibilityLabel("Next: \(steps[index + 1].text)")
                .accessibilityIdentifier("coaching-next")
            }
        }
    }

    /// Every check on the swing, from the card's top row.
    private var allChecksButton: some View {
        // The shared panel capsule: drawn 28 points tall, 44 to tap,
        // without making the row taller.
        Button(action: showChecks) {
            HStack(spacing: 3) {
                Text("All checks")
                Image(systemName: "chevron.right").font(.appCaptionLabel)
            }
        }
        .buttonStyle(PanelCapsuleButtonStyle())
        .accessibilityLabel("All checks on this swing")
        .accessibilityIdentifier("coaching-all-checks")
    }

    /// A check picked from the list, on its own frame.
    private func checkCard(_ result: CoachingMetricResult, report: SwingCoachingReport, steps: [CoachingStep]) -> some View {
        VStack(alignment: .leading, spacing: Self.rowGap) {
            Text(CoachingWalkthrough.place(result.position))
                .font(.appLabel)
                .foregroundStyle(.white.opacity(0.82))
            titleRow(CoachingLevelBadge(level: result.level, scored: result.definition.scored,
                                        neutral: report.exclusion != nil, size: CoachingLevelBadge.markSize),
                     CoachingWords.headline(result),
                     level: CoachingWords.level(result, neutral: report.exclusion != nil),
                     severity: result.definition.scored && report.exclusion == nil && result.level != 0 ? result.level : nil)
            HStack(spacing: 10) {
                Button {
                    highlighted = nil
                    if let first = steps.first { go(to: first) }
                } label: {
                    Text("Back to the coach")
                }
                .buttonStyle(PanelButtonStyle())
                .accessibilityIdentifier("coaching-back-to-steps")
                Button("All checks", action: showChecks)
                .buttonStyle(PanelButtonStyle(prominent: true))
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
                    // What a tap does and where it goes, so the finding
                    // never reads as a verdict on the frame on screen.
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

    /// "Jump to impact finding": off the walkthrough the line is an
    /// action, so the finding under it never reads as a verdict on the
    /// frame on screen (whose position the transport row names), and it
    /// says where in the swing the tap goes.
    private func foldedCaption(_ step: CoachingStep) -> String? {
        let name = SwingPosition.names[min(max(step.position, 1), SwingPosition.names.count) - 1]
        let place = name.prefix(1).lowercased() + name.dropFirst()
        switch step.kind {
        case .pointer, .finding: return "Jump to \(place) finding"
        case .better: return "Jump to \(place) · back in zone"
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
    /// The card's buttons: the 44 pt minimum, no taller.
    private static let buttonHeight: CGFloat = HitArea.minimum

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

/// One mark of the key, the same shape wherever a reading or drawing is
/// keyed (the legend, the zone track's columns): you as a solid dot in the
/// level's colour (grey not judged; one shape, so only the colour changes),
/// the good zone as a green band, address as a dashed ring. Not judged,
/// the zone is a dashed outline, as the neutral guide style draws it. The glyphs stay fixed whatever
/// shape a check draws, so a key never changes from screen to screen.
struct CoachingKeyGlyph: View {
    enum Role { case you, zone, address }

    let role: Role
    var judged = true
    /// Your colours: one per swing where several are keyed together.
    var colours: [Color] = [.coachingLevel(0)]

    static let size: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let side = min(size.width, size.height)
            let circle = CGRect(x: rect.midX - side / 2 + 1, y: rect.midY - side / 2 + 1, width: side - 2, height: side - 2)
            switch role {
            case .you:
                let fills = judged ? colours : [CoachingDrawingLayer.neutralColour]
                let share = 360 / Double(max(fills.count, 1))
                for (index, colour) in fills.enumerated() {
                    var slice = Path()
                    slice.move(to: CGPoint(x: circle.midX, y: circle.midY))
                    slice.addArc(center: CGPoint(x: circle.midX, y: circle.midY), radius: circle.width / 2,
                                 startAngle: .degrees(share * Double(index) - 90),
                                 endAngle: .degrees(share * Double(index + 1) - 90), clockwise: false)
                    slice.closeSubpath()
                    context.fill(slice, with: .color(colour))
                }
                context.stroke(Path(ellipseIn: circle), with: .color(.black.opacity(0.6)), lineWidth: 1)
            case .zone:
                let band = Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 2)
                if judged {
                    context.fill(band, with: .color(Color.coachingLevel(0).opacity(0.4)))
                    context.stroke(band, with: .color(Color.coachingLevel(0)), lineWidth: 1.5)
                } else {
                    context.stroke(band, with: .color(CoachingDrawingLayer.neutralColour.opacity(0.8)),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                }
            case .address:
                context.stroke(Path(ellipseIn: circle.insetBy(dx: 0.5, dy: 0.5)), with: .color(.primary.opacity(0.85)),
                               style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
            }
        }
        .frame(width: role == .zone ? Self.size * 1.8 : Self.size, height: Self.size)
        .accessibilityHidden(true)
    }
}

/// The one key, wherever a drawing or a track is keyed (All checks, the
/// recap's comparison): the drawing's parts with the fixed
/// `CoachingKeyGlyph`s (You, Good zone, Address), a guide's dash and
/// dashed range ("Reference only"), then a club check's camera caveat,
/// all on one caption line that wraps only when it has to. Only what the
/// row or the drawing can show is keyed. The verdict badges need no key:
/// a tick, "!" and "!!" carry their meaning, and a word sits beside them.
struct CoachingLegend: View {
    /// The drawing keyed: its parts come from the first result's shapes.
    var results: [CoachingMetricResult] = []
    /// Several swings side by side: every colour their lines are drawn
    /// in, so "You" matches each picture.
    var subjectColours: [Color]? = nil
    /// The swing isn't judged: its line is drawn grey.
    var neutral = false
    /// Keys only what the pictures beside it show the way the key draws
    /// it (the recap's comparison): You, the zone, and Address only where
    /// it is the dashed ring round the head. The full key and the camera
    /// caveat are in All checks.
    var picturedOnly = false
    /// Keys the zone tracks of All checks' rows once, in its header: you
    /// as a dot in your level's colour, good players' zone as a band.
    var trackKey = false
    /// Keys a guide's rows (All checks): the dash badge and the dashed
    /// range together, "Reference only", the words beside the guide.
    var referenceKey = false

    static let badgeSize: CGFloat = 16

    var body: some View {
        let roles = keyedRoles
        FlowLayout(spacing: 12, lineSpacing: 4) {
            if trackKey {
                entry(CoachingKeyGlyph(role: .you, colours: [.coachingLevel(0), .coachingLevel(1),
                                                             .coachingLevel(CoachingSeverity.wellOutFrom)]), "You")
                entry(CoachingKeyGlyph(role: .zone), CoachingWords.zoneName)
            }
            if referenceKey {
                entry(HStack(spacing: 4) {
                    CoachingLevelBadge(level: 0, neutral: true, size: Self.badgeSize)
                    CoachingKeyGlyph(role: .zone, judged: false)
                }, CoachingWords.referenceOnly)
            }
            if roles.contains(.subject) {
                entry(CoachingKeyGlyph(role: .you, judged: judged, colours: subjectColours ?? [subjectColour]), "You")
            }
            if roles.contains(.zone) {
                entry(CoachingKeyGlyph(role: .zone, judged: results.first?.definition.scored ?? true),
                      CoachingWords.zoneName)
            }
            if roles.contains(.reference) {
                entry(CoachingKeyGlyph(role: .address), "Address")
            }
        }
        .font(.appCaption)
        .foregroundStyle(Color.helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(roles))
        .accessibilityIdentifier("coaching-legend")
    }

    private var judged: Bool { !neutral && (results.first?.definition.scored ?? true) }

    /// The drawing's parts to key: every role the results draw, less, for
    /// `picturedOnly`, an address drawn as anything but the ring.
    private var keyedRoles: Set<CoachingDrawing.Role> {
        var roles = Set(results.flatMap { $0.drawings.map(\.role) })
        if picturedOnly, !results.contains(where: { $0.drawings.contains { $0.role == .reference && $0.kind == .circle } }) {
            roles.remove(.reference)
        }
        return roles
    }

    private var subjectColour: Color {
        results.first.map { CoachingDrawingLayer.subjectColour($0, swingNeutral: neutral) } ?? .coachingLevel(0)
    }

    private func entry(_ glyph: some View, _ word: String) -> some View {
        HStack(spacing: 4) {
            glyph
            Text(word).fixedSize()
        }
    }

    private func accessibilityText(_ roles: Set<CoachingDrawing.Role>) -> String {
        var parts: [String] = []
        if trackKey { parts.append("on each track the dot is you, in your level's colour, and the green band is the good zone") }
        if referenceKey { parts.append("a dash and a dashed range are reference only, not judged") }
        if roles.contains(.subject) { parts.append(judged ? "you are drawn in your level's colour" : "you are drawn in grey") }
        if roles.contains(.zone) {
            parts.append(results.first?.definition.scored == false ? "the dashed outline is the good zone, for reference"
                                                                    : "the green shading is the good zone")
        }
        if roles.contains(.reference) { parts.append("white is where you were at address") }
        return "Key: " + parts.joined(separator: ", ")
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
    /// The list's height with its title bar, measured, so the sheet is as
    /// tall as what it holds.
    @State private var fittedHeight: CGFloat = 380

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $layers.coach) {
                        row("Coach's drawings", "The lines for each finding on the swing.")
                    }
                    .accessibilityIdentifier("coaching-layer-coach")
                    Toggle(isOn: $layers.clubPath) {
                        row("Clubhead path", hasTrail ? "Drawn while the swing plays, dashed where the club was lost."
                            : "Not on this swing: it comes with the full reading of the video.")
                    }
                    .accessibilityIdentifier("coaching-layer-club")
                    Toggle(isOn: $layers.everyCheck) {
                        row("Show all drawings here", "Includes checks in zone when paused.")
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
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // The list's own room under its last row gives way to
                // the fitted sheet's smaller one.
                geometry.contentSize.height + geometry.contentInsets.top
                    - SheetLayout.contentBottom + SheetLayout.fittedBottom
            } action: { _, height in
                if height > 0 { fittedHeight = height.rounded(.up) }
            }
        }
        .playerSheetStyle()
        .presentationDetents([.height(fittedHeight), .large])
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
                    .frame(minHeight: CapsuleButton.height)
                    .background(Capsule().fill(Color.white))
                    .padding(.vertical, CapsuleButton.tapPadding)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
                .accessibilityLabel("Reset layers to the coach's choice")
                .accessibilityIdentifier("coaching-layers-reset")
        }
        .foregroundStyle(.white)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(minHeight: HitArea.minimum)
        .background(RoundedRectangle(cornerRadius: 12).fill(PlayerChrome.panel))
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

    /// The whole swing first ("11 of 16 checks in zone"), then the
    /// sheet's one key on one caption line: the rows' track (You, Good
    /// zone) and, when a guide is listed, its dash and dashed range, so no
    /// row repeats it. The top finding is the card behind the sheet, so it
    /// isn't repeated here, and two rows show at the first detent. A swing
    /// without a finding says in one line why there is nothing to work on;
    /// a swing that isn't judged leads with its verdict.
    private var summaryCard: some View {
        let judged = report.metrics.filter(\.definition.scored)
        let guides = report.metrics.count - judged.count
        let inZone = judged.filter(\.inZone).count
        // Says what it counts: judged checks, not the guides listed too.
        let count = "\(inZone) of \(judged.count) judged checks in zone"
        let hasFinding = { if case .focus = verdict { true } else { false } }()
        let note: String? = if let exclusion = report.exclusion {
            CoachingWords.exclusion(exclusion)
        } else if hasFinding {
            nil
        } else {
            "Nothing is far enough out to work on."
        }
        return VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                if report.exclusion == nil {
                    // A headline number: proportional digits, so "11" never
                    // reads as "1 1".
                    Text(count).font(.appTitle)
                } else {
                    Text(verdict.headline).font(.appLabel)
                }
                if let note {
                    Text(note)
                        .font(.appCaption)
                        .foregroundStyle(Color.helpText)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(report.exclusion == nil
                ? "\(count).\(note.map { " \($0)" } ?? "")"
                : "\(verdict.headline). \(note ?? "")")
            .accessibilityIdentifier("coaching-summary")
            if report.exclusion == nil {
                // The one key for every row: the track's marks, and a
                // guide's dash and dashed range as "Reference only".
                CoachingLegend(trackKey: true, referenceKey: guides > 0)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    /// A row's picture of its check.
    static let thumbnailWidth: CGFloat = 64
    static let thumbnailHeight: CGFloat = 96

    private func row(_ result: CoachingMetricResult) -> some View {
        let neutral = report.exclusion != nil
        let judged = result.definition.scored && !neutral
        let reason = CoachingWords.notJudgedReason(result, exclusion: report.exclusion)
        return HStack(spacing: 12) {
            // Cut toward the drawing, big enough to see it on.
            CoachingFrameView(swing: swing, report: report, metric: result.id, cropsToGolfer: true)
                .frame(width: Self.thumbnailWidth, height: Self.thumbnailHeight)
                .clipShape(.rect(cornerRadius: 8))
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
                        Text(reason.map { CoachingWords.notJudged($0) } ?? CoachingWords.referenceOnly)
                            .font(.appCaptionLabel)
                            .foregroundStyle(Color.helpText)
                            .fixedSize()
                    }
                }
                // The badge carries the level; VoiceOver reads it as the value.
                CoachingZoneTrack(result: result, neutral: neutral)
                    .padding(.vertical, 2)
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
