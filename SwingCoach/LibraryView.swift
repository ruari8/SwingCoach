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
    
    @StateObject private var library = SwingLibrary.shared
    
    // Import flow
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var importedVideoURL: URL? = nil
    @State private var showTrimView = false
    @State private var isImporting = false
    
    // Playback
    @State private var selectedSwing: SavedSwing? = nil
    @State private var playbackURL: URL? = nil
    @State private var showPlayback = false
    
    // Filter
    @State private var filterVantage: Vantage? = nil
    
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
                    filterMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    importButton
                }
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
                if let url = playbackURL {
                    SwingPlaybackView(url: url, swing: selectedSwing) {
                        showPlayback = false
                        playbackURL = nil
                        selectedSwing = nil
                    }
                }
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
        ScrollView {
            // Stats header
            statsHeader
                .padding(.horizontal)
                .padding(.top, 8)
            
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(filteredSwings) { swing in
                    swingCard(swing)
                }
            }
            .padding()
        }
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
        Button {
            loadAndPlay(swing)
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
                    
                    // Play icon overlay
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                        .shadow(radius: 4)
                    
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
            Button(role: .destructive) {
                library.removeSwing(swing)
            } label: {
                Label("Remove from Library", systemImage: "trash")
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
    
    private var importButton: some View {
        PhotosPicker(selection: $selectedItem, matching: .videos) {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
        }
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
        
        Task {
            if let url = await library.getVideoURL(for: swing) {
                await MainActor.run {
                    playbackURL = url
                    showPlayback = true
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
    let url: URL
    let swing: SavedSwing?
    let onDismiss: () -> Void
    
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let player {
                VideoPlayer(player: player)
            }
            
            VStack {
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
                
                Spacer()
            }
        }
        .onAppear {
            let newPlayer = AVPlayer(url: url)
            newPlayer.play()
            player = newPlayer
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

#Preview {
    LibraryView(onNavigateToCapture: {})
}
