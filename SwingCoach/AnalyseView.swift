//
//  AnalyseView.swift
//  SwingCoach
//
//  Created by AI Assistant on 23/12/2024.
//

import SwiftUI
import AVFoundation

/// Analysis state for a swing
struct SwingAnalysis: Identifiable {
    let id = UUID()
    let swing: SavedSwing
    var status: AnalysisStatus
    var result: AnalysisResult?

    enum AnalysisStatus: Equatable {
        case pending
        case analyzing
        case complete
        case failed(String)
    }
}

struct AnalysisResult {
    let analysisID: String
    let summary: String
    let metrics: [SwingCoachAPI.AnalysisMetric]
    let annotatedVideoURL: String?
    let drills: [SwingCoachAPI.AnalysisDrill]
}

/// Main Analyse/Swing Coach tab
struct AnalyseView: View {
    @Binding var swingsToAnalyze: [SavedSwing]
    let onNavigateToLibrary: () -> Void

    @StateObject private var library = SwingLibrary.shared

    // Analysis state
    @State private var analyses: [SwingAnalysis] = []
    @State private var isAnalyzing = false
    @State private var showSwingPicker = false

    // Selection for picking from library
    @State private var selectedSwingIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if analyses.isEmpty && swingsToAnalyze.isEmpty {
                    emptyState
                } else {
                    analysisContent
                }
            }
            .navigationTitle("Swing Coach")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !isAnalyzing {
                        Button {
                            showSwingPicker = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                    }
                }
            }
            .sheet(isPresented: $showSwingPicker) {
                SwingPickerSheet(
                    library: library,
                    selectedIDs: $selectedSwingIDs,
                    onConfirm: {
                        addSelectedSwingsAndAnalyze()
                    },
                    onCancel: {
                        showSwingPicker = false
                        selectedSwingIDs.removeAll()
                    }
                )
            }
            .onChange(of: swingsToAnalyze) { _, newSwings in
                if !newSwings.isEmpty {
                    startAnalysis(for: newSwings)
                    swingsToAnalyze = [] // Clear after consuming
                }
            }
            .onAppear {
                // Handle swings passed in on appear
                if !swingsToAnalyze.isEmpty {
                    startAnalysis(for: swingsToAnalyze)
                    swingsToAnalyze = []
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("AI Swing Coach")
                .font(.title2.weight(.semibold))

            Text("Select swings from your library to get AI-powered analysis and drill recommendations")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(spacing: 12) {
                Button {
                    showSwingPicker = true
                } label: {
                    Label("Select Swings", systemImage: "film.stack")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .cornerRadius(12)
                }

                Button {
                    onNavigateToLibrary()
                } label: {
                    Text("Go to Library")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
            .padding(.top, 8)
        }
        .padding()
    }

    // MARK: - Analysis Content

    private var analysisContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(analyses) { analysis in
                    AnalysisCard(analysis: analysis) {
                        retryAnalysis(analysis)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Actions

    private func addSelectedSwingsAndAnalyze() {
        let swings = library.swings.filter { selectedSwingIDs.contains($0.id) }
        showSwingPicker = false
        selectedSwingIDs.removeAll()
        startAnalysis(for: swings)
    }

    private func retryAnalysis(_ analysis: SwingAnalysis) {
        analyses.removeAll { $0.id == analysis.id }
        startAnalysis(for: [analysis.swing])
    }

    private func startAnalysis(for swings: [SavedSwing]) {
        // Add new analyses
        let newAnalyses = swings.map { SwingAnalysis(swing: $0, status: .pending) }
        analyses.insert(contentsOf: newAnalyses, at: 0)

        // Start analyzing
        isAnalyzing = true

        Task {
            for i in analyses.indices where analyses[i].status == .pending {
                await MainActor.run {
                    analyses[i].status = .analyzing
                }

                do {
                    // Real API call
                    let response = try await SwingCoachAPI.shared.analyzeSwing(analyses[i].swing) { stage, progress in
                        // Could update UI with stage/progress here if we add more granular status
                        print("📤 \(stage) - \(progress.map { String(format: "%.0f%%", $0 * 100) } ?? "")")
                    }

                    // Convert API response to our local model
                    let result = AnalysisResult(
                        analysisID: response.analysisID,
                        summary: response.summary,
                        metrics: response.metrics,
                        annotatedVideoURL: response.annotatedVideoURL,
                        drills: response.drills
                    )

                    await MainActor.run {
                        analyses[i].result = result
                        analyses[i].status = .complete
                    }

                    // Mark as analyzed in library
                    library.markAnalyzed(analyses[i].swing)

                } catch {
                    await MainActor.run {
                        analyses[i].status = .failed(error.localizedDescription)
                    }
                }
            }

            await MainActor.run {
                isAnalyzing = false
            }
        }
    }
}

// MARK: - Analysis Card

struct AnalysisCard: View {
    let analysis: SwingAnalysis
    let onRetry: () -> Void

    @State private var showTechnicalDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                if let thumbnail = analysis.swing.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 40)
                        .clipped()
                        .cornerRadius(6)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(analysis.swing.vantage.displayName)
                        .font(.headline)
                    Text(formatDate(analysis.swing.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                statusBadge
            }

            // Content based on status
            switch analysis.status {
            case .pending:
                Text("Waiting...")
                    .foregroundColor(.secondary)

            case .analyzing:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Analyzing swing...")
                        .foregroundColor(.secondary)
                }

            case .complete:
                if let result = analysis.result {
                    resultContent(result)
                }

            case .failed(let error):
                failureContent(error)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }

    private var statusBadge: some View {
        Group {
            switch analysis.status {
            case .pending:
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
            case .analyzing:
                ProgressView()
                    .scaleEffect(0.8)
            case .complete:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
    }

    @ViewBuilder
    private func failureContent(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Analysis failed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text("We couldn't finish this swing analysis. Check your connection and try again.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showTechnicalDetails.toggle()
                } label: {
                    Text(showTechnicalDetails ? "Hide details" : "Details")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }

            if showTechnicalDetails {
                Text(error)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }
        }
    }

    @ViewBuilder
    private func resultContent(_ result: AnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let annotatedVideoURL = result.annotatedVideoURL,
               let url = URL(string: annotatedVideoURL) {
                AnnotatedAnalysisVideo(url: url)
            }

            // Metrics
            if !result.metrics.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Metrics")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    ForEach(result.metrics, id: \.key) { metric in
                        HStack {
                            Text(metric.name)
                                .font(.subheadline)
                            Spacer()
                            Text(metric.value)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }

            // Coach Text
            VStack(alignment: .leading, spacing: 6) {
                Text("Coach Notes")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Text(result.summary)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
            }

            // Drills
            if !result.drills.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recommendations")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    ForEach(result.drills, id: \.title) { drill in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(drill.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                            Text(drill.summary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct AnnotatedAnalysisVideo: View {
    let url: URL

    @State private var playerItem: AVPlayerItem?

    var body: some View {
        Group {
            if let playerItem {
                PlaybackChromeView(
                    playerItem: playerItem,
                    playbackEnabled: true,
                    showsSpeedControls: false,
                    startsPlaying: false
                ) {
                    HStack {
                        Label("Annotated Video", systemImage: "play.rectangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                }
            } else {
                ZStack {
                    Color.black
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading annotated video...")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            if playerItem == nil {
                playerItem = AVPlayerItem(url: url)
            }
        }
        .onChange(of: url) { _, newURL in
            playerItem = AVPlayerItem(url: newURL)
        }
    }
}

// MARK: - Swing Picker Sheet

struct SwingPickerSheet: View {
    let library: SwingLibrary
    @Binding var selectedIDs: Set<UUID>
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if library.swings.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "film")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No swings in library")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(library.swings) { swing in
                            swingTile(swing)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Select Swings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Analyze (\(selectedIDs.count))") { onConfirm() }
                        .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }

    private func swingTile(_ swing: SavedSwing) -> some View {
        let isSelected = selectedIDs.contains(swing.id)

        return Button {
            if isSelected {
                selectedIDs.remove(swing.id)
            } else {
                selectedIDs.insert(swing.id)
            }
        } label: {
            ZStack {
                if let thumbnail = swing.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 80)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 80)
                }

                // Selection indicator
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundColor(isSelected ? .blue : .white)
                            .shadow(radius: 2)
                    }
                    Spacer()
                    HStack {
                        Text(swing.vantage.shortName)
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(3)
                        Spacer()
                    }
                }
                .padding(6)
            }
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AnalyseView(
        swingsToAnalyze: .constant([]),
        onNavigateToLibrary: {}
    )
}
