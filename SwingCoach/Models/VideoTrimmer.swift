//
//  VideoTrimmer.swift
//  SwingCoach
//
//  Created by AI Assistant on 22/12/2024.
//

import Foundation
import AVFoundation
import UIKit

/// Handles video processing: thumbnail generation and clip export
actor VideoTrimmer {
    
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
        size: CGSize = CGSize(width: 80, height: 45)
    ) async throws -> [(time: CMTime, image: UIImage)] {
        
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
        
        return thumbnails
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
        to outputURL: URL
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
        
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw TrimmerError.exportSessionCreationFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = timeRange
        
        await exportSession.export()
        
        switch exportSession.status {
        case .completed:
            let clipDuration = CMTimeGetSeconds(CMTimeSubtract(endTime, startTime))
            print("✅ Exported clip: \(String(format: "%.1f", clipDuration))s → \(outputURL.lastPathComponent)")
        case .failed:
            throw TrimmerError.exportFailed(exportSession.error?.localizedDescription ?? "Unknown error")
        case .cancelled:
            throw TrimmerError.exportFailed("Export cancelled")
        default:
            throw TrimmerError.exportFailed("Unexpected status: \(exportSession.status.rawValue)")
        }
    }
    
    /// Export multiple clips from a source video
    func exportClips(
        from asset: AVAsset,
        clips: [SwingClip],
        outputDirectory: URL,
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
                to: outputURL
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
}




