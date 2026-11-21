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

    /// Coaching drawings and the video are both placed with `contentRect`
    /// in the same frame, so a normalised point lands on the same pixel of
    /// the picture whichever way the frame is letterboxed.
    func testANormalisedPointMapsOntoTheAspectFitVideo() {
        // A 9:16 clip on a 402 x 874 screen: full width, black above and below.
        let tall = VideoDisplayGeometry.contentRect(in: CGSize(width: 402, height: 874), aspectRatio: 9.0 / 16.0)
        XCTAssertEqual(tall.minX, 0)
        XCTAssertEqual(tall.width, 402)
        XCTAssertEqual(tall.height, 402 * 16.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(tall.midY, 437, accuracy: 0.001)
        XCTAssertEqual(tall.minY + 0.15 * tall.height, 79.67 + 107.2, accuracy: 0.01)

        // A 16:9 clip on the same screen: letterboxed, centred.
        let wide = VideoDisplayGeometry.contentRect(in: CGSize(width: 402, height: 874), aspectRatio: 16.0 / 9.0)
        XCTAssertEqual(wide.width, 402)
        XCTAssertEqual(wide.height, 226.125, accuracy: 0.001)
        XCTAssertEqual(wide.midY, 437, accuracy: 0.001)
    }

    /// A 9:16 clip edge to edge on a 402 x 874 screen with a 62-point top
    /// inset is anchored with its top at the safe area's top (62), so no
    /// black is left above it; the top row ends at 114.
    func testStopLiftNeverPutsTheFocusUnderTheTopRow() {
        let videoTop: CGFloat = 62, height: CGFloat = 402 * 16.0 / 9.0, topRowBottom: CGFloat = 114
        // The head, a tenth of the way down: 19 points under the row.
        let head = videoTop + 0.1 * height
        XCTAssertEqual(VideoDisplayGeometry.stopLift(wanted: 200, focusTop: head, topRowBottom: topRowBottom,
                                                     blackBand: 0, most: 350), 0,
                       "With no black above the clip, the lift stops at the headroom")
        // The hips, halfway down: the lift keeps the headroom under the row.
        let hips = videoTop + 0.5 * height
        let lift = VideoDisplayGeometry.stopLift(wanted: 400, focusTop: hips, topRowBottom: topRowBottom,
                                                 blackBand: 0, most: 350)
        XCTAssertEqual(hips - lift, topRowBottom + VideoDisplayGeometry.stopHeadroom, accuracy: 0.001)
        // No more than is wanted, and never down.
        XCTAssertEqual(VideoDisplayGeometry.stopLift(wanted: 30, focusTop: hips, topRowBottom: topRowBottom,
                                                     blackBand: 0, most: 350), 30)
        XCTAssertEqual(VideoDisplayGeometry.stopLift(wanted: -20, focusTop: hips, topRowBottom: topRowBottom,
                                                     blackBand: 0, most: 350), 0)

        // A letterboxed clip, its top 262 points under the safe area: the
        // black above it may be used, giving up the headroom, but the
        // focus's top stops at the row.
        let letterboxedTop: CGFloat = 324, focus = letterboxedTop + 10
        let intoBand = VideoDisplayGeometry.stopLift(wanted: 400, focusTop: focus, topRowBottom: topRowBottom,
                                                     blackBand: 262, most: 350)
        XCTAssertEqual(focus - intoBand, topRowBottom, accuracy: 0.001)
        XCTAssertEqual(VideoDisplayGeometry.stopLift(wanted: 400, focusTop: focus, topRowBottom: topRowBottom,
                                                     blackBand: 262, most: 100), 100)
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
