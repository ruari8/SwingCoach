import AVKit
import SwiftUI

struct AutoSwingReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let swings: [SavedSwing]
    let onDelete: @MainActor (SavedSwing) async throws -> Void
    /// The check to open the start swing on, from a comparison.
    let focus: CoachingMetricID?
    /// The top-left button: "Done" closes the review; from a comparison
    /// it is "Back" and returns there.
    let leadingTitle: String
    let onLeading: (() -> Void)?

    @State private var selectedSwingID: UUID?
    @State private var swingPendingDeletion: SavedSwing?
    @State private var deletionError: ReviewDeletionError?
    @State private var isDeleting = false
    @State private var isDrawingLines = false
    @State private var controlsLocked = false
    @State private var coachingLayers = CoachingLayers.coachsChoice
    @State private var showsCoachingLayers = false
    @State private var showsInfo = false
    @ObservedObject private var library = SwingLibrary.shared
    @ObservedObject private var coachingStore = SwingCoachingStore.shared

    init(swings: [SavedSwing], startAt: UUID? = nil, focus: CoachingMetricID? = nil,
         leadingTitle: String = "Done", onLeading: (() -> Void)? = nil,
         onDelete: @escaping @MainActor (SavedSwing) async throws -> Void) {
        self.swings = swings
        self.onDelete = onDelete
        self.focus = focus
        self.leadingTitle = leadingTitle
        self.onLeading = onLeading
        // Capture appends clips chronologically. A presentation starts at
        // the newest clip unless it was opened on a particular swing, while
        // the others remain a swipe away.
        let start = startAt.flatMap { id in swings.first { $0.id == id } } ?? swings.last
        _selectedSwingID = State(initialValue: start?.id)
        _focusSwingID = State(initialValue: focus == nil ? nil : start?.id)
    }

    /// The swing `focus` applies to, until the golfer pages away.
    @State private var focusSwingID: UUID?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if swings.isEmpty {
                ContentUnavailableView(
                    "No Session Swings",
                    systemImage: "figure.golf",
                    description: Text("New Auto-captured swings will appear here.")
                )
                .foregroundStyle(.white)
            } else {
                SwingReviewPager(swings: swings, selection: $selectedSwingID, pagingEnabled: !isDeleting && !isDrawingLines,
                                 title: { $0.title ?? "Swing video" }) { swing in
                    AutoSwingReviewPage(
                        swing: swing,
                        isSelected: selectedSwingID == swing.id,
                        focus: swing.id == focusSwingID ? focus : nil,
                        isDrawingLines: $isDrawingLines,
                        deleteDisabled: isDeleting,
                        controlsLocked: $controlsLocked,
                        layers: $coachingLayers,
                        onShowLayers: { showsCoachingLayers = true },
                        onShowInfo: { showsInfo = true },
                        onDelete: { swingPendingDeletion = swing }
                    )
                }
            }

            // The same top row as Library; the player's tool rail hangs
            // under the star and holds Delete.
            reviewToolbar

            if !isDrawingLines, !coachingLayers.isCoachsChoice {
                CoachingLayersChangedTag(layers: $coachingLayers)
                    .underReviewTopBar()
            }
        }
        .sheet(isPresented: $showsInfo) {
            if let selectedSwing {
                SwingInfoView(swing: selectedSwing)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showsCoachingLayers) {
            CoachingLayersSheet(layers: $coachingLayers,
                                hasTrail: selectedSwing.map { coachingStore.clubTrail(for: $0) != nil } ?? false)
        }
        .overlayPreferenceValue(ReviewPlaybackCornerControlsKey.self) { toolRail in
            toolRail
                .padding(.horizontal, ReviewTopBar.railInset)
                .padding(.top, ReviewTopBar.topPadding)
        }
        .overlayPreferenceValue(SwingLineControlsKey.self) { controls in
            // While drawing, the line bar sits under Done and the page count.
            VStack {
                controls
                    .padding(.top, ReviewTopBar.topPadding + ReviewTopBar.railTop)
                Spacer(minLength: 0)
            }
        }
        .playerSheetDimming()
        .onChange(of: swings.map(\.id)) { _, ids in
            if let selectedSwingID, ids.contains(selectedSwingID) { return }
            self.selectedSwingID = ids.first
        }
        .onChange(of: selectedSwingID) { _, id in
            isDrawingLines = false
            if id != focusSwingID { focusSwingID = nil }
        }
        .confirmationDialog(
            "Delete this swing?",
            isPresented: Binding(
                get: { swingPendingDeletion != nil },
                set: { if !$0 { swingPendingDeletion = nil } }
            ),
            presenting: swingPendingDeletion
        ) { swing in
            Button(swing.photoAssetID.isEmpty ? "Delete from SwingCoach" : "Delete from SwingCoach and Photos", role: .destructive) {
                delete(swing)
            }
            Button("Cancel", role: .cancel) {}
        } message: { swing in
            Text(swing.photoAssetID.isEmpty
                 ? "This permanently removes the video from SwingCoach."
                 : "This permanently removes the video from SwingCoach and this phone's Photos library.")
        }
        .alert(item: $deletionError) { error in
            Alert(
                title: Text("Couldn’t Delete Swing"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var selectedSwing: SavedSwing? {
        guard let selectedSwingID else { return nil }
        return library.swings.first { $0.id == selectedSwingID } ?? swings.first { $0.id == selectedSwingID }
    }

    private var reviewToolbar: some View {
        VStack {
            ReviewTopBar(
                leadingTitle: leadingTitle,
                leadingAccessibilityLabel: onLeading == nil ? "Close swing review" : "Back to the comparison",
                onLeading: { if let onLeading { onLeading() } else { dismiss() } },
                counter: selectedSwingID.flatMap { ReviewTopBar.counter(for: $0, in: swings, id: \.id, date: \.createdAt) },
                isStarred: selectedSwing?.isFavorite ?? false,
                onStar: { if let selectedSwing { library.toggleFavorite(selectedSwing) } }
            )
            .padding(.horizontal, 14)
            .padding(.top, ReviewTopBar.topPadding)

            Spacer()
        }
    }

    private func delete(_ swing: SavedSwing) {
        isDeleting = true
        let index = swings.firstIndex { $0.id == swing.id } ?? 0
        let remaining = swings.filter { $0.id != swing.id }
        let nextID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        Task { @MainActor in
            do {
                try await onDelete(swing)
                if selectedSwingID == swing.id { selectedSwingID = nextID }
            } catch {
                deletionError = ReviewDeletionError(message: error.localizedDescription)
            }
            swingPendingDeletion = nil
            isDeleting = false
        }
    }
}

private struct AutoSwingReviewPage: View {
    let swing: SavedSwing
    let isSelected: Bool
    let focus: CoachingMetricID?
    @Binding var isDrawingLines: Bool
    let deleteDisabled: Bool
    @Binding var controlsLocked: Bool
    @Binding var layers: CoachingLayers
    let onShowLayers: () -> Void
    let onShowInfo: () -> Void
    let onDelete: () -> Void

    @State private var playerItem: AVPlayerItem?
    @State private var videoAspectRatio: Double?
    @State private var draftLine: ManualAnnotation?
    @State private var coachingSeek: Double?
    @State private var highlightedMetric: CoachingMetricID?
    @State private var coachInteracted = false
    @State private var showsCoachingChecks = false
    @ObservedObject private var library = SwingLibrary.shared
    @ObservedObject private var coachingStore = SwingCoachingStore.shared

    /// The library's copy, which gains positions after the save.
    private var librarySwing: SavedSwing {
        library.swings.first { $0.id == swing.id } ?? swing
    }

    private var drawingEnabled: Bool { isSelected && isDrawingLines }
    private var canCoach: Bool { SwingCoachingStore.canCoach(librarySwing) }

    private var tools: [PlayerTool] {
        var tools: [PlayerTool] = []
        if canCoach {
            tools.append(.coachingDrawings(changed: !layers.isCoachsChoice, action: onShowLayers))
        }
        // Destructive: the rail puts it last, after a divider, in red.
        tools.append(PlayerTool(id: "delete", title: "Delete", accessibilityLabel: "Delete this swing",
                                isDestructive: true, icon: .system("trash")) {
            if !deleteDisabled { onDelete() }
        })
        return tools
    }

    var body: some View {
        Group {
            if let playerItem {
                PlaybackChromeView(
                    playerItem: playerItem,
                    playbackEnabled: isSelected,
                    showsSpeedControls: true,
                    startsPlaying: false,
                    allowsFullscreen: false,
                    allowsTransportGestures: !drawingEnabled,
                    contentOverlayAllowsHitTesting: drawingEnabled,
                    edgeToEdge: true,
                    controlsLocked: $controlsLocked,
                    infoAction: onShowInfo,
                    realTimeRate: swing.realTimePlaybackRate,
                    // Positions arrive about a second after the save, after
                    // the session list copied the swing: read the library's.
                    swingPositions: librarySwing.swingPositions,
                    drawing: videoAspectRatio != nil ? $isDrawingLines : nil,
                    seekRequest: isSelected ? $coachingSeek : nil,
                    positionMarks: coachingStore.stripMarks(for: librarySwing),
                    extraTools: tools,
                    walkthroughStops: coachingStore.walkthroughStops(
                        for: librarySwing, highlighted: isSelected ? highlightedMetric : nil),
                    bottomPanel: canCoach ? { context in
                        AnyView(SwingCoachingPanel(
                            swing: librarySwing, context: context, highlighted: $highlightedMetric,
                            onShowChecks: { showsCoachingChecks = true },
                            onInteract: { coachInteracted = true }
                        ))
                    } : nil,
                    stopFocus: { time in coachingStore.focusRange(for: librarySwing, at: time, highlighted: isSelected ? highlightedMetric : nil) },
                    contentOverlay: { currentTime in
                        AnyView(ZStack {
                            SwingCoachingOverlay(
                                report: coachingStore.report(for: librarySwing),
                                steps: coachingStore.steps(for: librarySwing),
                                trail: coachingStore.clubTrail(for: librarySwing),
                                layers: layers,
                                aspectRatio: videoAspectRatio,
                                currentTime: currentTime,
                                highlighted: isSelected ? highlightedMetric : nil
                            )
                            SwingLineOverlay(
                                swing: swing,
                                aspectRatio: videoAspectRatio,
                                currentTime: currentTime,
                                isDrawing: drawingEnabled,
                                draft: $draftLine
                            )
                        })
                    }
                ) {
                    EmptyView()
                }
                // The review screen hosts the rail, under the star.
                .environment(\.reviewCornerControlsInNavigation, true)
                .preference(
                    key: SwingLineControlsKey.self,
                    value: isSelected && videoAspectRatio != nil ? AnyView(SwingLineControls(
                        annotationID: swing.manualAnnotationID,
                        isDrawing: $isDrawingLines,
                        draft: $draftLine
                    )) : nil
                )
            } else {
                ProgressView()
                    .scaleEffect(1.35)
                    .tint(.white)
            }
        }
        .swingCoachingOpening(swing: librarySwing, isActive: isSelected, focus: focus, seek: $coachingSeek,
                              interacted: $coachInteracted, highlighted: $highlightedMetric)
        .sheet(isPresented: $showsCoachingChecks) {
            if let report = coachingStore.report(for: librarySwing) {
                SwingCoachingChecks(swing: librarySwing, report: report,
                                    verdict: coachingStore.verdict(for: librarySwing, report: report)) { result in
                    coachInteracted = true
                    highlightedMetric = result.id
                    coachingSeek = result.clipTime
                    showsCoachingChecks = false
                }
                .presentationDetents([.fraction(0.62), .large])
            }
        }
        .task(id: swing.id) {
            let item = await SwingLibrary.shared.getPlayerItem(for: swing)
            guard !Task.isCancelled else { return }
            playerItem = item
            if let item {
                let aspectRatio = try? await VideoDisplayGeometry.aspectRatio(for: item.asset)
                guard !Task.isCancelled else { return }
                videoAspectRatio = aspectRatio
            }
        }
        .onChange(of: isSelected) { _, _ in
            draftLine = nil
            highlightedMetric = nil
        }
    }
}

private struct ReviewDeletionError: Identifiable {
    let id = UUID()
    let message: String
}
