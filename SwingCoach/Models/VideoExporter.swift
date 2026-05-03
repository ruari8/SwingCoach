//
//  VideoExporter.swift
//  SwingCoach
//
//  Created by AI Assistant on 23/12/2024.
//

import Foundation
import AVFoundation
import Photos

/// Target FPS options for video export
enum ExportFPS: Int, CaseIterable, Identifiable {
    case normal = 30
    case cinematic = 24
    case extraSlow = 15
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .normal: return "Normal (30fps)"
        case .cinematic: return "Cinematic (24fps)"
        case .extraSlow: return "Extra Slow (15fps)"
        }
    }
    
    var shortName: String {
        "\(rawValue)fps"
    }
}

/// Handles video export operations including FPS time-stretching
class VideoExporter {
    
    enum ExportError: LocalizedError {
        case noVideoTrack
        case compositionFailed
        case exportFailed(String)
        case saveFailed
        
        var errorDescription: String? {
            switch self {
            case .noVideoTrack:
                return "No video track found in source"
            case .compositionFailed:
                return "Failed to create video composition"
            case .exportFailed(let reason):
                return "Export failed: \(reason)"
            case .saveFailed:
                return "Failed to save to Photos library"
            }
        }
    }
    
    /// Calculate the new duration after FPS conversion
    /// - Parameters:
    ///   - originalDuration: Original video duration in seconds
    ///   - sourceFPS: Source video FPS (typically 30)
    ///   - targetFPS: Target FPS for export
    /// - Returns: New duration in seconds
    static func calculateNewDuration(
        originalDuration: Double,
        sourceFPS: Double = 30,
        targetFPS: Double
    ) -> Double {
        // Same frames, different playback rate
        // duration = frames / fps
        // newDuration = (originalDuration * sourceFPS) / targetFPS
        return (originalDuration * sourceFPS) / targetFPS
    }
    
    /// Export a video with time-stretching to achieve target FPS
    /// Keeps all frames, just changes how long it takes to play them
    /// - Parameters:
    ///   - sourceAsset: The source AVAsset
    ///   - targetFPS: Target frames per second (lower = slower playback)
    ///   - sourceFPS: Source FPS (defaults to 30)
    ///   - outputURL: Where to save the exported file
    ///   - progress: Progress callback (0.0 to 1.0)
    /// - Returns: URL of the exported file
    func exportWithTimeStretch(
        sourceAsset: AVAsset,
        targetFPS: ExportFPS,
        sourceFPS: Double = 30,
        outputURL: URL,
        progress: ((Float) -> Void)? = nil
    ) async throws -> URL {
        
        // Load tracks
        let videoTracks = try await sourceAsset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw ExportError.noVideoTrack
        }
        
        let audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        let sourceAudioTrack = audioTracks.first
        
        let duration = try await sourceAsset.load(.duration)
        
        // Calculate time scale factor
        // targetFPS < sourceFPS means video plays slower (longer duration)
        let scaleFactor = sourceFPS / Double(targetFPS.rawValue)
        let newDuration = CMTimeMultiplyByFloat64(duration, multiplier: scaleFactor)
        
        // Create composition
        let composition = AVMutableComposition()
        
        // Add video track
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.compositionFailed
        }
        
        // Insert video at original timerange
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try compositionVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)
        
        // Scale the time to stretch the video
        compositionVideoTrack.scaleTimeRange(timeRange, toDuration: newDuration)
        
        // Copy video transform (orientation)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        compositionVideoTrack.preferredTransform = preferredTransform
        
        // Add audio track if present (also time-stretched)
        if let sourceAudioTrack {
            if let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) {
                try compositionAudioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)
                compositionAudioTrack.scaleTimeRange(timeRange, toDuration: newDuration)
            }
        }
        
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        // Export
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.compositionFailed
        }
        
        exportSession.shouldOptimizeForNetworkUse = true

        do {
            if let progress {
                progress(0)
                async let export: Void = exportSession.export(to: outputURL, as: .mp4)

                for await state in exportSession.states(updateInterval: 0.1) {
                    switch state {
                    case .pending, .waiting:
                        progress(0)
                    case .exporting(let exportProgress):
                        progress(Float(exportProgress.fractionCompleted))
                    @unknown default:
                        break
                    }
                }

                try await export
                progress(1)
            } else {
                try await exportSession.export(to: outputURL, as: .mp4)
            }
        } catch {
            throw ExportError.exportFailed(error.localizedDescription)
        }
        
        return outputURL
    }
    
    /// Export video and save directly to Photos library
    /// - Parameters:
    ///   - sourceAsset: Source video asset
    ///   - targetFPS: Target FPS
    ///   - sourceFPS: Source FPS (default 30)
    ///   - progress: Progress callback
    /// - Returns: PHAsset local identifier of saved video
    func exportToPhotos(
        sourceAsset: AVAsset,
        targetFPS: ExportFPS,
        sourceFPS: Double = 30,
        progress: ((Float) -> Void)? = nil
    ) async throws -> String {
        
        // Create temp file for export
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        // Export with time stretch
        let exportedURL = try await exportWithTimeStretch(
            sourceAsset: sourceAsset,
            targetFPS: targetFPS,
            sourceFPS: sourceFPS,
            outputURL: tempURL,
            progress: progress
        )
        
        // Save to Photos
        guard let assetID = await PHPhotoLibrary.saveVideoAndGetID(url: exportedURL) else {
            // Clean up temp file
            try? FileManager.default.removeItem(at: exportedURL)
            throw ExportError.saveFailed
        }
        
        // Clean up temp file
        try? FileManager.default.removeItem(at: exportedURL)
        
        return assetID
    }
    
    /// Get video metadata including FPS
    static func getVideoInfo(asset: AVAsset) async -> (fps: Double, duration: Double, frameCount: Int)? {
        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = videoTracks.first else { return nil }
            
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            let nominalFrameRate = try await track.load(.nominalFrameRate)
            let fps = Double(nominalFrameRate)
            let frameCount = Int(durationSeconds * fps)
            
            return (fps: fps, duration: durationSeconds, frameCount: frameCount)
        } catch {
            return nil
        }
    }
}
