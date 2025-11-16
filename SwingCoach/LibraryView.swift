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
    
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var statusText: String = "No video chosen"
    @State private var player: AVPlayer? = nil
    
    var body: some View {
        VStack {
            Image(systemName: "film")
            Text("Library")
            PhotosPicker(
                "Pick a video",
                selection: $selectedItem,
                matching: .videos
            )
            .padding(.top, 12)
            
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 300)
                    .padding(.top, 16)
            }
            
            Button("Open Camera Tab") {
                onNavigateToCapture()
            }
            .padding(.top, 12)
        }
        .font(.title)
        .padding()
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else {
                statusText = "No video chosen"
                player = nil
                return
            }
            
            statusText = "Loading video..."
            
            Task {
                do {
                    let data = try await newItem.loadTransferable(type: Data.self)
                    
                    guard let data else {
                        statusText = "Failed to load video"
                        return
                    }
                    
                    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("mov")
                    
                    try data.write(to: tmpURL)
                    
                    let newPlayer = AVPlayer(url: tmpURL)
                    
                    await MainActor.run {
                        player = newPlayer
                        statusText = "Video loaded"
                    }
                } catch {
                    await MainActor.run {
                        statusText = "Error loading video"
                        player = nil
                    }
                    print("Error loading video", error)
                }
            }
        }
    }
}

#Preview {
    LibraryView(onNavigateToCapture: {})
}
