import AVFoundation

/// Shared Trim preparation; source-time conversion happens only at the boundary.
enum TrimClipPreparation {
    static func detectedClip(_ detection: DetectedSwing, duration: CMTime,
                             sourceTimeScale: Double, vantage: Vantage,
                             context: SwingClipContext) -> SwingClip {
        let range = context.range(for: detection, sourceTimeScale: sourceTimeScale)
        return SwingClip(
            startTime: range.start,
            endTime: CMTimeMinimum(duration, range.end),
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
