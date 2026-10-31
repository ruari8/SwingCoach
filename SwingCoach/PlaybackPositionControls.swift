//
//  PlaybackPositionControls.swift
//  SwingCoach
//
//  Player pieces for P1-P10 quick navigation and the player's tool rail:
//  the scrubber mapping, the pose strip, and the foldable, dockable rail.
//  Design study: playgrounds/ui/web/positions.html.
//

import SwiftUI
import UIKit

// MARK: - Scrubber mapping

/// Maps clip time to scrubber position. With positions, each stretch between
/// neighbouring positions gets width in proportion to the square root of its
/// length, so the short downswing stretches open up without the long
/// follow-through collapsing. Without positions the mapping is linear.
nonisolated struct PositionScrubMapping: Equatable {
    /// Clip seconds at each segment edge: 0, P1...P10, duration.
    let times: [Double]
    /// Scrubber fraction (0...1) at each segment edge.
    let fractions: [Double]

    /// Shortest stretch given room, so positions that share a frame stay apart.
    static let minimumSegment = 1.0 / 120
    /// The lead-in before P1 and the tail after P10 get less room.
    static let edgeWeight = 0.6

    init(duration: Double, positionTimes: [Double]? = nil) {
        let end = max(duration, 0)
        guard end > 0, let positionTimes, !positionTimes.isEmpty,
              zip(positionTimes, positionTimes.dropFirst()).allSatisfy({ $0 <= $1 }),
              positionTimes.allSatisfy({ $0.isFinite }) else {
            times = [0, end]
            fractions = [0, 1]
            return
        }
        let edges = [0] + positionTimes.map { min(max($0, 0), end) } + [end]
        var weights: [Double] = []
        for index in 0..<(edges.count - 1) {
            var weight = max(edges[index + 1] - edges[index], Self.minimumSegment).squareRoot()
            if index == 0 || index == edges.count - 2 { weight *= Self.edgeWeight }
            weights.append(weight)
        }
        let total = weights.reduce(0, +)
        var running = 0.0
        var fractions = [0.0]
        for weight in weights {
            running += weight / total
            fractions.append(running)
        }
        fractions[fractions.count - 1] = 1
        times = edges
        self.fractions = fractions
    }

    func fraction(at time: Double) -> Double {
        guard let last = times.last, last > 0 else { return 0 }
        let time = min(max(time, 0), last)
        for index in 0..<(times.count - 1) where time <= times[index + 1] {
            let span = times[index + 1] - times[index]
            let local = span > 0 ? (time - times[index]) / span : 0
            return fractions[index] + local * (fractions[index + 1] - fractions[index])
        }
        return 1
    }

    func time(at fraction: Double) -> Double {
        let fraction = min(max(fraction, 0), 1)
        for index in 0..<(fractions.count - 1) where fraction <= fractions[index + 1] {
            let span = fractions[index + 1] - fractions[index]
            let local = span > 0 ? (fraction - fractions[index]) / span : 0
            return times[index] + local * (times[index + 1] - times[index])
        }
        return times.last ?? 0
    }
}

// MARK: - Pose glyphs

/// Original stick-figure poses for P1-P10, drawn in a design grid
/// (viewBox 4 3 32 36): head, neck, hip, trail shoulder, lead shoulder,
/// hands, clubhead, trail knee, trail foot, lead knee, lead foot, ball.
private enum SwingPositionGlyphData {
    typealias Pose = [CGPoint?]

    static func pose(_ number: Int) -> Pose {
        poses[min(max(number, 1), poses.count) - 1].map { pair in pair.map { CGPoint(x: $0[0], y: $0[1]) } }
    }

