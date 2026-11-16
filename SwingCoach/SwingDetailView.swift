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
        guard navigationSwings.count > 1,
              let index = navigationSwings.firstIndex(where: { $0.id == currentSwing.id }) else { return nil }
        return "\(index + 1) of \(navigationSwings.count)"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            reviewPager

            if isDrawingLines, videoAspectRatios[currentSwingID] != nil {
                drawingToolBar
            }

            if !isDrawingLines, SwingCoachingStore.canCoach(currentSwing) {
                VStack {
                    SwingCoachingPill(swing: currentSwing, seek: { coachingSeek = $0 }, highlighted: $highlightedMetric)
                        // Clear of the tool rail, which can dock on either side.
                        .padding(.horizontal, 14 + PlayerToolRail.buttonSize + PlayerToolRail.spacing)
                    Spacer(minLength: 0)
                }
                .padding(.top, 64)
            }
        }
        .overlayPreferenceValue(ReviewPlaybackCornerControlsKey.self) { cornerControls in
            topNavOverlay(cornerControls: cornerControls)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showMetadata) {
            metadataSheet
                .presentationDetents([.medium])
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
            HStack {
                navCircleButton(systemName: "chevron.left") { dismiss() }
                    .accessibilityLabel("Back to library")

                Spacer()

                if let swingPositionText {
                    Text(swingPositionText)
                        .accessibilityIdentifier("swing-position")
                        .accessibilityValue(currentSwing.title ?? "")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                }

                Spacer()

                Button {
                    library.toggleFavorite(currentSwing)
                } label: {
                    Image(systemName: currentSwing.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(currentSwing.isFavorite ? .yellow : .white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(currentSwing.isFavorite ? "Remove star" : "Star swing")
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        // The player's tool rail starts one gap under the star, or under Back
        // when docked left, without moving the navigation row.
        .overlay {
            cornerControls
                .padding(.horizontal, 14)
                .padding(.top, 6)
        }
    }

    private func navCircleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
        .buttonStyle(.plain)
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
                contentOverlay: { currentTime, _ in
                    AnyView(
                        ZStack {
                            SwingCoachingOverlay(
                                report: coachingStore.report(for: swing),
                                picks: coachingStore.coachPicks(for: swing),
                                aspectRatio: videoAspectRatios[swing.id],
                                currentTime: currentTime,
                                timeScale: swing.sourceTimeScale ?? 1,
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
            } overlayAccessory: {
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
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        Text(loadingSwingIDs.contains(swing.id) ? "Loading swing..." : "Preparing playback...")
                            .font(.caption)
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
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var metadataSheet: some View {
        NavigationStack {
            ScrollView {
                metadataContent
                    .padding()
            }
            .navigationTitle("Swing Info")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var metadataContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metadata")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 10) {
                metadataRow("View", currentSwing.vantage.displayName)
                metadataRow("Duration", formatDuration(currentSwing.duration))
                metadataRow("Saved", formatDate(currentSwing.createdAt))
            }

            swingPositionsSection
        }
    }

    @ViewBuilder
    private var swingPositionsSection: some View {
        if SwingPositionProcessor.canFindPositions(for: currentSwing) {
            Text("Swing positions")
                .font(.subheadline.weight(.semibold))
                .padding(.top, 8)

            if let positions = currentSwing.swingPositions?.positions {
                VStack(spacing: 8) {
                    ForEach(positions, id: \.number) { position in
                        swingPositionRow(position)
                    }
                }
                .accessibilityIdentifier("swing-positions")
                Text("Times are on the clip's slow-motion timeline. A ? marks positions the model was unsure of.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if positionProcessor.failed.contains(currentSwing.id) {
                Text("Swing positions could not be found for this clip.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Finding swing positions…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func swingPositionRow(_ position: SwingPosition) -> some View {
        HStack(alignment: .firstTextBaseline) {
            // Below 0.5 the model found no clear peak for this position.
            Text(position.confidence < 0.5 ? "\(position.label)? \(position.name)" : "\(position.label) \(position.name)")
                .font(.subheadline)
            Spacer(minLength: 12)
            Text(String(format: "%.2fs", position.clipTime))
                .font(.subheadline.weight(.medium).monospacedDigit())
            Text("\(Int((position.confidence * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
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
        coachingSeek = nil
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
