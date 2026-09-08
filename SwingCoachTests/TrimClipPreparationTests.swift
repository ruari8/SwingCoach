import AVFoundation
import XCTest
@testable import SwingCoach

@MainActor
final class TrimClipPreparationTests: XCTestCase {
    private func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

    func testPaddingAddsContextAndPreservesDetectionTiming() {
        let detection = DetectedSwing(startTime: time(8.4), endTime: time(10.8), confidence: 1,
                                      impactTime: 10, declaredAt: 11)
        let clip = TrimClipPreparation.detectedClip(detection, duration: time(20), sourceTimeScale: 1, vantage: .dtl, context: SwingClipContext(before: 1, after: 1))
        XCTAssertEqual(clip.startTime, 7.4, accuracy: 0.001)
        XCTAssertEqual(clip.endTime, 11.8, accuracy: 0.001)
        XCTAssertEqual(clip.detectionImpactTime, 10)
        XCTAssertEqual(clip.detectionDeclaredAt, 11)
    }

    func testPaddingClampsAtVideoEdgesAndScalesImportedSlowMotion() {
        let detection = DetectedSwing(startTime: time(4), endTime: time(80), confidence: 1)
        let clip = TrimClipPreparation.detectedClip(detection, duration: time(84), sourceTimeScale: 8, vantage: .dtl, context: SwingClipContext(before: 1, after: 1))
        XCTAssertEqual(clip.startTime, 0)
        XCTAssertEqual(clip.endTime, 84)
        let middle = DetectedSwing(startTime: time(20), endTime: time(40), confidence: 1)
        let padded = TrimClipPreparation.detectedClip(middle, duration: time(84), sourceTimeScale: 8, vantage: .dtl, context: SwingClipContext(before: 1, after: 1))
        XCTAssertEqual(padded.startTime, 12)
        XCTAssertEqual(padded.endTime, 48)
    }

    func testAnalysisUsesChosenSuccessfullySavedRecordsInClipOrder() {
        let clips = (0..<3).map { SwingClip(startTime: time(Double($0)), endTime: time(Double($0 + 1))) }
        let a = saved(), b = saved()
        let records = [clips[0].id: a, clips[1].id: b]
        XCTAssertTrue(TrimClipPreparation.analysisSwings(clips: clips, selectedIDs: [], savedSwings: records).isEmpty)
        XCTAssertEqual(TrimClipPreparation.analysisSwings(clips: clips, selectedIDs: [clips[1].id], savedSwings: records).map(\.id), [b.id])
        XCTAssertEqual(TrimClipPreparation.analysisSwings(clips: clips, selectedIDs: Set(clips.map(\.id)), savedSwings: records).map(\.id), [a.id, b.id])
    }

    func testReviewCompositionBoundsVideoAndPreservesOrientationWithoutExport() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("trim-unit-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeRotatedVideo(to: url)
        let source = AVURLAsset(url: url)
        let clip = SwingClip(startTime: time(0.2), endTime: time(0.8))
        let asset = try await TrimClipPreparation.reviewAsset(source: source, clip: clip)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 0.6, accuracy: 0.01)
        let videos = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videos.count, 1)
        XCTAssertTrue(audio.isEmpty)
        let sourceTransform = try await source.loadTracks(withMediaType: .video).first!.load(.preferredTransform)
        let transform = try await videos[0].load(.preferredTransform)
        XCTAssertEqual(transform, sourceTransform)
    }

    private func writeRotatedVideo(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 640, AVVideoHeightKey: 360
        ])
        input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 360, ty: 0)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 640, 360, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        let pixelBuffer = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        memset(CVPixelBufferGetBaseAddress(pixelBuffer), 0, CVPixelBufferGetDataSize(pixelBuffer))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        for _ in 0..<100 where !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: .zero))
        writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
    }

    private func saved() -> SavedSwing {
        SavedSwing(id: UUID(), photoAssetID: "fixture", vantage: .dtl, duration: 3,
                   createdAt: Date(), notes: nil, analyzed: false)
    }
}
