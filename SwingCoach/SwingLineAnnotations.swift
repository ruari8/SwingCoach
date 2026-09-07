import AVFoundation
import SwiftUI

extension SavedSwing {
    // Preserve the key used by Library before Auto review supported drawings.
    var manualAnnotationID: String { "swing-\(id.uuidString)" }
}

/// Original-video line tools shared by Library and Auto review.
struct SwingLineControls: View {
    let annotationID: String
    @Binding var isDrawing: Bool
    @Binding var draft: ManualAnnotation?
    @ObservedObject private var manualStore = ManualAnnotationStore.shared

    var body: some View {
        VStack(spacing: 8) {
            Button {
                isDrawing.toggle()
                draft = nil
            } label: {
                Image(systemName: isDrawing ? "checkmark" : "pencil.and.outline")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isDrawing ? .black : .white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(isDrawing ? Color.yellow : Color.black.opacity(0.54)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDrawing ? "Finish drawing lines" : "Draw straight lines")

            if isDrawing, !manualStore.annotations(for: annotationID).isEmpty {
                Button {
                    manualStore.undoLast(for: annotationID)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.black.opacity(0.54)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo last line")

                Button {
                    manualStore.clear(for: annotationID)
                    draft = nil
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.red.opacity(0.72)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear all lines")
            }
        }
        .padding(6)
        .background(Capsule().fill(Color.black.opacity(0.34)))
    }
}

struct SwingLineOverlay: View {
    let swing: SavedSwing
    let aspectRatio: Double?
    let currentTime: CMTime
    let isDrawing: Bool
    @Binding var draft: ManualAnnotation?
    @ObservedObject private var manualStore = ManualAnnotationStore.shared

    var body: some View {
        ManualAnnotationCanvasOverlay(
            tracks: nil,
            sourceAspectRatio: aspectRatio,
            currentTime: currentTime,
            analysisID: swing.manualAnnotationID,
            annotations: manualStore.annotations(for: swing.manualAnnotationID),
            draftAnnotation: draft,
            enabled: aspectRatio != nil,
            editingEnabled: isDrawing,
            selectedTool: .line,
            selectedColorHex: "#FFD60A",
            labelText: "",
            appliesToFullSwing: true,
            onDraftChanged: { draft = $0 },
            onCommit: { annotation in
                manualStore.add(annotation)
                draft = nil
            },
            onErase: { _, _ in }
        )
    }
}