    private static let poses: [[[CGFloat]?]] = [
        [[20, 8.6], [20, 13], [20, 24], [16.8, 14.2], [23.2, 13.8], [20.6, 26], [18.4, 36.4], [16.6, 30.6], [15.6, 37], [23.4, 30.6], [24.4, 37], [19, 37.2]],
        [[19.8, 8.6], [19.8, 13], [20, 24], [17.6, 13.4], [22.2, 14.6], [16.6, 25.6], [6.4, 25.2], [16.6, 30.6], [15.6, 37], [23, 30.8], [24.4, 37], [19, 37.2]],
        [[19.6, 8.6], [19.6, 13], [19.8, 24], [18, 13.2], [21.4, 14.8], [11.2, 18.4], [9.6, 6.6], [16.4, 30.6], [15.6, 37], [22.2, 31], [24.4, 37], [19, 37.2]],
        [[19.4, 8.8], [19.4, 13.2], [19.6, 24], [17.8, 13], [21, 15], [14, 8.2], [28.6, 4.6], [16.4, 30.6], [15.6, 37], [21.8, 31.2], [24.4, 37], [19, 37.2]],
        [[19.6, 8.8], [19.8, 13.2], [21, 24.2], [17.4, 13.6], [22, 14.8], [12.8, 19.6], [13.2, 7.4], [17, 30.8], [15.6, 37], [24, 30.6], [24.4, 37], [19, 37.2]],
        [[19.8, 9], [20, 13.4], [21.6, 24.4], [17.2, 14.4], [22.8, 14.2], [16.8, 25], [7.2, 21.6], [17.6, 31], [15.8, 37], [24.4, 30.6], [24.4, 37], [19, 37.2]],
        [[19.4, 9], [20, 13.4], [22.6, 24], [17.4, 15], [23.6, 13.8], [23, 26.4], [20.4, 36.4], [20.2, 30.6], [17.2, 35.8], [25.4, 30.4], [25, 37], [26.5, 35.6]],
        [[20.2, 9.2], [20.6, 13.4], [22.2, 24], [18.6, 14.6], [23.4, 13.6], [25.6, 24.8], [35, 22.6], [19.6, 31], [17.4, 36.4], [24.6, 30.6], [24.4, 37], nil],
        [[20.6, 9], [21, 13.2], [22.2, 24], [19.2, 14.2], [23.4, 13.2], [29, 17.4], [30.6, 5.8], [20, 31], [17.6, 36.2], [24.6, 30.6], [24.4, 37], nil],
        [[22.2, 8.2], [22.2, 12.4], [22.4, 23.6], [20, 13], [24.6, 12.6], [25.4, 6.8], [11.4, 12.8], [21.6, 30.4], [18.4, 36.2], [24.4, 30.2], [24.6, 37], nil],
    ]
}

struct SwingPositionGlyph: View {
    let number: Int
    var figure: Color = .white
    var club: Color = .swingPositionAccent

    var body: some View {
        Canvas { context, size in
            let joints = SwingPositionGlyphData.pose(number)
            let scale = min(size.width / 32, size.height / 36)
            let origin = CGPoint(x: (size.width - 32 * scale) / 2, y: (size.height - 36 * scale) / 2)
            func point(_ index: Int) -> CGPoint {
                let joint = joints[index] ?? .zero
                return CGPoint(x: origin.x + (joint.x - 4) * scale, y: origin.y + (joint.y - 3) * scale)
            }
            func dot(_ center: CGPoint, radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: center.x - radius * scale, y: center.y - radius * scale,
                                       width: radius * 2 * scale, height: radius * 2 * scale))
            }
            func polyline(_ indices: [Int]) -> Path {
                var path = Path()
                path.addLines(indices.map(point))
                return path
            }
            let stroke = { (width: CGFloat) in StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round) }

            if joints[11] != nil {
                context.fill(dot(point(11), radius: 1.1), with: .color(figure.opacity(0.75)))
            }
            context.stroke(polyline([5, 6]), with: .color(club), style: stroke(2.1))
            context.fill(dot(point(6), radius: 1.4), with: .color(club))
            context.stroke(polyline([8, 7, 2, 9, 10]), with: .color(figure), style: stroke(3.1))
            context.stroke(polyline([1, 2]), with: .color(figure), style: stroke(3.1))
            context.stroke(polyline([5, 3, 1, 4, 5]), with: .color(figure), style: stroke(2.6))
            context.fill(dot(point(0), radius: 3.6), with: .color(figure))
        }
        .accessibilityHidden(true)
    }
}

extension Color {
    /// Lime used for swing positions: the pose strip's clubs and the positions toggle.
    static let swingPositionAccent = Color(red: 0.847, green: 0.953, blue: 0.416)
}

// MARK: - Pose strip

/// Ten pose chips for jumping straight to a position. Dragging across the
/// strip moves one whole position per chip, however many frames apart they are.
struct SwingPositionStrip: View {
    let positions: [SwingPosition]
    let selectedNumber: Int?
    let onSelect: (SwingPosition) -> Void

    @State private var draggedIndex: Int?

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array(positions.enumerated()), id: \.element.number) { index, position in
                    chip(position)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !positions.isEmpty, geometry.size.width > 0 else { return }
                        let raw = Int(value.location.x / geometry.size.width * CGFloat(positions.count))
                        let index = min(max(raw, 0), positions.count - 1)
                        guard index != draggedIndex else { return }
                        if draggedIndex != nil { UISelectionFeedbackGenerator().selectionChanged() }
                        draggedIndex = index
                        onSelect(positions[index])
                    }
                    .onEnded { _ in draggedIndex = nil }
            )
        }
        .frame(height: 56)
        .padding(.horizontal, 2)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Capsule().fill(Color.black.opacity(0.2)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("swing-position-strip")
    }

    private func chip(_ position: SwingPosition) -> some View {
        let selected = position.number == selectedNumber
        let unsure = position.confidence < 0.5
        return VStack(spacing: 0) {
            SwingPositionGlyph(
                number: position.number,
                figure: selected ? .black : .white,
                club: selected ? Color(red: 0.36, green: 0.49, blue: 0) : .swingPositionAccent
            )
            .frame(width: 30, height: 30)

            // Below 0.5 the model found no clear peak for this position.
            Text(unsure ? "\(position.label)?" : position.label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(selected ? .black : .white.opacity(0.75))
        }
        .frame(width: 34, height: 46)
        .background(Capsule().fill(selected ? Color.white : Color.clear))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("swing-position-\(position.label)")
        .accessibilityLabel("\(position.label), \(position.name)\(unsure ? ", unsure" : "")")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onSelect(position) }
    }
}

