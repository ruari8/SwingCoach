//
//  SwingDetailView.swift
//  SwingCoach
//
//  A swing-first workspace for playback, metadata, and attached analysis.
//

import SwiftUI
import AVFoundation

struct SwingDetailView: View {
    let swing: SavedSwing

    @Environment(\.dismiss) private var dismiss
    @StateObject private var library = SwingLibrary.shared
    @StateObject private var analysisLibrary = AnalysisLibrary.shared
    @StateObject private var reviewAnalysis = SwingReviewAnalysis()

    @State private var currentSwingID: UUID
    @State private var reviewSwingIDs: [UUID]
    @State private var playerItems: [UUID: AVPlayerItem] = [:]
    @State private var videoAspectRatios: [UUID: Double] = [:]
    @State private var loadingSwingIDs: Set<UUID> = []
    @State private var playbackErrors: [UUID: String] = [:]
    @State private var showTechnicalDetails = false
    @State private var showMetadata = false
    @State private var selectedPage = 0
    @State private var isDrawingLines = false
    @State private var controlsLocked = false
    @State private var draftLine: ManualAnnotation?

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

    private var analysisStatus: SwingAnalysis.AnalysisStatus {
        reviewAnalysis.requests[currentSwingID]?.status ?? .pending
    }

    private var analysisProgressText: String? {
        reviewAnalysis.requests[currentSwingID]?.progressText
    }

    private var analysisProgressValue: Float? {
        reviewAnalysis.requests[currentSwingID]?.progress
    }

    private var swingPositionText: String? {
        guard navigationSwings.count > 1,
              let index = navigationSwings.firstIndex(where: { $0.id == currentSwing.id }) else { return nil }
        return "\(index + 1) of \(navigationSwings.count)"
    }

    private var savedAnalysis: SavedAnalysis? {
        analysisLibrary.analysis(for: currentSwing)
    }

    private var isAnalyzing: Bool {
        if case .analyzing = analysisStatus {
            return true
        }
        return false
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            reviewPager

            if shouldShowAnalysisAction {
                analysisFloatingLayer
            }

            if selectedPage == 0, videoAspectRatios[currentSwingID] != nil {
                drawingToolRail
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
            Task {
                await library.loadThumbnails()
            }
        }
        .onChange(of: currentSwingID) { _, _ in
            resetReviewState()
            preparePlaybackWindow()
        }
    }

