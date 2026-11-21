import XCTest
import AVFoundation
import Photos
@testable import SwingCoach

@MainActor
final class ClipStorageTests: XCTestCase {
    func testLocalClipSurvivesValidationSupportsPlaybackAndDeletesWithoutPhotos() async throws {
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

    /// A Photos-backed swing that also has positions and its own copy of
    /// the clip (so its tile shows the impact frame, not Photos' frame)
    /// must still be asked about: left out, it would look deleted from
    /// Photos and be removed from the library.
    func testPhotosCheckKeepsACoachedSwingWithItsOwnCopy() {
        func swing(asset: String, reference: Bool = false) -> SavedSwing {
            SavedSwing(id: UUID(), photoAssetID: asset, vantage: .dtl, duration: 3, createdAt: Date(), notes: nil,
                       isReference: reference, localVideoFilename: "\(UUID().uuidString).mov")
        }
        var coached = swing(asset: "COACHED/L0/001")
        coached.swingPositions = SwingPositions(model: SwingPositions.currentModel, positions: (1...10).map {
            SwingPosition(number: $0, clipTime: Double($0) * 0.2, confidence: 0.9)
        })
        XCTAssertNotNil(SwingLibrary.impactTime(coached.swingPositions!))
        let plain = swing(asset: "PLAIN/L0/001")
        let deletedInPhotos = swing(asset: "DELETED/L0/001")
        let reference = swing(asset: "REFERENCE/L0/001", reference: true)
        let localOnly = swing(asset: "")
        let photos: Set = [coached.photoAssetID, plain.photoAssetID]

        var asked: [String] = []
        let missing = SwingLibrary.swingsMissingFromPhotos(
            [coached, plain, deletedInPhotos, reference, localOnly]
        ) { ids in
            asked = ids
            // Photos answers only for what it was asked about.
            return photos.intersection(ids)
        }

        XCTAssertTrue(asked.contains(coached.photoAssetID), "Every Photos-backed swing is asked about")
        XCTAssertFalse(asked.contains(""), "A local-only clip is never looked up in Photos")
        XCTAssertEqual(missing, [deletedInPhotos.id])
    }

    func testPhotosCheckAsksNothingWithoutPhotosBackedSwings() {
        let localOnly = SavedSwing(id: UUID(), photoAssetID: "", vantage: .dtl, duration: 3, createdAt: Date(), notes: nil)
        let missing = SwingLibrary.swingsMissingFromPhotos([localOnly]) { _ in
            XCTFail("Photos must not be asked")
            return []
        }
        XCTAssertTrue(missing.isEmpty)
    }

    /// The placeholder every swing carries is small; the tile's picture is
    /// read at the tile's size from the same frame and crop.
    func testPlaceholderIsSmallAndTilePictureIsReadAtTheTileSize() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("poster-test-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: source) }
        try await writeRotatedVideo(to: source)

        // The clip is 360 x 640 as displayed: a 360-pixel square at most.
        let placeholder = await SwingPoster.picture(fromClipAt: source, time: 0, side: SwingPoster.placeholderSide)
        let small = try XCTUnwrap(placeholder)
        XCTAssertEqual(small.size.width * small.scale, SwingPoster.placeholderSide, accuracy: 1)
        XCTAssertEqual(small.size.height * small.scale, SwingPoster.placeholderSide, accuracy: 1)
        XCTAssertLessThan(LibraryTilePictures.bytes(of: small), 150_000)

        let tile = await SwingPoster.picture(fromClipAt: source, time: 0, side: 300)
        XCTAssertEqual(try XCTUnwrap(tile).size.width, 300, accuracy: 1)
        let neverScaledUp = await SwingPoster.picture(fromClipAt: source, time: 0, side: 660)
        XCTAssertLessThanOrEqual(try XCTUnwrap(neverScaledUp).size.width, 360)

        // A portrait frame is cut above its middle; a landscape one from its middle.
        let portrait = SwingPoster.cropRect(in: CGSize(width: 360, height: 640))
        XCTAssertEqual(portrait, CGRect(x: 0, y: 280 * LibraryGrid.thumbnailFocus, width: 360, height: 360))
        XCTAssertEqual(SwingPoster.cropRect(in: CGSize(width: 640, height: 360)), CGRect(x: 140, y: 0, width: 360, height: 360))
    }

    func testTilePicturesAreKeyedByPosterFrameSizedToTheTileAndForgotten() {
        var swing = SavedSwing(id: UUID(), photoAssetID: "", vantage: .dtl, duration: 3, createdAt: Date(), notes: nil)
        let pictures = LibraryTilePictures(byteLimit: 1_000_000)
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }

        XCTAssertNil(pictures.cached(for: swing))
        pictures.store(picture, side: 399, for: swing)
        XCTAssertNotNil(pictures.cached(for: swing))

        // Positions move the poster to impact: the old picture is not this swing's any more.
        let before = LibraryTilePictures.key(for: swing)
        swing.swingPositions = SwingPositions(model: SwingPositions.currentModel, positions: [
            SwingPosition(number: 7, clipTime: 1.95, confidence: 0.9),
        ])
        XCTAssertNotEqual(LibraryTilePictures.key(for: swing), before)
        XCTAssertNil(pictures.cached(for: swing))

        pictures.store(picture, side: 399, for: swing)
        pictures.forget(swing.id)
        XCTAssertNil(pictures.cached(for: swing))

        // Three columns on a 402-point, 3x screen; never above the largest tile.
        XCTAssertEqual(LibraryTilePictures.pixelSide(points: 132.67, scale: 3), 399)
        XCTAssertEqual(LibraryTilePictures.pixelSide(points: 400, scale: 3), LibraryGrid.largestTile * 3)
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
