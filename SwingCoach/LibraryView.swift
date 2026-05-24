//
//  LibraryView.swift
//  SwingCoach
//
//  Created by Ruari Craig on 01/11/2025.
//

import SwiftUI
import PhotosUI
import Photos
import AVKit
import UniformTypeIdentifiers
import UIKit

struct LibraryView: View {
    let onNavigateToCapture: () -> Void
    var onAnalyzeSwings: (([SavedSwing]) -> Void)? = nil

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var library = SwingLibrary.shared

    // Import flow
    @State private var importedVideoSource: TrimVideoSource? = nil
    @State private var isImporting = false
    @State private var importTask: Task<Void, Never>? = nil
    @State private var importStatusText: String = "Preparing import..."
    @State private var importProgress: Double? = nil  // 0.0-1.0, nil = indeterminate
    @State private var showVideoPicker = false
    @State private var showExperimentalSettings = false
    @State private var photoLibraryAccessStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var showLimitedPhotoAccessOptions = false

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

    private var shouldShowPhotoAccessBanner: Bool {
        photoLibraryAccessStatus != .authorized
    }

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
            .safeAreaInset(edge: .top) {
                if shouldShowPhotoAccessBanner {
                    photoAccessBanner
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
            }
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
                        Button {
                            showExperimentalSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Experimental settings")
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
                refreshPhotoLibraryAccessStatus()
                Task {
                    await loadLibraryAssetsIfPermitted()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                refreshPhotoLibraryAccessStatus()
                Task {
                    await loadLibraryAssetsIfPermitted()
                }
            }
            .sheet(isPresented: $showVideoPicker) {
                VideoPickerWithProgress(
                    onPickerDismissed: {
                        showVideoPicker = false
                    },
                    onVideoSelected: { source in
                        importedVideoSource = source
                        isImporting = false
                        importProgress = nil
                    },
                    onProgress: { fraction, completed, total in
                        isImporting = true
                        if total == 0 {
                            importProgress = nil
                            importStatusText = "Opening from Photos..."
                        } else {
                            importProgress = max(0, min(1, fraction))
                            importStatusText = "Loading video..."
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
            .sheet(isPresented: $showExperimentalSettings) {
                NavigationStack {
                    ExperimentalSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    showExperimentalSettings = false
                                }
                            }
                        }
                }
            }
            .confirmationDialog("Photos Access", isPresented: $showLimitedPhotoAccessOptions, titleVisibility: .visible) {
                Button("Continue Import") {
                    showVideoPicker = true
                }
                Button("Choose Allowed Videos") {
                    presentLimitedLibraryPicker()
                }
                Button("Open Settings") {
                    openAppSettings()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("SwingCoach currently has limited Photos access. Continue import for the slower fallback path, choose allowed videos so PhotoKit can reopen them directly, or switch to full access in Settings.")
            }
            .fullScreenCover(item: $importedVideoSource) { source in
                TrimView(
                    source: source,
                    onComplete: { clips, _ in
                        print("✅ Added \(clips.count) swings to library")
                        cleanupImport()
                    },
                    onCancel: {
                        cleanupImport()
                    }
                )
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

    private var photoAccessBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: photoLibraryAccessStatus == .limited ? "photo.stack" : "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.yellow)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(photoAccessBannerTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)

                Text(photoAccessBannerMessage)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(photoAccessBannerActionTitle) {
                handlePhotoAccessBannerAction()
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.yellow)
            .cornerRadius(8)
        }
        .padding(14)
        .background(Color.black.opacity(0.82))
        .cornerRadius(14)
    }

    private var photoAccessBannerTitle: String {
        switch photoLibraryAccessStatus {
        case .limited:
            return "Limited Photos Access"
        case .authorized:
            return ""
        case .denied, .restricted:
            return "Photos Access Off"
        case .notDetermined:
            return "Allow Photos Access"
        @unknown default:
            return "Photos Access Needed"
        }
    }

    private var photoAccessBannerMessage: String {
        switch photoLibraryAccessStatus {
        case .limited:
            return "SwingCoach has limited Photos access. Full access is the fastest path; otherwise only selected videos can use the fast reopen path."
        case .denied, .restricted:
            return "SwingCoach needs read access to show saved swings from Photos and reliably reopen imported videos."
        case .notDetermined:
            return "Grant Photos access so the library can show saved swings and import videos consistently."
        case .authorized:
            return ""
        @unknown default:
            return "Photos access affects imports and saved swing playback."
        }
    }

    private var photoAccessBannerActionTitle: String {
        switch photoLibraryAccessStatus {
        case .notDetermined:
            return "Allow"
        case .limited:
            return "Manage"
        case .denied, .restricted:
            return "Open Settings"
        case .authorized:
            return ""
        @unknown default:
            return "Open Settings"
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
                    beginImportFlow()
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

        return Group {
            if isSelecting {
                Button {
                    toggleSelection(swing)
                } label: {
                    swingCardContent(swing, isSelected: isSelected)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    SwingDetailView(swing: swing)
                } label: {
                    swingCardContent(swing, isSelected: isSelected)
                }
                .buttonStyle(.plain)
            }
        }
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

    private func swingCardContent(_ swing: SavedSwing, isSelected: Bool) -> some View {
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
                        if swing.analyzed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.green)
                                .shadow(radius: 2)
                        }
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
            beginImportFlow()
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

    private func refreshPhotoLibraryAccessStatus() {
        photoLibraryAccessStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    private func loadLibraryAssetsIfPermitted() async {
        guard photoLibraryAccessStatus == .authorized || photoLibraryAccessStatus == .limited else {
            return
        }

        if photoLibraryAccessStatus == .authorized {
            library.validateAssets()
        }
        await library.loadThumbnails()
    }

    private func beginImportFlow() {
        refreshPhotoLibraryAccessStatus()

        switch photoLibraryAccessStatus {
        case .authorized:
            showVideoPicker = true
        case .limited:
            showLimitedPhotoAccessOptions = true
        case .notDetermined:
            requestPhotoLibraryAccess(openPickerAfterAuthorization: true)
        case .denied, .restricted:
            openAppSettings()
        @unknown default:
            openAppSettings()
        }
    }

    private func handlePhotoAccessBannerAction() {
        switch photoLibraryAccessStatus {
        case .notDetermined:
            requestPhotoLibraryAccess(openPickerAfterAuthorization: false)
        case .limited:
            showLimitedPhotoAccessOptions = true
        case .denied, .restricted:
            openAppSettings()
        case .authorized:
            break
        @unknown default:
            openAppSettings()
        }
    }

    private func requestPhotoLibraryAccess(openPickerAfterAuthorization: Bool) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            Task { @MainActor in
                photoLibraryAccessStatus = status
                await loadLibraryAssetsIfPermitted()
                if openPickerAfterAuthorization {
                    switch status {
                    case .authorized:
                        showVideoPicker = true
                    case .limited:
                        showLimitedPhotoAccessOptions = true
                    default:
                        break
                    }
                }
            }
        }
    }

    private func presentLimitedLibraryPicker() {
        DispatchQueue.main.async {
            guard let rootViewController = activeRootViewController() else {
                openAppSettings()
                return
            }

            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootViewController)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                refreshPhotoLibraryAccessStatus()
                Task {
                    await loadLibraryAssetsIfPermitted()
                }
            }
        }
    }

    private func activeRootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        var controller = keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }

