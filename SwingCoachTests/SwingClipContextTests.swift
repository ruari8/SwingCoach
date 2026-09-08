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

    private func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 60000) }

    private func record(seconds: Int, range: CMTimeRange) async throws -> (AutoRollingVideoBuffer, DispatchQueue, AutoRollingVideoBuffer.PreparedClip) {
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
                        let pts = CMTime(value: Int64(index), timescale: 30)
                        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: pts, decodeTimeStamp: .invalid)
                        var sample: CMSampleBuffer?
                        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                            formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
                              let sample else { throw TestError.sample }
                        buffer.append(sampleBuffer: sample, relativeTime: pts.seconds, videoRotationAngle: 90, sourceFPS: 30, queueDelay: 0)
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

    private func assertFrames(_ asset: AVAsset, count: Int) async throws {
        let reader = try AVAssetReader(asset: asset)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var frames = 0
        var previous = -Double.infinity
        while let sample = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            XCTAssertGreaterThan(pts, previous)
            previous = pts
            frames += 1
        }
        XCTAssertEqual(reader.status, .completed, reader.error?.localizedDescription ?? "")
        XCTAssertEqual(frames, count, "Chunk overlap must not duplicate or drop frames")
    }

    private enum TestError: Error { case sample }
}
