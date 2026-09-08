import AVFoundation
import XCTest
@testable import SwingCoach

@MainActor
final class SwingClipContextTests: XCTestCase {
    func testDefaultsPersistenceAndInputBounds() {
        let name = "SwingClipContextTests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(SwingClipContext.load(from: defaults), SwingClipContext())
        defaults.set(0.5, forKey: SwingClipContext.beforeKey)
        defaults.set(2.25, forKey: SwingClipContext.afterKey)
        XCTAssertEqual(SwingClipContext.load(from: defaults), SwingClipContext(before: 0.5, after: 2.25))
        XCTAssertEqual(SwingClipContext(before: -2, after: 300), SwingClipContext(before: 0, after: 30))
        XCTAssertEqual(SwingClipContext(before: .nan, after: .infinity), SwingClipContext())
    }

    func testIndependentContextUsesRealSecondsAndClampsRecordingEdges() {
        let detection = DetectedSwing(startTime: time(2), endTime: time(4), confidence: 0.9,
                                      impactTime: 3, declaredAt: 4.1)
        let context = SwingClipContext(before: 0.5, after: 2.25)
        let clip = TrimClipPreparation.detectedClip(detection, duration: time(6), sourceTimeScale: 1,
                                                    vantage: .dtl, context: context)
        XCTAssertEqual(clip.startTime, 1.5, accuracy: 0.001)
        XCTAssertEqual(clip.endTime, 6, accuracy: 0.001)
        XCTAssertEqual(clip.detectionImpactTime, 3)
        XCTAssertEqual(clip.detectionDeclaredAt, 4.1)
        let range = context.range(for: detection, sourceTimeScale: 8)
        XCTAssertEqual(range.start.seconds, 0)
        XCTAssertEqual(range.end.seconds, 22)
        XCTAssertEqual(detection.startTime.seconds, 2, "Clip context must not mutate detector output")
    }

    func testTrimTimecodeRefreshesInPlaybackTenthsIncludingSlowMotion() {
        for scale in [1.0, 2, 4, 8] {
            let interval = TrimTimecode.observationInterval(playbackRate: Float(1 / scale))
            XCTAssertEqual(interval.seconds * scale, 0.1, accuracy: 0.00001)
            XCTAssertEqual(TrimTimecode.format(interval, scale: scale), "00.1")
        }
        XCTAssertEqual([0.0, 0.1, 0.2, 1.0].map { TrimTimecode.format(time($0)) }, ["00.0", "00.1", "00.2", "01.0"])
        XCTAssertEqual(TrimTimecode.format(time(59.99)), "59.9")
        XCTAssertEqual(TrimTimecode.format(time(60)), "60.0")
        XCTAssertEqual(TrimTimecode.format(CMTime(value: 25, timescale: 240)), "00.1")
        XCTAssertEqual(TrimTimecode.format(.invalid), "00.0")
    }

