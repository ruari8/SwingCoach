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

/// Metadata for a saved swing clip in app storage, Photos, or both.
struct SavedSwing: Identifiable, Codable, Equatable {
    let id: UUID
    let photoAssetID: String  // PHAsset.localIdentifier; empty for app-local clips.
    var vantage: Vantage
    var duration: Double  // seconds
    var createdAt: Date
    var notes: String?
    var isFavorite: Bool
    var isReference: Bool
    var title: String?
    // Filename (not full path) of an app-owned copy of the clip, if one exists.
    // Lets playback open the local file directly instead of resolving Photos.
    var localVideoFilename: String? = nil
    /// How many times slower than real time the clip plays (8 for 240 fps
    /// exported at 30 fps). Set only for clips captured in the app; nil for
    /// imports, whose real-time rate is unknown.
    var sourceTimeScale: Double? = nil
    /// The player rate that shows the swing in real time; nil when the clip
    /// already plays in real time or its scale is unknown.
    var realTimePlaybackRate: Float? {
        guard let sourceTimeScale, sourceTimeScale > 1 else { return nil }
        return Float(sourceTimeScale)
    }
    /// P1-P10 found after capture (down-the-line clips only).
    var swingPositions: SwingPositions? = nil
    /// The swing itself on the clip's timeline, without the extra footage
    /// before and after. Swing positions are found only here; nil means the
    /// whole clip (imports, and swings saved before this was recorded).
    var swingWindow: ClosedRange<Double>? = nil

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
        isFavorite: Bool = false,
        isReference: Bool = false,
        title: String? = nil,
        localVideoFilename: String? = nil,
        sourceTimeScale: Double? = nil
    ) {
        self.id = id
        self.photoAssetID = photoAssetID
        self.vantage = vantage
        self.duration = duration
        self.createdAt = createdAt
        self.notes = notes
        self.isFavorite = isFavorite
        self.isReference = isReference
        self.title = title
        self.localVideoFilename = localVideoFilename
        self.sourceTimeScale = sourceTimeScale
    }

    enum CodingKeys: String, CodingKey {
        case id, photoAssetID, vantage, duration, createdAt, notes, isFavorite, isReference, title, localVideoFilename
        case sourceTimeScale, swingPositions, swingWindow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        photoAssetID = try container.decode(String.self, forKey: .photoAssetID)
        vantage = try container.decode(Vantage.self, forKey: .vantage)
        duration = try container.decode(Double.self, forKey: .duration)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isReference = try container.decodeIfPresent(Bool.self, forKey: .isReference) ?? false
        title = try container.decodeIfPresent(String.self, forKey: .title)
        localVideoFilename = try container.decodeIfPresent(String.self, forKey: .localVideoFilename)
        sourceTimeScale = try container.decodeIfPresent(Double.self, forKey: .sourceTimeScale)
        swingPositions = try container.decodeIfPresent(SwingPositions.self, forKey: .swingPositions)
        swingWindow = try container.decodeIfPresent(ClosedRange<Double>.self, forKey: .swingWindow)
    }

    // Custom Equatable (ignore non-codable properties)
    static func == (lhs: SavedSwing, rhs: SavedSwing) -> Bool {
        lhs.id == rhs.id &&
        lhs.photoAssetID == rhs.photoAssetID &&
        lhs.vantage == rhs.vantage &&
        lhs.duration == rhs.duration &&
        lhs.createdAt == rhs.createdAt &&
        lhs.notes == rhs.notes &&
        lhs.isFavorite == rhs.isFavorite &&
        lhs.isReference == rhs.isReference &&
        lhs.title == rhs.title &&
        lhs.localVideoFilename == rhs.localVideoFilename &&
        lhs.sourceTimeScale == rhs.sourceTimeScale &&
        lhs.swingPositions == rhs.swingPositions &&
        lhs.swingWindow == rhs.swingWindow
    }
}

