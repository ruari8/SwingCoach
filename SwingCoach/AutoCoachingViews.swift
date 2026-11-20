//
//  AutoCoachingViews.swift
//  SwingCoach
//
//  Coaching on the Auto camera screen: the chip that sets how often the
//  coach speaks, the latest swing's verdict, the recap of the last few
//  swings, and the side-by-side comparison the recap opens.
//

import AVFoundation
import SwiftUI

/// What the Auto review cover opens on.
struct AutoSwingReviewPresentation: Identifiable {
    let id = UUID()
    /// The swing to start on; the newest when nil.
    var startAt: UUID?
    /// The recap's swings side by side first, before the player.
    var compare: CoachingComparison?
}

/// A recap's swings and the theme they are compared on.
struct CoachingComparison: Equatable {
    let swingIDs: [UUID]
    let theme: CoachingTheme
}

// MARK: - On the camera screen

/// Sits between the camera's top bar and its bottom row in Auto.
struct AutoCoachingPanel: View {
    /// The Auto session's swings, oldest first.
    let swings: [SavedSwing]
    let open: (AutoSwingReviewPresentation) -> Void

    /// Which swings have been recapped, and the recap on screen. Kept by
    /// the camera screen, so they outlive this panel when the camera
    /// leaves Auto and comes back.
    @Binding var schedule: CoachingRecapSchedule
    @Binding var recapIDs: [UUID]?

    @ObservedObject private var store = SwingCoachingStore.shared
    @AppStorage(CoachingCadence.key) private var cadenceName = CoachingCadence.standard.rawValue

    private var cadence: CoachingCadence { CoachingCadence(rawValue: cadenceName) ?? .standard }

    private var measured: [(swing: SavedSwing, report: SwingCoachingReport)] {
        swings.compactMap { swing in store.report(for: swing).map { (swing, $0) } }
    }

