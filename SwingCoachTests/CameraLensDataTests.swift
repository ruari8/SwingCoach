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
}
