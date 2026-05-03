//
//  AnalysisResultView.swift
//  SwingCoach
//
//  Shared rendering for completed swing analysis results.
//

import SwiftUI
import AVFoundation

struct AnalysisResultView: View {
    let result: AnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let annotatedVideo = result.annotatedVideo {
                AnnotatedAnalysisVideo(video: annotatedVideo, analysisID: result.analysisID)
            }

            if !result.metrics.isEmpty {
                metricsSection
            }

            coachNotesSection

            if !result.drills.isEmpty {
                drillsSection
            }
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metrics")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            ForEach(result.metrics, id: \.key) { metric in
                HStack(alignment: .firstTextBaseline) {
                    Text(metric.name)
                        .font(.subheadline)

                    Spacer(minLength: 12)

                    Text(metric.value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private var coachNotesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Coach Notes")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            Text(result.summary)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var drillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommendations")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            ForEach(result.drills, id: \.title) { drill in
                VStack(alignment: .leading, spacing: 3) {
                    Text(drill.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)

                    Text(drill.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }
        }
    }
}

struct AnnotatedAnalysisVideo: View {
    let video: SavedAnalysisVideo
    let analysisID: String

    @State private var playerItem: AVPlayerItem?
    @State private var errorMessage: String?

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
                    if let errorMessage {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    } else {
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
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            prepareVideo()
        }
        .onChange(of: video.url) { _, _ in
            playerItem = nil
            errorMessage = nil
            prepareVideo()
        }
    }

    private func prepareVideo() {
        guard playerItem == nil else { return }

        if Date().timeIntervalSince(video.refreshedAt) > 45 * 60 {
            Task {
                do {
                    let refreshed = try await SwingCoachAPI.shared.refreshArtifactURL(key: video.key)
                    await MainActor.run {
                        AnalysisLibrary.shared.updateAnnotatedVideoURL(
                            for: analysisID,
                            url: refreshed.url
                        )
                        loadPlayer(urlString: refreshed.url)
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Could not refresh annotated video."
                    }
                }
            }
        } else {
            loadPlayer(urlString: video.url)
        }
    }

    private func loadPlayer(urlString: String) {
        guard let url = URL(string: urlString) else {
            errorMessage = "Annotated video link is invalid."
            return
        }
        playerItem = AVPlayerItem(url: url)
    }
}