    private func cancelImport() {
        importTask?.cancel()
        importTask = nil
        isImporting = false
        importProgress = nil
        showVideoPicker = false

        // Clean up any partial import
        if let url = importedVideoSource?.cleanupURL {
            try? FileManager.default.removeItem(at: url)
        }
        importedVideoSource = nil
    }

    private func cleanupImport() {
        if let url = importedVideoSource?.cleanupURL {
            try? FileManager.default.removeItem(at: url)
        }
        importedVideoSource = nil
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

struct PlaybackChromeView<Header: View, OverlayAccessory: View>: View {
    let playerItem: AVPlayerItem
    let initialPlaybackRate: Float
    let playbackEnabled: Bool
    let showsSpeedControls: Bool
    let startsPlaying: Bool
    let allowsFullscreen: Bool

    private let header: Header
    private let overlayAccessory: OverlayAccessory
    private let contentOverlay: (CMTime, CGSize) -> AnyView

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: CMTime = .zero
    @State private var duration: CMTime = .zero
    @State private var playbackSpeed: Float
    @State private var timeObserver: Any?
    @State private var isScrubbing = false
    @State private var resumePlaybackAfterScrub = false
    @State private var transportHoldTask: Task<Void, Never>?
    @State private var transportGestureDirection: Int?
    @State private var didActivateTransportHold = false
    @State private var activeTransportDirection: Int?
    @State private var showsFullscreen = false

    private let speedOptions: [Float] = [0.25, 0.5, 0.75, 1.0]

    init(
        playerItem: AVPlayerItem,
        initialPlaybackRate: Float = 1.0,
        playbackEnabled: Bool = true,
        showsSpeedControls: Bool = true,
        startsPlaying: Bool = true,
        allowsFullscreen: Bool = true,
        contentOverlay: @escaping (CMTime, CGSize) -> AnyView = { _, _ in AnyView(EmptyView()) },
        @ViewBuilder header: () -> Header,
        @ViewBuilder overlayAccessory: () -> OverlayAccessory
    ) {
        self.playerItem = playerItem
        self.initialPlaybackRate = initialPlaybackRate
        self.playbackEnabled = playbackEnabled
        self.showsSpeedControls = showsSpeedControls
        self.startsPlaying = startsPlaying
        self.allowsFullscreen = allowsFullscreen
        self.header = header()
        self.overlayAccessory = overlayAccessory()
        self.contentOverlay = contentOverlay
        _playbackSpeed = State(initialValue: max(0.1, initialPlaybackRate))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            videoArea
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanup()
        }
        .onChange(of: playbackEnabled) { _, enabled in
            guard !enabled else { return }
            player?.pause()
            isPlaying = false
            stopTransportHold()
        }
        .fullScreenCover(isPresented: $showsFullscreen) {
            fullscreenPlayback
        }
    }

    private var videoArea: some View {
        GeometryReader { geometry in
            let timelineWidth = max(geometry.size.width - 28, 1)

            ZStack {
                Group {
                    if let player {
                        VideoPlayer(player: player)
                            .disabled(true)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                contentOverlay(currentTime, geometry.size)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)

                transportTouchLayer

                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.62),
                            Color.black.opacity(0.18),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 140)

                    Spacer(minLength: 0)

                    LinearGradient(
                        colors: [
                            .clear,
                            Color.black.opacity(0.3),
                            Color.black.opacity(0.76)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 160)
                }
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 10) {
                        header

                        Spacer(minLength: 0)

                        playerCornerControls
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                    Spacer(minLength: 0)

                    if activeTransportDirection != nil {
                        transportFeedback
                            .padding(.bottom, isScrubbing ? 16 : 30)
                    }

                    if isScrubbing {
                        scrubTimeBadge
                            .padding(.bottom, 10)
                    }

                    integratedTimeline(width: timelineWidth)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                }

                VStack {
                    Spacer()

                    HStack {
                        Spacer()
                        overlayAccessory
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 34)
                }
            }
            .background(Color.black)
        }
    }

    private var playerCornerControls: some View {
        HStack(spacing: 8) {
            if showsSpeedControls {
                Button {
                    cyclePlaybackSpeed()
                } label: {
                    Text(speedLabel(playbackSpeed))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 44, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.yellow)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change playback speed")
                .accessibilityValue(speedLabel(playbackSpeed))
            }

            if allowsFullscreen {
                Button {
                    showsFullscreen = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.58))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open full screen")
            }
        }
    }

    private var fullscreenPlayback: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            PlaybackChromeView<EmptyView, EmptyView>(
                playerItem: playerItem,
                initialPlaybackRate: playbackSpeed,
                playbackEnabled: playbackEnabled,
                showsSpeedControls: showsSpeedControls,
                startsPlaying: false,
                allowsFullscreen: false,
                contentOverlay: contentOverlay
            ) {
                EmptyView()
            } overlayAccessory: {
                EmptyView()
            }

            Button {
                showsFullscreen = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.62)))
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.leading, 18)
            .accessibilityLabel("Close full screen")
        }
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard value.translation.height > 80, abs(value.translation.width) < 120 else { return }
                    showsFullscreen = false
                }
        )
    }

    private var transportTouchLayer: some View {
        HStack(spacing: 0) {
            transportTouchZone(direction: -1)
            transportTouchZone(direction: 0)
            transportTouchZone(direction: 1)
        }
        .padding(.bottom, 44)
    }

    private var transportFeedback: some View {
        HStack {
            if activeTransportDirection == -1 {
                transportFeedbackIcon(systemName: "backward.fill")
            } else {
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            if activeTransportDirection == 1 {
                transportFeedbackIcon(systemName: "forward.fill")
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 36)
    }

    private func transportFeedbackIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 48, height: 48)
            .background(Circle().fill(Color.black.opacity(0.46)))
    }

    private func transportTouchZone(direction: Int) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        beginTransportGesture(direction: direction)
                    }
                    .onEnded { _ in
                        endTransportGesture(direction: direction)
                    }
            )
    }

    private var scrubTimeBadge: some View {
        Text("\(formatTime(currentTime))/\(formatTime(duration))")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.7))
            )
    }

    private func integratedTimeline(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(height: 4)

            Capsule()
                .fill(Color.yellow)
                .frame(width: progressWidth(in: width), height: 4)

            Circle()
                .fill(Color.white)
                .frame(width: isScrubbing ? 16 : 12, height: isScrubbing ? 16 : 12)
                .shadow(color: .black.opacity(0.28), radius: 3)
                .offset(x: playheadOffset(in: width))
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    beginScrubbing()
                    let fraction = max(0, min(1, value.location.x / width))
                    let newTime = CMTimeMultiplyByFloat64(duration, multiplier: Float64(fraction))
                    seek(to: newTime)
                }
                .onEnded { _ in
                    endScrubbing()
                }
        )
    }

    private func setupPlayer() {
        guard player == nil else { return }

        // AVPlayerItem instances are single-owner; SwiftUI can recreate this chrome
        // around the same source item during result-card updates, so each player
        // needs a fresh item backed by the same asset.
        let playbackItem = AVPlayerItem(asset: playerItem.asset)
        let newPlayer = AVPlayer(playerItem: playbackItem)
        newPlayer.actionAtItemEnd = .pause
        player = newPlayer

        Task {
            if let dur = try? await playbackItem.asset.load(.duration) {
                await MainActor.run {
                    duration = dur
                }
            }
        }

        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time

            if CMTimeCompare(time, duration) >= 0 && CMTimeGetSeconds(duration) > 0 {
                isPlaying = false
            }
        }

        guard playbackEnabled, startsPlaying else { return }
        newPlayer.playImmediately(atRate: playbackSpeed)
        isPlaying = true
    }

    private func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
        stopTransportHold()
    }

    private func togglePlayback() {
        guard playbackEnabled, let player else { return }

        if isPlaying {
            player.pause()
        } else {
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

    private func beginScrubbing() {
        guard !isScrubbing else { return }
        resumePlaybackAfterScrub = isPlaying
        player?.pause()
        isPlaying = false
        isScrubbing = true
    }

    private func endScrubbing() {
        isScrubbing = false
        guard playbackEnabled, resumePlaybackAfterScrub else { return }
        player?.playImmediately(atRate: playbackSpeed)
        isPlaying = true
        resumePlaybackAfterScrub = false
    }

    private func beginTransportGesture(direction: Int) {
        guard playbackEnabled, !isScrubbing else { return }
        guard transportGestureDirection != direction else { return }

        stopTransportHold()
        transportGestureDirection = direction
        didActivateTransportHold = false
        activeTransportDirection = nil

        guard direction != 0 else { return }

        transportHoldTask = Task {
            let holdStart = Date()
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                didActivateTransportHold = true
                activeTransportDirection = direction
                step(direction: direction)
            }

            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(holdStart)
                let interval = transportRepeatInterval(for: elapsed)
                let multiplier = transportStepMultiplier(for: elapsed)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    step(direction: direction, multiplier: multiplier)
                }
            }
        }
    }

    private func endTransportGesture(direction: Int) {
        guard transportGestureDirection == direction else { return }
        let didHold = didActivateTransportHold
        stopTransportHold()

        if !didHold {
            togglePlayback()
        }
    }

    private func stopTransportHold() {
        transportHoldTask?.cancel()
        transportHoldTask = nil
        transportGestureDirection = nil
        didActivateTransportHold = false
        activeTransportDirection = nil
    }

    private func step(direction: Int, multiplier: Int = 1) {
        if isPlaying {
            player?.pause()
            isPlaying = false
        }

        let frameDuration = CMTimeMultiplyByFloat64(
            CMTime(value: 1, timescale: 30),
            multiplier: Double(multiplier)
        )
        let candidateTime = direction >= 0
            ? CMTimeAdd(currentTime, frameDuration)
            : CMTimeSubtract(currentTime, frameDuration)

        let clampedTime: CMTime
        if CMTimeCompare(candidateTime, .zero) < 0 {
            clampedTime = .zero
        } else if CMTimeCompare(candidateTime, duration) > 0 {
            clampedTime = duration
        } else {
            clampedTime = candidateTime
        }

        seek(to: clampedTime)
    }

    private func stepForward() {
        step(direction: 1)
    }

    private func stepBackward() {
        step(direction: -1)
    }

    private func transportRepeatInterval(for holdDuration: TimeInterval) -> Double {
        switch holdDuration {
        case 0..<1.0:
            return 0.12
        case 1.0..<2.2:
            return 0.08
        default:
            return 0.055
        }
    }

    private func transportStepMultiplier(for holdDuration: TimeInterval) -> Int {
        switch holdDuration {
        case 0..<1.0:
            return 1
        case 1.0..<2.2:
            return 2
        default:
            return 4
        }
    }

    private func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        if isPlaying {
            player?.rate = speed
        }
    }

    private func cyclePlaybackSpeed() {
        guard let currentIndex = speedOptions.firstIndex(of: playbackSpeed) else {
            setSpeed(1.0)
            return
        }
        let nextIndex = speedOptions.index(after: currentIndex)
        setSpeed(speedOptions[nextIndex == speedOptions.endIndex ? speedOptions.startIndex : nextIndex])
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard CMTimeGetSeconds(duration) > 0 else { return 0 }
        let fraction = CMTimeGetSeconds(currentTime) / CMTimeGetSeconds(duration)
        return CGFloat(fraction) * totalWidth
    }

    private func playheadOffset(in totalWidth: CGFloat) -> CGFloat {
        guard CMTimeGetSeconds(duration) > 0 else { return 0 }
        let fraction = CMTimeGetSeconds(currentTime) / CMTimeGetSeconds(duration)
        let thumbRadius: CGFloat = isScrubbing ? 8 : 6
        return CGFloat(fraction) * totalWidth - thumbRadius
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

extension PlaybackChromeView where OverlayAccessory == EmptyView {
    init(
        playerItem: AVPlayerItem,
        initialPlaybackRate: Float = 1.0,
        playbackEnabled: Bool = true,
        showsSpeedControls: Bool = true,
        startsPlaying: Bool = true,
        allowsFullscreen: Bool = true,
        contentOverlay: @escaping (CMTime, CGSize) -> AnyView = { _, _ in AnyView(EmptyView()) },
        @ViewBuilder header: () -> Header
    ) {
        self.init(
            playerItem: playerItem,
            initialPlaybackRate: initialPlaybackRate,
            playbackEnabled: playbackEnabled,
            showsSpeedControls: showsSpeedControls,
            startsPlaying: startsPlaying,
            allowsFullscreen: allowsFullscreen,
            contentOverlay: contentOverlay,
            header: header,
            overlayAccessory: { EmptyView() }
        )
    }
}

struct SwingPlaybackView: View {
    let playerItem: AVPlayerItem
    let swing: SavedSwing?
    let onDismiss: () -> Void

    @State private var duration: CMTime = .zero

    // Export state
    @State private var showExportSheet = false
    @State private var isExporting = false
    @State private var exportProgress: Float = 0
    @State private var showExportSuccess = false
    @State private var sourceFPS: Double = 30

    var body: some View {
        ZStack {
            PlaybackChromeView(playerItem: playerItem) {
                topBar
            }

            if isExporting {
                exportProgressOverlay
            }
        }
        .onAppear {
            loadVideoInfo()
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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.black.opacity(0.42)))
                    .shadow(radius: 4)
            }
            .padding(.trailing, 12)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.black.opacity(0.42)))
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

    private func loadVideoInfo() {
        Task {
            if let info = await VideoExporter.getVideoInfo(asset: playerItem.asset) {
                await MainActor.run {
                    sourceFPS = info.fps
                    duration = CMTime(seconds: info.duration, preferredTimescale: 600)
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
                SwingLibrary.shared.addSwing(
                    photoAssetID: assetID,
                    vantage: swing?.vantage ?? .dtl,
                    duration: newDuration,
                    notes: "Exported at \(targetFPS.shortName)",
                    initialThumbnail: swing?.thumbnail
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
/// Uses PhotoKit to open the selected video without duplicating the full source upfront.
struct VideoPickerWithProgress: UIViewControllerRepresentable {
    let onPickerDismissed: () -> Void
    let onVideoSelected: (TrimVideoSource) -> Void
    let onProgress: (Double, Int64, Int64) -> Void  // (fraction, completedBytes, totalBytes)
    let onCancel: () -> Void
    let onError: (Error) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current

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
        private var importStartTime: Date?

        init(_ parent: VideoPickerWithProgress) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            importStartTime = Date()

            // Dismiss picker first, then begin the handoff/import work.
            picker.dismiss(animated: true) {
                DispatchQueue.main.async {
                    self.parent.onPickerDismissed()
                }
                self.handlePickedResults(results)
            }
        }

        private func handlePickedResults(_ results: [PHPickerResult]) {
            guard let result = results.first else {
                print("📹 Import: User cancelled picker")
                DispatchQueue.main.async {
                    self.parent.onCancel()
                }
                return
            }

            let readWriteStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            let canAttemptAssetFetch = readWriteStatus == .authorized || readWriteStatus == .limited
            if !canAttemptAssetFetch {
                print("📹 Import: Photos access is \(readWriteStatus.rawValue); using picker file handoff instead of PHAsset fast path")
                fallbackToItemProvider(result: result)
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

            DispatchQueue.main.async {
                print("📹 Import: Got PHAsset - duration: \(asset.duration)s, mediaType: \(asset.mediaType.rawValue)")
                if let importStartTime = self.importStartTime {
                    print("📹 Import: Handing off to trim after \(String(format: "%.2f", Date().timeIntervalSince(importStartTime)))s")
                }
                self.parent.onVideoSelected(
                    .photoLibrary(
                        assetIdentifier: assetIdentifier,
                        durationSeconds: asset.duration
                    )
                )
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

                // Copy is currently an indeterminate stage.
                DispatchQueue.main.async {
                    self.parent.onProgress(0, 0, 0)
                }

                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                print("✅ Import: Copy complete!")

                DispatchQueue.main.async {
                    self.parent.onProgress(1.0, 100, 100)
                    self.parent.onVideoSelected(.localFile(url: destURL))
                }
            } catch {
                print("❌ Import: Copy failed - \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.parent.onError(ImportError.copyFailed)
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
                self.parent.onProgress(0, 0, 0)
            }

            _ = itemProvider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, isInPlace, error in
                guard let self = self else { return }

                if let error = error {
                    print("❌ Import: in-place file handoff failed - \(error.localizedDescription)")
                    self.loadCopiedFileRepresentation(from: itemProvider)
                    return
                }

                guard let sourceURL = url else {
                    print("❌ Import: No in-place URL from itemProvider - falling back to copied file")
                    self.loadCopiedFileRepresentation(from: itemProvider)
                    return
                }

                if isInPlace {
                    print("📹 Import: Using in-place file URL from picker")
                    DispatchQueue.main.async {
                        if let importStartTime = self.importStartTime {
                            print("📹 Import: Handing off in-place file after \(String(format: "%.2f", Date().timeIntervalSince(importStartTime)))s")
                        }
                        self.parent.onVideoSelected(.externalFile(url: sourceURL))
                    }
                } else {
                    print("📹 Import: Picker provided a temporary copied file; promoting into app temp storage")
                    self.copyVideoFile(from: sourceURL)
                }
            }
        }

        private func loadCopiedFileRepresentation(from itemProvider: NSItemProvider) {
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
