//
//  ThumbnailTimeline.swift
//  SwingCoach
//
//  Created by AI Assistant on 22/12/2024.
//

import SwiftUI
import AVFoundation

/// A horizontal timeline showing video thumbnails with draggable range selection
struct ThumbnailTimeline: View {
    let thumbnails: [(time: CMTime, image: UIImage)]
    let placeholderCount: Int
    let isLoading: Bool
    let displayTimeScale: Double
    let duration: CMTime
    let clips: [SwingClip]  // Show markers for existing clips
    
    @Binding var currentTime: CMTime
    @Binding var rangeStart: CMTime?
    @Binding var rangeEnd: CMTime?
    
    let onSeek: (CMTime) -> Void
    
    // Zoom level
    enum ZoomLevel: String {
        case overview = "Overview"
        case medium = "Medium"
        case detail = "Detail"
        
        var pixelsPerSecond: CGFloat {
            switch self {
            case .overview: return 1.5   // ~260s visible (4+ min) - whole video scannable quickly
            case .medium: return 6       // ~65s visible - good for finding swings
            case .detail: return 15      // ~26s visible - current, for precise trimming
            }
        }
        
        var next: ZoomLevel {
            switch self {
            case .overview: return .medium
            case .medium: return .detail
            case .detail: return .overview
            }
        }
        
        var buttonFill: Color {
            switch self {
            case .overview:
                return Color.white.opacity(0.14)
            case .medium:
                return Color.yellow.opacity(0.78)
            case .detail:
                return Color.orange.opacity(0.88)
            }
        }
        
        var buttonForeground: Color {
            switch self {
            case .overview:
                return .white
            case .medium, .detail:
                return .black
            }
        }
    }
    
    @State private var zoomLevel: ZoomLevel = .overview
    
    // Layout
    private let thumbnailHeight: CGFloat = 50
    private let playheadID = "playhead"
    
    private var pixelsPerSecond: CGFloat {
        zoomLevel.pixelsPerSecond
    }
    
    private var rawDurationSeconds: CGFloat {
        CGFloat(CMTimeGetSeconds(duration))
    }
    
    private var displayDurationSeconds: CGFloat {
        rawDurationSeconds * CGFloat(displayTimeScale)
    }
    
    private var totalWidth: CGFloat {
        // Ensure we have a reasonable minimum width
        guard displayDurationSeconds > 0 else { return UIScreen.main.bounds.width - 32 }
        return max(UIScreen.main.bounds.width - 32, displayDurationSeconds * pixelsPerSecond)
    }
    
