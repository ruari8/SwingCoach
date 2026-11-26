//
//  SwingDetailView.swift
//  SwingCoach
//
//  A swing-first workspace for playback, metadata, drawing and coaching.
//

import SwiftUI
import AVFoundation

struct SwingDetailView: View {
    let swing: SavedSwing

    @Environment(\.dismiss) private var dismiss
    @StateObject private var library = SwingLibrary.shared
    @StateObject private var positionProcessor = SwingPositionProcessor.shared

    @State private var currentSwingID: UUID
    @State private var reviewSwingIDs: [UUID]
    @State private var playerItems: [UUID: AVPlayerItem] = [:]
    @State private var videoAspectRatios: [UUID: Double] = [:]
    @State private var loadingSwingIDs: Set<UUID> = []
    @State private var playbackErrors: [UUID: String] = [:]
    @State private var showMetadata = false
    @State private var isDrawingLines = false
    @State private var controlsLocked = false
    @State private var draftLine: ManualAnnotation?
    @State private var coachingSeek: Double?
    @State private var highlightedMetric: CoachingMetricID?
    @State private var coachInteracted = false
    @State private var coachingLayers = CoachingLayers.coachsChoice
    @State private var showsCoachingLayers = false
    @State private var showsCoachingChecks = false
    @ObservedObject private var coachingStore = SwingCoachingStore.shared

    init(swing: SavedSwing, reviewSwings: [SavedSwing]? = nil) {
        self.swing = swing
        _currentSwingID = State(initialValue: swing.id)
        // Freeze the visible collection on entry: starring a video while
        // reviewing it updates the grid without moving the page mid-gesture.
        _reviewSwingIDs = State(initialValue: (reviewSwings ?? [swing]).map(\.id))
    }

    private var currentSwing: SavedSwing {
        library.swings.first { $0.id == currentSwingID } ?? swing
    }

    private var navigationSwings: [SavedSwing] {
        reviewSwingIDs.compactMap { id in
            library.swings.first { $0.id == id }
        }
    }

