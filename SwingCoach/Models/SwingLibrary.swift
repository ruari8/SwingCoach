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
import AVFoundation

/// Metadata for a saved swing clip (the actual video lives in Photos library)
struct SavedSwing: Identifiable, Codable, Equatable {
    let id: UUID
    let photoAssetID: String  // PHAsset.localIdentifier
    var vantage: Vantage
    var duration: Double  // seconds
    var createdAt: Date
    var notes: String?
    var analyzed: Bool
    var isFavorite: Bool
    var isReference: Bool
    var title: String?
    // Filename (not full path) of an app-owned copy of the clip, if one exists.
    // Lets playback open the local file directly instead of resolving Photos.
    var localVideoFilename: String? = nil

    // Not persisted - loaded at runtime
    var thumbnail: UIImage?
    var videoURL: URL?

    init(
        id: UUID,
        photoAssetID: String,
        vantage: Vantage,
        duration: Double,
        createdAt: Date,
        notes: String?,
        analyzed: Bool,
        isFavorite: Bool = false,
        isReference: Bool = false,
        title: String? = nil,
        localVideoFilename: String? = nil
    ) {
        self.id = id
        self.photoAssetID = photoAssetID
        self.vantage = vantage
        self.duration = duration
        self.createdAt = createdAt
        self.notes = notes
        self.analyzed = analyzed
        self.isFavorite = isFavorite
        self.isReference = isReference
        self.title = title
        self.localVideoFilename = localVideoFilename
    }

    enum CodingKeys: String, CodingKey {
        case id, photoAssetID, vantage, duration, createdAt, notes, analyzed, isFavorite, isReference, title, localVideoFilename
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        photoAssetID = try container.decode(String.self, forKey: .photoAssetID)
        vantage = try container.decode(Vantage.self, forKey: .vantage)
        duration = try container.decode(Double.self, forKey: .duration)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        analyzed = try container.decode(Bool.self, forKey: .analyzed)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isReference = try container.decodeIfPresent(Bool.self, forKey: .isReference) ?? false
        title = try container.decodeIfPresent(String.self, forKey: .title)
        localVideoFilename = try container.decodeIfPresent(String.self, forKey: .localVideoFilename)
    }

    // Custom Equatable (ignore non-codable properties)
    static func == (lhs: SavedSwing, rhs: SavedSwing) -> Bool {
        lhs.id == rhs.id &&
        lhs.photoAssetID == rhs.photoAssetID &&
        lhs.vantage == rhs.vantage &&
        lhs.duration == rhs.duration &&
        lhs.createdAt == rhs.createdAt &&
        lhs.notes == rhs.notes &&
        lhs.analyzed == rhs.analyzed &&
        lhs.isFavorite == rhs.isFavorite &&
        lhs.isReference == rhs.isReference &&
        lhs.title == rhs.title &&
        lhs.localVideoFilename == rhs.localVideoFilename
    }
}

/// Manages the collection of saved swing clips
/// Videos live in Photos library, metadata lives in app's Documents
@MainActor
class SwingLibrary: ObservableObject {
    enum DeletionError: LocalizedError {
        case photosAccessDenied
        case photosDeleteFailed(String)

        var errorDescription: String? {
            switch self {
            case .photosAccessDenied:
                return "Photos access is required to delete this swing from the phone."
            case .photosDeleteFailed(let message):
                return "The swing could not be deleted from Photos: \(message)"
            }
        }
    }

    @Published var swings: [SavedSwing] = []
    @Published var isLoading = false
    
    private let storageURL: URL
    private let videosDirectory: URL
    private let thumbnailTargetSize = CGSize(width: 240, height: 140)

    static let shared = SwingLibrary()

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = documents.appendingPathComponent("swing_library.json")

        // App-owned copies of swing clips live here. Application Support is
        // persistent (unlike Caches) and we exclude it from iCloud/device backup
        // since every clip is re-derivable from Photos.
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        var videos = support.appendingPathComponent("SwingVideos", isDirectory: true)
        try? FileManager.default.createDirectory(at: videos, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? videos.setResourceValues(resourceValues)
        videosDirectory = videos

        loadFromDisk()
        installBundledReferenceSwings()
    }

