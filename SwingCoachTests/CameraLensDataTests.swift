import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import simd
import XCTest
@testable import SwingCoach

final class CameraLensDataTests: XCTestCase {
    func testFocalLengthFromIntrinsicMatrixHandlesPortraitRotationAndScaling() throws {
        let intrinsic = CameraLensData.IntrinsicMatrix(
            fx: 1600,
            fy: 1596,
            cx: 960,
            cy: 540,
            referenceWidth: 1920,
            referenceHeight: 1080,
            lensPosition: 0.72
        )
        let lens = try XCTUnwrap(CameraLensData.make(
            cameraType: "AVCaptureDeviceTypeBuiltInWideAngleCamera",
            formatWidth: 1920,
            formatHeight: 1080,
            videoRotationAngle: 90,
            videoFieldOfView: 62.0,
            videoZoomFactor: 1.0,
            geometricDistortionCorrectionEnabled: true,
            intrinsicMatrixDeliverySupported: true,
            intrinsicMatrix: intrinsic
        ))

        XCTAssertEqual(lens.recordedWidth, 1080)
        XCTAssertEqual(lens.recordedHeight, 1920)
        XCTAssertEqual(lens.focalLengthSource, .intrinsicMatrix)
        XCTAssertEqual(lens.focalLengthPixels, 1598.0, accuracy: 0.001)
        XCTAssertEqual(lens.focalLengthPixels(forWidth: 540, height: 960), 799.0, accuracy: 0.001)
        XCTAssertEqual(lens.summaryText, "1598 px (intrinsic)")
    }

    func testFocalLengthFallsBackToFieldOfViewAndZoomFactor() throws {
        let lens1x = try XCTUnwrap(CameraLensData.make(
            cameraType: "AVCaptureDeviceTypeBuiltInWideAngleCamera",
            formatWidth: 1920,
            formatHeight: 1080,
            videoRotationAngle: 90,
            videoFieldOfView: 62.0,
            videoZoomFactor: 1.0,
            geometricDistortionCorrectionEnabled: false,
            intrinsicMatrixDeliverySupported: false,
            intrinsicMatrix: nil
        ))
        // 960 / tan(31 deg) = 1597.709...
        XCTAssertEqual(lens1x.focalLengthSource, .fieldOfViewFallback)
        XCTAssertEqual(lens1x.recordedWidth, 1080)
        XCTAssertEqual(lens1x.recordedHeight, 1920)
        XCTAssertEqual(lens1x.focalLengthPixels, 960.0 / tan(31.0 * .pi / 180.0), accuracy: 0.01)
        XCTAssertEqual(lens1x.summaryText, "1598 px (62.0° FOV)")

        let lens2x = try XCTUnwrap(CameraLensData.make(
            cameraType: nil,
            formatWidth: 1920,
            formatHeight: 1080,
            videoRotationAngle: 0,
            videoFieldOfView: 62.0,
            videoZoomFactor: 2.0,
            geometricDistortionCorrectionEnabled: nil,
            intrinsicMatrixDeliverySupported: false,
            intrinsicMatrix: nil
        ))
        XCTAssertEqual(lens2x.recordedWidth, 1920)
        XCTAssertEqual(lens2x.recordedHeight, 1080)
        XCTAssertEqual(lens2x.focalLengthPixels, lens1x.focalLengthPixels * 2.0, accuracy: 0.01)
    }

