//
//  SwingCoachingViews.swift
//  SwingCoach
//
//  The session review. Coaching inside the player
//  is in CoachingPlayerViews.swift.
//

import AVFoundation
import SwiftUI

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
                    // One card with its own dividers, so the headline, the
                    // marks and the counts sit closer than list rows do and
                    // the first theme starts higher.
                    VStack(alignment: .leading, spacing: Self.summaryGap) {
                        if !judged.isEmpty {
                            headline(good: good, judged: judged.count)
                            Divider()
                        }
                        if !measured.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                // Shapes, no numerals and no key: a tick,
                                // a "!" in its level's colour, a dash.
                                // Then the swings without a level, and why.
                                swingDots(measured, verdicts)
                                if judged.count < reports.count {
                                    Text(notJudgedTotal(reports))
                                        .font(.appCaption.monospacedDigit())
                                        .foregroundStyle(Color.helpText)
                                        .accessibilityIdentifier("session-coaching-not-judged")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                if themes.isEmpty, waiting == 0 {
                    Section {
                        Text(judged.count < CoachingFeedback.themeMinimumSwings
                             ? "Not enough measured swings to see a pattern yet."
                             : "Nothing kept repeating: no fault on half the swings.")
                            .foregroundStyle(Color.helpText)
                    }
                }
                if !themes.isEmpty {
                    // Three is plenty to think about; the rest are weaker.
                    let shown = Array(themes.prefix(3))
                    Section {
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
                    } header: {
                        SectionHeading("What kept happening")
                    }
                    if shown.count > 1 {
                        Section {
                            links(shown.sorted { ($0.position, $0.id) < ($1.position, $1.id) }, reports)
                        } header: {
                            SectionHeading("How they sit together")
                        } footer: {
                            Text("Earliest first: it often causes the later ones.")
                        }
                    }
                    Section {
                        ForEach(shown) { theme in
                            trend(of: theme, measured, reports)
                        }
                    } header: {
                        SectionHeading("Swing by swing")
                    }
                    if themes.count > 3 {
                        Section {
                            ForEach(Array(themes.dropFirst(3))) { theme in
                                Text("\(theme.text) · \(CoachingWords.themeShare(theme))")
                                    .font(.appCaption)
                                    .foregroundStyle(Color.helpText)
                            }
                        } header: {
                            SectionHeading("Also seen, weaker")
                        }
                    }
                }
            }
            .sheetContentTop()
            .navigationTitle("Session coaching")
            .navigationBarTitleDisplayMode(.inline)
            // A bar of its own once the list scrolls, so the title and
            // Done never sit on the photos.
            .hardTopScrollEdge()
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
        .tint(.appAccent)
        // Positions can arrive while the sheet is open.
        .task(id: coachable.map(\.id)) {
            for swing in coachable { store.coachIfNeeded(swing) }
        }
    }

    /// The session in one line at a section heading's size: "7 of 11
    /// judged swings good", the swings the coach had nothing to say
    /// about. Not larger, so "Start here" and its pictures come into view.
    private func headline(good: Int, judged: Int) -> some View {
        // Proportional digits: a headline number, never a column, so "11"
        // never reads as "1 1".
        Text("\(good) of \(judged) judged swing\(judged == 1 ? "" : "s") good")
            .font(.appTitle)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("session-coaching-headline")
    }


    /// Between the summary's headline, marks and counts: tight, so the
    /// summary stays short and the first theme starts higher.
    private static let summaryGap: CGFloat = 6
    /// A swing's mark as laid out: 44 points wide, shorter than that, with
    /// its target grown to 44 points tall, so rows of marks sit closer.
    private static let dotWidth: CGFloat = 44
    private static let dotHeight: CGFloat = 32

    /// "1 not judged", and why when every one of them shares the reason:
    /// "1 not judged · short swing".
    private func notJudgedTotal(_ reports: [SwingCoachingReport]) -> String {
        let exclusions = reports.compactMap(\.exclusion)
        let count = "\(exclusions.count) not judged"
        guard let reason = exclusions.first, exclusions.allSatisfy({ $0 == reason }) else { return count }
        return "\(count) · \(CoachingWords.reason(reason))"
    }

    /// A mark a swing, each a 44 point target, wrapping in the order hit:
    /// a tick for a good swing, a "!" in the top finding's level colour
    /// (amber a little out, red well out), a dash not judged. No numeral,
    /// so a swing's mark never disagrees with a theme's word below.
    private func swingDots(_ measured: [SavedSwing], _ verdicts: [CoachingVerdict]) -> some View {
        FlowLayout(spacing: 0, lineSpacing: 0) {
            ForEach(Array(zip(measured, verdicts).enumerated()), id: \.element.0.id) { index, entry in
                Button {
                    opened = entry.0.id
                } label: {
                    badge(entry.1)
                        .frame(width: Self.dotWidth, height: Self.dotHeight)
                        .contentShape(.rect.inset(by: -(44 - Self.dotHeight) / 2))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Swing \(index + 1): \(entry.1.headline)")
                .accessibilityIdentifier("session-swing-dot-\(index + 1)")
            }
        }
        .padding(.horizontal, -9)
    }

    private func badge(_ verdict: CoachingVerdict) -> CoachingLevelBadge {
        switch verdict {
        case .notJudged: CoachingLevelBadge(level: 0, neutral: true, size: CoachingLevelBadge.markSize)
        case .good, .better: CoachingLevelBadge(level: 0, size: CoachingLevelBadge.markSize)
        case .focus(let finding): CoachingLevelBadge(level: finding.level, size: CoachingLevelBadge.markSize, mark: .glyph)
        }
    }

    private func themeRow(_ theme: CoachingTheme, leads: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // Above the title in the secondary style, so it reads as
                // where to begin, never as a level.
                if leads {
                    Text("Start here")
                        .font(.appCaptionLabel)
                        .foregroundStyle(Color.helpText)
                        .accessibilityIdentifier("session-start-here")
                }
                // The lead finding a heading size up, so it, not the
                // tally's key, is the first thing read after the count.
                Text(theme.text).font(leads ? .appTitle : .appLabel)
                // The typical level as its word tier: "Typically well out".
                CoachingLevelPill(level: theme.medianLevel, lead: "Typically")
                // One caption: how many swings and which check, with the
                // camera mark alone after it on a club check; its sentence
                // is in All checks.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(CoachingWords.themeShare(theme))
                    if CoachingMetricDefinition.definition(theme.metric).dependsOnCamera {
                        CoachingCameraMark()
                    }
                }
                .font(.appCaption)
                .foregroundStyle(Color.helpText)
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
                    // What the picture is, above it, so it is read first.
                    Text(title).font(.appCaptionLabel)
                    CoachingFrameView(swing: measured[index], report: report, metric: metric)
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 10))
                    // The swing only: the picture's own colours carry
                    // its level, and the numbers are in All checks.
                    Text("Swing \(index + 1)")
                        .font(.appCaption.monospacedDigit())
                        .foregroundStyle(Color.helpText)
                        .accessibilityLabel("Swing \(index + 1), \(CoachingSeverity(level: result.level).word.lowercased())")
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
                    PositionTag(position: theme.position)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(theme.text).font(.appLabel)
                        Text(CoachingWords.themeShare(theme, namingPosition: false))
                            .font(.appCaption)
                            .foregroundStyle(Color.helpText)
                    }
                }
                if index + 1 < ordered.count {
                    let both = CoachingFeedback.swingsShowingBoth(theme, ordered[index + 1], in: reports)
                    // A plain connector, no arrowhead: seen together is
                    // not one causing the other.
                    HStack(spacing: 10) {
                        Capsule()
                            .fill(Color.helpText.opacity(0.6))
                            .frame(width: 2, height: 18)
                            .frame(width: 28)
                        Text("Seen together on \(both) swing\(both == 1 ? "" : "s")")
                            .font(.appCaption)
                            .foregroundStyle(Color.helpText)
                    }
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
                Text(definition.title).font(.appLabel)
                Spacer()
                Text("green band \(definition.unit.format(definition.zone.lowerBound)) to \(definition.unit.format(definition.zone.upperBound))")
                    .font(.appCaption)
                    .foregroundStyle(Color.helpText)
            }
            if points.count < 2 {
                Text("Too few swings to show a trend.")
                    .font(.appCaption)
                    .foregroundStyle(Color.helpText)
            } else {
                CoachingTrendChart(points: points, zone: definition.zone)
                    .frame(height: 96)
                HStack {
                    Text("First swing")
                    Spacer()
                    Text("Last swing")
                }
                .font(.appCaption)
                .foregroundStyle(Color.helpText)
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
