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
    /// Swings in a recap: the setting's window, or the asked-for size.
    private var recapSize: Int { cadence.recapSize ?? CoachingCadence.requestedRecapSize }

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
            // No icon, so it lines up with the options above; the number
            // is the window the current setting recaps.
            Button("Recap last \(recapSize)") {
                recapIDs = measured.suffix(recapSize).map(\.swing.id)
            }
            .disabled(!canRecap)
        } label: {
            HStack(spacing: 6) {
                Text("Coach: \(cadence.title.lowercased())")
                    .font(.appLabel)
                Image(systemName: "chevron.down")
                    .font(.appCaptionLabel)
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
                        .font(.appLabel)
                        .foregroundStyle(PlayerChrome.secondaryText)
                    Text(verdict.headline)
                        .font(.appTitle)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("Look")
                    .font(.appLabel)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white))
            }
            .foregroundStyle(.white)
            .solidPanelBackground()
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
    /// The shared level badge for this swing on the theme: a tick in zone,
    /// the level out of it, a dash not judged. Out the other way is not the
    /// theme, so its badge is only outlined.
    func badge(size: CGFloat) -> CoachingLevelBadge {
        switch self {
        case .notJudged: CoachingLevelBadge(level: 0, neutral: true, size: size)
        case .inZone: CoachingLevelBadge(level: 0, size: size)
        case .shows(let level): CoachingLevelBadge(level: level, size: size)
        case .otherWay(let level): CoachingLevelBadge(level: level, size: size, outlined: true)
        }
    }
}

/// What the last few swings had in common, over the camera, read at a
/// glance from the tripod: a picture of the swing that shows it most, the
/// finding with its typical level as a badge, and Compare. The count, each
/// swing's level, the key and the camera caveat are in the comparison, so
/// the card covers as little of the viewfinder as it can.
struct CoachingRecapCard: View {
    struct Example {
        let swing: SavedSwing
        let report: SwingCoachingReport
        let metric: CoachingMetricID
        let number: Int
        /// How this swing stands on the theme, as its badge shows it.
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
        HStack(alignment: .top, spacing: 12) {
            if recap.theme != nil, let example {
                examplePicture(example)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: severityWord == nil ? .top : .center, spacing: 10) {
                    levelBadge
                        .padding(.top, severityWord == nil ? 1 : 0)
                    VStack(alignment: .leading, spacing: 0) {
                        // How far out it typically is, in one plain word.
                        if let severityWord, let theme = recap.theme {
                            Text(severityWord)
                                .font(.appCaptionLabel)
                                .foregroundStyle(Color.coachingLevelText(theme.medianLevel))
                                .accessibilityIdentifier("coach-recap-severity")
                        }
                        Text(title)
                            .font(.appTitle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    closeButton
                }
                Button(action: onOpen) {
                    HStack(spacing: 6) {
                        Text(recap.theme == nil ? "Look at them" : "Compare")
                            .font(.appLabel)
                        Image(systemName: "chevron.right").font(.appCaptionLabel)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(recap.theme == nil ? "Look at them" : "Compare the last \(numbers.count) swings")
                .accessibilityIdentifier("coach-recap-open")
            }
        }
        // The picture fills the card's height, set by the words beside it.
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.white)
        .solidPanelBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach-recap")
    }

    /// "Typically well out": the theme's typical level as the plain word.
    private var severityWord: String? {
        guard let theme = recap.theme, let word = CoachingWords.severity(theme.medianLevel) else { return nil }
        return "Typically " + word.prefix(1).lowercased() + word.dropFirst()
    }

    private var title: String {
        if let theme = recap.theme { return theme.text }
        return recap.judged == 0 ? "None of these could be judged" : "Nothing kept repeating"
    }

    /// The theme's typical level as the bare badge, in its level's colour:
    /// a number out of zone, a tick when nothing repeated, a dash when
    /// nothing could be judged. VoiceOver says the words.
    private var levelBadge: some View {
        let badge: CoachingLevelBadge
        let words: String
        if let theme = recap.theme {
            badge = CoachingLevelBadge(level: theme.medianLevel, size: CoachingLevelBadge.markSize)
            words = "Typically \(CoachingWords.steps(theme.medianLevel).lowercased())"
        } else if recap.judged == 0 {
            badge = CoachingLevelBadge(level: 0, neutral: true, size: CoachingLevelBadge.markSize)
            words = "Not judged"
        } else {
            badge = CoachingLevelBadge(level: 0, size: CoachingLevelBadge.markSize)
            words = "\(recap.good) of \(recap.judged) needed no pointer"
        }
        return badge
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(words)
            .accessibilityIdentifier("coach-recap-level")
    }

    /// The shared close style: drawn 28 points, 44 to tap, without making
    /// the title row taller.
    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
        }
        .buttonStyle(CloseButtonStyle())
        .accessibilityLabel("Close recap")
        .accessibilityIdentifier("coach-recap-close")
    }

