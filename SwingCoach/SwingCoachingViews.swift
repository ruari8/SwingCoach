//
//  SwingCoachingViews.swift
//  SwingCoach
//
//  Coaching in the review player: the drawings over the video, the one-line
//  verdict, the full metric list, and the session summary.
//

import AVFoundation
import SwiftUI

extension Color {
    static func coachingLevel(_ level: Int) -> Color {
        switch abs(level) {
        case 0: Color(red: 0.24, green: 0.86, blue: 0.43)
        case 1...3: Color(red: 1.0, green: 0.75, blue: 0.16)
        default: Color(red: 1.0, green: 0.33, blue: 0.27)
        }
    }
}

// MARK: - Which checks are drawn

/// The coach decides what is drawn (the one fault in the swing's verdict,
/// nothing on a good swing) unless the golfer has turned a check on or off. The choices are app-wide, stored as
/// comma-separated metric ids.
struct CoachingDrawingChoices {
    static let shownKey = "coaching.shownMetrics"
    static let hiddenKey = "coaching.hiddenMetrics"

    var shown: Set<String>
    var hidden: Set<String>

    init(shown: String, hidden: String) {
        self.shown = Set(shown.split(separator: ",").map(String.init))
        self.hidden = Set(hidden.split(separator: ",").map(String.init))
    }

    var isCoachsChoice: Bool { shown.isEmpty && hidden.isEmpty }

    func draws(_ id: CoachingMetricID, coachPicked: Bool, showsAll: Bool) -> Bool {
        if hidden.contains(id.rawValue) { return false }
        return showsAll || coachPicked || shown.contains(id.rawValue)
    }

    /// Flips a check against what is drawn now.
    mutating func toggle(_ id: CoachingMetricID, drawnNow: Bool) {
        if drawnNow {
            shown.remove(id.rawValue)
            hidden.insert(id.rawValue)
        } else {
            hidden.remove(id.rawValue)
            shown.insert(id.rawValue)
        }
    }

    var shownValue: String { shown.sorted().joined(separator: ",") }
    var hiddenValue: String { hidden.sorted().joined(separator: ",") }
}

// MARK: - Drawings over the video

/// Draws a swing's coaching on the frames it was measured on. A metric's
/// drawing shows while the playhead is within a frame or two of its swing
/// position, so it holds when paused there and passes when playing.
struct SwingCoachingOverlay: View {
    let report: SwingCoachingReport?
    /// The checks the coach draws unasked: the verdict's fault.
    let picks: Set<CoachingMetricID>
    let aspectRatio: Double?
    let currentTime: CMTime
    /// The clip's slow-motion factor; sets how long a drawing stays up.
    let timeScale: Double
    /// Metric picked from the list: shown even when it is in zone.
    let highlighted: CoachingMetricID?

    @AppStorage("coaching.showAllDrawings") private var showsAll = false
    @AppStorage("coaching.showDrawings") private var showsDrawings = true
    @AppStorage(CoachingDrawingChoices.shownKey) private var shownMetrics = ""
    @AppStorage(CoachingDrawingChoices.hiddenKey) private var hiddenMetrics = ""

    private var visible: [CoachingMetricResult] {
        guard showsDrawings, let report else { return [] }
        let now = CMTimeGetSeconds(currentTime)
        guard now.isFinite else { return [] }
        // One slot of the position grid either side, in clip time.
        let window = timeScale / 30
        let choices = CoachingDrawingChoices(shown: shownMetrics, hidden: hiddenMetrics)
        return report.metrics.filter { result in
            guard abs(result.clipTime - now) <= window else { return false }
            // A check picked from the list shows on its own.
            if result.id == highlighted { return true }
            if highlighted != nil, !showsAll { return false }
            return choices.draws(result.id, coachPicked: picks.contains(result.id), showsAll: showsAll)
        }
    }