    private var isScrollable: Bool {
        totalWidth > UIScreen.main.bounds.width - 32
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 4) {
                // Zoom control bar
                zoomControlBar(proxy: proxy)
                
                // Scrollable timeline
                ScrollView(.horizontal, showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            // Time labels at the top
                            timeLabels
                            
                            // Thumbnail strip
                            thumbnailStrip
                                .padding(.top, 18)
                            
                            // Clip markers (show where clips have been marked)
                            clipMarkers
                                .padding(.top, 18)
                            
                            // Start marker (when only start is set)
                            if let start = rangeStart, rangeEnd == nil {
                                startMarkerLine(at: start)
                            }
                            
                            // Selected range overlay (when both start and end are set)
                            if let start = rangeStart, let end = rangeEnd {
                                rangeOverlay(start: start, end: end)
                            }
                            
                            // Current time indicator (playhead)
                            playhead
                                .id(playheadID)
                        }
                        .frame(width: totalWidth, height: thumbnailHeight + 28)
                        .coordinateSpace(name: "timeline")
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            // Tap to seek - allows scrolling to work
                            let time = timeFromPosition(location.x)
                            onSeek(time)
                        }
                }
                .frame(height: thumbnailHeight + 28)
                
                // Info bar below timeline
                HStack {
                    Text(formatSeconds(currentTime))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.yellow)
                    
                    Spacer()
                    
                    // Scroll hint for long videos
                    if isScrollable {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 10))
                            Text("Scroll")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.white.opacity(0.4))
                    }
                    
                    Spacer()
                    
                    Text(formatSeconds(duration))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.4))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Zoom Control Bar
    
    private func zoomControlBar(proxy: ScrollViewProxy) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                zoomCycleButton(proxy: proxy)
                Spacer(minLength: 8)
                zoomSummary
            }
            
            HStack(spacing: 8) {
                zoomCycleButton(proxy: proxy)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
    
    private func zoomCycleButton(proxy: ScrollViewProxy) -> some View {
        Button {
            cycleZoom(using: proxy)
        } label: {
            HStack(spacing: 8) {
                Text("Precision")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(zoomLevel.buttonForeground.opacity(0.75))
                
                Text(zoomLevel.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(zoomLevel.buttonForeground)
            }
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(zoomLevel.buttonFill)
            )
        }
    }
    
    private var zoomSummary: some View {
        Text("\(visibleTimeDescription) · tap to cycle")
            .font(.system(size: 10))
            .lineLimit(1)
            .foregroundColor(.white.opacity(0.5))
    }
    
    private var visibleTimeDescription: String {
        let screenWidth: CGFloat = UIScreen.main.bounds.width - 48
        let visibleSeconds = Int(isScrollable ? (screenWidth / pixelsPerSecond) : displayDurationSeconds)
        if visibleSeconds >= 60 {
            return "~\(visibleSeconds / 60)m visible"
        }
        return "~\(visibleSeconds)s visible"
    }
    
    // MARK: - Time Labels (inline, not separate ScrollView)
    
    private var timeLabels: some View {
        let displayDuration = Double(displayDurationSeconds)
        let labelInterval = calculateLabelInterval(displayDuration)
        let labelCount = Int(displayDuration / labelInterval) + 1
        
        return ZStack(alignment: .topLeading) {
            ForEach(0..<labelCount, id: \.self) { i in
                let displayedSeconds = Double(i) * labelInterval
                let rawSeconds = displayedSeconds / max(displayTimeScale, 0.0001)
                let xPosition = positionFromTime(CMTime(seconds: rawSeconds, preferredTimescale: 600))
                
                Text(formatLabelTime(displayedSeconds))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .offset(x: xPosition - 15, y: 0)
            }
        }
        .frame(width: totalWidth, height: 16, alignment: .topLeading)
    }
    
    private func calculateLabelInterval(_ durationSeconds: Double) -> Double {
        // Adjust label density based on zoom level
        // At lower zoom (more zoomed out), need larger intervals
        switch zoomLevel {
        case .overview:
            // Very zoomed out - show labels every 2-5 minutes
            if durationSeconds <= 60 { return 15 }
            if durationSeconds <= 300 { return 60 }
            if durationSeconds <= 900 { return 120 }
            return 300
        case .medium:
            // Medium zoom - show labels every 30s-2min
            if durationSeconds <= 30 { return 5 }
            if durationSeconds <= 120 { return 15 }
            if durationSeconds <= 300 { return 30 }
            if durationSeconds <= 900 { return 60 }
            return 120
        case .detail:
            // Zoomed in - original behavior
            if durationSeconds <= 30 { return 5 }
            if durationSeconds <= 60 { return 10 }
            if durationSeconds <= 180 { return 15 }
            if durationSeconds <= 300 { return 30 }
            return 60
        }
    }
    
    private func formatLabelTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return String(format: "%d:%02d", mins, secs)
        }
        return String(format: "%ds", secs)
    }
    
    // MARK: - Thumbnail Strip
    
    private var thumbnailStrip: some View {
        let displayCount = max(1, max(placeholderCount, thumbnails.count))
        
        return HStack(spacing: 0) {
            ForEach(0..<displayCount, id: \.self) { index in
                let thumbWidth = totalWidth / CGFloat(displayCount)
                
                Group {
                    if index < thumbnails.count {
                        Image(uiImage: thumbnails[index].image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isLoading ? 0.12 : 0.08),
                                        Color.white.opacity(isLoading ? 0.06 : 0.04)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
                .frame(width: thumbWidth, height: thumbnailHeight)
                .clipped()
            }
        }
        .frame(width: totalWidth, height: thumbnailHeight)
        .cornerRadius(6)
    }
    
    // MARK: - Clip Markers
    
    private var clipMarkers: some View {
        ZStack(alignment: .topLeading) {
            ForEach(clips) { clip in
                let startX = positionFromTime(clip.startCMTime)
                let endX = positionFromTime(clip.endCMTime)
                let width = max(4, endX - startX)
                
                // Marker bar at top of timeline
                VStack(spacing: 0) {
                    // Top indicator line
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: width, height: 3)
                    
                    Spacer()
                    
                    // Bottom indicator line
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: width, height: 3)
                }
                .frame(height: thumbnailHeight)
                .offset(x: startX)
            }
        }
        .frame(width: totalWidth, height: thumbnailHeight)
    }
    
    // MARK: - Start Marker Line (when only start is set)
    
    private func startMarkerLine(at time: CMTime) -> some View {
        let position = positionFromTime(time)
        
        return VStack(spacing: 0) {
            Triangle()
                .fill(Color.yellow)
                .frame(width: 14, height: 10)
                .rotationEffect(.degrees(180))
            
            Rectangle()
                .fill(Color.yellow)
                .frame(width: 3, height: thumbnailHeight + 18)
        }
        .shadow(color: .black.opacity(0.5), radius: 2)
        .offset(x: position - 7)
    }
    
    // MARK: - Range Overlay (SIMPLIFIED)
    // Just draw a box from start position to end position. That's it.
    
    @ViewBuilder
    private func rangeOverlay(start: CMTime, end: CMTime) -> some View {
        let startPos = positionFromTime(start)
        let endPos = positionFromTime(end)
        let boxWidth = endPos - startPos
        
        // Yellow box - simply positioned at startPos with width to endPos
        Rectangle()
            .fill(Color.yellow.opacity(0.3))
            .frame(width: max(4, boxWidth), height: thumbnailHeight)
            .overlay(
                Rectangle()
                    .stroke(Color.yellow, lineWidth: 3)
            )
            .offset(x: startPos)
            .padding(.top, 18)
        
        // Start handle line - SAME code as startMarkerLine
        VStack(spacing: 0) {
            Triangle()
                .fill(Color.yellow)
                .frame(width: 14, height: 10)
                .rotationEffect(.degrees(180))
            
            Rectangle()
                .fill(Color.yellow)
                .frame(width: 3, height: thumbnailHeight + 18)
        }
        .shadow(color: .black.opacity(0.5), radius: 2)
        .offset(x: startPos - 7)
        .highPriorityGesture(
            DragGesture(coordinateSpace: .named("timeline"))
                .onChanged { value in
                    let newTime = timeFromPosition(value.location.x)
                    if CMTimeCompare(newTime, end) < 0, CMTimeCompare(newTime, .zero) >= 0 {
                        rangeStart = newTime
                    }
                }
        )
        
        // End handle line - SAME code as startMarkerLine but at endPos
        VStack(spacing: 0) {
            Triangle()
                .fill(Color.yellow)
                .frame(width: 14, height: 10)
                .rotationEffect(.degrees(180))
            
            Rectangle()
                .fill(Color.yellow)
                .frame(width: 3, height: thumbnailHeight + 18)
        }
        .shadow(color: .black.opacity(0.5), radius: 2)
        .offset(x: endPos - 7)
        .highPriorityGesture(
            DragGesture(coordinateSpace: .named("timeline"))
                .onChanged { value in
                    let newTime = timeFromPosition(value.location.x)
                    if CMTimeCompare(newTime, start) > 0, CMTimeCompare(newTime, duration) <= 0 {
                        rangeEnd = newTime
                    }
                }
        )
    }
    
    // MARK: - Playhead
    
    @ViewBuilder
    private var playhead: some View {
        let position = positionFromTime(currentTime)
        
        ZStack {
            // Invisible wider hit area for easier dragging
            Rectangle()
                .fill(Color.clear)
                .frame(width: 44, height: thumbnailHeight + 28)
                .contentShape(Rectangle())
            
            // Visible playhead
            VStack(spacing: 0) {
                Triangle()
                    .fill(Color.white)
                    .frame(width: 14, height: 10)
                
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: thumbnailHeight + 18)
            }
            .shadow(color: .black.opacity(0.5), radius: 2)
        }
        .offset(x: position - 22)
        .highPriorityGesture(
            DragGesture(coordinateSpace: .named("timeline"))
                .onChanged { value in
                    // Use absolute location in timeline coordinate space
                    let newTime = timeFromPosition(value.location.x)
                    onSeek(newTime)
                }
        )
    }
    
    // MARK: - Coordinate Conversion
    
    private func positionFromTime(_ time: CMTime) -> CGFloat {
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0 else { return 0 }
        
        let timeSeconds = CMTimeGetSeconds(time)
        let fraction = timeSeconds / durationSeconds
        return CGFloat(fraction) * totalWidth
    }
    
    private func timeFromPosition(_ x: CGFloat) -> CMTime {
        let fraction = max(0, min(1, x / totalWidth))
        let durationSeconds = CMTimeGetSeconds(duration)
        let seconds = Double(fraction) * durationSeconds
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }
    
    private func formatSeconds(_ time: CMTime) -> String {
        let totalSeconds = CMTimeGetSeconds(time) * displayTimeScale
        let secs = Int(totalSeconds)
        let tenths = Int((totalSeconds * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%02d.%d", secs, tenths)
    }
    
    private func cycleZoom(using proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.22)) {
            zoomLevel = zoomLevel.next
        }
        
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.22)) {
                proxy.scrollTo(playheadID, anchor: .center)
            }
        }
    }
}

// MARK: - Helper Shapes

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        Text("Timeline Preview").foregroundColor(.white)
    }
}
