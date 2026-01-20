//
//  LibraryView.swift
//  SwingCoach
//
//  Created by Ruari Craig on 01/11/2025.
//

import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

struct LibraryView: View {
    let onNavigateToCapture: () -> Void
    var onAnalyzeSwings: (([SavedSwing]) -> Void)? = nil
    
    @StateObject private var library = SwingLibrary.shared
    
    // Import flow
    @State private var importedVideoURL: URL? = nil
    @State private var showTrimView = false
    @State private var isImporting = false
    @State private var importTask: Task<Void, Never>? = nil
    @State private var importStatusText: String = "Preparing import..."
    @State private var importProgress: Double? = nil  // 0.0-1.0, nil = indeterminate
    @State private var showVideoPicker = false
    
    // Playback
    @State private var selectedSwing: SavedSwing? = nil
    @State private var playbackItem: AVPlayerItem? = nil
    @State private var showPlayback = false
    @State private var isLoadingPlayback = false
    @State private var showPlaybackError = false
    
    // Filter
    @State private var filterVantage: Vantage? = nil
    
    // Multi-select
    @State private var isSelecting = false
    @State private var selectedSwings: Set<UUID> = []
    @State private var showDeleteConfirmation = false
    
    private var filteredSwings: [SavedSwing] {
        if let vantage = filterVantage {
            return library.swings.filter { $0.vantage == vantage }
        }
        return library.swings
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if library.swings.isEmpty {
                    emptyState
                } else {
                    swingGrid
                }
            }
            .navigationTitle("My Swings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isSelecting {
                        Button("Cancel") {
                            exitSelectionMode()
                        }
                    } else {
                        filterMenu
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isSelecting {
                        if !selectedSwings.isEmpty {
                            // Analyze button
                            if onAnalyzeSwings != nil {
                                Button {
                                    analyzeSelectedSwings()
                                } label: {
                                    Image(systemName: "wand.and.stars")
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            // Delete button
                            Button {
                                showDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    } else {
                        selectButton
                        importButton
                    }
                }
            }
            .alert("Delete \(selectedSwings.count) Swing\(selectedSwings.count == 1 ? "" : "s")?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteSelectedSwings()
                }
            } message: {
                Text("This will remove the selected swings from your library. The videos will remain in your Photos library.")
            }
            .onAppear {
                Task {
                    library.validateAssets()
                    await library.loadThumbnails()
                }
            }
            .sheet(isPresented: $showVideoPicker) {
                VideoPickerWithProgress(
                    onVideoSelected: { url in
                        importedVideoURL = url
                        isImporting = false
                        importProgress = nil
                        showTrimView = true
                    },
                    onProgress: { fraction, completed, total in
                        isImporting = true
                        importProgress = fraction
                        // Progress uses arbitrary units (0-10000), not bytes
                        // Just show the percentage
                        if fraction > 0 {
                            importStatusText = "Importing video..."
                        } else {
                            importStatusText = "Preparing import..."
                        }
                    },
                    onCancel: {
                        isImporting = false
                        importProgress = nil
                    },
                    onError: { error in
                        print("❌ Import failed: \(error)")
                        isImporting = false
                        importProgress = nil
                    }
                )
            }
            .fullScreenCover(isPresented: $showTrimView) {
                if let url = importedVideoURL {
                    TrimView(
                        sourceURL: url,
                        playbackRate: 1.0,  // Normal speed for imported videos
                        onComplete: { clips, _ in
                            print("✅ Added \(clips.count) swings to library")
                            showTrimView = false
                            cleanupImport()
                        },
                        onCancel: {
                            showTrimView = false
                            cleanupImport()
                        }
                    )
                }
            }
            .fullScreenCover(isPresented: $showPlayback) {
                if let playerItem = playbackItem {
                    SwingPlaybackView(playerItem: playerItem, swing: selectedSwing) {
                        showPlayback = false
                        playbackItem = nil
                        selectedSwing = nil
                    }
                }
            }
            .overlay {
                if isLoadingPlayback {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("Loading video...")
                                .foregroundColor(.white)
                                .font(.subheadline)
                        }
                        .padding(24)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(12)
                    }
                }
            }
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            // Show determinate progress if available, otherwise spinner
                            if let progress = importProgress {
                                ZStack {
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 4)
                                        .frame(width: 56, height: 56)
                                    Circle()
                                        .trim(from: 0, to: progress)
                                        .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                        .frame(width: 56, height: 56)
                                        .rotationEffect(.degrees(-90))
                                    Text("\(Int(progress * 100))%")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }
                            } else {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                            }
                            
                            Text(importStatusText)
                                .foregroundColor(.white)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                            
                            Button {
                                cancelImport()
                            } label: {
                                Text("Cancel")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.2))
                                    .cornerRadius(8)
                            }
                        }
                        .padding(28)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(16)
                    }
                }
            }
            .alert("Unable to Load Video", isPresented: $showPlaybackError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The video could not be loaded. It may have been deleted from your Photos library.")
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.golf")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Swings Yet")
                .font(.title2.weight(.semibold))
            
            Text("Record a swing or import from Photos")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                Button {
                    onNavigateToCapture()
                } label: {
                    Label("Record", systemImage: "camera.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                
                Button {
                    showVideoPicker = true
                } label: {
                    Label("Import", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Swing Grid
    
    private var swingGrid: some View {
        VStack(spacing: 0) {
            ScrollView {
                // Stats header (hide in selection mode)
                if !isSelecting {
                    statsHeader
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredSwings) { swing in
                        swingCard(swing)
                    }
                }
                .padding()
                .padding(.bottom, isSelecting ? 60 : 0) // Space for selection bar
            }
            
            // Selection bar
            if isSelecting {
                selectionBar
            }
        }
    }
    
    private var selectionBar: some View {
        HStack {
            Button {
                if selectedSwings.count == filteredSwings.count {
                    selectedSwings.removeAll()
                } else {
                    selectedSwings = Set(filteredSwings.map { $0.id })
                }
            } label: {
                Text(selectedSwings.count == filteredSwings.count ? "Deselect All" : "Select All")
                    .font(.subheadline.weight(.medium))
            }
            
            Spacer()
            
            Text("\(selectedSwings.count) selected")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button {
                exitSelectionMode()
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5),
            alignment: .top
        )
    }
    
    private var statsHeader: some View {
        HStack(spacing: 20) {
            statItem(value: "\(library.totalSwings)", label: "Swings")
            statItem(value: "\(library.swings(for: .dtl).count)", label: "DTL")
            statItem(value: "\(library.swings(for: .faceOn).count)", label: "Face-On")
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func swingCard(_ swing: SavedSwing) -> some View {
        let isSelected = selectedSwings.contains(swing.id)
        
        return Button {
            if isSelecting {
                toggleSelection(swing)
            } else {
                loadAndPlay(swing)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Thumbnail
                ZStack {
                    if let thumbnail = swing.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 100)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 100)
                            .overlay {
                                ProgressView()
                            }
                    }
                    
                    // Play icon overlay (hide in selection mode)
                    if !isSelecting {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    
                    // Selection checkmark (show in selection mode)
                    if isSelecting {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 24))
                                    .foregroundColor(isSelected ? .blue : .white)
                                    .shadow(radius: 2)
                            }
                        }
                        .padding(8)
                    }
                    
                    // Vantage badge
                    VStack {
                        HStack {
                            Text(swing.vantage.shortName)
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(4)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(6)
                }
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                )
                
                // Info
                HStack {
                    Text(formatDuration(swing.duration))
                        .font(.caption.weight(.medium))
                    
                    Spacer()
                    
                    Text(formatDate(swing.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isSelecting {
                Button(role: .destructive) {
                    library.removeSwing(swing)
                } label: {
                    Label("Remove from Library", systemImage: "trash")
                }
            }
        }
    }
    
    // MARK: - Toolbar Items
    
    private var filterMenu: some View {
        Menu {
            Button {
                filterVantage = nil
            } label: {
                HStack {
                    Text("All Swings")
                    if filterVantage == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            Divider()
            
            ForEach(Vantage.allCases, id: \.self) { vantage in
                Button {
                    filterVantage = vantage
                } label: {
                    HStack {
                        Text(vantage.displayName)
                        if filterVantage == vantage {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: filterVantage == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }
    
    private var selectButton: some View {
        Button {
            withAnimation {
                isSelecting = true
            }
        } label: {
            Text("Select")
        }
        .disabled(library.swings.isEmpty)
    }
    
    private var importButton: some View {
        Button {
            showVideoPicker = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
        }
    }
    
    // MARK: - Selection Actions
    
    private func exitSelectionMode() {
        withAnimation {
            isSelecting = false
            selectedSwings.removeAll()
        }
    }
    
    private func toggleSelection(_ swing: SavedSwing) {
        if selectedSwings.contains(swing.id) {
            selectedSwings.remove(swing.id)
        } else {
            selectedSwings.insert(swing.id)
        }
    }
    
    private func deleteSelectedSwings() {
        for id in selectedSwings {
            if let swing = library.swings.first(where: { $0.id == id }) {
                library.removeSwing(swing)
            }
        }
        exitSelectionMode()
    }
    
    private func analyzeSelectedSwings() {
        let swings = library.swings.filter { selectedSwings.contains($0.id) }
        exitSelectionMode()
        onAnalyzeSwings?(swings)
    }
    
    // MARK: - Import Actions
    
    private func cancelImport() {
        importTask?.cancel()
        importTask = nil
        isImporting = false
        importProgress = nil
        showVideoPicker = false
        
        // Clean up any partial import
        if let url = importedVideoURL {
            try? FileManager.default.removeItem(at: url)
            importedVideoURL = nil
        }
    }
    
    private func cleanupImport() {
        if let url = importedVideoURL {
            try? FileManager.default.removeItem(at: url)
        }
        importedVideoURL = nil
        importProgress = nil
    }
    
    private func loadAndPlay(_ swing: SavedSwing) {
        selectedSwing = swing
        isLoadingPlayback = true
        
        Task {
            if let playerItem = await library.getPlayerItem(for: swing) {
                await MainActor.run {
                    playbackItem = playerItem
                    isLoadingPlayback = false
                    showPlayback = true
                }
            } else {
                await MainActor.run {
                    isLoadingPlayback = false
                    showPlaybackError = true
                    selectedSwing = nil
                }
            }
        }
    }
    
    // MARK: - Formatting
    
    private func formatDuration(_ seconds: Double) -> String {
        let secs = Int(seconds)
        return "\(secs)s"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Playback View

struct SwingPlaybackView: View {
    let playerItem: AVPlayerItem
    let swing: SavedSwing?
    let onDismiss: () -> Void
    
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: CMTime = .zero
    @State private var duration: CMTime = .zero
    @State private var playbackSpeed: Float = 1.0
    @State private var timeObserver: Any?
    
    // Export state
    @State private var showExportSheet = false
    @State private var isExporting = false
    @State private var exportProgress: Float = 0
    @State private var showExportSuccess = false
    @State private var sourceFPS: Double = 30
    
    // Speed presets
    private let speedOptions: [Float] = [0.25, 0.5, 0.75, 1.0]
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top bar with dismiss and vantage
                topBar
                
                // Video display area
                videoArea
                    .frame(maxHeight: .infinity)
                
                // Playback controls
                controlsSection
                
                // Timeline scrubber
                timelineSection
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                
                // Speed control
                speedSection
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            }
            
            // Export progress overlay
            if isExporting {
                exportProgressOverlay
            }
        }
        .onAppear {
            setupPlayer()
            loadVideoInfo()
        }
        .onDisappear {
            cleanup()
        }
        .sheet(isPresented: $showExportSheet) {
            FPSExportSheet(
                currentDuration: CMTimeGetSeconds(duration),
                sourceFPS: sourceFPS,
                vantage: swing?.vantage ?? .dtl,
                onExport: { targetFPS in
                    exportWithFPS(targetFPS)
                },
                onCancel: {
                    showExportSheet = false
                }
            )
            .presentationDetents([.medium])
        }
        .alert("Export Complete", isPresented: $showExportSuccess) {
            Button("OK") { }
        } message: {
            Text("Your slowed-down video has been saved to Photos and added to your library.")
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            if let swing {
                Text(swing.vantage.displayName)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(8)
            }
            
            Spacer()
            
            // Export button
            Button {
                showExportSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
                    .foregroundColor(.white)
                    .shadow(radius: 4)
            }
            .padding(.trailing, 12)
            
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .shadow(radius: 4)
            }
        }
        .padding()
    }
    
    // MARK: - Export Progress Overlay
    
    private var exportProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView(value: Double(exportProgress))
                    .progressViewStyle(.linear)
                    .tint(.yellow)
                    .frame(width: 200)
                
                Text("Exporting... \(Int(exportProgress * 100))%")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(Color.black.opacity(0.7))
            .cornerRadius(16)
        }
    }
    
    // MARK: - Video Area
    
    private var videoArea: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .disabled(true)  // Disable built-in controls
                    .overlay(
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                togglePlayback()
                            }
                    )
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }
        }
    }
    
    // MARK: - Controls Section
    
    private var controlsSection: some View {
        HStack(spacing: 24) {
            // Frame step backward
            Button {
                stepBackward()
            } label: {
                Image(systemName: "backward.frame.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            // Play/Pause
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
            }
            
            // Frame step forward
            Button {
                stepForward()
            } label: {
                Image(systemName: "forward.frame.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }
        }
        .padding(.vertical, 12)
    }
    
    // MARK: - Timeline Section
    
    private var timelineSection: some View {
        VStack(spacing: 8) {
            // Scrubber
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 6)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.yellow)
                        .frame(width: progressWidth(in: geo.size.width), height: 6)
                    
                    // Playhead
                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .offset(x: playheadOffset(in: geo.size.width))
                }
                .frame(height: 18)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = max(0, min(1, value.location.x / geo.size.width))
                            let newTime = CMTimeMultiplyByFloat64(duration, multiplier: Float64(fraction))
                            seek(to: newTime)
                        }
                )
            }
            .frame(height: 18)
            
            // Time labels
            HStack {
                Text(formatTime(currentTime))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.yellow)
                
                Spacer()
                
                Text(formatTime(duration))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.4))
        .cornerRadius(10)
    }
    
    // MARK: - Speed Section
    
    private var speedSection: some View {
        VStack(spacing: 8) {
            Text("Playback Speed")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            
            HStack(spacing: 12) {
                ForEach(speedOptions, id: \.self) { speed in
                    Button {
                        setSpeed(speed)
                    } label: {
                        Text(speedLabel(speed))
                            .font(.system(size: 14, weight: playbackSpeed == speed ? .bold : .medium))
                            .foregroundColor(playbackSpeed == speed ? .black : .white)
                            .frame(width: 54, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(playbackSpeed == speed ? Color.yellow : Color.white.opacity(0.15))
                            )
                    }
                }
            }
            
            // Continuous slider for fine control
            HStack(spacing: 12) {
                Text("0.1x")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                
                Slider(value: Binding(
                    get: { Double(playbackSpeed) },
                    set: { setSpeed(Float($0)) }
                ), in: 0.1...1.0, step: 0.05)
                .tint(.yellow)
                
                Text("1.0x")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }
    
    // MARK: - Player Setup
    
    private func setupPlayer() {
        let newPlayer = AVPlayer(playerItem: playerItem)
        player = newPlayer
        
        // Load duration
        Task {
            if let dur = try? await playerItem.asset.load(.duration) {
                await MainActor.run {
                    duration = dur
                }
            }
        }
        
        // Time observer
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time
            
            // Check if at end
            if CMTimeCompare(time, duration) >= 0 && CMTimeGetSeconds(duration) > 0 {
                isPlaying = false
            }
        }
        
        // Start playing
        newPlayer.play()
        isPlaying = true
    }
    
    private func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
    }
    
    private func loadVideoInfo() {
        Task {
            if let info = await VideoExporter.getVideoInfo(asset: playerItem.asset) {
                await MainActor.run {
                    sourceFPS = info.fps
                }
            }
        }
    }
    
    private func exportWithFPS(_ targetFPS: ExportFPS) {
        showExportSheet = false
        isExporting = true
        exportProgress = 0
        
        Task {
            do {
                let exporter = VideoExporter()
                let assetID = try await exporter.exportToPhotos(
                    sourceAsset: playerItem.asset,
                    targetFPS: targetFPS,
                    sourceFPS: sourceFPS
                ) { progress in
                    Task { @MainActor in
                        exportProgress = progress
                    }
                }
                
                // Calculate new duration for library entry
                let currentDuration = CMTimeGetSeconds(duration)
                let newDuration = VideoExporter.calculateNewDuration(
                    originalDuration: currentDuration,
                    sourceFPS: sourceFPS,
                    targetFPS: Double(targetFPS.rawValue)
                )
                
                // Add to library
                await SwingLibrary.shared.addSwing(
                    photoAssetID: assetID,
                    vantage: swing?.vantage ?? .dtl,
                    duration: newDuration,
                    notes: "Exported at \(targetFPS.shortName)"
                )
                
                await MainActor.run {
                    isExporting = false
                    showExportSuccess = true
                }
            } catch {
                print("❌ Export failed: \(error)")
                await MainActor.run {
                    isExporting = false
                }
            }
        }
    }
    
    // MARK: - Playback Actions
    
    private func togglePlayback() {
        guard let player else { return }
        
        if isPlaying {
            player.pause()
        } else {
            // If at end, restart
            if CMTimeCompare(currentTime, duration) >= 0 {
                seek(to: .zero)
            }
            player.rate = playbackSpeed
        }
        isPlaying.toggle()
    }
    
    private func seek(to time: CMTime) {
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }
    
    private func stepForward() {
        // Step one frame (assuming ~30fps base, but works for any)
        let frameDuration = CMTime(value: 1, timescale: 30)
        let newTime = CMTimeAdd(currentTime, frameDuration)
        if CMTimeCompare(newTime, duration) <= 0 {
            seek(to: newTime)
        }
    }
    
    private func stepBackward() {
        let frameDuration = CMTime(value: 1, timescale: 30)
        let newTime = CMTimeSubtract(currentTime, frameDuration)
        if CMTimeCompare(newTime, .zero) >= 0 {
            seek(to: newTime)
        } else {
            seek(to: .zero)
        }
    }
    
    private func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        if isPlaying {
            player?.rate = speed
        }
    }
    
    // MARK: - Helpers
    
    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard CMTimeGetSeconds(duration) > 0 else { return 0 }
        let fraction = CMTimeGetSeconds(currentTime) / CMTimeGetSeconds(duration)
        return CGFloat(fraction) * totalWidth
    }
    
    private func playheadOffset(in totalWidth: CGFloat) -> CGFloat {
        guard CMTimeGetSeconds(duration) > 0 else { return 0 }
        let fraction = CMTimeGetSeconds(currentTime) / CMTimeGetSeconds(duration)
        // Offset so the playhead center aligns with progress
        return CGFloat(fraction) * totalWidth - 9
    }
    
    private func formatTime(_ time: CMTime) -> String {
        let totalSeconds = CMTimeGetSeconds(time)
        guard totalSeconds.isFinite else { return "00.0" }
        let secs = Int(totalSeconds)
        let tenths = Int((totalSeconds * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%02d.%d", secs, tenths)
    }
    
    private func speedLabel(_ speed: Float) -> String {
        if speed == 1.0 {
            return "1x"
        } else if speed == 0.5 {
            return "0.5x"
        } else if speed == 0.25 {
            return "0.25x"
        } else if speed == 0.75 {
            return "0.75x"
        }
        return String(format: "%.2fx", speed)
    }
}

// MARK: - FPS Export Sheet

struct FPSExportSheet: View {
    let currentDuration: Double
    let sourceFPS: Double
    let vantage: Vantage
    let onExport: (ExportFPS) -> Void
    let onCancel: () -> Void
    
    @State private var selectedFPS: ExportFPS = .cinematic
    
    private func newDuration(for fps: ExportFPS) -> Double {
        VideoExporter.calculateNewDuration(
            originalDuration: currentDuration,
            sourceFPS: sourceFPS,
            targetFPS: Double(fps.rawValue)
        )
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let secs = Int(seconds)
        let tenths = Int((seconds * 10).truncatingRemainder(dividingBy: 10))
        if secs >= 60 {
            let mins = secs / 60
            let remainingSecs = secs % 60
            return String(format: "%d:%02d.%d", mins, remainingSecs, tenths)
        }
        return String(format: "%d.%ds", secs, tenths)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header info
                VStack(spacing: 8) {
                    Text("Export Slower Version")
                        .font(.title2.weight(.semibold))
                    
                    Text("Current: \(formatDuration(currentDuration)) at \(Int(sourceFPS))fps")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                // FPS options
                VStack(spacing: 12) {
                    ForEach(ExportFPS.allCases) { fps in
                        let duration = newDuration(for: fps)
                        let isSelected = selectedFPS == fps
                        
                        Button {
                            selectedFPS = fps
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(fps.displayName)
                                        .font(.headline)
                                        .foregroundColor(isSelected ? .white : .primary)
                                    
                                    Text("Duration: \(formatDuration(duration))")
                                        .font(.subheadline)
                                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                }
                                
                                Spacer()
                                
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? Color.blue : Color(.secondarySystemBackground))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Export button
                Button {
                    onExport(selectedFPS)
                } label: {
                    Text("Export at \(selectedFPS.shortName)")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
}

#Preview {
    LibraryView(onNavigateToCapture: {})
}

// MARK: - Video Import Helpers

/// Error type for import failures
enum ImportError: Error, LocalizedError {
    case noData
    case copyFailed
    
    var errorDescription: String? {
        switch self {
        case .noData:
            return "No video data received"
        case .copyFailed:
            return "Failed to copy video file"
        }
    }
}

/// Transferable wrapper for video files that copies to a temp location
struct VideoFileTransferable: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            // Copy the received file to our own temp location
            // This is important because the system may delete the original
            let tempDir = FileManager.default.temporaryDirectory
            let filename = "\(UUID().uuidString).mov"
            let destURL = tempDir.appendingPathComponent(filename)
            
            try FileManager.default.copyItem(at: received.file, to: destURL)
            
            return VideoFileTransferable(url: destURL)
        }
    }
}

// MARK: - PHPicker with Progress Support

/// A UIViewControllerRepresentable that wraps PHPickerViewController and provides progress tracking
/// Uses PHImageManager for reliable large video export instead of NSItemProvider
struct VideoPickerWithProgress: UIViewControllerRepresentable {
    let onVideoSelected: (URL) -> Void
    let onProgress: (Double, Int64, Int64) -> Void  // (fraction, completedBytes, totalBytes)
    let onCancel: () -> Void
    let onError: (Error) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPickerWithProgress
        private var exportSession: AVAssetExportSession?
        private var progressTimer: Timer?
        private var phImageRequestID: PHImageRequestID?
        
        init(_ parent: VideoPickerWithProgress) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Dismiss picker immediately
            picker.dismiss(animated: true)
            
            guard let result = results.first else {
                print("📹 Import: User cancelled picker")
                parent.onCancel()
                return
            }
            
            // Get the PHAsset identifier
            guard let assetIdentifier = result.assetIdentifier else {
                print("❌ Import: No asset identifier - falling back to itemProvider")
                fallbackToItemProvider(result: result)
                return
            }
            
            print("📹 Import: Got asset identifier: \(assetIdentifier)")
            
            // Fetch the PHAsset
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
            guard let asset = fetchResult.firstObject else {
                print("❌ Import: Could not fetch PHAsset - falling back to itemProvider")
                fallbackToItemProvider(result: result)
                return
            }
            
            print("📹 Import: Got PHAsset - duration: \(asset.duration)s, mediaType: \(asset.mediaType.rawValue)")
            
            // Request the video using PHImageManager
            let options = PHVideoRequestOptions()
            options.version = .current  // Get the edited version if available
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true  // Allow downloading from iCloud
            
            // Progress handler for iCloud downloads
            options.progressHandler = { [weak self] progress, error, stop, info in
                print("📹 iCloud download progress: \(Int(progress * 100))%")
                DispatchQueue.main.async {
                    self?.parent.onProgress(progress, Int64(progress * 100), 100)
                }
                if let error = error {
                    print("❌ iCloud download error: \(error.localizedDescription)")
                }
            }
            
            print("📹 Import: Requesting AVAsset from PHImageManager...")
            
            // Signal that import has started
            DispatchQueue.main.async {
                self.parent.onProgress(0.01, 0, 0)  // Show we're starting
            }
            
            phImageRequestID = PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { [weak self] avAsset, audioMix, info in
                guard let self = self else { return }
                
                if let error = info?[PHImageErrorKey] as? Error {
                    print("❌ Import: PHImageManager error - \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.parent.onError(error)
                    }
                    return
                }
                
                guard let avAsset = avAsset else {
                    print("❌ Import: No AVAsset received")
                    DispatchQueue.main.async {
                        self.parent.onError(ImportError.noData)
                    }
                    return
                }
                
                print("📹 Import: Got AVAsset, type: \(type(of: avAsset))")
                
                // If it's a URL asset, we can just copy the file
                if let urlAsset = avAsset as? AVURLAsset {
                    print("📹 Import: AVURLAsset with URL: \(urlAsset.url.lastPathComponent)")
                    self.copyVideoFile(from: urlAsset.url)
                } else {
                    // Need to export the asset (e.g., composition from slo-mo)
                    print("📹 Import: Need to export asset (not a URL asset)")
                    self.exportAsset(avAsset)
                }
            }
        }
        
        private func copyVideoFile(from sourceURL: URL) {
            // Get file size for logging
            if let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
               let size = attrs[.size] as? Int64 {
                print("📹 Import: Source file size: \(Double(size) / 1_000_000) MB")
            }
            
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let filename = "\(UUID().uuidString).mov"
                let destURL = tempDir.appendingPathComponent(filename)
                
                print("📹 Import: Copying to \(destURL.lastPathComponent)...")
                
                // For large files, copy with progress
                DispatchQueue.main.async {
                    self.parent.onProgress(0.5, 0, 0)  // Indicate copying
                }
                
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                print("✅ Import: Copy complete!")
                
                DispatchQueue.main.async {
                    self.parent.onVideoSelected(destURL)
                }
            } catch {
                print("❌ Import: Copy failed - \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.parent.onError(ImportError.copyFailed)
                }
            }
        }
        
        private func exportAsset(_ asset: AVAsset) {
            let tempDir = FileManager.default.temporaryDirectory
            let filename = "\(UUID().uuidString).mov"
            let destURL = tempDir.appendingPathComponent(filename)
            
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                print("❌ Import: Could not create export session")
                DispatchQueue.main.async {
                    self.parent.onError(ImportError.noData)
                }
                return
            }
            
            self.exportSession = exportSession
            exportSession.outputURL = destURL
            exportSession.outputFileType = .mov
            
            print("📹 Import: Starting export session...")
            
            // Start progress timer
            progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let session = self.exportSession else { return }
                let progress = Double(session.progress)
                print("📹 Export progress: \(Int(progress * 100))%")
                DispatchQueue.main.async {
                    self.parent.onProgress(progress, Int64(progress * 100), 100)
                }
            }
            
            exportSession.exportAsynchronously { [weak self] in
                guard let self = self else { return }
                
                self.progressTimer?.invalidate()
                self.progressTimer = nil
                
                switch exportSession.status {
                case .completed:
                    print("✅ Import: Export complete!")
                    DispatchQueue.main.async {
                        self.parent.onVideoSelected(destURL)
                    }
                case .failed:
                    print("❌ Import: Export failed - \(exportSession.error?.localizedDescription ?? "unknown")")
                    DispatchQueue.main.async {
                        self.parent.onError(exportSession.error ?? ImportError.noData)
                    }
                case .cancelled:
                    print("📹 Import: Export cancelled")
                    DispatchQueue.main.async {
                        self.parent.onCancel()
                    }
                default:
                    print("📹 Import: Export status: \(exportSession.status.rawValue)")
                }
            }
        }
        
        private func fallbackToItemProvider(result: PHPickerResult) {
            let itemProvider = result.itemProvider
            print("📹 Import: Fallback - using itemProvider")
            print("📹 Import: Registered types: \(itemProvider.registeredTypeIdentifiers)")
            
            guard itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                print("❌ Import: Item does not conform to movie type")
                parent.onError(ImportError.noData)
                return
            }
            
            // Signal start
            DispatchQueue.main.async {
                self.parent.onProgress(0.01, 0, 0)
            }
            
            _ = itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Import: itemProvider error - \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.parent.onError(error)
                    }
                    return
                }
                
                guard let sourceURL = url else {
                    print("❌ Import: No URL from itemProvider")
                    DispatchQueue.main.async {
                        self.parent.onError(ImportError.noData)
                    }
                    return
                }
                
                self.copyVideoFile(from: sourceURL)
            }
        }
    }
}