    /// Local URL of the app-owned clip copy, if it exists on disk.
    func localVideoURL(for swing: SavedSwing) -> URL? {
        guard let name = swing.localVideoFilename else { return nil }
        let url = videosDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Copy a clip file into app storage, returning the stored filename.
    private func storeLocalVideo(from sourceURL: URL, swingID: UUID) -> String? {
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let filename = "\(swingID.uuidString).\(ext)"
        let destination = videosDirectory.appendingPathComponent(filename)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return filename
        } catch {
            print("⚠️ Failed to store local swing video: \(error)")
            return nil
        }
    }

    /// One-time backfill: after resolving a swing from Photos, copy the file
    /// locally (off the main thread) so the next open is instant.
    private func backfillLocalVideo(from sourceURL: URL, for swing: SavedSwing) {
        guard swing.localVideoFilename == nil else { return }
        let directory = videosDirectory
        let swingID = swing.id
        Task.detached(priority: .utility) {
            let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
            let filename = "\(swingID.uuidString).\(ext)"
            let destination = directory.appendingPathComponent(filename)
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: sourceURL, to: destination)
            } catch {
                return
            }
            await MainActor.run {
                guard let index = SwingLibrary.shared.swings.firstIndex(where: { $0.id == swingID }) else { return }
                SwingLibrary.shared.swings[index].localVideoFilename = filename
                SwingLibrary.shared.saveToDisk()
            }
        }
    }
    
    // MARK: - CRUD Operations
    
    /// Add a new swing after saving to Photos. If `localSourceURL` is provided
    /// (the just-exported clip file), a copy is retained in app storage so the
    /// swing plays back instantly without resolving Photos.
    @discardableResult
    func addSwing(
        photoAssetID: String,
        vantage: Vantage,
        duration: Double,
        notes: String? = nil,
        initialThumbnail: UIImage? = nil,
        localSourceURL: URL? = nil
    ) -> SavedSwing {
        let id = UUID()
        var swing = SavedSwing(
            id: id,
            photoAssetID: photoAssetID,
            vantage: vantage,
            duration: duration,
            createdAt: Date(),
            notes: notes,
            analyzed: false
        )
        swing.thumbnail = initialThumbnail
        if let localSourceURL {
            swing.localVideoFilename = storeLocalVideo(from: localSourceURL, swingID: id)
        }
        swings.insert(swing, at: 0)  // Newest first
        saveToDisk()

        Task {
            await refreshThumbnail(
                forPhotoAssetID: photoAssetID,
                retryDelays: initialThumbnail == nil ? [0.35, 1.0, 2.0, 4.0] : [1.0, 3.0]
            )
        }
        return swing
    }

    /// Remove a swing (doesn't delete from Photos - user manages that)
    func removeSwing(_ swing: SavedSwing) {
        swings.removeAll { $0.id == swing.id }
        if let name = swing.localVideoFilename {
            try? FileManager.default.removeItem(at: videosDirectory.appendingPathComponent(name))
        }
        saveToDisk()
    }

    func toggleFavorite(_ swing: SavedSwing) {
        guard let index = swings.firstIndex(where: { $0.id == swing.id }) else { return }
        swings[index].isFavorite.toggle()
        saveToDisk()
    }

    /// Delete an Auto-captured swing from Photos and the app-owned library copy.
    /// The library entry is retained if Photos rejects the deletion.
    func deleteSwingAndPhoto(_ swing: SavedSwing) async throws {
        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
        guard status == .authorized || status == .limited else {
            throw DeletionError.photosAccessDenied
        }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [swing.photoAssetID], options: nil)
        if assets.firstObject != nil {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets(assets)
                } completionHandler: { success, error in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(
                            throwing: DeletionError.photosDeleteFailed(
                                error?.localizedDescription ?? "Unknown error"
                            )
                        )
                    }
                }
            }
        }

        removeSwing(swing)
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

        await loadLocalThumbnails()
        
        let assetIDs = swings.filter { !$0.photoAssetID.isEmpty }.map { $0.photoAssetID }
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
        return await withCheckedContinuation { continuation in
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
        // Fast path: an app-owned local copy plays instantly, no Photos round-trip.
        if let localURL = localVideoURL(for: swing) {
            return AVPlayerItem(url: localURL)
        }

        // Resolve the on-device file directly (AVURLAsset, or AVComposition for
        // slow-mo). This avoids requestPlayerItem's heavyweight "prepare/wait" path.
        let avAsset: AVAsset? = await withCheckedContinuation { continuation in
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [swing.photoAssetID], options: nil)

            guard let asset = fetchResult.firstObject else {
                continuation.resume(returning: nil)
                return
            }

            let options = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .automatic
            options.isNetworkAccessAllowed = true  // Allow iCloud downloads when offloaded

            var didResume = false
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: avAsset)
            }
        }

        guard let avAsset else { return nil }

        // Backfill a local copy for next time (file-backed assets only; slow-mo
        // compositions don't expose a file URL and keep using the Photos path).
        if let urlAsset = avAsset as? AVURLAsset {
            backfillLocalVideo(from: urlAsset.url, for: swing)
        }

        return AVPlayerItem(asset: avAsset)
    }
    
    /// Check if Photos contains the assets we expect (user may have deleted some)
    func validateAssets() {
        let assetIDs = swings.filter { !$0.photoAssetID.isEmpty }.map { $0.photoAssetID }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        
        var validIDs = Set<String>()
        fetchResult.enumerateObjects { asset, _, _ in
            validIDs.insert(asset.localIdentifier)
        }
        
        // Remove swings whose assets no longer exist
        let originalCount = swings.count
        swings.removeAll { !$0.isReference && !validIDs.contains($0.photoAssetID) }
        
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
    
    var totalSwings: Int { swings.filter { !$0.isReference }.count }
    var analyzedSwings: Int { swings.filter { !$0.isReference && $0.analyzed }.count }
    
    func swings(for vantage: Vantage) -> [SavedSwing] {
        swings.filter { !$0.isReference && $0.vantage == vantage }
    }

    private func installBundledReferenceSwings() {
        struct ReferenceDefinition {
            let id: UUID
            let filename: String
            let title: String
            let duration: Double
        }

        let references = [
            ReferenceDefinition(
                id: UUID(uuidString: "93F08C01-6795-46B0-B092-7F9C17CE5A01")!,
                filename: "DaB3eJ3gAcv_1.mp4",
                title: "Reference swing 1",
                duration: 14.626
            ),
            ReferenceDefinition(
                id: UUID(uuidString: "93F08C01-6795-46B0-B092-7F9C17CE5A02")!,
                filename: "DaBMIbhpel9_1.mp4",
                title: "Reference swing 2",
                duration: 22.312
            ),
            ReferenceDefinition(
                id: UUID(uuidString: "93F08C01-6795-46B0-B092-7F9C17CE5A03")!,
                filename: "DaD04inv5-Z_1.mp4",
                title: "Reference swing 3",
                duration: 24.634
            ),
        ]

        var changed = false
        for reference in references {
            if let index = swings.firstIndex(where: { $0.id == reference.id }) {
                let destination = videosDirectory.appendingPathComponent(reference.filename)
                if !FileManager.default.fileExists(atPath: destination.path),
                   copyBundledReference(named: reference.filename, to: destination) {
                    swings[index].localVideoFilename = reference.filename
                    changed = true
                }
                continue
            }

            let destination = videosDirectory.appendingPathComponent(reference.filename)
            guard copyBundledReference(named: reference.filename, to: destination) else { continue }

            swings.append(
                SavedSwing(
                    id: reference.id,
                    photoAssetID: "",
                    vantage: .dtl,
                    duration: reference.duration,
                    createdAt: Date(timeIntervalSince1970: 0),
                    notes: "Bundled DTL reference swing",
                    analyzed: false,
                    isFavorite: true,
                    isReference: true,
                    title: reference.title,
                    localVideoFilename: reference.filename
                )
            )
            changed = true
        }

        if changed {
            saveToDisk()
        }
    }

    private func copyBundledReference(named filename: String, to destination: URL) -> Bool {
        let basename = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        let source = Bundle.main.url(forResource: basename, withExtension: ext, subdirectory: "ReferenceSwings")
            ?? Bundle.main.url(forResource: basename, withExtension: ext)
        guard let source else { return false }

        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            return true
        } catch {
            print("Failed to install bundled reference swing: \(error)")
            return false
        }
    }

    private func loadLocalThumbnails() async {
        let pending = swings.filter { $0.thumbnail == nil && localVideoURL(for: $0) != nil }
        for swing in pending {
            guard let url = localVideoURL(for: swing) else { continue }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = thumbnailTargetSize
            let thumbnailTime = CMTime(seconds: min(1, swing.duration / 2), preferredTimescale: 600)
            guard let generated = try? await generator.image(at: thumbnailTime) else { continue }
            if let index = swings.firstIndex(where: { $0.id == swing.id }) {
                swings[index].thumbnail = UIImage(cgImage: generated.image)
            }
        }
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