/// Toggle icon for showing positions: a scrubber line with marks under it.
struct PositionMarksIcon: View {
    var color: Color = .white

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 24
            var line = Path()
            line.move(to: CGPoint(x: 3 * unit, y: 10 * unit))
            line.addLine(to: CGPoint(x: 21 * unit, y: 10 * unit))
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2.1 * unit, lineCap: .round))
            for x in [5.5, 10.5, 13.5, 18.5] {
                let radius = 1.5 * unit
                context.fill(Path(ellipseIn: CGRect(x: x * unit - radius, y: 16 * unit - radius,
                                                    width: radius * 2, height: radius * 2)), with: .color(color))
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

// MARK: - Tool rail

enum PlayerToolSide: String {
    case leading, trailing
}

struct PlayerTool: Identifiable {
    enum Icon {
        case system(String)
        case text(String)
        case positionMarks
    }

    let id: String
    /// Short name shown beside the button when labels flash or on hold.
    let title: String
    let accessibilityLabel: String
    var accessibilityValue: String?
    var isOn = false
    let icon: Icon
    let action: () -> Void
}

/// The player's tool column. It sits under the top-right button by default;
/// dragging the fold button to the other half docks it on the left. Tapping the
/// fold button folds the tools away. Names flash when the tools open, and holding
/// any tool shows its name.
struct PlayerToolRail: View {
    let tools: [PlayerTool]
    /// Distance from the container top to the fold button on each side.
    let trailingTop: CGFloat
    let leadingTop: CGFloat

    @AppStorage("playerToolRailSide") private var side: PlayerToolSide = .trailing
    @AppStorage("playerToolRailOpen") private var isOpen = true
    @AppStorage("playerToolLabelsIntroduced") private var labelsIntroduced = false

    // Gesture state resets itself if the system cancels the drag; the reset
    // springs, so a docking release animates from where the finger let go.
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.35, dampingFraction: 0.82)))
    private var dragTranslation: CGSize = .zero
    @State private var labelsVisible = false
    @State private var labelsToken = 0
    @State private var peekedToolID: String?

    static let buttonSize: CGFloat = 38
    static let spacing: CGFloat = 10

    private var isDragging: Bool { hypot(dragTranslation.width, dragTranslation.height) > 6 }
    private var dragOffset: CGSize { isDragging ? dragTranslation : .zero }
    /// A single tool is not worth a fold button.
    private var isFoldable: Bool { tools.count > 1 }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let dropSide = targetSide(width: width)
            ZStack(alignment: .topLeading) {
                if isDragging {
                    dockOutline(highlighted: dropSide == .leading)
                        .offset(x: 0, y: leadingTop)
                    dockOutline(highlighted: dropSide == .trailing)
                        .offset(x: width - Self.buttonSize, y: trailingTop)
                }

                column(width: width)
                    .offset(dragOffset)
                    .padding(.top, side == .leading ? leadingTop : trailingTop)
                    .frame(width: width, alignment: side == .leading ? .leading : .trailing)
            }
            .frame(width: width, height: geometry.size.height, alignment: .topLeading)
        }
        .onAppear {
            guard isOpen || !isFoldable, !labelsIntroduced else { return }
            labelsIntroduced = true
            flashLabels(delay: 0.4)
        }
    }

    private func column(width: CGFloat) -> some View {
        VStack(alignment: side == .leading ? .leading : .trailing, spacing: Self.spacing) {
            if isFoldable {
                foldButton(width: width)
            }

            if isOpen || !isFoldable {
                ForEach(tools) { tool in
                    RailToolRow(
                        tool: tool,
                        side: side,
                        showsLabel: (labelsVisible || peekedToolID == tool.id) && !isDragging,
                        peekedToolID: $peekedToolID
                    )
                    .opacity(isDragging ? 0.35 : 1)
                    .transition(.opacity.combined(with: .scale(scale: 0.4, anchor: .top)))
                }
            }
        }
    }

    private func foldButton(width: CGFloat) -> some View {
        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.white)
            .frame(width: Self.buttonSize, height: Self.buttonSize)
            .background(Circle().fill(Color.black.opacity(0.45)))
            .scaleEffect(isDragging ? 1.12 : 1)
            .shadow(color: .black.opacity(isDragging ? 0.45 : 0), radius: 8, y: 3)
            .contentShape(Circle())
            // Global space: the button moves with the finger, so a local
            // translation would stay near zero.
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($dragTranslation) { value, translation, _ in
                        translation = value.translation
                    }
                    .onEnded { value in
                        if hypot(value.translation.width, value.translation.height) > 6 {
                            dock(width: width, translation: value.translation)
                        } else {
                            toggleOpen()
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("player-tools-fold")
            .accessibilityLabel(isOpen ? "Hide player tools" : "Show player tools")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggleOpen() }
            .accessibilityAction(named: side == .leading ? "Move tools to the right" : "Move tools to the left") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    side = side == .leading ? .trailing : .leading
                }
            }
    }

    private func dockOutline(highlighted: Bool) -> some View {
        Circle()
            .strokeBorder(highlighted ? Color.swingPositionAccent : Color.white.opacity(0.7),
                          style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .background(Circle().fill(highlighted ? Color.swingPositionAccent.opacity(0.2) : .clear))
            .frame(width: Self.buttonSize, height: Self.buttonSize)
            .allowsHitTesting(false)
    }

    private func targetSide(width: CGFloat) -> PlayerToolSide {
        let restingCenter = side == .leading ? Self.buttonSize / 2 : width - Self.buttonSize / 2
        return restingCenter + dragOffset.width < width / 2 ? .leading : .trailing
    }

    private func dock(width: CGFloat, translation: CGSize) {
        let restingCenter = side == .leading ? Self.buttonSize / 2 : width - Self.buttonSize / 2
        let newSide: PlayerToolSide = restingCenter + translation.width < width / 2 ? .leading : .trailing
        if newSide != side { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            side = newSide
        }
    }

    private func toggleOpen() {
        withAnimation(.snappy(duration: 0.24)) {
            isOpen.toggle()
        }
        if isOpen {
            flashLabels(delay: 0.15)
        } else {
            labelsVisible = false
        }
    }

    private func flashLabels(delay: Double) {
        labelsToken += 1
        let token = labelsToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard token == labelsToken else { return }
            withAnimation(.easeOut(duration: 0.2)) { labelsVisible = true }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard token == labelsToken else { return }
            withAnimation(.easeIn(duration: 0.3)) { labelsVisible = false }
        }
    }
}