    /// The swing that shows it most, as tall as the card, cut toward the
    /// golfer and club, with that swing's own badge on its corner and its
    /// number under the badge ("Swing 5"), so the badge reads as that
    /// swing's, apart from the theme's typical level beside it, and the
    /// line's colour always matches a badge.
    private func examplePicture(_ example: Example) -> some View {
        CoachingFrameView(swing: example.swing, report: example.report, metric: example.metric, cropsToGolfer: true)
            .frame(width: CoachingPreview.recapPictureWidth)
            .frame(minHeight: CoachingPreview.recapPictureMinHeight, maxHeight: .infinity)
            .clipShape(.rect(cornerRadius: 8))
            .overlay(alignment: .topLeading) {
                if let showing = example.showing {
                    VStack(spacing: 3) {
                        showing.badge(size: 22)
                            .background(Circle().fill(PlayerChrome.solidPanel).padding(-2))
                        Text("Swing \(example.number)")
                            .font(FixedType.cellLabel.monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(PlayerChrome.solidPanel))
                    }
                    .padding(5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Picture of swing \(example.number)"
                + (example.showing.map { ", \($0.label)" } ?? "") + ", which shows it most")
            .accessibilityIdentifier("coach-recap-picture")
    }
}

// MARK: - One check on one swing, as a picture

/// The frame a check was measured on, with its drawing. Reads the frame
/// from the swing's saved clip.
struct CoachingFrameView: View {
    let swing: SavedSwing
    let report: SwingCoachingReport
    let metric: CoachingMetricID
    /// Fill the view and cut toward the golfer and club (everything drawn
    /// on this frame) instead of fitting the whole frame with its sky and
    /// foreground.
    var cropsToGolfer = false

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
            if let frame, cropsToGolfer {
                GeometryReader { geometry in
                    let rect = croppedRect(of: frame.size, in: geometry.size, around: result)
                    Image(uiImage: frame)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    if let result {
                        CoachingDrawingLayer(results: [result], rect: rect, still: true, neutral: report.exclusion != nil)
                    }
                }
                .clipped()
            } else if let frame {
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

    /// Where the frame sits when it fills `size`: centred on everything
    /// drawn on this frame (the golfer's body and the club), kept inside
    /// the frame's own edges.
    private func croppedRect(of image: CGSize, in size: CGSize, around result: CoachingMetricResult?) -> CGRect {
        let scale = max(size.width / max(image.width, 1), size.height / max(image.height, 1))
        let width = image.width * scale, height = image.height * scale
        var xs: [Double] = [], ys: [Double] = []
        if let result {
            for other in report.metrics where abs(other.clipTime - result.clipTime) < 0.02 {
                for shape in other.drawings {
                    let radius = shape.size ?? 0
                    xs += shape.points.map(\.x)
                    ys += shape.points.flatMap { [$0.y - radius, $0.y + radius] }
                }
            }
        }
        let centreX = xs.isEmpty ? 0.5 : (xs.min()! + xs.max()!) / 2
        let centreY = ys.isEmpty ? 0.5 : (ys.min()! + ys.max()!) / 2
        let x = min(0, max(size.width - width, size.width / 2 - CGFloat(centreX) * width))
        let y = min(0, max(size.height - height, size.height / 2 - CGFloat(centreY) * height))
        return CGRect(x: x, y: y, width: width, height: height)
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
                        Text(theme.text).font(.appTitle)
                        // How many showed it, out of the swings judged.
                        Text(CoachingWords.recapShare(theme, judged: judgedCount))
                            .font(.appBody)
                            .accessibilityIdentifier("coach-compare-share")
                        // The drawing's key and, kept off the recap card
                        // over the camera, a club check's caveat: one
                        // caption line.
                        CoachingLegend(results: Array(swings.lazy.compactMap { store.report(for: $0.swing)?.metric(theme.metric) }.prefix(1)),
                                       subjectColours: subjectColours,
                                       cameraCaveat: CoachingMetricDefinition.definition(theme.metric).dependsOnCamera)
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

    /// "short swing" as a line of its own: "Short swing".
    private func sentenceCase(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    /// The swings that were judged: the recap's denominator.
    private var judgedCount: Int {
        swings.filter { store.report(for: $0.swing).map { $0.exclusion == nil } ?? false }.count
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
                        CoachingFrameView(swing: swing, report: report, metric: metric, cropsToGolfer: true)
                    } else {
                        // The same bounds as a picture, on a neutral fill,
                        // so it reads as a swing with nothing to show, not
                        // a picture that failed to load.
                        Color(white: 0.16).overlay {
                            VStack(spacing: 4) {
                                showing.badge(size: 30)
                                    .padding(.bottom, 4)
                                Text(showing.label)
                                    .font(.appLabel)
                                    .foregroundStyle(PlayerChrome.secondaryText)
                                // Why, on its own line.
                                if showing == .notJudged {
                                    Text(sentenceCase(CoachingWords.reason(notJudged: report)))
                                        .font(.appCaption)
                                        .foregroundStyle(PlayerChrome.secondaryText)
                                }
                            }
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.14), lineWidth: 1))
                    }
                }
                // One capped height for every tile, cut toward the golfer
                // and club, so more swings fit on the first view.
                .aspectRatio(CoachingPreview.compareAspect, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 12))
                HStack(spacing: 6) {
                    // The same badge as the swing's picture on the recap.
                    showing.badge(size: 20)
                    Text("Swing \(number)").font(.appLabel)
                        .fixedSize()
                    Spacer(minLength: 0)
                    // A swing that isn't judged says why inside its tile;
                    // its footer is just the swing, never a repeat.
                    if showing != .notJudged {
                        Text(showing.label)
                            .font(.appCaption)
                            .foregroundStyle(Color.helpText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
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