    var body: some View {
        let results = visible
        GeometryReader { geometry in
            if let aspectRatio, !results.isEmpty {
                let rect = VideoDisplayGeometry.contentRect(in: geometry.size, aspectRatio: aspectRatio)
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for result in results {
                            draw(result, in: rect, context: &context)
                        }
                    }
                    // Under the verdict pill and the old Analyze button.
                    captions(results)
                        .padding(.leading, max(rect.minX, 0) + 12)
                        .padding(.top, max(rect.minY + 12, 178))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func captions(_ results: [CoachingMetricResult]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(results, id: \.id) { result in
                HStack(spacing: 6) {
                    Circle().fill(Color.coachingLevel(result.level)).frame(width: 8, height: 8)
                    Text(result.finding ?? "\(result.definition.title): in zone")
                        .font(.system(size: 13, weight: .semibold))
                    Text(result.definition.unit.format(result.value))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.55)))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("coaching-caption-\(result.id.rawValue)")
            }
        }
    }

    private func draw(_ result: CoachingMetricResult, in rect: CGRect, context: inout GraphicsContext) {
        let subject = Color.coachingLevel(result.level)
        func place(_ point: CoachingPoint) -> CGPoint {
            CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
        }
        for shape in result.drawings {
            let colour: Color = switch shape.role {
            case .reference: .white
            case .zone: Color.coachingLevel(0)
            case .subject: subject
            }
            let points = shape.points.map(place)
            let size = CGFloat(shape.size ?? 0) * rect.height
            let stroke = StrokeStyle(lineWidth: 3, lineCap: .round, dash: shape.dashed ? [7, 6] : [])
            switch shape.kind {
            case .line:
                guard points.count == 2 else { continue }
                var path = Path()
                path.move(to: points[0])
                path.addLine(to: points[1])
                // A dark edge keeps a white line readable on sky.
                context.stroke(path, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: stroke.dash))
                context.stroke(path, with: .color(colour), style: stroke)
            case .area:
                guard points.count >= 3 else { continue }
                var path = Path()
                path.addLines(points)
                path.closeSubpath()
                context.fill(path, with: .color(colour.opacity(0.24)))
            case .band:
                guard points.count == 2 else { continue }
                let delta = CGPoint(x: points[1].x - points[0].x, y: points[1].y - points[0].y)
                let length = max(hypot(delta.x, delta.y), 0.001)
                let normal = CGPoint(x: -delta.y / length * size, y: delta.x / length * size)
                var path = Path()
                path.move(to: CGPoint(x: points[0].x + normal.x, y: points[0].y + normal.y))
                path.addLine(to: CGPoint(x: points[1].x + normal.x, y: points[1].y + normal.y))
                path.addLine(to: CGPoint(x: points[1].x - normal.x, y: points[1].y - normal.y))
                path.addLine(to: CGPoint(x: points[0].x - normal.x, y: points[0].y - normal.y))
                path.closeSubpath()
                context.fill(path, with: .color(colour.opacity(0.28)))
            case .circle:
                guard let centre = points.first else { continue }
                let path = Path(ellipseIn: CGRect(x: centre.x - size, y: centre.y - size, width: size * 2, height: size * 2))
                context.stroke(path, with: .color(colour), style: stroke)
            case .dot:
                guard let centre = points.first else { continue }
                let radius: CGFloat = 6
                let path = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
                context.fill(path, with: .color(colour))
                context.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: 1.5)
            case .label:
                guard let anchor = points.first, let text = shape.text else { continue }
                context.draw(Text(text).font(.system(size: 12, weight: .semibold)).foregroundColor(colour), at: anchor, anchor: .leading)
            }
        }
    }
}

// MARK: - Verdict pill

/// One line on the swing: the verdict, or that coaching is still running.
/// Tapping opens the metric list.
struct SwingCoachingPill: View {
    let swing: SavedSwing
    /// Jumps the player to a clip time.
    let seek: (Double) -> Void
    @Binding var highlighted: CoachingMetricID?

    @ObservedObject private var store = SwingCoachingStore.shared
    @State private var showsList = false

