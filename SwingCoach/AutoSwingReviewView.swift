import AVKit
import SwiftUI

struct AutoSwingReviewPresentation: Identifiable {
    let id = UUID()
}

struct AutoSwingReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var camera: CameraSession

    @State private var selectedSwingID: UUID?
    @State private var swingPendingDeletion: SavedSwing?
    @State private var deletionError: ReviewDeletionError?
    @State private var isDeleting = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.autoSessionSwings.isEmpty {
                ContentUnavailableView(
                    "No Session Swings",
                    systemImage: "figure.golf",
                    description: Text("New Auto-captured swings will appear here.")
                )
                .foregroundStyle(.white)
            } else {
                TabView(selection: $selectedSwingID) {
                    ForEach(camera.autoSessionSwings) { swing in
                        AutoSwingReviewPage(
                            swing: swing,
                            deleteDisabled: isDeleting,
                            onDelete: { swingPendingDeletion = swing }
                        )
                        .tag(swing.id as UUID?)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            }

            // Only the close button and page label live up top; the player's
            // own corner controls occupy the top-right, and delete sits in the
            // player's bottom-right accessory slot.
            reviewToolbar
        }
        .onAppear {
            selectedSwingID = selectedSwingID ?? camera.autoSessionSwings.first?.id
        }
        .onChange(of: camera.autoSessionSwings.map(\.id)) { _, ids in
            if let selectedSwingID, ids.contains(selectedSwingID) { return }
            self.selectedSwingID = ids.first
        }
        .confirmationDialog(
            "Delete this swing?",
            isPresented: Binding(
                get: { swingPendingDeletion != nil },
                set: { if !$0 { swingPendingDeletion = nil } }
            ),
            presenting: swingPendingDeletion
        ) { swing in
            Button("Delete from SwingCoach and Photos", role: .destructive) {
                delete(swing)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This permanently removes the video from this phone's Photos library.")
        }
        .alert(item: $deletionError) { error in
            Alert(
                title: Text("Couldn’t Delete Swing"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var reviewToolbar: some View {
        VStack {
            HStack {
                circleButton(systemName: "xmark") { dismiss() }
                    .accessibilityLabel("Close swing review")

                Spacer()

                Text(pageLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.48)))

                Spacer()

                // Balances the close button so the page label stays centered.
                Color.clear
                    .frame(width: 42, height: 42)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Spacer()
        }
    }

    private var pageLabel: String {
        guard let selectedSwingID,
              let index = camera.autoSessionSwings.firstIndex(where: { $0.id == selectedSwingID })
        else {
            return "0 of \(camera.autoSessionSwings.count)"
        }
        return "\(index + 1) of \(camera.autoSessionSwings.count)"
    }

    private func circleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(.black.opacity(0.48)))
        }
        .buttonStyle(.plain)
    }

    private func delete(_ swing: SavedSwing) {
        isDeleting = true
        Task { @MainActor in
            do {
                try await camera.deleteAutoCapturedSwing(swing)
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
    let deleteDisabled: Bool
    let onDelete: () -> Void

    @State private var playerItem: AVPlayerItem?

    var body: some View {
        Group {
            if let playerItem {
                PlaybackChromeView(
                    playerItem: playerItem,
                    playbackEnabled: true,
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
                    }
                    .buttonStyle(.plain)
                    .disabled(deleteDisabled)
                    .accessibilityLabel("Delete this swing")
                }
            } else {
                ProgressView()
                    .scaleEffect(1.35)
                    .tint(.white)
            }
        }
        .task(id: swing.id) {
            playerItem = await SwingLibrary.shared.getPlayerItem(for: swing)
        }
    }
}

private struct ReviewDeletionError: Identifiable {
    let id = UUID()
    let message: String
}
