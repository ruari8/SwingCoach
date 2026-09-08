import AVKit
import SwiftUI

struct AutoSwingReviewPresentation: Identifiable {
    let id = UUID()
}

struct AutoSwingReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let swings: [SavedSwing]
    let onDelete: @MainActor (SavedSwing) async throws -> Void

    @State private var selectedSwingID: UUID?
    @State private var swingPendingDeletion: SavedSwing?
    @State private var deletionError: ReviewDeletionError?
    @State private var isDeleting = false
    @State private var controlsLocked = false

    init(swings: [SavedSwing], onDelete: @escaping @MainActor (SavedSwing) async throws -> Void) {
        self.swings = swings
        self.onDelete = onDelete
        // Capture appends clips chronologically. Every presentation starts at
        // the newest clip while earlier swings remain a swipe to the right away.
        _selectedSwingID = State(initialValue: swings.last?.id)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if swings.isEmpty {
                ContentUnavailableView(
                    "No Session Swings",
                    systemImage: "figure.golf",
                    description: Text("New Auto-captured swings will appear here.")
                )
                .foregroundStyle(.white)
            } else {
                SwingReviewPager(swings: swings, selection: $selectedSwingID, pagingEnabled: !isDeleting,
                                 title: { $0.title ?? "Swing video" }) { swing in
                    AutoSwingReviewPage(
                        swing: swing,
                        isSelected: selectedSwingID == swing.id,
                        deleteDisabled: isDeleting,
                        controlsLocked: $controlsLocked,
                        onDelete: { swingPendingDeletion = swing }
                    )
                }
            }

            // Only the close button and page label live up top; the player's
            // own corner controls occupy the top-right, and delete sits in the
            // player's bottom-right accessory slot.
            reviewToolbar
        }
        .onChange(of: swings.map(\.id)) { _, ids in
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
                closeButton
                    .frame(width: 70)
                    .accessibilityLabel("Close swing review")

                Spacer()

                Text(pageLabel)
                    .accessibilityIdentifier("swing-position")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.48)))

                Spacer()

                // Balances the close button so the page label stays centered.
                Color.clear
                    .frame(width: 70, height: 36)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Spacer()
        }
    }

    private var pageLabel: String {
        guard let selectedSwingID,
              let index = swings.firstIndex(where: { $0.id == selectedSwingID })
        else {
            return "0 of \(swings.count)"
        }
        return "\(index + 1) of \(swings.count)"
    }

    @ViewBuilder
    private var closeButton: some View {
        let button = Button("Done") { dismiss() }
            .font(.subheadline.weight(.semibold))
            .tint(.white)
        if #available(iOS 26, *) {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }

    private func delete(_ swing: SavedSwing) {
        isDeleting = true
        let index = swings.firstIndex { $0.id == swing.id } ?? 0
        let remaining = swings.filter { $0.id != swing.id }
        let nextID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        Task { @MainActor in
            do {
                try await onDelete(swing)
                if selectedSwingID == swing.id { selectedSwingID = nextID }
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
    let isSelected: Bool
    let deleteDisabled: Bool
    @Binding var controlsLocked: Bool
    let onDelete: () -> Void

    @State private var playerItem: AVPlayerItem?

    var body: some View {
        Group {
            if let playerItem {
                PlaybackChromeView(
                    playerItem: playerItem,
                    playbackEnabled: isSelected,
                    showsSpeedControls: true,
                    startsPlaying: false,
                    allowsFullscreen: false,
                    allowsTransportGestures: true,
                    edgeToEdge: true,
                    controlsLocked: $controlsLocked
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
            let item = await SwingLibrary.shared.getPlayerItem(for: swing)
            guard !Task.isCancelled else { return }
            playerItem = item
        }
    }
}

private struct ReviewDeletionError: Identifiable {
    let id = UUID()
    let message: String
}
