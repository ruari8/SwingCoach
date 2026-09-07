import XCTest
import AVFoundation
import Photos
@testable import SwingCoach

@MainActor
final class ClipStorageTests: XCTestCase {
    func testLocalClipSurvivesValidationSupportsPlaybackAndAnalysisAndDeletesWithoutPhotos() async throws {
        let previous = UserDefaults.standard.object(forKey: ClipStoragePreference.saveToPhotosKey)
        defer { UserDefaults.standard.set(previous, forKey: ClipStoragePreference.saveToPhotosKey) }
        UserDefaults.standard.set(false, forKey: ClipStoragePreference.saveToPhotosKey)
        let library = SwingLibrary.shared
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("storage-test-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: source) }
        try await writeRotatedVideo(to: source)
        let authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let swing = try await library.saveExportedSwing(from: source, vantage: .dtl, duration: 1)
        defer { library.removeSwings(withIDs: [swing.id]) }
        XCTAssertTrue(swing.photoAssetID.isEmpty)
        let local = try XCTUnwrap(library.localVideoURL(for: swing))
        XCTAssertEqual(try Data(contentsOf: local), try Data(contentsOf: source))
        XCTAssertEqual(try local.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, false)
        library.validateAssets()
        XCTAssertTrue(library.swings.contains { $0.id == swing.id })
        let item = await library.getPlayerItem(for: swing)
        XCTAssertNotNil(item)
        await library.loadThumbnails()
        XCTAssertNotNil(library.swings.first { $0.id == swing.id }?.thumbnail)
        let upload = try await SwingCoachAPI.shared.exportVideoToMP4(swing: swing)
        XCTAssertGreaterThan(upload.count, 0)
        try await library.deleteSwingAndPhoto(swing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path))
        XCTAssertEqual(PHPhotoLibrary.authorizationStatus(for: .addOnly), authorization)
    }

    func testFailedLocalCopyDoesNotPublishASwing() async {
        let library = SwingLibrary.shared
        let before = library.swings.map(\.id)
        do {
            try await library.saveExportedSwing(from: URL(fileURLWithPath: "/missing-clip.mp4"), vantage: .dtl, duration: 2)
            XCTFail("Missing source must fail before publishing a library entry")
        } catch {
            XCTAssertEqual(library.swings.map(\.id), before)
        }
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