/// One tool: a tap runs it; holding shows its name instead.
private struct RailToolRow: View {
    let tool: PlayerTool
    let side: PlayerToolSide
    let showsLabel: Bool
    @Binding var peekedToolID: String?

    @GestureState private var isPressed = false
    @State private var didPeek = false
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 10) {
            if side == .trailing { label }
            button
            if side == .leading { label }
        }
    }

    private var label: some View {
        Text(tool.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
            .lineLimit(1)
            .fixedSize()
            .opacity(showsLabel ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var button: some View {
        icon
            .foregroundColor(tool.isOn ? .black : .white)
            .frame(width: PlayerToolRail.buttonSize, height: PlayerToolRail.buttonSize)
            .background(Circle().fill(tool.isOn ? Color.swingPositionAccent : Color.black.opacity(0.45)))
            .opacity(isPressed && !didPeek ? 0.6 : 1)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, pressed, _ in pressed = true }
                    .onChanged { _ in
                        guard holdTask == nil else { return }
                        didPeek = false
                        holdTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            guard !Task.isCancelled else { return }
                            // A cancelled gesture never ends, so the task clears itself.
                            holdTask = nil
                            guard isPressed else { return }
                            didPeek = true
                            withAnimation(.easeOut(duration: 0.15)) { peekedToolID = tool.id }
                        }
                    }
                    .onEnded { value in
                        holdTask?.cancel()
                        holdTask = nil
                        if didPeek {
                            let id = tool.id
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 700_000_000)
                                guard peekedToolID == id else { return }
                                withAnimation(.easeIn(duration: 0.25)) { peekedToolID = nil }
                            }
                        } else if hypot(value.translation.width, value.translation.height) < 24 {
                            tool.action()
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tool.accessibilityLabel)
            .accessibilityValue(tool.accessibilityValue ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { tool.action() }
    }

    @ViewBuilder
    private var icon: some View {
        switch tool.icon {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: 16, weight: .semibold))
        case .text(let text):
            Text(text)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
                .fixedSize()
        case .positionMarks:
            PositionMarksIcon(color: tool.isOn ? .black : .white)
        }
    }
}
