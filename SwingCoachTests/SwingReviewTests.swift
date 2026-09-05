import XCTest
import AVFoundation
@testable import SwingCoach

@MainActor
final class SwingReviewTests: XCTestCase {
    func testConcurrentAnalysesKeepTheirVideoIdentityAndProgress() async {
        let a = swing(), b = swing()
        let service = ControlledAnalysis()
        let started = expectation(description: "Both requests started")
        started.expectedFulfillmentCount = 2
        service.onStart = { started.fulfill() }
        var saved: [UUID: String] = [:]
        let model = SwingReviewAnalysis(analyze: service.analyze) { response, swing in
            saved[swing.id] = response.analysisID
        }

        let first = Task { await model.run(for: a) }
        let second = Task { await model.run(for: b) }
        await fulfillment(of: [started], timeout: 2)
        // Opening B while A runs must leave A's state intact. Reopening A and
        // tapping again must not submit another request for the same video.
        await model.run(for: a)
        XCTAssertEqual(Set(service.startedIDs), [a.id, b.id])
        XCTAssertEqual(service.startedIDs.count, 2)
        service.progress[a.id]?("Uploading A", 0.4)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(model.requests[a.id]?.progressText, "Uploading A")
        XCTAssertEqual(model.requests[b.id]?.progressText, "Preparing video...")

        service.finish(b, response: response("result-B"))
        await second.value
        XCTAssertEqual(model.requests[a.id]?.status, .analyzing)
        XCTAssertEqual(model.requests[b.id]?.status, .complete)
        XCTAssertEqual(saved, [b.id: "result-B"])

        service.finish(a, response: response("result-A"))
        await first.value
        XCTAssertEqual(saved, [a.id: "result-A", b.id: "result-B"])
        service.progress[a.id]?("Late progress", 0.8)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertNil(model.requests[a.id]?.progressText)
    }

    func testRetryIgnoresProgressFromFailedRequest() async {
        let video = swing()
        let service = ControlledAnalysis()
        let started = expectation(description: "Initial request started")
        service.onStart = { started.fulfill() }
        let model = SwingReviewAnalysis(analyze: service.analyze, save: { _, _ in })
        let first = Task { await model.run(for: video) }
        await fulfillment(of: [started], timeout: 2)
        let staleProgress = service.progress[video.id]
        service.pending.removeValue(forKey: video.id)?.resume(throwing: URLError(.timedOut))
        await first.value
        guard case .failed = model.requests[video.id]?.status else {
            return XCTFail("A failed request must offer a retry")
        }

        let retried = expectation(description: "Retry started")
        service.onStart = { retried.fulfill() }
        let retry = Task { await model.run(for: video) }
        await fulfillment(of: [retried], timeout: 2)
        staleProgress?("Old attempt", 0.9)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(model.requests[video.id]?.progressText, "Preparing video...")
        service.finish(video, response: response("retry"))
        await retry.value
        XCTAssertEqual(model.requests[video.id]?.status, .complete)
    }

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

    private func swing() -> SavedSwing {
        SavedSwing(id: UUID(), photoAssetID: "test", vantage: .dtl, duration: 3,
                   createdAt: Date(), notes: nil, analyzed: false)
    }

    private func response(_ id: String) -> SwingCoachAPI.AnalysisResponse {
        .init(analysisID: id, summary: "Test", metrics: [], annotatedVideo: nil, drills: [])
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

@MainActor
private final class ControlledAnalysis {
    var pending: [UUID: CheckedContinuation<SwingCoachAPI.AnalysisResponse, Error>] = [:]
    var progress: [UUID: (String, Float?) -> Void] = [:]
    var startedIDs: [UUID] = []
    var onStart: () -> Void = {}

    func analyze(_ swing: SavedSwing, onProgress: @escaping (String, Float?) -> Void) async throws -> SwingCoachAPI.AnalysisResponse {
        startedIDs.append(swing.id)
        progress[swing.id] = onProgress
        return try await withCheckedThrowingContinuation { continuation in
            pending[swing.id] = continuation
            onStart()
        }
    }

    func finish(_ swing: SavedSwing, response: SwingCoachAPI.AnalysisResponse) {
        pending.removeValue(forKey: swing.id)?.resume(returning: response)
    }
}
