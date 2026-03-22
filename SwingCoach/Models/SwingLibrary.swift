//
//  SwingLibrary.swift
//  SwingCoach
//
//  Created by AI Assistant on 22/12/2024.
//

import Foundation
import Photos
import UIKit
import Combine

/// Metadata for a saved swing clip (the actual video lives in Photos library)
struct SavedSwing: Identifiable, Codable, Equatable {
    let id: UUID
    let photoAssetID: String  // PHAsset.localIdentifier
    var vantage: Vantage
    var duration: Double  // seconds
    var createdAt: Date
    var notes: String?
    var analyzed: Bool
    
    // Not persisted - loaded at runtime
    var thumbnail: UIImage?
    var videoURL: URL?
    
    enum CodingKeys: String, CodingKey {
        case id, photoAssetID, vantage, duration, createdAt, notes, analyzed
    }
    
    // Custom Equatable (ignore non-codable properties)
    static func == (lhs: SavedSwing, rhs: SavedSwing) -> Bool {
        lhs.id == rhs.id &&
        lhs.photoAssetID == rhs.photoAssetID &&
        lhs.vantage == rhs.vantage &&
        lhs.duration == rhs.duration &&
        lhs.createdAt == rhs.createdAt &&
        lhs.notes == rhs.notes &&
        lhs.analyzed == rhs.analyzed
    }
}

/// Manages the collection of saved swing clips
/// Videos live in Photos library, metadata lives in app's Documents
@MainActor
class SwingLibrary: ObservableObject {
    @Published var swings: [SavedSwing] = []
    @Published var isLoading = false
    
    private let storageURL: URL
    private let thumbnailTargetSize = CGSize(width: 240, height: 140)
    