/// Manages the collection of saved swing clips
/// Metadata lives in Documents; clips can be app-local or backed by Photos.
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
    /// A library tile's picture in pixels: the largest tile (two columns)
    /// times the screen scale, so it is sharp at every column count.
    static var thumbnailTargetSize: CGSize {
        let displayScale = UITraitCollection.current.displayScale
        let scale = displayScale > 0 ? max(displayScale, 2) : 3
        return CGSize(width: LibraryGrid.largestTile * scale, height: LibraryGrid.largestTile * scale)
    }

    private var thumbnailTargetSize: CGSize { Self.thumbnailTargetSize }

    /// What a frame is read at before it is cropped: big enough that a
    /// 16:9 frame either way up still covers the card.
    private var thumbnailSourceSize: CGSize {
        let side = max(thumbnailTargetSize.width, thumbnailTargetSize.height) * 16 / 9
        return CGSize(width: side, height: side)
    }

    /// The tile's picture cut from a whole frame: a square at the tile's
    /// largest pixel size, never scaled up. A portrait clip is cut nearer
    /// its top than its middle (`LibraryGrid.thumbnailFocus`), so the
    /// golfer's head and body show rather than the feet and the mat.
    static func cardThumbnail(from image: UIImage) -> UIImage {
        let target = thumbnailTargetSize
        let source = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard source.width > 0, source.height > 0, target.width > 0, target.height > 0 else { return image }
        let aspect = target.width / target.height
        var crop = CGRect(origin: .zero, size: source)
        if source.width / source.height > aspect {
            crop.size.width = source.height * aspect
            crop.origin.x = (source.width - crop.width) / 2
        } else {
            crop.size.height = source.width / aspect
            crop.origin.y = (source.height - crop.height) * LibraryGrid.thumbnailFocus
        }
        let factor = min(1, target.width / crop.width)
        let output = CGSize(width: (crop.width * factor).rounded(), height: (crop.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: output, format: format).image { _ in
            image.draw(in: CGRect(x: -crop.minX * factor, y: -crop.minY * factor,
                                  width: source.width * factor, height: source.height * factor))
        }
    }

    static let shared = SwingLibrary()

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = documents.appendingPathComponent("swing_library.json")

        // Local-only clips are originals, so this persistent directory must
        // participate in device backup, including for existing installations.
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        var videos = support.appendingPathComponent("SwingVideos", isDirectory: true)
        try? FileManager.default.createDirectory(at: videos, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = false
        try? videos.setResourceValues(resourceValues)
        videosDirectory = videos

        loadFromDisk()
        installBundledReferenceSwings()
        for swing in swings {
            if let url = localVideoURL(for: swing) {
                setBackupExcluded(swing.isReference || !swing.photoAssetID.isEmpty, for: url)
            }
        }
    }

    /// Local URL of the app-owned clip copy, if it exists on disk.
    func localVideoURL(for swing: SavedSwing) -> URL? {
        guard let name = swing.localVideoFilename else { return nil }
        let url = videosDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Copy a clip file into app storage, returning the stored filename.
    private func storeLocalVideo(from sourceURL: URL, swingID: UUID, excludeFromBackup: Bool = true) -> String? {
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let filename = "\(swingID.uuidString).\(ext)"
        let destination = videosDirectory.appendingPathComponent(filename)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            setBackupExcluded(excludeFromBackup, for: destination)
            return filename
        } catch {
            print("⚠️ Failed to store local swing video: \(error)")
            return nil
        }
    }

    private func setBackupExcluded(_ excluded: Bool, for url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = excluded
        try? url.setResourceValues(values)
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
                SwingLibrary.shared.setBackupExcluded(true, for: destination)
                SwingLibrary.shared.saveToDisk()
            }
        }
    }
    
    // MARK: - CRUD Operations

    enum SaveError: LocalizedError {
        case localCopyFailed
        case photosSaveFailed

        var errorDescription: String? {
            switch self {
            case .localCopyFailed:
                return "The clip could not be stored in SwingCoach. Check available storage."
            case .photosSaveFailed:
                return "The clip could not be saved to Photos. Check Photos access and available storage."
            }
        }
    }

    /// Retain the export before its caller removes the temporary file. OFF never
    /// calls PhotoKit. Snapshot the preference once for this save operation.
    @discardableResult
    func saveExportedSwing(
        from sourceURL: URL,
        vantage: Vantage,
        duration: Double,
        sourceTimeScale: Double? = nil,
        swingWindow: ClosedRange<Double>? = nil,
        initialThumbnail: UIImage? = nil
    ) async throws -> SavedSwing {
        let savesToPhotos = ClipStoragePreference.savesToPhotos
        let id = UUID()
        guard let filename = storeLocalVideo(from: sourceURL, swingID: id, excludeFromBackup: savesToPhotos) else {
            throw SaveError.localCopyFailed
        }
        do {
            let photoAssetID: String
            if savesToPhotos {
                guard let savedID = await PHPhotoLibrary.saveVideoAndGetID(url: sourceURL) else {
                    throw SaveError.photosSaveFailed
                }
                photoAssetID = savedID
            } else {
                photoAssetID = ""
            }
            var swing = SavedSwing(
                id: id, photoAssetID: photoAssetID, vantage: vantage,
                duration: duration, createdAt: Date(), notes: nil,
                localVideoFilename: filename,
                sourceTimeScale: sourceTimeScale
            )
            swing.swingWindow = swingWindow
            swing.thumbnail = initialThumbnail.map(Self.cardThumbnail)
            // Persist before publishing success or allowing temp-file cleanup.
            let updated = [swing] + swings
            try JSONEncoder().encode(updated).write(to: storageURL, options: .atomic)
            swings = updated
            // The capture's quick preview is small; read a sharp one from
            // the saved copy.
            let saved = swing
            Task { await loadLocalThumbnail(for: saved) }
            return swing
        } catch {
            try? FileManager.default.removeItem(at: videosDirectory.appendingPathComponent(filename))
            throw error
        }
    }
    
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
            notes: notes
        )
        swing.thumbnail = initialThumbnail.map(Self.cardThumbnail)
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

    /// Remove library entries and their local copies, saving the collection once.
    /// Photos originals remain untouched.
    func removeSwings(withIDs ids: Set<UUID>) {
        let removed = swings.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        swings.removeAll { ids.contains($0.id) }
        SwingCoachingStore.shared.removeCoaching(for: Set(removed.map(\.id)))
        for swing in removed {
            if let name = swing.localVideoFilename {
                try? FileManager.default.removeItem(at: videosDirectory.appendingPathComponent(name))
            }
        }
        saveToDisk()
    }

    func setSwingPositions(_ positions: SwingPositions, for id: UUID) {
        guard let index = swings.firstIndex(where: { $0.id == id }) else { return }
        let posterMoved = swings[index].swingPositions.flatMap(Self.impactTime) != Self.impactTime(positions)
        swings[index].swingPositions = positions
        saveToDisk()
        SwingCoachingStore.shared.coachIfNeeded(swings[index])
        // The tile's picture moves to the new impact frame.
        if posterMoved {
            let swing = swings[index]
            Task { await loadLocalThumbnail(for: swing) }
        }
    }

    func toggleFavorite(_ swing: SavedSwing) {
        guard let index = swings.firstIndex(where: { $0.id == swing.id }) else { return }
        swings[index].isFavorite.toggle()
        saveToDisk()
    }

    /// Delete an Auto-captured swing from Photos and the app-owned library copy.
    /// The library entry is retained if Photos rejects the deletion.
    func deleteSwingAndPhoto(_ swing: SavedSwing) async throws {
        guard !swing.photoAssetID.isEmpty else {
            removeSwings(withIDs: [swing.id])
            return
        }
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

        removeSwings(withIDs: [swing.id])
    }
    
    // MARK: - Photos Integration
    
    /// Load app-owned previews first; PhotoKit reads require separate permission.
    func loadThumbnails() async {
        isLoading = true
        defer { isLoading = false }
        await loadLocalThumbnails()

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }
        // A swing with its own impact poster keeps it over Photos' frame.
        let assetIDs = swings.filter { !$0.photoAssetID.isEmpty && !hasImpactPoster($0) }.map { $0.photoAssetID }
        guard !assetIDs.isEmpty else { return }
        
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
                    // Positions may have arrived since the request: the
                    // impact poster wins over Photos' first frame.
                    if let index = self.swings.firstIndex(where: { $0.photoAssetID == asset.localIdentifier }),
                       !self.hasImpactPoster(self.swings[index]) {
                        self.swings[index].thumbnail = image.map(Self.cardThumbnail)
                    }
                }
            }
        }
    }

    private func refreshThumbnail(forPhotoAssetID photoAssetID: String, retryDelays: [TimeInterval]) async {
        guard swings.contains(where: { $0.photoAssetID == photoAssetID }) else { return }
        func keepsImpactPoster() -> Bool {
            swings.first { $0.photoAssetID == photoAssetID }.map(hasImpactPoster) ?? true
        }
        guard !keepsImpactPoster() else { return }
        
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [photoAssetID], options: nil)
        guard let asset = fetchResult.firstObject else { return }
        
        for delay in [0.0] + retryDelays {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            
            if let image = await requestThumbnailImage(for: asset) {
                // Positions can land while Photos is still asked.
                guard !keepsImpactPoster() else { return }
                if let index = swings.firstIndex(where: { $0.photoAssetID == photoAssetID }) {
                    swings[index].thumbnail = Self.cardThumbnail(from: image)
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
        guard !swing.photoAssetID.isEmpty else { return nil }

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
        // Every Photos-backed swing is checked: one left out of this fetch
        // would look missing below and be removed.
        let assetIDs = swings.filter { !$0.photoAssetID.isEmpty }.map { $0.photoAssetID }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        
        var validIDs = Set<String>()
        fetchResult.enumerateObjects { asset, _, _ in
            validIDs.insert(asset.localIdentifier)
        }
        
        // Remove swings whose assets no longer exist
        let originalCount = swings.count
        let missing = swings.filter { !$0.isReference && !$0.photoAssetID.isEmpty && !validIDs.contains($0.photoAssetID) }
        swings.removeAll { !$0.isReference && !$0.photoAssetID.isEmpty && !validIDs.contains($0.photoAssetID) }
        SwingCoachingStore.shared.removeCoaching(for: Set(missing.map(\.id)))
        
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
    
    func swings(for vantage: Vantage) -> [SavedSwing] {
        swings.filter { !$0.isReference && $0.vantage == vantage }
    }

    private func installBundledReferenceSwings() {
        #if DEBUG
        // UI tests seed their own synthetic references.
        if UITestFixture.isActive { return }
        #endif
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
            await loadLocalThumbnail(for: swing)
        }
    }

    /// Impact (P7) on the clip's own timeline, the frame a tile shows once
    /// the swing has positions: every swing looks different there, where
    /// at address they all look alike.
    static func impactTime(_ positions: SwingPositions) -> Double? {
        positions.positions.first { $0.number == 7 }?.clipTime
    }

    /// The frame a tile's picture is read at: impact once the swing has
    /// positions, else a second in (or halfway, for a shorter clip).
    static func posterTime(for swing: SavedSwing) -> Double {
        swing.swingPositions.flatMap(impactTime) ?? min(1, swing.duration / 2)
    }

    /// The tile shows the impact frame read from the app's own copy, so
    /// Photos' first frame must not replace it.
    private func hasImpactPoster(_ swing: SavedSwing) -> Bool {
        swing.swingPositions.flatMap(Self.impactTime) != nil && localVideoURL(for: swing) != nil
    }

    /// The card's picture from the app's own copy of the clip.
    private func loadLocalThumbnail(for swing: SavedSwing) async {
        guard let url = localVideoURL(for: swing) else { return }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = thumbnailSourceSize
        let thumbnailTime = CMTime(seconds: Self.posterTime(for: swing), preferredTimescale: 600)
        guard let generated = try? await generator.image(at: thumbnailTime) else { return }
        if let index = swings.firstIndex(where: { $0.id == swing.id }) {
            swings[index].thumbnail = Self.cardThumbnail(from: UIImage(cgImage: generated.image))
        }
    }
}

// MARK: - Helper to get PHAsset ID after saving

extension PHPhotoLibrary {
    /// Save video and return the asset identifier
    static func saveVideoAndGetID(url: URL) async -> String? {
        #if DEBUG
        if UITestFixture.shouldFailPhotosSave() { return nil }
        #endif
        return await withCheckedContinuation { continuation in
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
