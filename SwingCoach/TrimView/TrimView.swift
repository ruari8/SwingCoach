//
//  TrimView.swift
//  SwingCoach
//
//  Created by AI Assistant on 22/12/2024.
//

import SwiftUI
import AVKit
import AVFoundation
import Photos

/// Main view for trimming a long video into individual swing clips
struct TrimView: View {
    let sourceURL: URL
    let onComplete: ([SwingClip], [URL]) -> Void
    let onCancel: () -> Void
    var onExportAndAnalyze: (([SwingClip]) -> Void)? = nil
    
    @State private var player: AVPlayer?
    @State private var duration: CMTime = .zero
    @State private var currentTime: CMTime = .zero
    @State private var isPlaying = false
    
    // Thumbnail state
    @State private var thumbnails: [(time: CMTime, image: UIImage)] = []
    @State private var isLoadingThumbnails = true
    
    // Range selection
    @State private var rangeStart: CMTime?
    @State private var rangeEnd: CMTime?
    
    // Clips
    @State private var clips: [SwingClip] = []
    @State private var selectedVantage: Vantage = .dtl
    
    // Export state
    @State private var isExporting = false
    @State private var exportProgress: (current: Int, total: Int)?
    
    // Time observer
    @State private var timeObserver: Any?
    
    private let trimmer = VideoTrimmer()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top bar
                topBar
                
                // Video preview
                videoPreview
                    .frame(maxHeight: .infinity)
                
                // Controls
                controlsSection
                
                // Timeline
                timelineSection
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                
                // Clips list
                clipsSection
                
