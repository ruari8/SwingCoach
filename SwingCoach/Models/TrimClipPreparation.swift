import AVFoundation

/// Trim adds context around detector windows without changing Auto capture.
enum TrimClipPreparation {
    static let extraPaddingSeconds = 1.0

    static func detectedClip(_ detection: DetectedSwing, duration: CMTime,
                             sourceTimeScale: Double, vantage: Vantage) -> SwingClip {
        let padding = CMTime(seconds: extraPaddingSeconds * sourceTimeScale, preferredTimescale: 600)
        return SwingClip(
            startTime: CMTimeMaximum(.zero, CMTimeSubtract(detection.startTime, padding)),
            endTime: CMTimeMinimum(duration, CMTimeAdd(detection.endTime, padding)),
            vantage: vantage,
            detectionImpactTime: detection.impactTime,
            detectionDeclaredAt: detection.declaredAt
        )
    }

    static func analysisSwings(clips: [SwingClip], selectedIDs: Set<UUID>,
                               savedSwings: [UUID: SavedSwing]) -> [SavedSwing] {
        clips.filter { selectedIDs.contains($0.id) }.compactMap { savedSwings[$0.id] }
    }

    /// A bounded composition lets the shared player scrub only this clip,
    /// including its audio and orientation, without exporting a temporary movie.
    static func reviewAsset(source: AVAsset, clip: SwingClip) async throws -> AVAsset {
        let composition = AVMutableComposition()
        let range = CMTimeRange(start: clip.startCMTime, end: clip.endCMTime)
        let videoTracks = try await source.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { throw VideoTrimmer.TrimmerError.noVideoTrack }
        let audioTracks = try await source.loadTracks(withMediaType: .audio)
        for sourceTrack in videoTracks + audioTracks {
            guard let track = composition.addMutableTrack(withMediaType: sourceTrack.mediaType,
                                                         preferredTrackID: kCMPersistentTrackID_Invalid)
            else { throw VideoTrimmer.TrimmerError.assetLoadFailed }
            // An audio track may start later or end earlier than the video.
            let trackRange = try await sourceTrack.load(.timeRange)
            let intersection = CMTimeRangeGetIntersection(range, otherRange: trackRange)
            if intersection.duration > .zero {
                try track.insertTimeRange(intersection, of: sourceTrack,
                                          at: CMTimeSubtract(intersection.start, range.start))
            }
            track.preferredTransform = try await sourceTrack.load(.preferredTransform)
        }
        return composition
    }
}
