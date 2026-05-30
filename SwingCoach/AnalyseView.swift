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
    var progressText: String?
    var progress: Float?

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
    let metrics: [SavedAnalysisMetric]
    let annotatedVideo: SavedAnalysisVideo?
    let drills: [SavedAnalysisDrill]

    init(savedAnalysis: SavedAnalysis) {
        analysisID = savedAnalysis.analysisID
        summary = savedAnalysis.summary
        metrics = savedAnalysis.metrics
        annotatedVideo = savedAnalysis.annotatedVideo
        drills = savedAnalysis.drills
    }
}

/// Main Analyse/Swing Coach tab
struct AnalyseView: View {
    @Binding var swingsToAnalyze: [SavedSwing]
    let onNavigateToLibrary: () -> Void

    @StateObject private var library = SwingLibrary.shared
    @StateObject private var analysisLibrary = AnalysisLibrary.shared

    // Analysis state
    @State private var analyses: [SwingAnalysis] = []
    @State private var isAnalyzing = false
    @State private var showSwingPicker = false

    // Selection for picking from library
    @State private var selectedSwingIDs: Set<UUID> = []

    private var activeAnalyses: [SwingAnalysis] {
        analyses.filter {
            if case .complete = $0.status {
                return false
            }
            return true
        }
    }

    private var completedAnalyses: [SwingAnalysis] {
        analyses.filter {
            if case .complete = $0.status {
                return true
            }
            return false
        }
    }

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
                loadSavedAnalyses()
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
            VStack(alignment: .leading, spacing: 22) {
                if !activeAnalyses.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("Analysis Queue")

                        LazyVStack(spacing: 10) {
                            ForEach(activeAnalyses) { analysis in
                                AnalysisQueueRow(analysis: analysis) {
                                    retryAnalysis(analysis)
                                }
                            }
                        }
                    }
                }

                if !completedAnalyses.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("Recent Analyses")

                        LazyVStack(spacing: 10) {
                            ForEach(completedAnalyses) { analysis in
                                NavigationLink {
                                    SwingDetailView(swing: analysis.swing)
                                } label: {
                                    RecentAnalysisRow(analysis: analysis)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal, 2)
    }

    // MARK: - Actions

    private func addSelectedSwingsAndAnalyze() {
        let swings = library.swings.filter { selectedSwingIDs.contains($0.id) }
        showSwingPicker = false
        selectedSwingIDs.removeAll()
        startAnalysis(for: swings)
    }

    private func loadSavedAnalyses() {
        let savedCards = library.swings.compactMap { swing -> SwingAnalysis? in
            guard let saved = analysisLibrary.analysis(for: swing) else { return nil }
            return SwingAnalysis(
                swing: swing,
                status: .complete,
                result: AnalysisResult(savedAnalysis: saved)
            )
        }

        let activeCards = analyses.filter {
            if case .complete = $0.status {
                return false
            }
            return true
        }

        analyses = activeCards + savedCards
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
                    analyses[i].progressText = "Preparing video..."
                    analyses[i].progress = nil
                }

                do {
                    // Real API call
                    let response = try await SwingCoachAPI.shared.analyzeSwing(analyses[i].swing) { stage, progress in
                        Task { @MainActor in
                            guard analyses.indices.contains(i) else { return }
                            analyses[i].progressText = stage
                            analyses[i].progress = progress
                        }
                    }

                    let savedAnalysis = await MainActor.run {
                        analysisLibrary.save(response, for: analyses[i].swing)
                    }
                    let result = AnalysisResult(savedAnalysis: savedAnalysis)

                    await MainActor.run {
                        analyses[i].result = result
                        analyses[i].status = .complete
                        analyses[i].progressText = nil
                        analyses[i].progress = nil
                    }

                    library.markAnalyzed(analyses[i].swing)

                } catch {
                    await MainActor.run {
                        analyses[i].status = .failed(SwingCoachAPI.displayMessage(for: error))
                        analyses[i].progressText = nil
                        analyses[i].progress = nil
                    }
                }
            }

            await MainActor.run {
                isAnalyzing = false
            }
        }
    }
}

// MARK: - Coach Dashboard Rows

struct AnalysisQueueRow: View {
    let analysis: SwingAnalysis
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            swingThumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(analysis.swing.vantage.displayName)
                    .font(.subheadline.weight(.semibold))

                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            trailingControl
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }

    private var swingThumbnail: some View {
        Group {
            if let thumbnail = analysis.swing.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.2)
                    .overlay {
                        Image(systemName: "film")
                            .foregroundColor(.secondary)
                    }
            }
        }
        .frame(width: 68, height: 48)
        .clipped()
        .cornerRadius(6)
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch analysis.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundColor(.secondary)
        case .analyzing:
            if let progress = analysis.progress {
                ProgressView(value: Double(progress))
                    .frame(width: 42)
            } else {
                ProgressView()
            }
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise")
                    .font(.headline)
            }
            .buttonStyle(.bordered)
        }
    }

    private var statusText: String {
        switch analysis.status {
        case .pending:
            return "Waiting to start"
        case .analyzing:
            if let progressText = analysis.progressText {
                if let progress = analysis.progress {
                    return "\(progressText) \(Int(progress * 100))%"
                }
                return progressText
            }
            return "Analyzing swing"
        case .complete:
            return "Complete"
        case .failed:
            return "Failed. Tap retry to run this swing again."
        }
    }
}

struct RecentAnalysisRow: View {
    let analysis: SwingAnalysis

    var body: some View {
        HStack(spacing: 12) {
            swingThumbnail

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(analysis.swing.vantage.displayName)
                        .font(.subheadline.weight(.semibold))

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(Color(uiColor: .tertiaryLabel))
                }

                if let summary = analysis.result?.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Text(formatDate(analysis.swing.createdAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }

    private var swingThumbnail: some View {
        Group {
            if let thumbnail = analysis.swing.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.2)
                    .overlay {
                        Image(systemName: "film")
                            .foregroundColor(.secondary)
                    }
            }
        }
        .frame(width: 76, height: 56)
        .clipped()
        .cornerRadius(6)
        .overlay(alignment: .topLeading) {
            Text(analysis.swing.vantage.shortName)
                .font(.caption2.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.58))
                .cornerRadius(4)
                .padding(5)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
                    AnalysisResultView(result: result)
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
                Text("We couldn't finish this swing analysis. Open details for the exact error, then try again.")
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

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