    var body: some View {
        let measured = measured
        VStack(spacing: 0) {
            chip(canRecap: !measured.isEmpty)
                .padding(.top, 10)
            Spacer(minLength: 16)
            if let recapIDs {
                recapCard(for: measured.filter { recapIDs.contains($0.swing.id) })
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if cadence == .everySwing, let latest = swings.last, let report = store.report(for: latest) {
                latestVerdict(store.verdict(for: latest, report: report), swing: latest)
                    .padding(.bottom, 10)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: recapIDs)
        .onAppear { update(measured.map(\.swing.id)) }
        .onChange(of: measured.map(\.swing.id)) { _, ids in update(ids) }
        .onChange(of: cadenceName) { _, _ in
            schedule.cadenceChanged(measured: measured.map(\.swing.id))
        }
    }

    /// Shows a recap when a new one comes due. `ids` are the measured
    /// swings, oldest first.
    private func update(_ ids: [UUID]) {
        if let shown = recapIDs, !shown.allSatisfy(ids.contains) { recapIDs = nil }
        if let due = schedule.update(measured: ids, cadence: cadence) {
            recapIDs = due
        }
    }

    private func chip(canRecap: Bool) -> some View {
        Menu {
            Picker("Coach speaks", selection: $cadenceName) {
                ForEach(CoachingCadence.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Button("Recap the last swings", systemImage: "list.bullet.rectangle") {
                let size = cadence.recapSize ?? CoachingCadence.requestedRecapSize
                recapIDs = measured.suffix(size).map(\.swing.id)
            }
            .disabled(!canRecap)
        } label: {
            HStack(spacing: 6) {
                Text("Coach: \(cadence.title.lowercased())")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Capsule().fill(.black.opacity(0.45)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
        }
        .accessibilityIdentifier("coach-cadence")
        .accessibilityLabel("Coach speaks: \(cadence.title)")
    }

    /// The last swing's verdict, big enough to read from the tee. Opens
    /// the swing on the coach's first step.
    private func latestVerdict(_ verdict: CoachingVerdict, swing: SavedSwing) -> some View {
        let number = (swings.firstIndex { $0.id == swing.id } ?? 0) + 1
        return Button {
            open(AutoSwingReviewPresentation(startAt: swing.id))
        } label: {
            HStack(spacing: 12) {
                CoachingLevelBadge(level: verdictLevel(verdict), neutral: isNotJudged(verdict), size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Swing \(number)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Text(verdict.headline)
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("Look")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white))
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.07).opacity(0.88)))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coach-latest-verdict")
        .accessibilityLabel("Last swing: \(verdict.headline)")
        .accessibilityHint("Opens the swing on the coach's drawing")
    }

    private func verdictLevel(_ verdict: CoachingVerdict) -> Int {
        if case .focus(let finding) = verdict { return finding.level }
        return 0
    }

    private func isNotJudged(_ verdict: CoachingVerdict) -> Bool {
        if case .notJudged = verdict { return true }
        return false
    }

    private func recapCard(for group: [(swing: SavedSwing, report: SwingCoachingReport)]) -> some View {
        let recap = CoachingFeedback.recap(of: group.map(\.report))
        let numbers = group.map { entry in (swings.firstIndex { $0.id == entry.swing.id } ?? 0) + 1 }
        // The swing that shows the theme most, at the theme's check.
        var example: CoachingRecapCard.Example?
        if let theme = recap.theme, let most = CoachingFeedback.examples(of: theme, in: group.map(\.report)).most,
           let metric = CoachingFeedback.metric(showing: theme, in: group[most].report) {
            example = .init(swing: group[most].swing, report: group[most].report, metric: metric, number: numbers[most],
                            showing: recap.swings.indices.contains(most) ? recap.swings[most] : nil)
        }
        return CoachingRecapCard(recap: recap, numbers: numbers, example: example) {
            if let theme = recap.theme {
                open(AutoSwingReviewPresentation(compare: CoachingComparison(swingIDs: group.map(\.swing.id), theme: theme)))
            } else {
                open(AutoSwingReviewPresentation(startAt: group.first?.swing.id))
            }
        } onClose: {
            recapIDs = nil
        }
    }
}

extension CoachingThemeShowing {
    var colour: Color {
        switch self {
        case .notJudged: .gray.opacity(0.6)
        case .inZone: .coachingLevel(0)
        case .shows(let level), .otherWay(let level): .coachingLevel(level)
        }
    }

    /// Solid, except out the other way: that is not the theme, so it is
    /// only outlined.
    var fill: Color {
        if case .otherWay = self { return .clear }
        return colour
    }

    /// The shared level badge for this swing on the theme: a tick in zone,
    /// the level out of it, a dash not judged.
    func badge(size: CGFloat) -> CoachingLevelBadge {
        switch self {
        case .notJudged: CoachingLevelBadge(level: 0, neutral: true, size: size)
        case .inZone: CoachingLevelBadge(level: 0, size: size)
        case .shows(let level), .otherWay(let level): CoachingLevelBadge(level: level, size: size)
        }
    }
}

/// What the last few swings had in common, over the camera.
struct CoachingRecapCard: View {
    struct Example {
        let swing: SavedSwing
        let report: SwingCoachingReport
        let metric: CoachingMetricID
        let number: Int
        /// How this swing stands on the theme, as its bar shows it.
        var showing: CoachingThemeShowing?
    }

    let recap: CoachingRecap
    /// The swings' numbers in the session, oldest first.
    let numbers: [Int]
    /// A picture of the theme on the swing that shows it most.
    var example: Example?
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(numbers.count == 1 ? "Last swing" : "Last \(numbers.count) swings")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close recap")
                .accessibilityIdentifier("coach-recap-close")
            }
            if let theme = recap.theme {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            CoachingLevelBadge(level: theme.medianLevel, size: 22)
                            Text(theme.text)
                                .font(.title3.weight(.bold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(CoachingWords.themeShare(theme))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                        if CoachingMetricDefinition.definition(theme.metric).dependsOnCamera {
                            Text("A club reading: it depends on where the camera stands.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    if let example {
                        VStack(spacing: 3) {
                            CoachingFrameView(swing: example.swing, report: example.report, metric: example.metric)
                                .frame(width: 62, height: 110)
                                .clipShape(.rect(cornerRadius: 8))
                            HStack(spacing: 4) {
                                // The same look as this swing's bar below.
                                if let showing = example.showing {
                                    RecapBar(showing: showing).frame(width: 12)
                                }
                                Text("Swing \(example.number)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.78))
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Picture of swing \(example.number), which shows it most")
                        .accessibilityIdentifier("coach-recap-picture")
                    }
                }
                levelBars
                barLegend
            } else {
                Text(recap.judged == 0 ? "None of these could be judged" : "Nothing kept repeating")
                    .font(.title3.weight(.bold))
                Text(recap.judged == 0
                     ? "Chips, a moved camera or unclear positions are measured but not judged."
                     : "\(recap.good) of \(recap.judged) needed no pointer. Carry on.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    Text(recap.theme == nil ? "Look at them" : "Compare them")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coach-recap-open")
        }
        .padding(16)
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 22).fill(.black.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach-recap")
    }

    /// What the slots mean, said once under them: the number is steps out
    /// of zone, with the tick, the dash and an outlined bar keyed only
    /// when a slot has one. The bar's colour repeats the level; the badge
    /// says it by number and shape.
    private var barLegend: some View {
        let showings = recap.swings
        let hasNumber = showings.contains { if case .shows = $0 { true } else if case .otherWay = $0 { true } else { false } }
        let hasTick = showings.contains(.inZone)
        let hasDash = showings.contains(.notJudged)
        let otherWay = showings.first { if case .otherWay = $0 { true } else { false } }
        var spoken: [String] = []
        if hasNumber { spoken.append("a number is steps out of zone") }
        if hasTick { spoken.append("a tick is in zone") }
        if hasDash { spoken.append("a dash is not judged") }
        if otherWay != nil { spoken.append("an outlined bar is out the other way") }
        return FlowLayout(spacing: 12, lineSpacing: 4) {
            if hasNumber {
                HStack(spacing: 4) {
                    CoachingLevelBadge(level: 2, size: 16)
                    Text("Number = steps out of zone")
                }
            }
            if hasTick {
                HStack(spacing: 4) {
                    CoachingLevelBadge(level: 0, size: 16)
                    Text("In zone")
                }
            }
            if hasDash {
                HStack(spacing: 4) {
                    CoachingLevelBadge(level: 0, neutral: true, size: 16)
                    Text("Not judged")
                }
            }
            if let otherWay {
                HStack(spacing: 4) {
                    RecapBar(showing: otherWay).frame(width: 16)
                    Text("Other way")
                }
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.78))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Key: " + spoken.joined(separator: ", "))
        .accessibilityIdentifier("coach-recap-key")
    }

    /// One slot per swing: a bar, green where the theme's check was in
    /// zone, amber or red by how far out it was, an outline where it was
    /// out the other way, grey where the swing couldn't be judged; under it
    /// the level badge, so the shape and number say it as well as the
    /// colour, and the swing's number.
    private var levelBars: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(zip(numbers, recap.swings).enumerated()), id: \.offset) { _, entry in
                VStack(spacing: 5) {
                    RecapBar(showing: entry.1)
                    entry.1.badge(size: CoachingLevelBadge.markSize)
                    Text("Swing \(entry.0)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Swing \(entry.0): \(entry.1.label)")
            }
        }
        .padding(.top, 2)
    }
}

/// One swing's bar on the recap, also its key in the legend and its mark
/// on the thumbnail and in the comparison: solid in its level's colour,
/// outlined when out the other way, grey when not judged.
struct RecapBar: View {
    let showing: CoachingThemeShowing

    var body: some View {
        Capsule()
            .fill(showing.fill)
            .overlay(Capsule().strokeBorder(showing.colour, lineWidth: 1.5))
            .frame(height: 6)
            .accessibilityHidden(true)
    }
}

// MARK: - One check on one swing, as a picture

/// The frame a check was measured on, with its drawing. Reads the frame
/// from the swing's saved clip.
struct CoachingFrameView: View {
    let swing: SavedSwing
    let report: SwingCoachingReport
    let metric: CoachingMetricID

    /// The last frame read, and what it was read for. A frame read for
    /// another time is never shown under this reading's drawing.
    @State private var loaded: (request: String, frame: UIImage?)?

    var body: some View {
        let result = report.metric(metric)
        let request = "\(swing.id.uuidString)-\(metric.rawValue)-\(result?.clipTime ?? -1)"
        let current = loaded?.request == request ? loaded : nil
        let frame = current?.frame
        ZStack {
            Color.black
            if let frame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFit()
                if let result {
                    GeometryReader { geometry in
                        let rect = VideoDisplayGeometry.contentRect(
                            in: geometry.size, aspectRatio: Double(frame.size.width / max(frame.size.height, 1)))
                        CoachingDrawingLayer(results: [result], rect: rect, still: true, neutral: report.exclusion != nil)
                    }
                }
            } else if current != nil {
                Image(systemName: "video.slash")
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ProgressView().tint(.white)
            }
        }
        // The clip's reading can replace a first reading while this is
        // on screen and move the check to another frame.
        .task(id: request) {
            let image = await Self.frame(of: swing, at: result?.clipTime)
            guard !Task.isCancelled else { return }
            loaded = (request, image)
        }
    }

    private static func frame(of swing: SavedSwing, at clipTime: Double?) async -> UIImage? {
        guard let clipTime, let url = SwingLibrary.shared.localVideoURL(for: swing) else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try? await generator.image(at: CMTime(seconds: clipTime, preferredTimescale: 600)).image
        return image.map(UIImage.init(cgImage:))
    }
}

// MARK: - Comparison

/// A recap's swings side by side at the theme's position, each with the
/// theme's drawing. Tapping one opens it in the player.
struct CoachingCompareView: View {
    /// The swings with their numbers in the session, oldest first.
    let swings: [(number: Int, swing: SavedSwing)]
    let theme: CoachingTheme
    let onOpen: (SavedSwing) -> Void
    let onClose: () -> Void

    @ObservedObject private var store = SwingCoachingStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(theme.text).font(.title3.weight(.bold))
                        Text("\(SwingPosition.title(theme.position)) on each swing. Tap one to walk through it.")
                            .font(.footnote)
                            .foregroundStyle(Color.helpText)
                        CoachingLegend(results: Array(swings.lazy.compactMap { store.report(for: $0.swing)?.metric(theme.metric) }.prefix(1)),
                                       subjectColours: subjectColours)
                            .padding(.top, 4)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 14) {
                        ForEach(swings, id: \.swing.id) { entry in
                            tile(entry.number, entry.swing)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Last \(swings.count) swings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.appAccent)
        .accessibilityIdentifier("coach-compare")
    }

    /// The colours the tiles draw their swing in, so the legend's "This
    /// swing" shows each of them, not only the first swing's.
    private var subjectColours: [Color] {
        var colours: [Color] = []
        for entry in swings {
            guard let report = store.report(for: entry.swing),
                  let metric = CoachingFeedback.metric(showing: theme, in: report),
                  let result = report.metric(metric) else { continue }
            let colour = report.exclusion != nil ? CoachingDrawingLayer.neutralColour : .coachingLevel(result.level)
            if !colours.contains(colour) { colours.append(colour) }
        }
        return colours
    }

    @ViewBuilder
    private func tile(_ number: Int, _ swing: SavedSwing) -> some View {
        let report = store.report(for: swing)
        // The label is about the check in the picture.
        let showing = report.map { CoachingFeedback.showing(of: theme, drawnIn: $0) } ?? .notJudged
        let metric = report.flatMap { CoachingFeedback.metric(showing: theme, in: $0) }
        Button {
            onOpen(swing)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let report, let metric {
                        CoachingFrameView(swing: swing, report: report, metric: metric)
                    } else {
                        // The same bounds as a picture, on a neutral fill,
                        // so it reads as a swing with nothing to show, not
                        // a picture that failed to load.
                        Color(white: 0.16).overlay {
                            VStack(spacing: 8) {
                                showing.badge(size: 30)
                                Text(showing.label)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.14), lineWidth: 1))
                    }
                }
                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 12))
                HStack(spacing: 6) {
                    // The same look as the swing's bar on the recap.
                    RecapBar(showing: showing).frame(width: 14)
                    Text("Swing \(number)").font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(showing.label)
                        .font(.caption)
                        .foregroundStyle(Color.helpText)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coach-compare-swing-\(number)")
    }
}

/// The Auto review cover: the recap's comparison first when it was asked
/// for, then the player.
struct AutoReviewCover: View {
    let presentation: AutoSwingReviewPresentation
    let swings: [SavedSwing]
    let onDelete: @MainActor (SavedSwing) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var comparing: Bool
    @State private var startAt: UUID?
    /// The theme's check on the swing opened from the comparison.
    @State private var focus: CoachingMetricID?
    @ObservedObject private var store = SwingCoachingStore.shared

