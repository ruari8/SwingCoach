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
    let source: TrimVideoSource
    var sourceCaptureMode: SloMoMode? = nil
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
    @State private var thumbnailPlaceholderCount = 12
    
    // Range selection
    @State private var rangeStart: CMTime?
    @State private var rangeEnd: CMTime?
    
    // Clips
    @State private var clips: [SwingClip] = []
    @State private var selectedVantage: Vantage = .dtl
    
    // Export state
    @State private var isExporting = false
    @State private var exportProgress: (current: Int, total: Int)?
    
    // Source loading state
    @State private var previewAsset: AVAsset?
    @State private var sourcePreparationTask: Task<Void, Never>?
    
    // Time observer
    @State private var timeObserver: Any?
    
    // Playback tuning
    @State private var preferredPlaybackRate: Float = 1.0
    @State private var frameStep = CMTime(value: 1, timescale: 30)
    @State private var seekRepeatTask: Task<Void, Never>?
    @State private var activeSeekDirection: Int?
    
    private let trimmer = VideoTrimmer()
    
    private var displayTimeScale: Double {
        sourceCaptureMode.map { $0.targetFPS / 30.0 } ?? 1.0
    }
    
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
            prepareSource()
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
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Opening video...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
    }
    
    // MARK: - Controls
    
    private var controlsSection: some View {
        HStack(spacing: 12) {
            // Playback controls
            HStack(spacing: 16) {
                seekButton(systemImage: "backward.frame.fill", direction: -1)
                
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                }
                
                seekButton(systemImage: "forward.frame.fill", direction: 1)
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
            ThumbnailTimeline(
                thumbnails: thumbnails,
                placeholderCount: thumbnailPlaceholderCount,
                isLoading: isLoadingThumbnails,
                displayTimeScale: displayTimeScale,
                duration: duration,
                clips: clips,
                currentTime: $currentTime,
                rangeStart: $rangeStart,
                rangeEnd: $rangeEnd,
                onSeek: { time in
                    seek(to: time)
                }
            )
            
            if isLoadingThumbnails {
                Text(thumbnails.isEmpty ? "Preparing timeline..." : "Loading more frames...")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            
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
            
            Text(clipDurationText(clip))
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
    
    private func clipDurationText(_ clip: SwingClip) -> String {
        formatDurationSeconds(clip.duration * displayTimeScale)
    }
    
    private func formatDurationSeconds(_ seconds: Double) -> String {
        let wholeSeconds = Int(seconds)
        let tenths = Int((seconds * 10).truncatingRemainder(dividingBy: 10))
        return "\(wholeSeconds).\(tenths)s"
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
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundColor(.white.opacity(0.6))
            
            Spacer()
            
            Button {
                handlePrimaryExportAction()
            } label: {
                Text(primaryExportButtonTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .foregroundColor(clips.isEmpty ? .gray : .black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(clips.isEmpty ? Color.gray.opacity(0.3) : Color.yellow)
                    .cornerRadius(10)
            }
            .fixedSize(horizontal: true, vertical: false)
            .disabled(clips.isEmpty)
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
    
    private func prepareSource() {
        preferredPlaybackRate = sourceCaptureMode?.slowMotionRate ?? 1.0
        let preparationStart = Date()
        
        if let durationHint = source.durationHint {
            duration = durationHint
        }
        
        sourcePreparationTask?.cancel()
        sourcePreparationTask = Task {
            do {
                let loadedPreviewAsset = try await source.loadPreviewAsset()
                print("📹 Trim: Preview asset ready after \(String(format: "%.2f", Date().timeIntervalSince(preparationStart)))s")
                let playerItem = AVPlayerItem(asset: loadedPreviewAsset)
                let newPlayer = AVPlayer(playerItem: playerItem)
                let loadedDuration = try await loadedPreviewAsset.load(.duration)
                var loadedFrameStep = frameStep
                
                if let videoTrack = try await loadedPreviewAsset.loadTracks(withMediaType: .video).first {
                    let sourceFrameRate = try await videoTrack.load(.nominalFrameRate)
                    if sourceFrameRate > 0 {
                        loadedFrameStep = CMTime(
                            value: 1,
                            timescale: CMTimeScale(max(30, Int32(sourceFrameRate.rounded())))
                        )
                    }
                }
                
                await MainActor.run {
                    previewAsset = loadedPreviewAsset
                    player = newPlayer
                    duration = loadedDuration
                    frameStep = loadedFrameStep
                    attachTimeObserver()
                }
                
                try await loadThumbnails(for: loadedPreviewAsset, duration: loadedDuration)
                print("📹 Trim: Initial timeline ready after \(String(format: "%.2f", Date().timeIntervalSince(preparationStart)))s")
            } catch {
                print("❌ Failed to prepare source: \(error)")
                await MainActor.run {
                    isLoadingThumbnails = false
                }
            }
        }
    }
    
    private func attachTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time
            
            if let player = player,
               let duration = player.currentItem?.duration,
               CMTimeCompare(time, duration) >= 0 {
                isPlaying = false
            }
        }
    }
    
    private func loadThumbnails(for asset: AVAsset, duration videoDuration: CMTime) async throws {
        let durationSeconds = CMTimeGetSeconds(videoDuration)
        let fullCount = thumbnailCount(for: durationSeconds)
        let previewCount = min(fullCount, previewThumbnailCount(for: durationSeconds))
        let previewSize = CGSize(width: 56, height: 32)
        let fullSize = CGSize(width: 80, height: 45)
        
        await MainActor.run {
            thumbnailPlaceholderCount = max(1, previewCount)
            isLoadingThumbnails = true
        }
        
        if let cachedFull = await trimmer.cachedThumbnails(for: source.cacheKey, count: fullCount, size: fullSize) {
            await MainActor.run {
                thumbnails = cachedFull
                thumbnailPlaceholderCount = fullCount
                isLoadingThumbnails = false
            }
            return
        }
        
        print("📹 Video: \(Int(durationSeconds))s → generating \(previewCount) quick thumbnails")
        let previewThumbnails = try await trimmer.generateThumbnails(
            for: asset,
            count: previewCount,
            size: previewSize,
            cacheKey: source.cacheKey
        )
        
        await MainActor.run {
            thumbnails = previewThumbnails
            thumbnailPlaceholderCount = previewCount
            isLoadingThumbnails = previewCount < fullCount
        }
        
        guard fullCount > previewCount else { return }
        
        print("📹 Video: refining timeline with \(fullCount) thumbnails")
        let fullThumbnails = try await trimmer.generateThumbnails(
            for: asset,
            count: fullCount,
            size: fullSize,
            cacheKey: source.cacheKey
        )
        
        await MainActor.run {
            thumbnails = fullThumbnails
            thumbnailPlaceholderCount = fullCount
            isLoadingThumbnails = false
        }
    }
    
    private func cleanup() {
        sourcePreparationTask?.cancel()
        sourcePreparationTask = nil
        stopContinuousStep()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
        previewAsset = nil
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
            player?.playImmediately(atRate: preferredPlaybackRate)
        }
        isPlaying.toggle()
    }
    
    private func seek(to time: CMTime) {
        let clampedTime = clamped(time)
        player?.seek(to: clampedTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clampedTime
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
        
        let newClip = SwingClip(
            startTime: start,
            endTime: end,
            vantage: selectedVantage
        )
        
        // Generate thumbnail for the clip
        if let previewAsset {
            Task {
                if let thumbnail = try? await trimmer.generateThumbnail(for: previewAsset, at: start) {
                    await MainActor.run {
                        // Find and update the clip with thumbnail
                        if let index = clips.firstIndex(where: { $0.id == newClip.id }) {
                            clips[index].thumbnail = thumbnail
                        }
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
                let exportAsset = try await source.loadExportAsset()
                
                // Export clips to temp files first
                let exportedURLs = try await trimmer.exportClips(
                    from: exportAsset,
                    clips: clips,
                    outputDirectory: tempDir,
                    slowMotionFactor: sourceCaptureMode.map { $0.targetFPS / 30.0 }
                ) { current, total in
                    Task { @MainActor in
                        exportProgress = (current, total)
                    }
                }
                
                // Save each clip to Photos library and add to SwingLibrary
                var savedCount = 0
                for (clip, url) in zip(clips, exportedURLs) {
                    if let assetID = await PHPhotoLibrary.saveVideoAndGetID(url: url) {
                        let libraryThumbnail = await immediateLibraryThumbnail(for: clip, exportAsset: exportAsset)
                        SwingLibrary.shared.addSwing(
                            photoAssetID: assetID,
                            vantage: clip.vantage,
                            duration: clip.duration * (sourceCaptureMode.map { $0.targetFPS / 30.0 } ?? 1.0),
                            initialThumbnail: libraryThumbnail
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
        let displaySeconds = totalSeconds * displayTimeScale
        let secs = Int(displaySeconds)
        let tenths = Int((displaySeconds * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%02d.%d", secs, tenths)
    }
    
    private var primaryExportButtonTitle: String {
        if onExportAndAnalyze != nil {
            return "Export & Analyze"
        }
        
        return "Export \(clips.count) Clip\(clips.count == 1 ? "" : "s")"
    }
    
    private func handlePrimaryExportAction() {
        // TODO: Re-enable automatic analyze handoff once the exported-clip coach flow is ready.
        exportClips()
    }
    
    private func seekButton(systemImage: String, direction: Int) -> some View {
        Image(systemName: systemImage)
            .font(.title3)
            .foregroundColor(.white)
            .frame(width: 44, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(activeSeekDirection == direction ? 0.22 : 0.12))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        startContinuousStep(direction: direction)
                    }
                    .onEnded { _ in
                        stopContinuousStep()
                    }
            )
    }
    
    private func startContinuousStep(direction: Int) {
        guard activeSeekDirection != direction else { return }
        
        stopContinuousStep()
        activeSeekDirection = direction
        step(by: direction)
        
        seekRepeatTask = Task {
            let holdStart = Date()
            
            try? await Task.sleep(nanoseconds: 350_000_000)
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(holdStart)
                let multiplier = seekStepMultiplier(for: elapsed)
                await MainActor.run {
                    step(by: direction, multiplier: multiplier)
                }
                
                let interval = seekRepeatInterval(for: elapsed)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }
    
    private func stopContinuousStep() {
        seekRepeatTask?.cancel()
        seekRepeatTask = nil
        activeSeekDirection = nil
    }
    
    private func seekStepMultiplier(for holdDuration: TimeInterval) -> Int {
        switch holdDuration {
        case 0..<1.2:
            return 1
        case 1.2..<2.5:
            return 2
        case 2.5..<4.0:
            return 4
        default:
            return 8
        }
    }
    
    private func seekRepeatInterval(for holdDuration: TimeInterval) -> Double {
        switch holdDuration {
        case 0..<1.2:
            return 0.16
        case 1.2..<2.5:
            return 0.12
        case 2.5..<4.0:
            return 0.085
        default:
            return 0.06
        }
    }
    
    private func step(by direction: Int, multiplier: Int = 1) {
        if isPlaying {
            player?.pause()
            isPlaying = false
        }
        
        let stepDuration = CMTimeMultiplyByFloat64(frameStep, multiplier: Double(multiplier))
        let candidateTime = direction >= 0
            ? CMTimeAdd(currentTime, stepDuration)
            : CMTimeSubtract(currentTime, stepDuration)
        
        seek(to: candidateTime)
    }
    
    private func clamped(_ time: CMTime) -> CMTime {
        if CMTimeCompare(time, .zero) < 0 {
            return .zero
        }
        
        if CMTimeCompare(time, duration) > 0 {
            return duration
        }
        
        return time
    }
    
    private func thumbnailCount(for durationSeconds: Double) -> Int {
        switch durationSeconds {
        case ..<30:
            return 18
        case ..<120:
            return min(42, max(20, Int(durationSeconds / 2)))
        case ..<300:
            return min(72, 30 + Int((durationSeconds - 120) / 5))
        default:
            return min(96, 66 + Int((durationSeconds - 300) / 10))
        }
    }
    
    private func previewThumbnailCount(for durationSeconds: Double) -> Int {
        switch durationSeconds {
        case ..<30:
            return 10
        case ..<120:
            return 12
        case ..<300:
            return 14
        default:
            return 16
        }
    }
    
    private func immediateLibraryThumbnail(for clip: SwingClip, exportAsset: AVAsset) async -> UIImage? {
        if let thumbnail = clip.thumbnail {
            return thumbnail
        }
        
        if let previewAsset,
           let thumbnail = try? await trimmer.generateThumbnail(for: previewAsset, at: clip.startCMTime) {
            return thumbnail
        }
        
        return try? await trimmer.generateThumbnail(for: exportAsset, at: clip.startCMTime)
    }
}

// MARK: - Preview

#Preview {
    TrimView(
        source: .localFile(url: URL(fileURLWithPath: "/tmp/test.mov")),
        onComplete: { _, _ in },
        onCancel: { }
    )
}
