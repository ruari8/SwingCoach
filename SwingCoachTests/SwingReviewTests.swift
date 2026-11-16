import XCTest
import AVFoundation
@testable import SwingCoach

@MainActor
final class SwingReviewTests: XCTestCase {
    func testDrawingLoadsRotatedVideoDimensionsWithoutPreparingPlayerItem() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("review-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeRotatedVideo(to: url)
        let item = AVPlayerItem(url: url)
        XCTAssertEqual(item.presentationSize, .zero)
        let loadedRatio = try await VideoDisplayGeometry.aspectRatio(for: item.asset)
        let ratio = try XCTUnwrap(loadedRatio)
        XCTAssertEqual(ratio, 360.0 / 640.0, accuracy: 0.0001)

        // A point on the video's left edge must follow that edge as letterboxes
        // change sides. It must never be positioned at the container's edge.
        let portrait = VideoDisplayGeometry.contentRect(in: CGSize(width: 390, height: 844), aspectRatio: ratio)
        let landscape = VideoDisplayGeometry.contentRect(in: CGSize(width: 844, height: 390), aspectRatio: ratio)
        XCTAssertEqual(portrait.minX, 0)
        XCTAssertGreaterThan(portrait.minY, 0)
        XCTAssertGreaterThan(landscape.minX, 300)
        XCTAssertEqual(landscape.minY, 0)
        XCTAssertFalse(portrait.contains(CGPoint(x: 195, y: 10)))
        XCTAssertFalse(landscape.contains(CGPoint(x: 10, y: 195)))
        XCTAssertEqual(landscape.width / landscape.height, 360.0 / 640.0, accuracy: 0.0001)
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
}