    init(presentation: AutoSwingReviewPresentation, swings: [SavedSwing],
         onDelete: @escaping @MainActor (SavedSwing) async throws -> Void) {
        self.presentation = presentation
        self.swings = swings
        self.onDelete = onDelete
        _comparing = State(initialValue: presentation.compare != nil)
        _startAt = State(initialValue: presentation.startAt)
    }

    var body: some View {
        if comparing, let compare = presentation.compare {
            CoachingCompareView(
                swings: swings.enumerated()
                    .filter { compare.swingIDs.contains($0.element.id) }
                    .map { (number: $0.offset + 1, swing: $0.element) },
                theme: compare.theme,
                onOpen: { swing in
                    startAt = swing.id
                    focus = store.report(for: swing).flatMap { CoachingFeedback.metric(showing: compare.theme, in: $0) }
                    comparing = false
                },
                onClose: { dismiss() }
            )
        } else if presentation.compare != nil {
            // Opened from the comparison: it opens on the picture tapped,
            // and Back returns to the comparison.
            AutoSwingReviewView(swings: swings, startAt: startAt, focus: focus, leadingTitle: "Back",
                                onLeading: { comparing = true }, onDelete: onDelete)
        } else {
            AutoSwingReviewView(swings: swings, startAt: startAt, onDelete: onDelete)
        }
    }
}
