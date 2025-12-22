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
    let duration: CMTime
    let clips: [SwingClip]  // Show markers for existing clips
    
    @Binding var currentTime: CMTime
    @Binding var rangeStart: CMTime?
    @Binding var rangeEnd: CMTime?
    
    let onSeek: (CMTime) -> Void
    
    // Layout: scale timeline width based on duration
    private let pixelsPerSecond: CGFloat = 15
    private let thumbnailHeight: CGFloat = 50
    private let handleWidth: CGFloat = 14
    
    private var durationSeconds: CGFloat {
        CGFloat(CMTimeGetSeconds(duration))
    }
    
    private var totalWidth: CGFloat {
        // Ensure we have a reasonable minimum width
        guard durationSeconds > 0 else { return UIScreen.main.bounds.width - 32 }
        return max(UIScreen.main.bounds.width - 32, durationSeconds * pixelsPerSecond)
    }
    
    private var isScrollable: Bool {
        totalWidth > UIScreen.main.bounds.width - 32
    }
    
    var body: some View {
        VStack(spacing: 4) {
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
                        
                        // Selected range overlay
                        if let start = rangeStart, let end = rangeEnd {
                            rangeOverlay(start: start, end: end)
                                .padding(.top, 18)
                        }
                        
                        // Current time indicator (playhead)
                        playhead
                            .id("playhead")
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
    
    // MARK: - Time Labels (inline, not separate ScrollView)
    
    private var timeLabels: some View {
        let durationSeconds = CMTimeGetSeconds(duration)
        let labelInterval = calculateLabelInterval(durationSeconds)
        let labelCount = Int(durationSeconds / labelInterval) + 1
        
        return ZStack(alignment: .topLeading) {
            ForEach(0..<labelCount, id: \.self) { i in
                let seconds = Double(i) * labelInterval
                let xPosition = positionFromTime(CMTime(seconds: seconds, preferredTimescale: 600))
                
                Text(formatLabelTime(seconds))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .offset(x: xPosition - 15, y: 0)
            }
        }
        .frame(width: totalWidth, height: 16, alignment: .topLeading)
    }
    
    private func calculateLabelInterval(_ durationSeconds: Double) -> Double {
        if durationSeconds <= 30 { return 5 }
        if durationSeconds <= 60 { return 10 }
        if durationSeconds <= 180 { return 15 }
        if durationSeconds <= 300 { return 30 }
        return 60
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
        // Distribute thumbnails evenly across the timeline width
        HStack(spacing: 0) {
            ForEach(Array(thumbnails.enumerated()), id: \.offset) { index, item in
                let thumbWidth = totalWidth / CGFloat(max(1, thumbnails.count))
                
                Image(uiImage: item.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
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
    
    // MARK: - Range Overlay
    
    private func rangeOverlay(start: CMTime, end: CMTime) -> some View {
        let startX = positionFromTime(start)
        let endX = positionFromTime(end)
        let width = max(handleWidth * 2, endX - startX)
        
        return ZStack(alignment: .leading) {
            // Dimmed area before selection
            Rectangle()
                .fill(Color.black.opacity(0.6))
                .frame(width: max(0, startX), height: thumbnailHeight)
            
            // Dimmed area after selection
            Rectangle()
                .fill(Color.black.opacity(0.6))
                .frame(width: max(0, totalWidth - endX), height: thumbnailHeight)
                .offset(x: endX)
            
            // Selection border
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.yellow, lineWidth: 3)
                .frame(width: width, height: thumbnailHeight + 4)
                .offset(x: startX, y: -2)
            
            // Start handle
            handleView()
                .offset(x: startX - handleWidth / 2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newX = startX + value.translation.width
                            let newTime = timeFromPosition(newX)
                            if let end = rangeEnd, CMTimeCompare(newTime, end) < 0,
                               CMTimeCompare(newTime, .zero) >= 0 {
                                rangeStart = newTime
                            }
                        }
                )
            
            // End handle
            handleView()
                .offset(x: endX - handleWidth / 2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newX = endX + value.translation.width
                            let newTime = timeFromPosition(newX)
                            if let start = rangeStart, CMTimeCompare(newTime, start) > 0,
                               CMTimeCompare(newTime, duration) <= 0 {
                                rangeEnd = newTime
                            }
                        }
                )
        }
        .frame(width: totalWidth, height: thumbnailHeight)
    }
    
    private func handleView() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.yellow)
                .frame(width: handleWidth, height: thumbnailHeight + 8)
            
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 4, height: 2)
                }
            }
        }
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
        let totalSeconds = CMTimeGetSeconds(time)
        let secs = Int(totalSeconds)
        let tenths = Int((totalSeconds * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%02d.%d", secs, tenths)
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