    var body: some View {
        let report = store.report(for: swing)
        Group {
            if let report {
                let verdict = store.verdict(for: swing, report: report)
                Button {
                    if case .focus(let finding) = verdict, let result = report.metric(finding.metric), highlighted == nil {
                        highlighted = finding.metric
                        seek(result.clipTime)
                    } else {
                        showsList = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(colour(verdict)).frame(width: 9, height: 9)
                        Text(verdict.headline)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        if case .focus(let finding) = verdict {
                            Text("P\(finding.position)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .simultaneousGesture(LongPressGesture().onEnded { _ in showsList = true })
                .accessibilityIdentifier("swing-coaching-pill")
                .accessibilityLabel("Coaching: \(verdict.headline)")
                .accessibilityHint("Shows the measurements for this swing")
            } else if store.pending.contains(swing.id) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Reading swing")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(.black.opacity(0.45)))
                .accessibilityIdentifier("swing-coaching-pending")
            }
        }
        .sheet(isPresented: $showsList) {
            if let report {
                let verdict = store.verdict(for: swing, report: report)
                SwingCoachingList(report: report, verdict: verdict, coachPicks: CoachingFeedback.picks(for: verdict)) { result in
                    highlighted = result.id
                    seek(result.clipTime)
                    showsList = false
                }
                .presentationDetents([.medium, .large])
            }
        }
        .onAppear { store.coachWithSession(swing) }
        .onChange(of: swing.swingPositions) { _, _ in store.coachWithSession(swing) }
    }

    private func colour(_ verdict: CoachingVerdict) -> Color {
        switch verdict {
        case .notJudged: .gray
        case .good, .better: .coachingLevel(0)
        case .focus(let finding): .coachingLevel(finding.level)
        }
    }
}

// MARK: - Metric list

struct SwingCoachingList: View {
    let report: SwingCoachingReport
    let verdict: CoachingVerdict
    /// The checks the coach draws unasked: the verdict's fault.
    let coachPicks: Set<CoachingMetricID>
    let onSelect: (CoachingMetricResult) -> Void

    @AppStorage("coaching.showAllDrawings") private var showsAll = false
    @AppStorage("coaching.showDrawings") private var showsDrawings = true
    @AppStorage(CoachingDrawingChoices.shownKey) private var shownMetrics = ""
    @AppStorage(CoachingDrawingChoices.hiddenKey) private var hiddenMetrics = ""

    private var choices: CoachingDrawingChoices {
        CoachingDrawingChoices(shown: shownMetrics, hidden: hiddenMetrics)
    }

    private func isDrawn(_ id: CoachingMetricID) -> Bool {
        showsDrawings && choices.draws(id, coachPicked: coachPicks.contains(id), showsAll: showsAll)
    }

    private func toggleDrawing(_ id: CoachingMetricID) {
        var updated = choices
        updated.toggle(id, drawnNow: isDrawn(id))
        shownMetrics = updated.shownValue
        hiddenMetrics = updated.hiddenValue
    }

    private var positions: [Int] {
        Array(Set(report.metrics.map(\.position))).sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verdict.headline).font(.headline)
                        Text(summary).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("coaching-summary")
                    Toggle("Drawings on the video", isOn: $showsDrawings)
                    Toggle("Draw every check", isOn: $showsAll)
                        .disabled(!showsDrawings)
                    if !choices.isCoachsChoice || showsAll {
                        Button("Let the coach decide what is drawn") {
                            shownMetrics = ""
                            hiddenMetrics = ""
                            showsAll = false
                        }
                        .accessibilityIdentifier("coaching-reset-choices")
                    }
                } footer: {
                    Text("The coach draws the one fault it names, and nothing on a good swing. Use the eye on a check to always draw it or never draw it.")
                }
                ForEach(positions, id: \.self) { position in
                    Section("P\(position) · \(SwingPosition.names[position - 1])") {
                        ForEach(report.metrics.filter { $0.position == position }, id: \.id) { result in
                            HStack(spacing: 8) {
                                Button { onSelect(result) } label: { row(result) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("coaching-metric-\(result.id.rawValue)")
                                Button { toggleDrawing(result.id) } label: {
                                    Image(systemName: isDrawn(result.id) ? "eye" : "eye.slash")
                                        .foregroundStyle(isDrawn(result.id) ? Color.accentColor : Color.secondary)
                                        .frame(width: 34, height: 34)
                                }
                                .buttonStyle(.plain)
                                .disabled(!showsDrawings)
                                .accessibilityIdentifier("coaching-draw-\(result.id.rawValue)")
                                .accessibilityLabel("Draw \(result.definition.title)")
                                .accessibilityValue(isDrawn(result.id) ? "On" : "Off")
                            }
                        }
                    }
                }
                if !report.unavailable.isEmpty {
                    Section("Not measured on this swing") {
                        Text(report.unavailable.map { CoachingMetricDefinition.definition($0).title }.joined(separator: ", "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Swing measurements")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var summary: String {
        switch report.exclusion {
        case .shortSwing?:
            return "A chip or pitch. The zones come from full swings, so it is measured but not judged."
        case .cameraMoved?:
            return "The camera moved during the swing, so it can't be compared with address."
        case .positionsUnclear?:
            return "Address or impact couldn't be found clearly on this clip."
        case nil:
            let judged = report.metrics.filter { $0.definition.scored }
            let out = judged.filter { !$0.inZone }.count
            return out == 0 ? "All \(judged.count) measurements in zone."
                : "\(judged.count - out) of \(judged.count) measurements in zone."
        }
    }

    private func rowNote(_ result: CoachingMetricResult) -> String {
        let state = !result.definition.scored ? "Guide, not judged" : result.inZone ? "In zone" : result.definition.title
        return result.definition.dependsOnCamera ? state + " · depends on camera position" : state
    }

    private func row(_ result: CoachingMetricResult) -> some View {
        HStack(spacing: 12) {
            LevelMeter(level: result.level)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.finding ?? result.definition.title)
                    .font(.subheadline.weight(.medium))
                Text(rowNote(result))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(result.definition.unit.format(result.value))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(result.inZone ? "In zone" : "Level \(abs(result.level))")
    }
}

/// A metric's level as a number in its colour: a tick in zone, otherwise
/// 1...10 with an arrow for the side of the zone it is on.
private struct LevelMeter: View {
    let level: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.coachingLevel(level).opacity(0.18))
            if level == 0 {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.coachingLevel(0))
            } else {
                Text("\(abs(level))")
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.coachingLevel(level))
            }
        }
        .frame(width: 34, height: 34)
    }
}

// MARK: - Session summary

/// What kept happening across a session's swings.
struct SessionCoachingView: View {
    let session: SwingSession
    @ObservedObject private var store = SwingCoachingStore.shared
    @ObservedObject private var library = SwingLibrary.shared
    @Environment(\.dismiss) private var dismiss

