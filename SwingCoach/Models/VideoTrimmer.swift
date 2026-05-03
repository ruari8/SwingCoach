//
//  VideoTrimmer.swift
//  SwingCoach
//
//  Created by AI Assistant on 22/12/2024.
//

import Foundation
import AVFoundation
import UIKit

private struct CachedThumbnail {
    let timeSeconds: Double
    let image: UIImage
}

private actor ThumbnailCacheStore {
    private var storage: [String: [CachedThumbnail]] = [:]
    
    func thumbnails(for key: String) -> [(time: CMTime, image: UIImage)]? {
        storage[key]?.map {
            (
                time: CMTime(seconds: $0.timeSeconds, preferredTimescale: 600),
                image: $0.image
            )
        }
    }
    
    func store(_ thumbnails: [(time: CMTime, image: UIImage)], for key: String) {
        storage[key] = thumbnails.map {
            CachedThumbnail(timeSeconds: CMTimeGetSeconds($0.time), image: $0.image)
        }
    }
}

/// Handles video processing: thumbnail generation and clip export
actor VideoTrimmer {
    private static let thumbnailCache = ThumbnailCacheStore()
    
    enum TrimmerError: Error, LocalizedError {
        case assetLoadFailed
        case noVideoTrack
        case thumbnailGenerationFailed
        case exportSessionCreationFailed
        case exportFailed(String)
        case invalidTimeRange
        
        var errorDescription: String? {
            switch self {
            case .assetLoadFailed:
                return "Failed to load video asset"
            case .noVideoTrack:
                return "Video has no video track"
            case .thumbnailGenerationFailed:
                return "Failed to generate thumbnail"
            case .exportSessionCreationFailed:
                return "Failed to create export session"
            case .exportFailed(let reason):
                return "Export failed: \(reason)"
            case .invalidTimeRange:
                return "Invalid time range for clip"
            }
        }
    }
    
    // MARK: - Thumbnail Generation
    
    /// Generate evenly-spaced thumbnails across the video duration
    func generateThumbnails(
        for asset: AVAsset,
        count: Int,
        size: CGSize = CGSize(width: 80, height: 45),
        cacheKey: String? = nil
    ) async throws -> [(time: CMTime, image: UIImage)] {
        if let cacheKey = thumbnailCacheKey(for: cacheKey, count: count, size: size),
           let cached = await Self.thumbnailCache.thumbnails(for: cacheKey) {
            return cached
        }
        
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        guard durationSeconds > 0 else {
            throw TrimmerError.assetLoadFailed
        }
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        
        // Generate evenly spaced times
        let times: [CMTime] = (0..<count).map { i in
            let seconds = durationSeconds * Double(i) / Double(max(count - 1, 1))
            return CMTime(seconds: seconds, preferredTimescale: 600)
        }
        
        var thumbnails: [(time: CMTime, image: UIImage)] = []
        
        for time in times {
            do {
                let (cgImage, actualTime) = try await generator.image(at: time)
                let image = UIImage(cgImage: cgImage)
                thumbnails.append((time: actualTime, image: image))
            } catch {
                // Skip failed frames but continue
                print("⚠️ Failed to generate thumbnail at \(CMTimeGetSeconds(time))s: \(error)")
                continue
            }
        }
        
        if let cacheKey = thumbnailCacheKey(for: cacheKey, count: count, size: size) {
            await Self.thumbnailCache.store(thumbnails, for: cacheKey)
        }
        
        return thumbnails
    }
    
    func cachedThumbnails(
        for sourceKey: String,
        count: Int,
        size: CGSize = CGSize(width: 80, height: 45)
    ) async -> [(time: CMTime, image: UIImage)]? {
        guard let cacheKey = thumbnailCacheKey(for: sourceKey, count: count, size: size) else {
            return nil
        }
        
        return await Self.thumbnailCache.thumbnails(for: cacheKey)
    }
    
    /// Generate a single thumbnail at a specific time
    func generateThumbnail(
        for asset: AVAsset,
        at time: CMTime,
        size: CGSize = CGSize(width: 120, height: 68)
    ) async throws -> UIImage {
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        let (cgImage, _) = try await generator.image(at: time)
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - Video Info
    
    /// Load video duration
    func getDuration(for asset: AVAsset) async throws -> CMTime {
        try await asset.load(.duration)
    }
    
    /// Load video properties
    func getVideoInfo(for asset: AVAsset) async throws -> (duration: CMTime, size: CGSize, frameRate: Float) {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw TrimmerError.noVideoTrack
        }
        
        let duration = try await asset.load(.duration)
        let size = try await track.load(.naturalSize)
        let frameRate = try await track.load(.nominalFrameRate)
        
        return (duration, size, frameRate)
    }
    
    // MARK: - Clip Export
    
    /// Export a clip from the source video
    func exportClip(
        from asset: AVAsset,
        startTime: CMTime,
        endTime: CMTime,
        to outputURL: URL,
        slowMotionFactor: Double? = nil
    ) async throws {
        
        let duration = try await asset.load(.duration)
        
        // Validate time range
        guard CMTimeCompare(startTime, endTime) < 0 else {
            throw TrimmerError.invalidTimeRange
        }
        
        guard CMTimeCompare(startTime, .zero) >= 0,
              CMTimeCompare(endTime, duration) <= 0 else {
            throw TrimmerError.invalidTimeRange
        }
        
        let timeRange = CMTimeRange(start: startTime, end: endTime)
        
        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)
        
        if let slowMotionFactor, slowMotionFactor > 1 {
            try await exportSlowMotionClip(
                from: asset,
                timeRange: timeRange,
                to: outputURL,
                slowMotionFactor: slowMotionFactor
            )
            
            let clipDuration = CMTimeGetSeconds(timeRange.duration) * slowMotionFactor
            print("✅ Exported slow-mo clip: \(String(format: "%.1f", clipDuration))s → \(outputURL.lastPathComponent)")
            return
        }
        
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw TrimmerError.exportSessionCreationFailed
        }
        
        exportSession.timeRange = timeRange

        do {
            try await exportSession.export(to: outputURL, as: .mp4)
            let clipDuration = CMTimeGetSeconds(CMTimeSubtract(endTime, startTime))
            print("✅ Exported clip: \(String(format: "%.1f", clipDuration))s → \(outputURL.lastPathComponent)")
        } catch {
            throw TrimmerError.exportFailed(error.localizedDescription)
        }
    }
    
    /// Export multiple clips from a source video
    func exportClips(
        from asset: AVAsset,
        clips: [SwingClip],
        outputDirectory: URL,
        slowMotionFactor: Double? = nil,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async throws -> [URL] {
        
        var exportedURLs: [URL] = []
        
        for (index, clip) in clips.enumerated() {
            progressHandler?(index + 1, clips.count)
            
            let filename = "swing_\(clip.id.uuidString.prefix(8)).mp4"
            let outputURL = outputDirectory.appendingPathComponent(filename)
            
            try await exportClip(
                from: asset,
                startTime: clip.startCMTime,
                endTime: clip.endCMTime,
                to: outputURL,
                slowMotionFactor: slowMotionFactor
            )
            
            exportedURLs.append(outputURL)
        }
        
        return exportedURLs
    }
    
    // MARK: - Utility
    
    /// Create the clips output directory if needed
    static func clipsDirectory() throws -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let clipsURL = documentsURL.appendingPathComponent("SwingClips", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: clipsURL.path) {
            try FileManager.default.createDirectory(at: clipsURL, withIntermediateDirectories: true)
        }
        
        return clipsURL
    }
    
    private func exportSlowMotionClip(
        from asset: AVAsset,
        timeRange: CMTimeRange,
        to outputURL: URL,
        slowMotionFactor: Double
    ) async throws {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw TrimmerError.noVideoTrack
        }
        
        let composition = AVMutableComposition()
        
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw TrimmerError.exportSessionCreationFailed
        }
        
        try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        compositionVideoTrack.preferredTransform = try await videoTrack.load(.preferredTransform)
        
        let compositionRange = CMTimeRange(start: .zero, duration: timeRange.duration)
        let scaledDuration = CMTimeMultiplyByFloat64(timeRange.duration, multiplier: slowMotionFactor)
        compositionVideoTrack.scaleTimeRange(compositionRange, toDuration: scaledDuration)
        
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
            compositionAudioTrack.scaleTimeRange(compositionRange, toDuration: scaledDuration)
        }
        
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw TrimmerError.exportSessionCreationFailed
        }
        

        do {
            try await exportSession.export(to: outputURL, as: .mp4)
        } catch {
            throw TrimmerError.exportFailed(error.localizedDescription)
        }
    }
    
    private func thumbnailCacheKey(
        for sourceKey: String?,
        count: Int,
        size: CGSize
    ) -> String? {
        guard let sourceKey else { return nil }
        
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        return "\(sourceKey)#\(count)#\(width)x\(height)"
    }
}
