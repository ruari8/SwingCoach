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

    @State private var playerItem: AVPlayerItem?
    @State private var isLoadingPlayback = false
    @State private var playbackError: String?
    @State private var analysisStatus: SwingAnalysis.AnalysisStatus = .pending
    @State private var analysisProgressText: String?
    @State private var analysisProgressValue: Float?
    @State private var showTechnicalDetails = false
    @State private var showMetadata = false
    @State private var selectedPage = 0

    private var currentSwing: SavedSwing {
        library.swings.first { $0.id == swing.id } ?? swing
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

            if let savedAnalysis {
                analyzedCarousel(savedAnalysis: savedAnalysis)
            } else {
                originalVideoPage()
            }

            // Navigation chrome stays available on every page so you can always
            // get back / open metadata, even with the player controls hidden.
            topNavOverlay

            if shouldShowAnalysisAction {
                analysisFloatingLayer
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showMetadata) {
            metadataSheet
                .presentationDetents([.medium])
        }
        .onAppear {
            preparePlayback()
            Task {
                await library.loadThumbnails()
            }
        }
    }

    private func analyzedCarousel(savedAnalysis: SavedAnalysis) -> some View {
        TabView(selection: $selectedPage) {
            originalVideoPage()
                .tag(0)

            annotatedVideoPage(savedAnalysis: savedAnalysis)
                .tag(1)

            coachNotesPage(savedAnalysis: savedAnalysis)
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func originalVideoPage() -> some View {
        originalPlayer
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topNavOverlay: some View {
        VStack(spacing: 10) {
            HStack {
                navCircleButton(systemName: "chevron.left") { dismiss() }
                    .accessibilityLabel("Back to library")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)

            if savedAnalysis != nil {
                carouselDots(count: 3)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 6)
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

    private func carouselDots(count: Int) -> some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == selectedPage ? Color.white : Color.white.opacity(0.34))
                    .frame(width: index == selectedPage ? 7 : 5, height: index == selectedPage ? 7 : 5)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .accessibilityLabel("Carousel page \(selectedPage + 1) of \(count)")
    }

    @ViewBuilder
    private var originalPlayer: some View {
        if let playerItem {
            PlaybackChromeView(
                playerItem: playerItem,
                playbackEnabled: true,
                showsSpeedControls: true,
                startsPlaying: false,
                allowsFullscreen: false,
                allowsTransportGestures: true,
                edgeToEdge: true,
                allowsLock: true,
                infoAction: { showMetadata = true }
            ) {
                EmptyView()
            }
        } else {
            ZStack {
                Color.black

                if let playbackError {
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
                        Text(isLoadingPlayback ? "Loading swing..." : "Preparing playback...")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
            }
            .onAppear {
                preparePlayback()
            }
        }
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

    private func preparePlayback() {
        guard playerItem == nil, !isLoadingPlayback else { return }
        isLoadingPlayback = true
        playbackError = nil

        Task {
            if let item = await library.getPlayerItem(for: currentSwing) {
                await MainActor.run {
                    playerItem = item
                    isLoadingPlayback = false
                }
            } else {
                await MainActor.run {
                    isLoadingPlayback = false
                    playbackError = "The original video could not be loaded. It may have been deleted from Photos."
                }
            }
        }
    }

    private func startAnalysis() {
        analysisStatus = .analyzing
        analysisProgressText = "Preparing video..."
        analysisProgressValue = nil
        showTechnicalDetails = false

        Task {
            do {
                let response = try await SwingCoachAPI.shared.analyzeSwing(currentSwing) { stage, progress in
                    Task { @MainActor in
                        if let progress {
                            analysisProgressText = stage
                            analysisProgressValue = progress
                        } else {
                            analysisProgressText = stage
                            analysisProgressValue = nil
                        }
                    }
                }

                await MainActor.run {
                    _ = analysisLibrary.save(response, for: currentSwing)
                    library.markAnalyzed(currentSwing)
                    analysisProgressText = nil
                    analysisProgressValue = nil
                    analysisStatus = .complete
                }
            } catch {
                await MainActor.run {
                    analysisProgressText = nil
                    analysisProgressValue = nil
                    analysisStatus = .failed(SwingCoachAPI.displayMessage(for: error))
                }
            }
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