    func testExtractIntrinsicMatrixFromSampleBufferAttachment() throws {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 1920, 1080,
            kCVPixelFormatType_32BGRA, nil, &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        let pb = try XCTUnwrap(pixelBuffer)

        var formatDescription: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pb, formatDescriptionOut: &formatDescription
        ), noErr)
        let fmt = try XCTUnwrap(formatDescription)

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 240),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pb,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fmt,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        ), noErr)
        let sb = try XCTUnwrap(sampleBuffer)

        // No attachment yet -> nil.
        XCTAssertNil(CameraLensData.extractIntrinsicMatrix(from: sb))

        var matrix = simd_float3x3(
            SIMD3<Float>(1612.5, 0, 0),
            SIMD3<Float>(0, 1610.5, 0),
            SIMD3<Float>(958.0, 541.0, 1)
        )
        let data = withUnsafeBytes(of: &matrix) { Data($0) }
        CMSetAttachment(
            sb,
            key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
            value: data as CFData,
            attachmentMode: kCMAttachmentMode_ShouldPropagate
        )

        let extracted = try XCTUnwrap(CameraLensData.extractIntrinsicMatrix(from: sb, lensPosition: 0.65))
        XCTAssertEqual(extracted.fx, 1612.5, accuracy: 0.001)
        XCTAssertEqual(extracted.fy, 1610.5, accuracy: 0.001)
        XCTAssertEqual(extracted.cx, 958.0, accuracy: 0.001)
        XCTAssertEqual(extracted.cy, 541.0, accuracy: 0.001)
        XCTAssertEqual(extracted.referenceWidth, 1920)
        XCTAssertEqual(extracted.referenceHeight, 1080)
        XCTAssertEqual(extracted.lensPosition ?? 0, 0.65, accuracy: 0.0001)
    }

    func testOlderSavedSwingWithoutLensDataDecodesAsUnknown() throws {
        let legacyJSON = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "photoAssetID": "",
          "vantage": "DTL",
          "duration": 2.4,
          "createdAt": 785000000,
          "isFavorite": false,
          "isReference": false,
          "sourceTimeScale": 8
        }
        """
        let swing = try JSONDecoder().decode(SavedSwing.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(swing.lensData)
        XCTAssertEqual(swing.sourceTimeScale, 8)
    }

    func testSavedSwingRoundTripsLensData() throws {
        let lens = try XCTUnwrap(CameraLensData.make(
            cameraType: "AVCaptureDeviceTypeBuiltInWideAngleCamera",
            formatWidth: 1920,
            formatHeight: 1080,
            videoRotationAngle: 90,
            videoFieldOfView: 62.5,
            videoZoomFactor: 1.0,
            geometricDistortionCorrectionEnabled: true,
            intrinsicMatrixDeliverySupported: true,
            intrinsicMatrix: CameraLensData.IntrinsicMatrix(
                fx: 1595, fy: 1595, cx: 960, cy: 540,
                referenceWidth: 1920, referenceHeight: 1080, lensPosition: 0.7
            )
        ))
        let original = SavedSwing(
            id: UUID(),
            photoAssetID: "",
            vantage: .dtl,
            duration: 18.0,
            createdAt: Date(timeIntervalSinceReferenceDate: 785_000_000),
            notes: nil,
            sourceTimeScale: 8,
            lensData: lens
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SavedSwing.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.lensData?.focalLengthPixels ?? 0, 1595.0, accuracy: 0.001)
    }

    func testRotation180And270AndInvalidInputs() throws {
        let lens180 = try XCTUnwrap(CameraLensData.make(
            cameraType: nil, formatWidth: 1920, formatHeight: 1080,
            videoRotationAngle: 180, videoFieldOfView: 65.0, videoZoomFactor: 1.0,
            geometricDistortionCorrectionEnabled: nil, intrinsicMatrixDeliverySupported: false,
            intrinsicMatrix: nil
        ))
        XCTAssertEqual(lens180.recordedWidth, 1920)
        XCTAssertEqual(lens180.recordedHeight, 1080)

        let lens270 = try XCTUnwrap(CameraLensData.make(
            cameraType: nil, formatWidth: 1920, formatHeight: 1080,
            videoRotationAngle: 270, videoFieldOfView: 65.0, videoZoomFactor: 1.0,
            geometricDistortionCorrectionEnabled: nil, intrinsicMatrixDeliverySupported: false,
            intrinsicMatrix: nil
        ))
        XCTAssertEqual(lens270.recordedWidth, 1080)
        XCTAssertEqual(lens270.recordedHeight, 1920)

        // Bad format dimensions, FOV, or zoom -> nil.
        XCTAssertNil(CameraLensData.make(
            cameraType: nil, formatWidth: 0, formatHeight: 1080,
            videoRotationAngle: 90, videoFieldOfView: 65.0, videoZoomFactor: 1.0,
            geometricDistortionCorrectionEnabled: nil, intrinsicMatrixDeliverySupported: false,
            intrinsicMatrix: nil
        ))
        XCTAssertNil(CameraLensData.make(
            cameraType: nil, formatWidth: 1920, formatHeight: 1080,
            videoRotationAngle: 90, videoFieldOfView: 0, videoZoomFactor: 1.0,
            geometricDistortionCorrectionEnabled: nil, intrinsicMatrixDeliverySupported: false,
            intrinsicMatrix: nil
        ))
        XCTAssertNil(CameraLensData.make(
            cameraType: nil, formatWidth: 1920, formatHeight: 1080,
            videoRotationAngle: 90, videoFieldOfView: 65.0, videoZoomFactor: 0,
            geometricDistortionCorrectionEnabled: nil, intrinsicMatrixDeliverySupported: false,
            intrinsicMatrix: nil
        ))
    }

    func testStaleIntrinsicWithMismatchedFormatDimensionsIsIgnored() throws {
        // Stale 1280x720 intrinsic while active format is 1920x1080 -> must fall back to FOV.
        let stale = CameraLensData.IntrinsicMatrix(
            fx: 900, fy: 900, cx: 640, cy: 360,
            referenceWidth: 1280, referenceHeight: 720, lensPosition: 0.5
        )
        let lens = try XCTUnwrap(CameraLensData.make(
            cameraType: "AVCaptureDeviceTypeBuiltInWideAngleCamera",
            formatWidth: 1920, formatHeight: 1080,
            videoRotationAngle: 90, videoFieldOfView: 62.0, videoZoomFactor: 1.0,
            geometricDistortionCorrectionEnabled: false,
            intrinsicMatrixDeliverySupported: true,
            intrinsicMatrix: stale
        ))
        XCTAssertEqual(lens.focalLengthSource, .fieldOfViewFallback)
        XCTAssertNil(lens.intrinsicMatrix)
        XCTAssertEqual(lens.focalLengthPixels, 960.0 / tan(31.0 * .pi / 180.0), accuracy: 0.01)
    }

    func testMalformedLensDataDoesNotBreakSavedSwingDecoding() throws {
        let corruptedJSON = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "photoAssetID": "",
          "vantage": "DTL",
          "duration": 2.4,
          "createdAt": 785000000,
          "isFavorite": false,
          "isReference": false,
          "sourceTimeScale": 8,
          "lensData": { "unexpected": true }
        }
        """
        let swing = try JSONDecoder().decode(SavedSwing.self, from: Data(corruptedJSON.utf8))
        XCTAssertNil(swing.lensData)
        XCTAssertEqual(swing.sourceTimeScale, 8)
    }

    func testExportManifestJSONShapeDecodesWithHarnessSchema() throws {
        struct HarnessManifest: Decodable {
            struct Item: Decodable {
                let filename: String
                let lens: CameraLensData?
            }
            let swings: [Item]
        }
        struct ExportItem: Encodable {
            let filename: String
            let lens: CameraLensData?
        }
        struct ExportManifest: Encodable {
            let swings: [ExportItem]
        }
        let lens = try XCTUnwrap(CameraLensData.make(
            cameraType: "AVCaptureDeviceTypeBuiltInWideAngleCamera",
            formatWidth: 1920, formatHeight: 1080,
            videoRotationAngle: 90, videoFieldOfView: 70.65, videoZoomFactor: 1.0,
            geometricDistortionCorrectionEnabled: false,
            intrinsicMatrixDeliverySupported: false,
            intrinsicMatrix: nil
        ))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(ExportManifest(swings: [
            ExportItem(filename: "001_dtl.mp4", lens: lens),
            ExportItem(filename: "002_dtl.mp4", lens: nil)
        ]))
        let decoded = try JSONDecoder().decode(HarnessManifest.self, from: data)
        XCTAssertEqual(decoded.swings.count, 2)
        XCTAssertEqual(decoded.swings[0].lens, lens)
        XCTAssertNil(decoded.swings[1].lens)
    }

    #if !targetEnvironment(simulator)
    func testPhysicalCameraLensCaptureAcrossFrameRates() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw XCTSkip("No back wide camera available")
        }
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let videoOutput = AVCaptureVideoDataOutput()
        let movieOutput = AVCaptureMovieFileOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        final class FrameGrabber: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
            let lock = NSLock()
            var intrinsic: CameraLensData.IntrinsicMatrix?
            var frames = 0
            func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
                lock.lock()
                frames += 1
                if intrinsic == nil {
                    intrinsic = CameraLensData.extractIntrinsicMatrix(from: sampleBuffer)
                }
                lock.unlock()
            }
            func reset() {
                lock.lock()
                intrinsic = nil
                frames = 0
                lock.unlock()
            }
        }

        let grabber = FrameGrabber()
        let q = DispatchQueue(label: "test.camera.lens.probe")
        videoOutput.setSampleBufferDelegate(grabber, queue: q)

        session.beginConfiguration()
        XCTAssertTrue(session.canAddInput(input))
        session.addInput(input)
        XCTAssertTrue(session.canAddOutput(movieOutput))
        session.addOutput(movieOutput)
        XCTAssertTrue(session.canAddOutput(videoOutput))
        session.addOutput(videoOutput)
        session.commitConfiguration()

        defer { if session.isRunning { session.stopRunning() } }

        for mode in [SloMoMode.ultra, .standard, .smooth, .normal] {
            let targetRes = mode.targetResolution
            let targetFPS = mode.targetFPS
            guard let format = device.formats.first(where: { fmt in
                let d = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
                return d.width == targetRes.width && d.height == targetRes.height &&
                    fmt.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= targetFPS }
            }) else { continue }

            session.beginConfiguration()
            try device.lockForConfiguration()
            device.activeFormat = format
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            device.unlockForConfiguration()
            let conn = try XCTUnwrap(videoOutput.connection(with: .video))
            let supported = conn.isCameraIntrinsicMatrixDeliverySupported
            if supported { conn.isCameraIntrinsicMatrixDeliveryEnabled = true }
            session.commitConfiguration()

            grabber.reset()
            if !session.isRunning { session.startRunning() }
            Thread.sleep(forTimeInterval: 0.35)

            grabber.lock.lock()
            let intrinsic = grabber.intrinsic
            let frameCount = grabber.frames
            grabber.lock.unlock()

            let lens = try XCTUnwrap(CameraLensData.capture(
                device: device,
                videoRotationAngle: 90,
                intrinsicMatrixDeliverySupported: supported,
                intrinsicMatrix: intrinsic
            ))
            print("HW_LENS_PROBE mode=\(mode.displayName) frames=\(frameCount) supported=\(supported) fov=\(format.videoFieldOfView) gdcFov=\(format.geometricDistortionCorrectedVideoFieldOfView) gdcOn=\(device.isGeometricDistortionCorrectionEnabled) focal=\(String(format: "%.2f", lens.focalLengthPixels)) source=\(lens.focalLengthSource.rawValue) fx=\(intrinsic?.fx ?? -1) fy=\(intrinsic?.fy ?? -1)")
            XCTAssertGreaterThan(lens.focalLengthPixels, 500)
            XCTAssertEqual(lens.recordedWidth, Int(targetRes.height))
            XCTAssertEqual(lens.recordedHeight, Int(targetRes.width))
        }
    }
    #endif
}