    /// Oldest first, as hit.
    private var swings: [SavedSwing] {
        let ids = Set(session.swings.map(\.id))
        return library.swings.filter { ids.contains($0.id) }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        let swings = swings
        let coachable = swings.filter(SwingCoachingStore.canCoach)
        let coached = coachable.map { store.report(for: $0) }
        let reports = coached.compactMap { $0 }
        let waiting = coachable.filter { store.pending.contains($0.id) }.count
        let themes = CoachingFeedback.themes(in: reports)
        let judged = reports.filter { $0.exclusion == nil }
        // Counted the way the swings' own pills read: each against the
        // swings before it, and on its own while any of those is still
        // to be coached.
        let good = CoachingFeedback.sessionVerdicts(coached).filter {
            switch $0 {
            case .good, .better: true
            default: false
            }
        }.count

        NavigationStack {
            List {
                Section {
                    if waiting > 0 {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Reading swings: \(reports.count) of \(coachable.count)")
                        }
                        .accessibilityIdentifier("session-coaching-progress")
                    }
                    LabeledContent("Swings measured", value: "\(reports.count) of \(swings.count)")
                    LabeledContent("Good swings", value: "\(good) of \(judged.count)")
                    if judged.count < reports.count {
                        LabeledContent("Not judged (chips, moved camera, unclear)", value: "\(reports.count - judged.count)")
                    }
                }
                if themes.isEmpty, waiting == 0 {
                    Section {
                        Text(judged.count < CoachingFeedback.themeMinimumSwings
                             ? "Not enough measured swings to see a pattern yet."
                             : "Nothing kept repeating. No single fault showed up on half the swings.")
                            .foregroundStyle(.secondary)
                    }
                }
                if !themes.isEmpty {
                    // Three is plenty to think about; the rest are weaker.
                    Section("What kept happening") {
                        ForEach(Array(themes.prefix(3).enumerated()), id: \.element.id) { index, theme in
                            HStack(alignment: .top, spacing: 12) {
                                LevelMeter(level: theme.medianLevel)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(theme.text).font(.subheadline.weight(.semibold))
                                    Text("\(theme.swings) of \(theme.measured) swings · P\(theme.position) \(SwingPosition.names[theme.position - 1].lowercased())")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if CoachingMetricDefinition.definition(theme.metric).dependsOnCamera {
                                        Text("A club reading: it shifts with where the camera stands. Check it with the camera on your hand line.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if index == 0 {
                                        Text("Start here")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(Color.coachingLevel(1))
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                            .accessibilityIdentifier("session-theme-\(theme.id)")
                        }
                    }
                    if themes.count > 3 {
                        Section("Also seen, weaker") {
                            ForEach(Array(themes.dropFirst(3))) { theme in
                                Text("\(theme.text) · \(theme.swings) of \(theme.measured) swings")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Session coaching")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Positions can arrive while the sheet is open.
        .task(id: coachable.map(\.id)) {
            for swing in coachable { store.coachIfNeeded(swing) }
        }
    }
}