    @ViewBuilder
    private var reviewPager: some View {
        if selectedPage != 0, let savedAnalysis {
            analyzedCarousel(savedAnalysis: savedAnalysis, swing: currentSwing)
        } else {
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
    }

    private var reviewWindow: [SavedSwing] {
        guard let currentIndex = navigationSwings.firstIndex(where: { $0.id == currentSwingID }) else { return [] }
        let lowerBound = max(navigationSwings.startIndex, currentIndex - 1)
        let upperBound = min(navigationSwings.index(before: navigationSwings.endIndex), currentIndex + 1)
        return Array(navigationSwings[lowerBound...upperBound])
    }

    private func analyzedCarousel(savedAnalysis: SavedAnalysis, swing: SavedSwing) -> some View {
        Group {
            if selectedPage == 0 {
                originalVideoPage(for: swing)
            } else if selectedPage == 1 {
                annotatedVideoPage(savedAnalysis: savedAnalysis)
            } else {
                coachNotesPage(savedAnalysis: savedAnalysis)
            }
        }
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

                VStack(spacing: 10) {
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
                    cornerControls
                }
                .fixedSize(horizontal: false, vertical: true)
                // The stack extends below the navigation row without moving
                // the back button, count, or analysis page picker.
                .frame(height: 38, alignment: .top)
            }
            .padding(.horizontal, 14)

            if savedAnalysis != nil {
                analysisPagePicker
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private var analysisPagePicker: some View {
        HStack(spacing: 5) {
            analysisPageButton("play.fill", page: 0, label: "Original video")
            analysisPageButton("scribble.variable", page: 1, label: "Annotated video")
            analysisPageButton("text.alignleft", page: 2, label: "Coach notes")
        }
        .padding(5)
        .background(Capsule().fill(Color.black.opacity(0.42)))
    }

    private func analysisPageButton(_ systemName: String, page: Int, label: String) -> some View {
        Button {
            selectedPage = page
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(selectedPage == page ? .black : .white)
                .frame(width: 34, height: 28)
                .background(Capsule().fill(selectedPage == page ? Color.white : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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

    private var analysisFloatingLayer: some View {
        VStack(spacing: 12) {
            analysisOverlayButton

            analysisInlineStatus
                .padding(.horizontal, 28)

            Spacer(minLength: 0)
        }
        .padding(.top, 64)
    }

    @ViewBuilder
    private func annotatedVideoPage(savedAnalysis: SavedAnalysis) -> some View {
        if let annotatedVideo = savedAnalysis.annotatedVideo {
            AnnotatedAnalysisVideo(
                video: annotatedVideo,
                analysisID: savedAnalysis.analysisID,
                presentation: .immersive
            )
        } else {
            statusFullscreen(
                icon: "video.slash",
                title: "No annotated video",
                message: "This analysis has coach notes and metrics, but no rendered video artifact yet."
            )
        }
    }

    private func coachNotesPage(savedAnalysis: SavedAnalysis) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Coach Notes")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)

                    Text(savedAnalysis.summary)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !savedAnalysis.metrics.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Metrics")
                            .font(.headline)
                            .foregroundColor(.white)

                        ForEach(savedAnalysis.metrics, id: \.key) { metric in
                            HStack(alignment: .firstTextBaseline) {
                                Text(metric.name)
                                    .foregroundColor(.white.opacity(0.72))

                                Spacer(minLength: 12)

                                Text(metric.value)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.trailing)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                if !savedAnalysis.drills.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Drills")
                            .font(.headline)
                            .foregroundColor(.white)

                        ForEach(savedAnalysis.drills, id: \.title) { drill in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(drill.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)

                                Text(drill.summary)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.68))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding()
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                Text("Note: this page is the future home for richer coach notes and linked drill content once the drill library is wired into the analysis flow.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.54))
            }
            .padding(.horizontal, 22)
            .padding(.top, 92)
            .padding(.bottom, 84)
        }
        .background(
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.09, blue: 0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    private func originalPlayer(for swing: SavedSwing) -> some View {
        let drawingEnabled = isDrawingLines && swing.id == currentSwingID

        return Group {
        if let playerItem = playerItems[swing.id] {
            PlaybackChromeView(
                playerItem: playerItem,
                playbackEnabled: swing.id == currentSwingID && !drawingEnabled,
                showsSpeedControls: true,
                startsPlaying: false,
                allowsFullscreen: false,
                allowsTransportGestures: !drawingEnabled,
                contentOverlayAllowsHitTesting: drawingEnabled,
                edgeToEdge: true,
                controlsLocked: $controlsLocked,
                infoAction: { showMetadata = true },
                contentOverlay: { currentTime, _ in
                    AnyView(
                        SwingLineOverlay(
                            swing: swing,
                            aspectRatio: videoAspectRatios[swing.id],
                            currentTime: currentTime,
                            isDrawing: drawingEnabled,
                            draft: $draftLine
                        )
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

    private var drawingToolRail: some View {
        HStack {
            SwingLineControls(
                annotationID: currentSwing.manualAnnotationID,
                isDrawing: $isDrawingLines,
                draft: $draftLine
            )
            Spacer(minLength: 0)
        }
        .padding(.leading, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var analysisOverlayButton: some View {
        Button {
            startAnalysis()
        } label: {
            HStack(spacing: 8) {
                if isAnalyzing {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: savedAnalysis == nil ? "wand.and.stars" : "arrow.clockwise")
                }

                Text(actionTitle)
                    .font(.subheadline.weight(.bold))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Capsule().fill(isAnalyzing ? Color.white.opacity(0.72) : Color.yellow))
        }
        .buttonStyle(.plain)
        .disabled(isAnalyzing)
    }

    @ViewBuilder
    private var analysisInlineStatus: some View {
        switch analysisStatus {
        case .analyzing:
            VStack(alignment: .leading, spacing: 8) {
                Text(analysisProgressTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.75))

                if let analysisProgressValue {
                    ProgressView(value: Double(analysisProgressValue))
                        .tint(.yellow)
                } else {
                    ProgressView()
                        .tint(.yellow)
                }
            }
        case .failed(let error):
            Button {
                showTechnicalDetails.toggle()
            } label: {
                Label(showTechnicalDetails ? error : "Analysis failed. Tap for details.", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.yellow)
                    .lineLimit(showTechnicalDetails ? nil : 1)
            }
            .buttonStyle(.plain)
        case .pending, .complete:
            EmptyView()
        }
    }

    private var metadataSheet: some View {
        NavigationStack {
            metadataContent
                .padding()
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
                metadataRow("Analysis", savedAnalysis == nil ? "Not analyzed" : "Complete")
            }
        }
    }

    private var shouldShowAnalysisAction: Bool {
        if currentSwing.isReference {
            return false
        }
        if isAnalyzing || savedAnalysis == nil {
            return true
        }
        if case .failed = analysisStatus {
            return true
        }
        return false
    }

    private func statusFullscreen(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(.white.opacity(0.72))
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Text(message)
                .font(.caption)
                .foregroundColor(.white.opacity(0.64))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea(edges: .top))
    }

    private var actionTitle: String {
        if isAnalyzing {
            return "Analyzing..."
        }
        if case .failed = analysisStatus {
            return "Retry Analysis"
        }
        return "Analyze Swing"
    }

    private var analysisProgressTitle: String {
        if let analysisProgressText {
            if let analysisProgressValue {
                return "\(analysisProgressText) \(Int(analysisProgressValue * 100))%"
            }
            return analysisProgressText
        }
        return "Analyzing swing..."
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
        selectedPage = 0
        isDrawingLines = false
        draftLine = nil
        showMetadata = false
    }

    private func startAnalysis() {
        let submittedSwing = currentSwing
        showTechnicalDetails = false
        Task {
            await reviewAnalysis.run(for: submittedSwing)
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
                notes: nil,
                analyzed: false
            )
        )
    }
}
