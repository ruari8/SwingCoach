//
//  ManualAnnotationCanvas.swift
//  SwingCoach
//
//  Draws a swing's hand-drawn annotations over its video and takes the
//  drags that make new ones.
//

import AVFoundation
import SwiftUI

struct ManualAnnotationCanvasOverlay: View {
    /// Width over height of the video as displayed.
    var sourceAspectRatio: Double? = nil
    let currentTime: CMTime
    let analysisID: String
    let annotations: [ManualAnnotation]
    let draftAnnotation: ManualAnnotation?
    let enabled: Bool
    let editingEnabled: Bool
    let selectedTool: ManualAnnotationTool
    let selectedColorHex: String
    let labelText: String
    let appliesToFullSwing: Bool
    let onDraftChanged: (ManualAnnotation?) -> Void
    let onCommit: (ManualAnnotation) -> Void
    let onErase: (ManualAnnotationPoint, Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let videoRect = contentRect(in: geometry.size)
            Canvas { context, _ in
                guard enabled else { return }
                let seconds = currentSeconds
                for annotation in annotations where annotation.isVisible(at: seconds) {
                    draw(annotation, in: &context, rect: videoRect, isDraft: false)
                }
                if let draftAnnotation {
                    draw(draftAnnotation, in: &context, rect: videoRect, isDraft: true)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: selectedTool == .label || selectedTool == .eraser ? 0 : 4)
                    .onChanged { value in
                        guard editingEnabled, videoRect.contains(value.startLocation) else { return }
                        updateDraft(with: value, rect: videoRect)
                    }
                    .onEnded { value in
                        guard editingEnabled, videoRect.contains(value.startLocation) else { return }
                        finishDraft(with: value, rect: videoRect)
                    }
            )
        }
        .allowsHitTesting(editingEnabled)
    }

    private var currentSeconds: Double {
        let seconds = CMTimeGetSeconds(currentTime)
        return seconds.isFinite ? seconds : 0
    }

    private func contentRect(in size: CGSize) -> CGRect {
        let sourceAspect: CGFloat
        if let sourceAspectRatio, sourceAspectRatio.isFinite, sourceAspectRatio > 0 {
            sourceAspect = CGFloat(sourceAspectRatio)
        } else {
            sourceAspect = size.width / max(size.height, 1)
        }
        return VideoDisplayGeometry.contentRect(in: size, aspectRatio: Double(sourceAspect))
    }

    private func normalizedPoint(_ point: CGPoint, in rect: CGRect) -> ManualAnnotationPoint {
        ManualAnnotationPoint(
            x: Double(min(max((point.x - rect.minX) / max(rect.width, 1), 0), 1)),
            y: Double(min(max((point.y - rect.minY) / max(rect.height, 1), 0), 1))
        )
    }

    private func screenPoint(_ point: ManualAnnotationPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + CGFloat(point.x) * rect.width,
            y: rect.minY + CGFloat(point.y) * rect.height
        )
    }

    private func updateDraft(with value: DragGesture.Value, rect: CGRect) {
        let start = normalizedPoint(value.startLocation, in: rect)
        let current = normalizedPoint(value.location, in: rect)

        if selectedTool == .eraser {
            onErase(current, currentSeconds)
            return
        }

        if selectedTool == .label {
            onDraftChanged(
                ManualAnnotation(
                    analysisID: analysisID,
                    tool: .label,
                    points: [current],
                    text: labelText.isEmpty ? "Note" : labelText,
                    colorHex: selectedColorHex,
                    strokeWidth: 3,
                    timestamp: currentSeconds,
                    appliesToFullSwing: appliesToFullSwing
                )
            )
            return
        }

        if selectedTool == .freehand {
            var points = draftAnnotation?.points ?? [start]
            if points.last != current {
                points.append(current)
            }
            onDraftChanged(makeDraft(tool: .freehand, points: points))
            return
        }

        onDraftChanged(makeDraft(tool: selectedTool, points: [start, current]))
    }

    private func finishDraft(with value: DragGesture.Value, rect: CGRect) {
        if selectedTool == .eraser {
            onErase(normalizedPoint(value.location, in: rect), currentSeconds)
            onDraftChanged(nil)
            return
        }

        if selectedTool == .label {
            let point = normalizedPoint(value.location, in: rect)
            onCommit(
                ManualAnnotation(
                    analysisID: analysisID,
                    tool: .label,
                    points: [point],
                    text: labelText.isEmpty ? "Note" : labelText,
                    colorHex: selectedColorHex,
                    strokeWidth: 3,
                    timestamp: currentSeconds,
                    appliesToFullSwing: appliesToFullSwing
                )
            )
            return
        }

        if let draftAnnotation, draftAnnotation.points.count >= 2 {
            onCommit(draftAnnotation)
        }
        onDraftChanged(nil)
    }

    private func makeDraft(tool: ManualAnnotationTool, points: [ManualAnnotationPoint]) -> ManualAnnotation {
        ManualAnnotation(
            analysisID: analysisID,
            tool: tool,
            points: points,
            colorHex: selectedColorHex,
            strokeWidth: 3,
            timestamp: currentSeconds,
            appliesToFullSwing: appliesToFullSwing
        )
    }

    private func draw(
        _ annotation: ManualAnnotation,
        in context: inout GraphicsContext,
        rect: CGRect,
        isDraft: Bool
    ) {
        let color = Color(hex: annotation.colorHex).opacity(isDraft ? 0.72 : 1.0)
        let points = annotation.points.map { screenPoint($0, in: rect) }
        let stroke = StrokeStyle(lineWidth: CGFloat(annotation.strokeWidth), lineCap: .round, lineJoin: .round)

        switch annotation.tool {
        case .line, .arrow:
            guard points.count >= 2 else { return }
            var path = Path()
            path.move(to: points[0])
            path.addLine(to: points[1])
            context.stroke(path, with: .color(color), style: stroke)
            if annotation.tool == .arrow {
                drawManualArrowHead(from: points[0], to: points[1], color: color, in: &context)
            }

        case .freehand:
            guard points.count >= 2 else { return }
            var path = Path()
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(color), style: stroke)

        case .rectangle:
            guard points.count >= 2 else { return }
            let drawRect = CGRect(
                x: min(points[0].x, points[1].x),
                y: min(points[0].y, points[1].y),
                width: abs(points[1].x - points[0].x),
                height: abs(points[1].y - points[0].y)
            )
            context.stroke(Path(roundedRect: drawRect, cornerRadius: 4), with: .color(color), style: stroke)

        case .circle:
            guard points.count >= 2 else { return }
            let radius = hypot(points[1].x - points[0].x, points[1].y - points[0].y)
            let circle = CGRect(x: points[0].x - radius, y: points[0].y - radius, width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: circle), with: .color(color), style: stroke)

        case .label:
            guard let point = points.first else { return }
            let text = Text(annotation.text ?? "Note")
                .font(FixedType.readout)
                .foregroundColor(color)
            context.draw(text, at: point)

        case .eraser:
            return
        }
    }

    private func drawManualArrowHead(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 14
        let spread: CGFloat = .pi / 7
        let p1 = CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread))
        let p2 = CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread))
        var path = Path()
        path.move(to: end)
        path.addLine(to: p1)
        path.move(to: end)
        path.addLine(to: p2)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
    }
}

private extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64
        switch sanitized.count {
        case 6:
            red = (value >> 16) & 0xFF
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
        default:
            red = 255
            green = 214
            blue = 10
        }

        self.init(
            .sRGB,
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0,
            opacity: 1.0
        )
    }
}
