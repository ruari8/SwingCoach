import AVFoundation
import SwiftUI

extension SavedSwing {
    // Preserve the key used by Library before Auto review supported drawings.
    var manualAnnotationID: String { "swing-\(id.uuidString)" }
}

/// Line tools shown while drawing on the original video, shared by Library
/// and Auto review. The player's tool rail starts drawing; Done ends it.
struct SwingLineControls: View {
    let annotationID: String
    @Binding var isDrawing: Bool
    @Binding var draft: ManualAnnotation?
    @ObservedObject private var manualStore = ManualAnnotationStore.shared

    var body: some View {
        if isDrawing {
            HStack(spacing: 4) {
                Label("Line", systemImage: "line.diagonal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 11)
                    .frame(height: 36)
                    .background(Capsule().fill(Color.white))
                    .accessibilityHidden(true)

                if !manualStore.annotations(for: annotationID).isEmpty {
                    Button {
                        manualStore.undoLast(for: annotationID)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
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
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.red.opacity(0.72)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear all lines")
                }

                Button {
                    isDrawing = false
                    draft = nil
                } label: {
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Capsule().fill(Color.swingPositionAccent))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Finish drawing lines")
            }
            .padding(4)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Capsule().fill(Color.black.opacity(0.35)))
            .environment(\.colorScheme, .dark)
        }
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

/// The selected page owns its draft; review renders the bar outside the scroll strip.
struct SwingLineControlsKey: PreferenceKey {
    static var defaultValue: AnyView? { nil }

    static func reduce(value: inout AnyView?, nextValue: () -> AnyView?) {
        value = nextValue() ?? value
    }
}