                // Bottom actions
                bottomBar
            }
            
            // Export overlay
            if isExporting {
                exportOverlay
            }
        }
        .onAppear {
            setupPlayer()
            loadThumbnails()
        }
        .onDisappear {
            cleanup()
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .foregroundColor(.white)
            
            Spacer()
            
            Text("Trim Swings")
                .font(.headline)
                .foregroundColor(.white)
            
            Spacer()
            
            // Vantage picker
            Menu {
                ForEach(Vantage.allCases, id: \.self) { vantage in
                    Button(vantage.displayName) {
                        selectedVantage = vantage
                    }
                }
            } label: {
                Text(selectedVantage.shortName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.15))
                    )
            }
        }
        .padding()
        .background(Color.black.opacity(0.5))
    }
    
    // MARK: - Video Preview
    
    private var videoPreview: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
                    .disabled(true)  // Disable built-in controls
                    .overlay(
                        // Tap to play/pause
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                togglePlayback()
                            }
                    )
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
    }
    
    // MARK: - Controls
    
    private var controlsSection: some View {
        HStack(spacing: 12) {
            // Playback controls
            HStack(spacing: 16) {
                Button {
                    stepBackward()
                } label: {
                    Image(systemName: "backward.frame.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                }
                
                Button {
                    stepForward()
                } label: {
                    Image(systemName: "forward.frame.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
            
            // Time display
            Text(formatTimeCompact(currentTime))
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
            
            Spacer()
            
            // Scissors button - tap once for start, again for end
            Button {
                if rangeStart == nil {
                    markStart()
                } else if rangeEnd == nil {
                    markEnd()
                }
            } label: {
                Image(systemName: "scissors")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(rangeStart != nil ? (rangeEnd != nil ? .green : .yellow) : .white)
                    .frame(width: 44, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.15))
                    )
            }
            .disabled(rangeStart != nil && rangeEnd != nil)
            
            // Clear button
            Button {
                clearSelection()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(rangeStart != nil ? .white : .gray)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(rangeStart != nil ? 0.15 : 0.08))
                    )
            }
            .disabled(rangeStart == nil)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.3))
    }
    
    // MARK: - Timeline
    
    private var timelineSection: some View {
        VStack(spacing: 4) {
            if isLoadingThumbnails {
                HStack {
                    ProgressView()
                        .tint(.white)
                    Text("Loading timeline...")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(height: 60)
            } else {
                ThumbnailTimeline(
                    thumbnails: thumbnails,
                    duration: duration,
                    clips: clips,
                    currentTime: $currentTime,
                    rangeStart: $rangeStart,
                    rangeEnd: $rangeEnd,
                    onSeek: { time in
                        seek(to: time)
                    }
                )
                
                // Add clip button (when range is selected)
                if rangeStart != nil && rangeEnd != nil {
                    Button {
                        addClip()
                    } label: {
                        Label("Add Swing", systemImage: "plus.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.yellow)
                            .cornerRadius(20)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
    
    // MARK: - Clips Section
    
    private var clipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !clips.isEmpty {
                Text("Clips (\(clips.count))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(clips) { clip in
                            clipThumbnail(clip)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func clipThumbnail(_ clip: SwingClip) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let thumbnail = clip.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 50)
                        .clipped()
                        .cornerRadius(6)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 50)
                        .cornerRadius(6)
                }
                
                // Delete button
                Button {
                    removeClip(clip)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
                .offset(x: 6, y: -6)
            }
            
            Text(clip.durationFormatted)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
        .onTapGesture {
            // Jump to clip start
            seek(to: clip.startCMTime)
            rangeStart = clip.startCMTime
            rangeEnd = clip.endCMTime
        }
    }
    
    // MARK: - Bottom Bar
    
    private var statusText: String {
        if rangeStart != nil && rangeEnd != nil {
            return "Adjust selection, then add swing"
        } else if rangeStart != nil {
            return "Navigate to end, tap ✂️ again"
        } else if clips.isEmpty {
            return "Tap ✂️ at start of swing"
        } else {
            return "\(clips.count) swing\(clips.count == 1 ? "" : "s") ready"
        }
    }
    
    private var bottomBar: some View {
        HStack {
            Text(statusText)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
            
            Spacer()
            
            if onExportAndAnalyze != nil {
                // Two buttons: Export only, Export & Analyze
                HStack(spacing: 8) {
                    Button {
                        exportClips()
                    } label: {
                        Text("Export")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(clips.isEmpty ? .gray : .white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(clips.isEmpty ? Color.gray.opacity(0.3) : Color.white.opacity(0.2))
                            .cornerRadius(10)
                    }
                    .disabled(clips.isEmpty)
                    
                    Button {
                        onExportAndAnalyze?(clips)
                        exportClips()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                            Text("Export & Analyze")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(clips.isEmpty ? .gray : .black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(clips.isEmpty ? Color.gray.opacity(0.3) : Color.yellow)
                        .cornerRadius(10)
                    }
                    .disabled(clips.isEmpty)
                }
            } else {
                Button {
                    exportClips()
                } label: {
                    Text("Export \(clips.count) Clip\(clips.count == 1 ? "" : "s")")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(clips.isEmpty ? .gray : .black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(clips.isEmpty ? Color.gray.opacity(0.3) : Color.yellow)
                        .cornerRadius(10)
                }
                .disabled(clips.isEmpty)
            }
        }
        .padding()
        .background(Color.black.opacity(0.5))
    }
    
    // MARK: - Export Overlay
    
    private var exportOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                
                if let progress = exportProgress {
                    Text("Exporting \(progress.current) of \(progress.total)...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func setupPlayer() {
        let asset = AVURLAsset(url: sourceURL)
        let playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        
        // Load duration
        Task {
            do {
                duration = try await asset.load(.duration)
            } catch {
                print("❌ Failed to load duration: \(error)")
            }
        }
        
        // Add time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time
            
            // Check if playback finished
            if let player = player,
               let duration = player.currentItem?.duration,
               CMTimeCompare(time, duration) >= 0 {
                isPlaying = false
            }
        }
    }
    
    private func loadThumbnails() {
        Task {
            do {
                let asset = AVURLAsset(url: sourceURL)
                let videoDuration = try await asset.load(.duration)
                let durationSeconds = CMTimeGetSeconds(videoDuration)
                
                // Scale thumbnail count based on video length
                // ~1 thumbnail per second for short videos, fewer for long ones
                let count: Int
                if durationSeconds <= 60 {
                    count = max(20, Int(durationSeconds))  // 1 per second, min 20
                } else if durationSeconds <= 300 {
                    count = 60 + Int((durationSeconds - 60) / 2)  // slower growth
                } else {
                    count = min(200, 120 + Int((durationSeconds - 300) / 5))  // cap at 200
                }
                
                print("📹 Video: \(Int(durationSeconds))s → generating \(count) thumbnails")
                thumbnails = try await trimmer.generateThumbnails(for: asset, count: count)
                isLoadingThumbnails = false
            } catch {
                print("❌ Failed to load thumbnails: \(error)")
                isLoadingThumbnails = false
            }
        }
    }
    
    private func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
    }
    
    private func togglePlayback() {
        if isPlaying {
            player?.pause()
        } else {
            // If at end, restart
            if let dur = player?.currentItem?.duration,
               CMTimeCompare(currentTime, dur) >= 0 {
                seek(to: .zero)
            }
            player?.play()
        }
        isPlaying.toggle()
    }
    
    private func seek(to time: CMTime) {
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }
    
    private func stepForward() {
        let frameDuration = CMTime(value: 1, timescale: 30)
        let newTime = CMTimeAdd(currentTime, frameDuration)
        seek(to: newTime)
    }
    
    private func stepBackward() {
        let frameDuration = CMTime(value: 1, timescale: 30)
        let newTime = CMTimeSubtract(currentTime, frameDuration)
        if CMTimeCompare(newTime, .zero) >= 0 {
            seek(to: newTime)
        }
    }
    
    private func markStart() {
        rangeStart = currentTime
        // If end is before start, clear it
        if let end = rangeEnd, CMTimeCompare(end, currentTime) <= 0 {
            rangeEnd = nil
        }
    }
    
    private func markEnd() {
        rangeEnd = currentTime
        // If start is after end, clear it
        if let start = rangeStart, CMTimeCompare(start, currentTime) >= 0 {
            rangeStart = nil
        }
    }
    
    private func clearSelection() {
        rangeStart = nil
        rangeEnd = nil
    }
    
    private func addClip() {
        guard let start = rangeStart, let end = rangeEnd else { return }
        
        var newClip = SwingClip(
            startTime: start,
            endTime: end,
            vantage: selectedVantage
        )
        
        // Generate thumbnail for the clip
        Task {
            let asset = AVURLAsset(url: sourceURL)
            if let thumbnail = try? await trimmer.generateThumbnail(for: asset, at: start) {
                await MainActor.run {
                    // Find and update the clip with thumbnail
                    if let index = clips.firstIndex(where: { $0.id == newClip.id }) {
                        clips[index].thumbnail = thumbnail
                    }
                }
            }
        }
        
        clips.append(newClip)
        
        // Clear selection for next clip
        rangeStart = nil
        rangeEnd = nil
    }
    
    private func removeClip(_ clip: SwingClip) {
        clips.removeAll { $0.id == clip.id }
    }
    
    private func exportClips() {
        guard !clips.isEmpty else { return }
        
        isExporting = true
        
        Task {
            do {
                // Use temp directory for intermediate files
                let tempDir = FileManager.default.temporaryDirectory
                let asset = AVURLAsset(url: sourceURL)
                
                // Export clips to temp files first
                let exportedURLs = try await trimmer.exportClips(
                    from: asset,
                    clips: clips,
                    outputDirectory: tempDir
                ) { current, total in
                    Task { @MainActor in
                        exportProgress = (current, total)
                    }
                }
                
                // Save each clip to Photos library and add to SwingLibrary
                var savedCount = 0
                for (clip, url) in zip(clips, exportedURLs) {
                    if let assetID = await PHPhotoLibrary.saveVideoAndGetID(url: url) {
                        await SwingLibrary.shared.addSwing(
                            photoAssetID: assetID,
                            vantage: clip.vantage,
                            duration: clip.duration
                        )
                        savedCount += 1
                    }
                    // Clean up temp file
                    try? FileManager.default.removeItem(at: url)
                }
                
                print("✅ Saved \(savedCount)/\(exportedURLs.count) clips to Photos & Library")
                
                await MainActor.run {
                    isExporting = false
                    onComplete(clips, exportedURLs)
                }
            } catch {
                print("❌ Export failed: \(error)")
                await MainActor.run {
                    isExporting = false
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    /// Compact format: just seconds and tenths (e.g., "05.3")
    private func formatTimeCompact(_ time: CMTime) -> String {
        let totalSeconds = CMTimeGetSeconds(time)
        let secs = Int(totalSeconds)
        let tenths = Int((totalSeconds * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%02d.%d", secs, tenths)
    }
}

// MARK: - Preview

#Preview {
    TrimView(
        sourceURL: URL(fileURLWithPath: "/tmp/test.mov"),
        onComplete: { _, _ in },
        onCancel: { }
    )
}

