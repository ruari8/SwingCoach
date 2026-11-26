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
        let tempoTrend = SwingTempoTrend.build(from: zip(coachable, coached).map { swing, report in
            (id: swing.id, tempo: swing.tempo, excluded: report?.exclusion != nil)
        })

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
                                // "!" amber or "!!" red, a dash.
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
                            Text("Listed in swing order. Work on the earliest first.")
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
                if !tempoTrend.samples.isEmpty {
                    Section {
                        tempoTrendCard(tempoTrend)
                    } header: {
                        SectionHeading("Tempo")
                    } footer: {
                        Text("First club movement after P1 to top (P4, ±33 ms), then top to impact (P7). Dashed line is 3:1.")
                            .foregroundStyle(Color.helpText)
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
    /// swings good", out of the swings judged (the caption under the
    /// marks says why any weren't), the swings the coach had nothing to
    /// say about. Not larger, so "Start here" and its pictures come into
    /// view.
    private func headline(good: Int, judged: Int) -> some View {
        // Proportional digits: a headline number, never a column, so "11"
        // never reads as "1 1".
        Text("\(good) of \(judged) swing\(judged == 1 ? "" : "s") good")
            .font(.appTitle)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("session-coaching-headline")
    }


    /// Between the summary's headline, marks and counts: tight, so the
    /// summary stays short and the first theme starts higher.
    private static let summaryGap: CGFloat = 6
    /// A swing's mark as laid out: the minimum target wide, shorter than
    /// that, with its target grown to the minimum tall, so rows of marks
    /// sit closer.
    private static let dotWidth: CGFloat = HitArea.minimum
    private static let dotHeight: CGFloat = 32

    /// "1 not judged", and why when every one of them shares the reason:
    /// "1 not judged · short swing".
    private func notJudgedTotal(_ reports: [SwingCoachingReport]) -> String {
        let exclusions = reports.compactMap(\.exclusion)
        let count = "\(exclusions.count) not judged"
        guard let reason = exclusions.first, exclusions.allSatisfy({ $0 == reason }) else { return count }
        return "\(count) · \(CoachingWords.reason(reason))"
    }

    /// One mark for each swing, each a 44 point target, wrapping in the
    /// order hit: a tick for a good swing, the top finding's level as a
    /// glyph in its colour ("!" amber a little out, "!!" red well out), a
    /// dash for a swing that isn't judged. A glyph, never a numeral, so a
    /// swing's mark never disagrees with a theme's word below.
    private func swingDots(_ measured: [SavedSwing], _ verdicts: [CoachingVerdict]) -> some View {
        FlowLayout(spacing: 0, lineSpacing: 0) {
            ForEach(Array(zip(measured, verdicts).enumerated()), id: \.element.0.id) { index, entry in
                Button {
                    opened = entry.0.id
                } label: {
                    badge(entry.1)
                        .frame(width: Self.dotWidth, height: Self.dotHeight)
                        .contentShape(.rect.inset(by: -(HitArea.minimum - Self.dotHeight) / 2))
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
        case .focus(let finding): CoachingLevelBadge(level: finding.level, size: CoachingLevelBadge.markSize)
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
                // One caption: how many of the measured swings, and which
                // check. A club check's camera caveat is in All checks,
                // with its words.
                Text(CoachingWords.themeShare(theme))
                    .font(.appCaption)
                    .foregroundStyle(Color.helpText)
            }
        }
    }

    /// The lead theme on the swing that shows it most and on the best one
    /// that doesn't, both cut to the same golfer-centred region (body,
    /// club and ball, from everything drawn on either swing) in the same
    /// 4:5 shape, so the drawing is large and the two compare like for
    /// like.
    @ViewBuilder
    private func examples(of theme: CoachingTheme, _ measured: [SavedSwing], _ reports: [SwingCoachingReport]) -> some View {
        let picked = CoachingFeedback.examples(of: theme, in: reports)
        let shown = [picked.most, picked.best].compactMap { $0 }.map { reports[$0] }
        let region = CoachingFrameView.golferRegion(shown, pictured: shown.compactMap { report in
            CoachingFeedback.metric(showing: theme, in: report).flatMap(report.metric)
        })
        if picked.most != nil || picked.best != nil {
            HStack(alignment: .top, spacing: 10) {
                if let most = picked.most {
                    example("Shows it most", most, theme, measured, reports, region: region)
                }
                if let best = picked.best {
                    example("Your best here", best, theme, measured, reports, region: region)
                }
            }
        }
    }

    @ViewBuilder
    private func example(_ title: String, _ index: Int, _ theme: CoachingTheme,
                         _ measured: [SavedSwing], _ reports: [SwingCoachingReport], region: CGRect?) -> some View {
        let report = reports[index]
        if let metric = CoachingFeedback.metric(showing: theme, in: report), let result = report.metric(metric) {
            Button {
                opened = measured[index].id
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    // What the picture is, above it, so it is read first.
                    Text(title).font(.appCaptionLabel)
                    CoachingFrameView(swing: measured[index], report: report, metric: metric,
                                      cropsToGolfer: true, region: region)
                        .aspectRatio(CoachingPreview.golferAspect, contentMode: .fit)
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
                Text("Good: \(CoachingWords.zone(definition))")
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

    /// Session tempo summary and swing-by-swing ratio chart.
    private func tempoTrendCard(_ trend: SwingTempoTrend) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    if let ratio = trend.medianRatioText {
                        Text(ratio)
                            .font(.appTitle.monospacedDigit())
                    }
                    Text(trend.direction.map { "Median ratio · \($0.label)" } ?? "Median ratio")
                        .font(.appCaption)
                        .foregroundStyle(Color.helpText)
                }
                Spacer(minLength: 8)
                if let times = trend.medianTimesText {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(times)
                            .font(.appBody.monospacedDigit())
                            .foregroundStyle(Color.helpText)
                        Text("Median times")
                            .font(.appCaption)
                            .foregroundStyle(Color.helpText)
                    }
                }
            }
            if trend.samples.count < SwingTempoTrend.minimumTrendSamples {
                Text("Too few swings to show a trend.")
                    .font(.appCaption)
                    .foregroundStyle(Color.helpText)
            } else {
                SwingTempoTrendChart(trend: trend)
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
        .accessibilityLabel(tempoTrendAccessibilityLabel(trend))
        .accessibilityIdentifier("session-tempo-trend")
    }

    private func tempoTrendAccessibilityLabel(_ trend: SwingTempoTrend) -> String {
        guard let ratio = trend.medianRatioText,
              let back = trend.medianBackswingMS,
              let down = trend.medianDownswingMS
        else { return "Session tempo" }
        let directionText = trend.direction.map { ", \($0.label.lowercased())" } ?? ""
        return "Tempo median \(ratio), backswing \(back) milliseconds, downswing \(down) milliseconds, "
            + "across \(trend.samples.count) swing\(trend.samples.count == 1 ? "" : "s")\(directionText)"
    }
}

/// Swing-by-swing tempo ratio across a session, over a neutral dashed 3:1
/// reference line labelled in the trailing gutter.
struct SwingTempoTrendChart: View {
    let trend: SwingTempoTrend

    var body: some View {
        Canvas { context, size in
            let ratios = trend.samples.map(\.tempo.ratio)
            let values = ratios + [SwingTempo.referenceRatio]
            let low = values.min() ?? 2.0
            let high = values.max() ?? 3.5
            let span = max(high - low, 0.8)
            let margin = max(span * 0.16, 0.2)
            let bottom = low - margin
            let top = high + margin

            func y(_ value: Double) -> CGFloat {
                size.height * CGFloat(1 - (value - bottom) / (top - bottom))
            }

            let word = context.resolve(Text("3:1").font(.appCaptionLabel.monospacedDigit()).foregroundColor(Color.helpText))
            let wordSize = word.measure(in: size)
            let plotWidth = max(size.width - wordSize.width - 10, 1)

            func x(_ swingNumber: Int) -> CGFloat {
                let inset: CGFloat = 6
                guard trend.totalSwings > 1 else { return plotWidth / 2 }
                return inset + (plotWidth - 2 * inset) * CGFloat(swingNumber - 1) / CGFloat(trend.totalSwings - 1)
            }

            let refY = y(SwingTempo.referenceRatio)
            var guide = Path()
            guide.move(to: CGPoint(x: 0, y: refY))
            guide.addLine(to: CGPoint(x: plotWidth, y: refY))
            context.stroke(guide, with: .color(Color.helpText.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            let wordY = min(max(refY, wordSize.height / 2), size.height - wordSize.height / 2)
            context.draw(word, at: CGPoint(x: size.width - 4, y: wordY), anchor: .trailing)

            let centres = trend.samples.map { CGPoint(x: x($0.swingNumber), y: y($0.tempo.ratio)) }
            if centres.count >= 2 {
                var line = Path()
                line.move(to: centres[0])
                for point in centres.dropFirst() { line.addLine(to: point) }
                context.stroke(line, with: .color(Color.appAccent.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            for centre in centres {
                let dot = Path(ellipseIn: CGRect(x: centre.x - 3.5, y: centre.y - 3.5, width: 7, height: 7))
                context.fill(dot, with: .color(Color.appAccent))
            }
        }
    }
}

/// One metric across a session: a dot a swing, left to right in the order
/// hit, over its good zone as a green band, named "Good" in words on the
/// band's own side of the chart so the better place reads without a key.
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
            // The better place in words: "Good" in a gutter of its own at
            // the trailing edge, level with the band, so no dot covers it.
            let word = context.resolve(Text("Good").font(.appCaptionLabel).foregroundColor(Color.coachingLevelText(0)))
            let wordSize = word.measure(in: size)
            let plotWidth = max(size.width - wordSize.width - 10, 1)
            func x(_ point: Point) -> CGFloat {
                let inset: CGFloat = 6
                guard point.of > 1 else { return plotWidth / 2 }
                return inset + (plotWidth - 2 * inset) * CGFloat(point.swing - 1) / CGFloat(point.of - 1)
            }
            let band = CGRect(x: 0, y: y(zone.upperBound), width: size.width, height: y(zone.lowerBound) - y(zone.upperBound))
            context.fill(Path(roundedRect: band, cornerRadius: 3), with: .color(Color.coachingLevel(0).opacity(0.2)))
            let wordY = min(max(band.midY, wordSize.height / 2), size.height - wordSize.height / 2)
            context.draw(word, at: CGPoint(x: size.width - 4, y: wordY), anchor: .trailing)
            for point in points {
                let centre = CGPoint(x: x(point), y: y(point.value))
                let dot = Path(ellipseIn: CGRect(x: centre.x - 3.5, y: centre.y - 3.5, width: 7, height: 7))
                context.fill(dot, with: .color(Color.coachingLevel(point.level)))
            }
        }
        .accessibilityLabel("\(points.filter { $0.level == 0 }.count) of \(points.count) swings in the good zone")
    }
}