    static let shared = SwingLibrary()
    
    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = documents.appendingPathComponent("swing_library.json")
        loadFromDisk()
    }
    
    // MARK: - CRUD Operations
    
    /// Add a new swing after saving to Photos
    func addSwing(
        photoAssetID: String,
        vantage: Vantage,
        duration: Double,
        notes: String? = nil,
        initialThumbnail: UIImage? = nil
    ) {
        var swing = SavedSwing(
            id: UUID(),
            photoAssetID: photoAssetID,
            vantage: vantage,
            duration: duration,
            createdAt: Date(),
            notes: notes,
            analyzed: false
        )
        swing.thumbnail = initialThumbnail
        swings.insert(swing, at: 0)  // Newest first
        saveToDisk()
        
        Task {
            await refreshThumbnail(
                forPhotoAssetID: photoAssetID,
                retryDelays: initialThumbnail == nil ? [0.35, 1.0, 2.0, 4.0] : [1.0, 3.0]
            )
        }
    }
    
    /// Remove a swing (doesn't delete from Photos - user manages that)
    func removeSwing(_ swing: SavedSwing) {
        swings.removeAll { $0.id == swing.id }
        saveToDisk()
    }
    
    /// Update swing metadata
    func updateSwing(_ swing: SavedSwing) {
        if let index = swings.firstIndex(where: { $0.id == swing.id }) {
            swings[index] = swing
            saveToDisk()
        }
    }
    
    /// Mark swing as analyzed
    func markAnalyzed(_ swing: SavedSwing) {
        if let index = swings.firstIndex(where: { $0.id == swing.id }) {
            swings[index].analyzed = true
            saveToDisk()
        }
    }
    
    // MARK: - Photos Integration
    
    /// Load thumbnails for all swings from Photos library
    func loadThumbnails() async {
        isLoading = true
        
        let assetIDs = swings.map { $0.photoAssetID }
        guard !assetIDs.isEmpty else {
            isLoading = false
            return
        }
        
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        
        fetchResult.enumerateObjects { asset, _, _ in
            imageManager.requestImage(
                for: asset,
                targetSize: self.thumbnailTargetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                Task { @MainActor in
                    if let index = self.swings.firstIndex(where: { $0.photoAssetID == asset.localIdentifier }) {
                        self.swings[index].thumbnail = image
                    }
                }
            }
        }
        
        isLoading = false
    }

    private func refreshThumbnail(forPhotoAssetID photoAssetID: String, retryDelays: [TimeInterval]) async {
        guard swings.contains(where: { $0.photoAssetID == photoAssetID }) else { return }
        
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [photoAssetID], options: nil)
        guard let asset = fetchResult.firstObject else { return }
        
        for delay in [0.0] + retryDelays {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            
            if let image = await requestThumbnailImage(for: asset) {
                if let index = swings.firstIndex(where: { $0.photoAssetID == photoAssetID }) {
                    swings[index].thumbnail = image
                }
                return
            }
        }
    }
    
    private func requestThumbnailImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            
            var didResume = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: thumbnailTargetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !didResume else { return }
                
                if let image {
                    didResume = true
                    continuation.resume(returning: image)
                    return
                }
                
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? NSError
                
                if cancelled || error != nil || !isDegraded {
                    didResume = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    /// Get an AVPlayerItem for a swing (handles slow-mo and edited videos properly)
    func getPlayerItem(for swing: SavedSwing) async -> AVPlayerItem? {
        await withCheckedContinuation { continuation in
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [swing.photoAssetID], options: nil)
            
            guard let asset = fetchResult.firstObject else {
                continuation.resume(returning: nil)
                return
            }
            
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true  // Allow iCloud downloads
            
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { playerItem, info in
                continuation.resume(returning: playerItem)
            }
        }
    }
    
    /// Get the video URL for a swing (for export/upload - may not work for slow-mo)
    func getVideoURL(for swing: SavedSwing) async -> URL? {
        await withCheckedContinuation { continuation in
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [swing.photoAssetID], options: nil)
            
            guard let asset = fetchResult.firstObject else {
                continuation.resume(returning: nil)
                return
            }
            
            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    /// Check if Photos contains the assets we expect (user may have deleted some)
    func validateAssets() {
        let assetIDs = swings.map { $0.photoAssetID }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        
        var validIDs = Set<String>()
        fetchResult.enumerateObjects { asset, _, _ in
            validIDs.insert(asset.localIdentifier)
        }
        
        // Remove swings whose assets no longer exist
        let originalCount = swings.count
        swings.removeAll { !validIDs.contains($0.photoAssetID) }
        
        if swings.count != originalCount {
            print("⚠️ Removed \(originalCount - swings.count) swings with missing assets")
            saveToDisk()
        }
    }
    
    // MARK: - Persistence
    
    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(swings)
            try data.write(to: storageURL)
        } catch {
            print("❌ Failed to save library: \(error)")
        }
    }
    
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: storageURL)
            swings = try JSONDecoder().decode([SavedSwing].self, from: data)
            print("📚 Loaded \(swings.count) swings from library")
        } catch {
            print("❌ Failed to load library: \(error)")
            swings = []
        }
    }
    
    // MARK: - Stats
    
    var totalSwings: Int { swings.count }
    var analyzedSwings: Int { swings.filter { $0.analyzed }.count }
    
    func swings(for vantage: Vantage) -> [SavedSwing] {
        swings.filter { $0.vantage == vantage }
    }
}

// MARK: - Helper to get PHAsset ID after saving

extension PHPhotoLibrary {
    /// Save video and return the asset identifier
    static func saveVideoAndGetID(url: URL) async -> String? {
        await withCheckedContinuation { continuation in
            var assetID: String?
            
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized else {
                    continuation.resume(returning: nil)
                    return
                }
                
                PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                    assetID = request?.placeholderForCreatedAsset?.localIdentifier
                } completionHandler: { success, error in
                    if success, let id = assetID {
                        continuation.resume(returning: id)
                    } else {
                        print("❌ Save failed: \(error?.localizedDescription ?? "unknown")")
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}
