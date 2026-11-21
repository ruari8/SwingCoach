import AVKit
import SwiftUI

struct TrimReviewPresentation: Identifiable {
    let id = UUID()
    let asset: AVAsset
    let clips: [SwingClip]
}

struct TrimReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let asset: AVAsset
    let clips: [SwingClip]
    @Binding var selection: UUID?
    let playbackRate: Float

    private var selectedIndex: Int { clips.firstIndex { $0.id == selection } ?? 0 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SwingReviewPager(swings: clips, selection: $selection) { clip in
                TrimReviewPage(asset: asset, clip: clip, isSelected: selection == clip.id,
                               playbackRate: playbackRate)
            }
            VStack {
                HStack {
                    Button("Done") { dismiss() }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .accessibilityLabel("Close trim review")
                    Spacer()
                    Text("\(selectedIndex + 1) of \(clips.count)")
                        .font(.appLabel)
                        .padding(8)
                        .background(Capsule().fill(.black.opacity(0.48)))
                        .accessibilityIdentifier("swing-position")
                    Spacer()
                    Color.clear.frame(width: 70, height: 36)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                Spacer()
            }
            .tint(.white)
            .foregroundStyle(.white)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trim-full-review")
    }
}

private struct TrimReviewPage: View {
    let asset: AVAsset
    let clip: SwingClip
    let isSelected: Bool
    let playbackRate: Float
    @State private var playerItem: AVPlayerItem?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let playerItem {
                PlaybackChromeView(playerItem: playerItem, initialPlaybackRate: playbackRate,
                                   playbackEnabled: isSelected, startsPlaying: false,
                                   allowsFullscreen: false, edgeToEdge: true) {
                    EmptyView()
                } overlayAccessory: {
                    EmptyView()
                }
            } else if let loadError {
                ContentUnavailableView("Couldn’t Open Swing", systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
                    .foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: clip.id) {
            do {
                let clipAsset = try await TrimClipPreparation.reviewAsset(source: asset, clip: clip)
                guard !Task.isCancelled else { return }
                playerItem = AVPlayerItem(asset: clipAsset)
            } catch {
                guard !Task.isCancelled else { return }
                loadError = error.localizedDescription
            }
        }
    }
}