    func testAutoBufferJoinsChunksWithoutRepeatingOverlapAndWaitsForPostRoll() async throws {
        let (buffer, queue, prepared) = try await record(seconds: 64, range: CMTimeRange(start: time(1), end: time(63)))
        defer { queue.sync { buffer.release(prepared); buffer.reset() } }
        XCTAssertGreaterThan(prepared.segments.count, 1)
        XCTAssertEqual(prepared.sourceStartTime, 1)
        let asset = try await prepared.makeAsset()
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 62, accuracy: 0.001)
        try await assertFrames(asset, count: 62 * 30)
    }

    func testStoppingEarlyFinishesPendingClipAndKeepsItsFilesUntilRelease() async throws {
        let (buffer, queue, prepared) = try await record(seconds: 5, range: CMTimeRange(start: time(1), end: time(20)))
        defer { queue.sync { buffer.release(prepared); buffer.reset() } }
        XCTAssertEqual(prepared.duration.seconds, 4, accuracy: 0.001)
        for segment in prepared.segments { XCTAssertTrue(FileManager.default.fileExists(atPath: segment.url.path)) }
        let asset = try await prepared.makeAsset()
        try await assertFrames(asset, count: 120)
        queue.sync { buffer.release(prepared) }
        for segment in prepared.segments { XCTAssertFalse(FileManager.default.fileExists(atPath: segment.url.path)) }
    }

    func testDroppedFrameBetweenExportChunksPreservesSourceTimeline() async throws {
        let (buffer, queue, prepared) = try await record(
            seconds: 10, range: CMTimeRange(start: time(4), end: time(8)),
            closeChunkAt: 150, droppedFrames: [151]
        )
        defer { queue.sync { buffer.release(prepared); buffer.reset() } }
        XCTAssertEqual(prepared.segments.count, 2)
        XCTAssertEqual(prepared.sourceStartTime, 4)
        let resumedSegment = try XCTUnwrap(prepared.segments.dropFirst().first)
        XCTAssertEqual(resumedSegment.timelineStart.seconds, 32.0 / 30, accuracy: 0.00002)
        let asset = try await prepared.makeAsset()
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 4, accuracy: 0.00002)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let segments = try await track.load(.segments)
        let gap = try XCTUnwrap(segments.first(where: \.isEmpty))
        XCTAssertEqual(gap.timeMapping.target.start.seconds, 31.0 / 30, accuracy: 0.00002)
        XCTAssertEqual(gap.timeMapping.target.duration.seconds, 1.0 / 30, accuracy: 0.00002)
        // The reader renders the empty range as a placeholder frame, preserving
        // four seconds of playback rather than collapsing the dropped frame.
        let timestamps = try await assertFrames(asset, count: 120)
        XCTAssertEqual(timestamps[30], 1, accuracy: 0.00002)
        XCTAssertEqual(timestamps[32], 32.0 / 30, accuracy: 0.00002,
                       "The missing frame must not shift later footage or detection metadata earlier")
        XCTAssertEqual(try XCTUnwrap(timestamps.last), 119.0 / 30, accuracy: 0.00002)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("gap-export-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let export = try XCTUnwrap(AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality))
        try await export.export(to: outputURL, as: .mov)
        let exportedAsset = AVURLAsset(url: outputURL)
        let exportedDuration = try await exportedAsset.load(.duration)
        XCTAssertEqual(exportedDuration.seconds, 4, accuracy: 0.00002)
        try await assertFrames(exportedAsset, count: 120)
    }

    func testClipEndingInsideDroppedFrameSavesAvailableFootage() async throws {
        let (buffer, queue, prepared) = try await record(
            seconds: 10, range: CMTimeRange(start: time(4), end: time(5.05)),
            closeChunkAt: 150, droppedFrames: [151]
        )
        defer { queue.sync { buffer.release(prepared); buffer.reset() } }
        let asset = try await prepared.makeAsset()
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 31.0 / 30, accuracy: 0.00002)
        XCTAssertEqual(prepared.duration.seconds, duration.seconds, accuracy: 0.00002)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let segments = try await track.load(.segments)
        XCTAssertFalse(segments.contains(where: \.isEmpty))
        try await assertFrames(asset, count: 31)
    }

    private func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 60000) }

    private func record(seconds: Int, range: CMTimeRange, closeChunkAt: Int? = nil,
                        droppedFrames: Set<Int> = []) async throws -> (AutoRollingVideoBuffer, DispatchQueue, AutoRollingVideoBuffer.PreparedClip) {
        let queue = DispatchQueue(label: "test.swing-context-buffer")
        let buffer = AutoRollingVideoBuffer(writerQueue: queue)
        let prepared: AutoRollingVideoBuffer.PreparedClip = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                buffer.prepareClip(in: range) { continuation.resume(with: $0) }
                do {
                    var pixelBuffer: CVPixelBuffer?
                    guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &pixelBuffer) == kCVReturnSuccess,
                          let pixelBuffer else { throw TestError.sample }
                    CVPixelBufferLockBaseAddress(pixelBuffer, [])
                    memset(CVPixelBufferGetBaseAddress(pixelBuffer), 0, CVPixelBufferGetDataSize(pixelBuffer))
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
                    var format: CMVideoFormatDescription?
                    guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format) == noErr,
                          let format else { throw TestError.sample }
                    for index in 0..<(seconds * 30) {
                        if droppedFrames.contains(index) { continue }
                        let pts = CMTime(value: Int64(index), timescale: 30)
                        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: pts, decodeTimeStamp: .invalid)
                        var sample: CMSampleBuffer?
                        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                            formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
                              let sample else { throw TestError.sample }
                        buffer.append(sampleBuffer: sample, relativeTime: pts.seconds, videoRotationAngle: 90, sourceFPS: 30, queueDelay: 0)
                        if index == closeChunkAt {
                            buffer.prepareClip(in: CMTimeRange(start: .zero, end: pts)) { result in
                                switch result {
                                case .success(let clip): buffer.release(clip)
                                case .failure(let error): XCTFail("Earlier clip failed: \(error)")
                                }
                            }
                        }
                    }
                    buffer.reset(preservingPendingExports: true)
                } catch {
                    // Reset completes the pending request with an error exactly once.
                    buffer.reset()
                }
            }
        }
        return (buffer, queue, prepared)
    }

    @discardableResult
    private func assertFrames(_ asset: AVAsset, count: Int) async throws -> [Double] {
        let reader = try AVAssetReader(asset: asset)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var frames = 0
        var previous = -Double.infinity
        var timestamps: [Double] = []
        while let sample = output.copyNextSampleBuffer() {
            guard CMSampleBufferGetImageBuffer(sample) != nil else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            XCTAssertGreaterThan(pts, previous)
            previous = pts
            timestamps.append(pts)
            frames += 1
        }
        XCTAssertEqual(reader.status, .completed, reader.error?.localizedDescription ?? "")
        XCTAssertEqual(frames, count, "Chunk overlap must not duplicate or drop frames")
        return timestamps
    }

    private enum TestError: Error { case sample }
}
