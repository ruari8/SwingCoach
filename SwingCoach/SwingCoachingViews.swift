//
//  SwingCoachingViews.swift
//  SwingCoach
//
//  The coaching colours and the session review. Coaching inside the player
//  is in CoachingPlayerViews.swift.
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

// MARK: - Session review

/// A session's coaching: how each swing went, what kept happening with a
/// picture of it at its worst and best, how the repeating faults sit
/// together, and each one swing by swing.
struct SessionCoachingView: View {
    let session: SwingSession
    @ObservedObject private var store = SwingCoachingStore.shared
    @ObservedObject private var library = SwingLibrary.shared
    @Environment(\.dismiss) private var dismiss
    @State private var opened: UUID?

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
        // The swings behind `reports`, in the same order.
        let measured = zip(coachable, coached).compactMap { swing, report in report == nil ? nil : swing }
        let waiting = coachable.filter { store.pending.contains($0.id) && store.report(for: $0) == nil }.count
        let themes = CoachingFeedback.themes(in: reports)
        let judged = reports.filter { $0.exclusion == nil }
        // Counted the way the swings' own pills read: each against the
        // swings before it, and on its own while any of those is still
        // to be coached.
        let verdicts = CoachingFeedback.sessionVerdicts(coached)
        let good = verdicts.filter {
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
                    if !measured.isEmpty {
                        swingDots(measured, verdicts)
                    }
                    LabeledContent("Swings measured", value: "\(reports.count) of \(swings.count)")
                    LabeledContent("Good swings", value: "\(good) of \(judged.count)")
                    if judged.count < reports.count {
                        LabeledContent("Not judged (chips, moved camera, unclear)", value: "\(reports.count - judged.count)")
                    }
                } footer: {
                    if !measured.isEmpty {
                        Text("One dot a swing, in the order hit. Green needed no pointer, amber or red had one, grey wasn't judged. Tap a dot to open the swing.")
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
                    let shown = Array(themes.prefix(3))
                    Section("What kept happening") {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, theme in
                            VStack(alignment: .leading, spacing: 10) {
                                themeRow(theme, leads: index == 0)
                                if index == 0 {
                                    examples(of: theme, measured, reports)
                                }
                            }
                            .padding(.vertical, 2)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("session-theme-\(theme.id)")
                        }
                    }
                    if shown.count > 1 {
                        Section {
                            links(shown.sorted { ($0.position, $0.id) < ($1.position, $1.id) }, reports)
                        } header: {
                            Text("How they sit together")
                        } footer: {
                            Text("In swing order. An earlier fault often causes a later one, so the earliest is the one to work on first.")
                        }
                    }
                    Section("Swing by swing") {
                        ForEach(shown) { theme in
                            trend(of: theme, measured, reports)
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
            .navigationDestination(item: $opened) { id in
                if let swing = swings.first(where: { $0.id == id }) {
                    SwingDetailView(swing: swing, reviewSwings: swings)
                }
            }
        }
        // Positions can arrive while the sheet is open.
        .task(id: coachable.map(\.id)) {
            for swing in coachable { store.coachIfNeeded(swing) }
        }
    }

    private func swingDots(_ measured: [SavedSwing], _ verdicts: [CoachingVerdict]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 22, maximum: 22), spacing: 2)], alignment: .leading, spacing: 2) {
            ForEach(Array(zip(measured, verdicts).enumerated()), id: \.element.0.id) { index, entry in
                Button {
                    opened = entry.0.id
                } label: {
                    Circle()
                        .fill(entry.1.colour)
                        .frame(width: 12, height: 12)
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Swing \(index + 1): \(entry.1.headline)")
                .accessibilityIdentifier("session-swing-dot-\(index + 1)")
            }
        }
        .padding(.vertical, 2)
    }

    private func themeRow(_ theme: CoachingTheme, leads: Bool) -> some View {
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
                if leads {
                    Text("Start here")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.coachingLevel(1))
                }
            }
        }
    }

    /// The lead theme on the swing that shows it most and on the best one
    /// that doesn't.
    @ViewBuilder
    private func examples(of theme: CoachingTheme, _ measured: [SavedSwing], _ reports: [SwingCoachingReport]) -> some View {
        let picked = CoachingFeedback.examples(of: theme, in: reports)
        if picked.most != nil || picked.best != nil {
            HStack(alignment: .top, spacing: 10) {
                if let most = picked.most {
                    example("Shows it most", most, theme, measured, reports)
                }
                if let best = picked.best {
                    example("Your best here", best, theme, measured, reports)
                }
            }
        }
    }

    @ViewBuilder
    private func example(_ title: String, _ index: Int, _ theme: CoachingTheme,
                         _ measured: [SavedSwing], _ reports: [SwingCoachingReport]) -> some View {
        let report = reports[index]
        if let metric = CoachingFeedback.metric(showing: theme, in: report), let result = report.metric(metric) {
            Button {
                opened = measured[index].id
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    CoachingFrameView(swing: measured[index], report: report, metric: metric)
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 10))
                    Text(title).font(.caption.weight(.semibold))
                    Text("Swing \(index + 1) · \(result.level == 0 ? "in zone" : "level \(abs(result.level))") · \(result.definition.unit.format(result.value))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .accessibilityIdentifier("session-example-\(index + 1)")
        }
    }

    private func links(_ ordered: [CoachingTheme], _ reports: [SwingCoachingReport]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, theme in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("P\(theme.position)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.coachingLevel(theme.medianLevel).opacity(0.22), in: .rect(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(theme.text).font(.subheadline.weight(.semibold))
                        Text("\(theme.swings) of \(theme.measured) swings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if index + 1 < ordered.count {
                    let both = CoachingFeedback.swingsShowingBoth(theme, ordered[index + 1], in: reports)
                    Label("Both on \(both) swing\(both == 1 ? "" : "s")", systemImage: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("session-links")
    }

    /// The theme's own metric on every swing, against its zone.
    private func trend(of theme: CoachingTheme, _ measured: [SavedSwing], _ reports: [SwingCoachingReport]) -> some View {
        let definition = CoachingMetricDefinition.definition(theme.metric)
        let points = reports.enumerated().compactMap { index, report -> CoachingTrendChart.Point? in
            guard report.exclusion == nil, let result = report.metric(theme.metric) else { return nil }
            return CoachingTrendChart.Point(swing: index + 1, of: reports.count, value: result.value, level: result.level,
                                            id: measured[index].id)
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(definition.title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("green band \(definition.unit.format(definition.zone.lowerBound)) to \(definition.unit.format(definition.zone.upperBound))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if points.count < 2 {
                Text("Too few swings to show a trend.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                CoachingTrendChart(points: points, zone: definition.zone)
                    .frame(height: 96)
                HStack {
                    Text("First swing")
                    Spacer()
                    Text("Last swing")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("session-trend-\(theme.metric.rawValue)")
    }
}

/// One metric across a session: a dot a swing, left to right in the order
/// hit, over the green band of its zone.
struct CoachingTrendChart: View {
    struct Point: Identifiable {
        /// The swing's number among the session's measured swings, and
        /// how many of those there are.
        let swing: Int
        let of: Int
        let value: Double
        let level: Int
        let id: UUID
    }

    let points: [Point]
    let zone: ClosedRange<Double>

    var body: some View {
        Canvas { context, size in
            let values = points.map(\.value) + [zone.lowerBound, zone.upperBound]
            let low = values.min() ?? 0, high = values.max() ?? 1
            let margin = max((high - low) * 0.12, 0.5)
            let bottom = low - margin, top = high + margin
            func y(_ value: Double) -> CGFloat {
                size.height * CGFloat(1 - (value - bottom) / (top - bottom))
            }
            func x(_ point: Point) -> CGFloat {
                let inset: CGFloat = 6
                guard point.of > 1 else { return size.width / 2 }
                return inset + (size.width - 2 * inset) * CGFloat(point.swing - 1) / CGFloat(point.of - 1)
            }
            let band = CGRect(x: 0, y: y(zone.upperBound), width: size.width, height: y(zone.lowerBound) - y(zone.upperBound))
            context.fill(Path(roundedRect: band, cornerRadius: 3), with: .color(Color.coachingLevel(0).opacity(0.2)))
            for point in points {
                let centre = CGPoint(x: x(point), y: y(point.value))
                let dot = Path(ellipseIn: CGRect(x: centre.x - 3.5, y: centre.y - 3.5, width: 7, height: 7))
                context.fill(dot, with: .color(Color.coachingLevel(point.level)))
            }
        }
        .accessibilityLabel("\(points.filter { $0.level == 0 }.count) of \(points.count) swings in the green band")
    }
}