    private var swingPositionText: String? {
        ReviewTopBar.counter(for: currentSwing.id, in: navigationSwings, id: \.id, date: \.createdAt)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            reviewPager

            if isDrawingLines, videoAspectRatios[currentSwingID] != nil {
                drawingToolBar
            }

            if !isDrawingLines, !coachingLayers.isCoachsChoice {
                CoachingLayersChangedTag(layers: $coachingLayers)
                    .underReviewTopBar()
            }
        }
        .swingCoachingOpening(swing: currentSwing, isActive: true, seek: $coachingSeek,
                              interacted: $coachInteracted, highlighted: $highlightedMetric)
        .sheet(isPresented: $showsCoachingLayers) {
            CoachingLayersSheet(layers: $coachingLayers, hasTrail: coachingStore.clubTrail(for: currentSwing) != nil)
        }
        .sheet(isPresented: $showsCoachingChecks) {
            if let report = coachingStore.report(for: currentSwing) {
                SwingCoachingChecks(swing: currentSwing, report: report,
                                    verdict: coachingStore.verdict(for: currentSwing, report: report)) { result in
                    coachInteracted = true
                    highlightedMetric = result.id
                    coachingSeek = result.clipTime
                    showsCoachingChecks = false
                }
                .presentationDetents([.fraction(0.62), .large])
            }
        }
        .overlayPreferenceValue(ReviewPlaybackCornerControlsKey.self) { cornerControls in
            topNavOverlay(cornerControls: cornerControls)
        }
        .playerSheetDimming()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showMetadata) {
            SwingInfoView(swing: currentSwing)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            preparePlaybackWindow()
            positionProcessor.findPositionsIfNeeded(for: currentSwing)
            Task {
                await library.loadThumbnails()
            }
        }
        .onChange(of: currentSwingID) { _, _ in
            resetReviewState()
            preparePlaybackWindow()
            positionProcessor.findPositionsIfNeeded(for: currentSwing)
        }
    }

    private var reviewPager: some View {
        SwingReviewPager(
            swings: navigationSwings,
            selection: Binding(
                get: { currentSwingID },
                set: { if let id = $0 { currentSwingID = id } }
            ),
            pagingEnabled: !isDrawingLines,
            title: { $0.title ?? "Swing video" }
        ) { pageSwing in
            originalVideoPage(for: pageSwing)
        }
    }

    private var reviewWindow: [SavedSwing] {
        guard let currentIndex = navigationSwings.firstIndex(where: { $0.id == currentSwingID }) else { return [] }
        let lowerBound = max(navigationSwings.startIndex, currentIndex - 1)
        let upperBound = min(navigationSwings.index(before: navigationSwings.endIndex), currentIndex + 1)
        return Array(navigationSwings[lowerBound...upperBound])
    }

    private func originalVideoPage(for swing: SavedSwing) -> some View {
        originalPlayer(for: swing)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func topNavOverlay(cornerControls: AnyView?) -> some View {
        VStack(spacing: 10) {
            ReviewTopBar(
                leadingTitle: "Done",
                leadingAccessibilityLabel: "Back to library",
                onLeading: { dismiss() },
                counter: swingPositionText,
                counterValue: currentSwing.title ?? "",
                isStarred: currentSwing.isFavorite,
                onStar: { library.toggleFavorite(currentSwing) }
            )
            .padding(.horizontal, 14)

            Spacer(minLength: 0)
        }
        .padding(.top, ReviewTopBar.topPadding)
        // The player's tool rail starts one gap under the star, or under
        // Done when docked left, without moving the top row.
        .overlay {
            // Centred under the star, which is wider than a rail button.
            cornerControls
                .padding(.horizontal, ReviewTopBar.railInset)
                .padding(.top, ReviewTopBar.topPadding)
        }
    }

    private func originalPlayer(for swing: SavedSwing) -> some View {
        let drawingEnabled = isDrawingLines && swing.id == currentSwingID

        return Group {
        if let playerItem = playerItems[swing.id] {
            PlaybackChromeView(
                playerItem: playerItem,
                playbackEnabled: swing.id == currentSwingID,
                showsSpeedControls: true,
                startsPlaying: false,
                allowsFullscreen: false,
                allowsTransportGestures: !drawingEnabled,
                contentOverlayAllowsHitTesting: drawingEnabled,
                edgeToEdge: true,
                controlsLocked: $controlsLocked,
                infoAction: { showMetadata = true },
                realTimeRate: swing.realTimePlaybackRate,
                swingPositions: swing.swingPositions,
                drawing: videoAspectRatios[swing.id] != nil ? $isDrawingLines : nil,
                seekRequest: swing.id == currentSwingID ? $coachingSeek : nil,
                positionMarks: coachingStore.stripMarks(for: swing),
                extraTools: SwingCoachingStore.canCoach(swing) ? [.coachingDrawings(changed: !coachingLayers.isCoachsChoice) {
                    showsCoachingLayers = true
                }] : [],
                walkthroughStops: coachingStore.walkthroughStops(
                    for: swing, highlighted: swing.id == currentSwingID ? highlightedMetric : nil),
                bottomPanel: SwingCoachingStore.canCoach(swing) ? { context in
                    AnyView(SwingCoachingPanel(
                        swing: swing, context: context, highlighted: $highlightedMetric,
                        onShowChecks: { showsCoachingChecks = true },
                        onInteract: { coachInteracted = true }
                    ))
                } : nil,
                stopFocus: { time in coachingStore.focusRange(for: swing, at: time, highlighted: swing.id == currentSwingID ? highlightedMetric : nil) },
                contentOverlay: { currentTime in
                    AnyView(
                        ZStack {
                            SwingCoachingOverlay(
                                report: coachingStore.report(for: swing),
                                steps: coachingStore.steps(for: swing),
                                trail: coachingStore.clubTrail(for: swing),
                                layers: coachingLayers,
                                aspectRatio: videoAspectRatios[swing.id],
                                currentTime: currentTime,
                                highlighted: swing.id == currentSwingID ? highlightedMetric : nil
                            )
                            SwingLineOverlay(
                                swing: swing,
                                aspectRatio: videoAspectRatios[swing.id],
                                currentTime: currentTime,
                                isDrawing: drawingEnabled,
                                draft: $draftLine
                            )
                        }
                    )
                }
            ) {
                EmptyView()
            }
            .environment(\.reviewCornerControlsInNavigation, true)
        } else {
            ZStack {
                Color.black

                if let thumbnail = swing.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(Color.black.opacity(0.18))
                }

                if let playbackError = playbackErrors[swing.id] {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(playbackError)
                            .font(.appCaption)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        Text(loadingSwingIDs.contains(swing.id) ? "Loading swing..." : "Preparing playback...")
                            .font(.appCaption)
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
            }
        }
        }
    }

    /// Under the navigation row, where the coaching pill sits otherwise.
    private var drawingToolBar: some View {
        SwingLineControls(
            annotationID: currentSwing.manualAnnotationID,
            isDrawing: $isDrawingLines,
            draft: $draftLine
        )
        .padding(.top, ReviewTopBar.topPadding + ReviewTopBar.railTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func preparePlaybackWindow() {
        guard let currentIndex = navigationSwings.firstIndex(where: { $0.id == currentSwingID }) else { return }
        let lowerBound = max(navigationSwings.startIndex, currentIndex - 1)
        let upperBound = min(navigationSwings.index(before: navigationSwings.endIndex), currentIndex + 1)
        let window = navigationSwings[lowerBound...upperBound]
        let retainedIDs = Set(window.map(\.id))

        playerItems = playerItems.filter { retainedIDs.contains($0.key) }
        videoAspectRatios = videoAspectRatios.filter { retainedIDs.contains($0.key) }
        playbackErrors = playbackErrors.filter { retainedIDs.contains($0.key) }

        for swing in window {
            preparePlayback(for: swing)
        }
    }

    private func preparePlayback(for swing: SavedSwing) {
        guard playerItems[swing.id] == nil, !loadingSwingIDs.contains(swing.id) else { return }
        loadingSwingIDs.insert(swing.id)
        playbackErrors[swing.id] = nil

        Task {
            let item = await library.getPlayerItem(for: swing)
            let aspectRatio: Double?
            if let item {
                aspectRatio = try? await VideoDisplayGeometry.aspectRatio(for: item.asset)
            } else {
                aspectRatio = nil
            }
            loadingSwingIDs.remove(swing.id)

            guard reviewWindow.contains(where: { $0.id == swing.id }) else { return }

            if let item {
                videoAspectRatios[swing.id] = aspectRatio
                playerItems[swing.id] = item
            } else {
                playbackErrors[swing.id] = "The original video could not be loaded. It may have been deleted from Photos."
            }
        }
    }

    private func resetReviewState() {
        isDrawingLines = false
        draftLine = nil
        showMetadata = false
        highlightedMetric = nil
    }

}


/// Swing Info: the clip's details, tempo, and its P1–P10, in Library and Auto review.
struct SwingInfoView: View {
    let swing: SavedSwing
    @ObservedObject private var positionProcessor = SwingPositionProcessor.shared
    @ObservedObject private var coachingStore = SwingCoachingStore.shared
    @Environment(\.dismiss) private var dismiss

    private var currentSwing: SavedSwing { swing }

    var body: some View { metadataSheet }

    var metadataSheet: some View {
        // The inset cards of the other sheets over the player (All checks,
        // Layers), with the shared room under the last row.
        NavigationStack {
            List {
                Section {
                    metadataRow("View", currentSwing.vantage.displayName)
                    metadataRow("Duration", formatDuration(currentSwing.duration))
                    metadataRow("Saved", formatDate(currentSwing.createdAt))
                    metadataRow("Lens", currentSwing.lensData?.summaryText ?? "Unknown")
                } header: {
                    SectionHeading("Details")
                }
                swingTempoSection
                swingPositionsSection
            }
            .listStyle(.insetGrouped)
            // A table, not a settings list: compact rows, so more of
            // P1–P10 shows at the sheet's height.
            .environment(\.defaultMinListRowHeight, Self.rowHeight)
            .navigationTitle("Swing Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .playerSheetStyle()
    }

    @ViewBuilder
    private var swingTempoSection: some View {
        let exclusion = coachingStore.report(for: currentSwing)?.exclusion
        if SwingPositionProcessor.canFindPositions(for: currentSwing), exclusion == nil {
            if let tempo = currentSwing.tempo(excluding: exclusion) {
                Section {
                    tempoSummaryRow(tempo)
                        .listRowInsets(Self.rowInsets)
                    metadataRow("Backswing", tempo.backswingText)
                        .listRowInsets(Self.rowInsets)
                        .accessibilityIdentifier("swing-tempo-backswing")
                    metadataRow("Downswing", tempo.downswingText)
                        .listRowInsets(Self.rowInsets)
                        .accessibilityIdentifier("swing-tempo-downswing")
                } header: {
                    SectionHeading("Tempo")
                } footer: {
                    Text(tempo.isLowConfidence
                         ? "First club movement after P1 to top (P4), then top to impact (P7). Top (P4) is on a 30 fps grid (±33 ms). A ? and Low mark tempo when P4 or P7 had low confidence."
                         : "First club movement after P1 to top (P4), then top to impact (P7). Top (P4) is on a 30 fps grid (±33 ms). Tour swings are often near 3:1.")
                        .foregroundStyle(Color.helpText)
                }
            } else if positionProcessor.pending.contains(currentSwing.id)
                        || coachingStore.pending.contains(currentSwing.id) {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Measuring tempo…")
                            .font(.appCaption)
                            .foregroundStyle(Color.helpText)
                    }
                    .listRowInsets(Self.rowInsets)
                    .accessibilityIdentifier("swing-tempo-pending")
                } header: {
                    SectionHeading("Tempo")
                }
            }
        }
    }

    private func tempoSummaryRow(_ tempo: SwingTempo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ratio")
                    .font(.appBody)
                    .foregroundStyle(Color.helpText)
                Spacer(minLength: 12)
                if tempo.isLowConfidence {
                    LowConfidenceTag(value: tempo.ratioText, font: .appTitle.monospacedDigit())
                } else {
                    Text(tempo.ratioText)
                        .font(.appTitle.monospacedDigit())
                }
            }
            GeometryReader { geometry in
                let gap: CGFloat = 2
                let usable = max(geometry.size.width - gap, 1)
                let backWidth = usable * CGFloat(tempo.backswingShare)
                HStack(spacing: gap) {
                    Capsule()
                        .fill(Color.appAccent.opacity(tempo.isLowConfidence ? 0.5 : 0.9))
                        .frame(width: max(backWidth, 4))
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("swing-tempo-ratio")
        .accessibilityLabel(
            "Tempo ratio \(tempo.ratioText)\(tempo.isLowConfidence ? ", \(SwingPosition.lowConfidenceWords)" : ""), "
            + "backswing \(tempo.backswingMS) milliseconds, downswing \(tempo.downswingMS) milliseconds"
        )
    }

    @ViewBuilder
    private var swingPositionsSection: some View {
        if SwingPositionProcessor.canFindPositions(for: currentSwing) {
            Section {
                if let positions = currentSwing.swingPositions?.positions {
                    positionColumnHeaders
                        .listRowInsets(Self.rowInsets)
                    ForEach(positions, id: \.number) { position in
                        swingPositionRow(position)
                            .listRowInsets(Self.rowInsets)
                    }
                } else if positionProcessor.failed.contains(currentSwing.id) {
                    Text("Swing positions could not be found for this clip.")
                        .font(.appCaption)
                        .foregroundStyle(Color.helpText)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Finding swing positions…")
                            .font(.appCaption)
                            .foregroundStyle(Color.helpText)
                    }
                }
            } header: {
                SectionHeading("Swing positions")
            } footer: {
                if currentSwing.swingPositions?.positions != nil {
                    Text("Times are on the clip's slow-motion timeline. A ? and Low mark positions the model was unsure of.")
                        .foregroundStyle(Color.helpText)
                }
            }
            .accessibilityIdentifier("swing-positions")
        }
    }

    /// Names the table's number columns.
    private var positionColumnHeaders: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Position")
            Spacer(minLength: 12)
            Text("Time")
            Text("Confidence")
                .frame(width: Self.confidenceWidth, alignment: .trailing)
        }
        .font(.appCaptionLabel)
        .foregroundStyle(Color.helpText)
        .accessibilityHidden(true)
    }

    private static let confidenceWidth: CGFloat = 112
    private static let rowHeight: CGFloat = 36
    private static let rowInsets = EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
    /// Time and confidence: the body size in tabular figures.
    private static let numberFont = Font.appBody.monospacedDigit()

    private func swingPositionRow(_ position: SwingPosition) -> some View {
        let low = position.isLowConfidence
        return HStack(alignment: .firstTextBaseline) {
            // Below 0.5 the model found no clear peak for this position:
            // "Low" says so beside its number; the row keeps the others'
            // weight.
            Text(position.title)
                .font(.appBody)
            Spacer(minLength: 12)
            Text(String(format: "%.2fs", position.clipTime))
                .font(Self.numberFont)
            // The same numbers as Time; a low one reads as one value,
            // "Low · 50%", at the same size.
            let percent = "\(Int((position.confidence * 100).rounded()))%"
            Group {
                if low {
                    LowConfidenceTag(value: percent, font: Self.numberFont)
                } else {
                    Text(percent).font(Self.numberFont)
                }
            }
            .frame(width: Self.confidenceWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(position.title)\(low ? ", \(SwingPosition.lowConfidenceWords)" : ""): "
            + String(format: "%.2f seconds", position.clipTime)
            + ", confidence \(Int((position.confidence * 100).rounded())) percent")
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.appBody)
                .foregroundStyle(Color.helpText)

            Spacer(minLength: 12)

            Text(value)
                .font(.appBody.monospacedDigit())
                .multilineTextAlignment(.trailing)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        String(format: "%.1fs", seconds)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        SwingDetailView(
            swing: SavedSwing(
                id: UUID(),
                photoAssetID: "",
                vantage: .dtl,
                duration: 3.8,
                createdAt: Date(),
                notes: nil
            )
        )
    }
}
