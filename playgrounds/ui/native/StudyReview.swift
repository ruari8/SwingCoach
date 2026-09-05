import SwiftUI
import AVKit

// Minimal fixture type for the unchanged shared pager. No Photos or persistence.
struct SavedSwing: Identifiable, Equatable {
    let id = UUID()
    let title: String?
    let url: URL
    static func samples() -> [SavedSwing] {
        (1...3).map { sample(number: $0) }
    }
    static func sample(number: Int) -> SavedSwing {
        SavedSwing(title: "Sample swing \(number)", url: Bundle.main.url(forResource: String(format: "sample-%03d", (number - 1) % 3 + 1), withExtension: "mp4")!)
    }
}

struct StudyReview: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var swings: [SavedSwing]
    @State private var selectedID: UUID?
    @State private var pendingDelete: SavedSwing?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if swings.isEmpty {
                VStack(spacing: 14) {
                    Text("No saved swings").font(.title2.weight(.semibold))
                    Text("Return to the camera to capture more.").foregroundStyle(.secondary)
                    Button("Done") { dismiss() }.buttonStyle(.glass)
                }
            } else {
                SwingReviewPager(swings: swings, selection: $selectedID, pagingEnabled: pendingDelete == nil) { swing in
                    StudyReviewPage(swing: swing, isSelected: selectedID == swing.id) {
                        pendingDelete = swing
                    }
                }
                VStack {
                    HStack {
                        Button("Done") { dismiss() }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.glass).tint(.white)
                            .frame(width: 70)
                        Spacer()
                        Text(position).font(.subheadline.weight(.medium))
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background(.black.opacity(0.45), in: Capsule())
                            .accessibilityIdentifier("swing-position")
                        Spacer()
                        Color.clear.frame(width: 70, height: 36)
                    }.padding(.horizontal, 14).padding(.top, 8)
                    Spacer()
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear { selectedID = selectedID ?? swings.first?.id }
        .confirmationDialog("Delete this sample swing?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { swing in
            Button("Remove sample from session", role: .destructive) {
                let index = swings.firstIndex(where: { $0.id == swing.id }) ?? 0
                swings.removeAll { $0.id == swing.id }
                selectedID = swings.isEmpty ? nil : swings[min(index, swings.count - 1)].id
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("Prototype only. The original video and your Photos library stay untouched.")
        }
    }

    private var position: String {
        let index = swings.firstIndex(where: { $0.id == selectedID }) ?? 0
        return "\(index + 1) of \(swings.count)"
    }
}

private struct StudyReviewPage: View {
    let swing: SavedSwing
    let isSelected: Bool
    let onDelete: () -> Void
    @State private var item: AVPlayerItem?

    var body: some View {
        Group {
            if let item {
                PlaybackChromeView(
                    playerItem: item,
                    playbackEnabled: isSelected,
                    showsSpeedControls: true,
                    startsPlaying: false,
                    allowsFullscreen: false,
                    allowsTransportGestures: true,
                    edgeToEdge: true,
                    allowsLock: false
                ) {
                    EmptyView()
                } overlayAccessory: {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(.black.opacity(0.48)))
                    }.buttonStyle(.plain).accessibilityLabel("Delete this swing")
                }
            } else { ProgressView().tint(.white) }
        }
        .task(id: swing.id) { item = AVPlayerItem(url: swing.url) }
    }
}
