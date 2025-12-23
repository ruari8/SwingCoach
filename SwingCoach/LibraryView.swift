//
//  LibraryView.swift
//  SwingCoach
//
//  Created by Ruari Craig on 01/11/2025.
//

import SwiftUI
import PhotosUI
import AVKit

struct LibraryView: View {
    let onNavigateToCapture: () -> Void
    var onAnalyzeSwings: (([SavedSwing]) -> Void)? = nil
    
    @StateObject private var library = SwingLibrary.shared
    
    // Import flow
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var importedVideoURL: URL? = nil
    @State private var showTrimView = false
    @State private var isImporting = false
    
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
            .onChange(of: selectedItem) { _, newItem in
                handleImport(newItem)
            }
            .fullScreenCover(isPresented: $showTrimView) {
                if let url = importedVideoURL {
                    TrimView(
                        sourceURL: url,
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
                
                PhotosPicker(selection: $selectedItem, matching: .videos) {
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
        PhotosPicker(selection: $selectedItem, matching: .videos) {
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
    
    // MARK: - Actions
    
    private func handleImport(_ item: PhotosPickerItem?) {
        guard let item else { return }
        
        isImporting = true
        
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    isImporting = false
                    return
                }
                
                let tmpURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")
                
                try data.write(to: tmpURL)
                
                await MainActor.run {
                    importedVideoURL = tmpURL
                    isImporting = false
                    showTrimView = true
                    selectedItem = nil
                }
            } catch {
                print("❌ Import failed: \(error)")
                await MainActor.run {
                    isImporting = false
                    selectedItem = nil
                }
            }
        }
    }
    
    private func cleanupImport() {
        if let url = importedVideoURL {
            try? FileManager.default.removeItem(at: url)
        }
        importedVideoURL = nil
        selectedItem = nil
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
