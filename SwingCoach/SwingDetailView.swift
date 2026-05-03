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

    @StateObject private var library = SwingLibrary.shared
    @StateObject private var analysisLibrary = AnalysisLibrary.shared

    @State private var playerItem: AVPlayerItem?
    @State private var isLoadingPlayback = false
    @State private var playbackError: String?
    @State private var analysisStatus: SwingAnalysis.AnalysisStatus = .pending
    @State private var analysisProgressText: String?
    @State private var showTechnicalDetails = false
    @State private var isOriginalExpanded = false

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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                originalVideoSection
                if shouldShowAnalysisAction {
                    analysisActionSection
                }
                analysisSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Swing Detail")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await library.loadThumbnails()
            }
        }
        .onChange(of: isOriginalExpanded) { _, expanded in
            if expanded {
                preparePlayback()
            }
        }
    }

    private var originalVideoSection: some View {
        DisclosureGroup(isExpanded: $isOriginalExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                originalPlayer
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                metadataContent
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 12) {
                originalThumbnail

                VStack(alignment: .leading, spacing: 4) {
                    Text("Original Swing")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("\(currentSwing.vantage.displayName) · \(formatDuration(currentSwing.duration))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var originalPlayer: some View {
        if let playerItem {
            PlaybackChromeView(
                playerItem: playerItem,
                playbackEnabled: true,
                showsSpeedControls: true,
                startsPlaying: false
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

    private var originalThumbnail: some View {
        ZStack {
            if let thumbnail = currentSwing.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
                Image(systemName: "play.rectangle.fill")
                    .foregroundColor(.white.opacity(0.75))
            }
        }
        .frame(width: 86, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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

    private var analysisActionSection: some View {
        Button {
            startAnalysis()
        } label: {
            HStack {
                if isAnalyzing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: savedAnalysis == nil ? "wand.and.stars" : "arrow.clockwise")
                }

                Text(actionTitle)
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isAnalyzing ? Color.gray : Color.blue)
            .cornerRadius(10)
        }
        .disabled(isAnalyzing)
    }

    @ViewBuilder
    private var analysisSection: some View {
        switch analysisStatus {
        case .analyzing:
            statusPanel(
                icon: "arrow.triangle.2.circlepath",
                title: analysisProgressText ?? "Analyzing swing...",
                message: "You can leave this screen open while SwingCoach prepares the coach result."
            )

        case .failed(let error):
            VStack(alignment: .leading, spacing: 10) {
                statusPanel(
                    icon: "exclamationmark.circle.fill",
                    title: "Analysis failed",
                    message: "Check your connection and try again."
                )

                Button {
                    showTechnicalDetails.toggle()
                } label: {
                    Text(showTechnicalDetails ? "Hide details" : "Show details")
                        .font(.subheadline)
                }

                if showTechnicalDetails {
                    Text(error)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                }
            }

        case .pending, .complete:
            if let savedAnalysis {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Coach Result")
                        .font(.headline)

                    AnalysisResultView(result: AnalysisResult(savedAnalysis: savedAnalysis))
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(8)
                }
            } else {
                statusPanel(
                    icon: "wand.and.stars",
                    title: "Ready for analysis",
                    message: "Run the coach analysis to attach metrics, annotated video, notes, and recommendations to this swing."
                )
            }
        }
    }

    private var actionTitle: String {
        if isAnalyzing {
            return analysisProgressText ?? "Analyzing..."
        }
        if case .failed = analysisStatus {
            return "Retry Analysis"
        }
        return "Analyze Swing"
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

    private func statusPanel(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
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
        showTechnicalDetails = false

        Task {
            do {
                let response = try await SwingCoachAPI.shared.analyzeSwing(currentSwing) { stage, progress in
                    Task { @MainActor in
                        if let progress {
                            analysisProgressText = "\(stage) \(Int(progress * 100))%"
                        } else {
                            analysisProgressText = stage
                        }
                    }
                }

                await MainActor.run {
                    _ = analysisLibrary.save(response, for: currentSwing)
                    library.markAnalyzed(currentSwing)
                    analysisProgressText = nil
                    analysisStatus = .complete
                }
            } catch {
                await MainActor.run {
                    analysisProgressText = nil
                    analysisStatus = .failed(error.localizedDescription)
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
