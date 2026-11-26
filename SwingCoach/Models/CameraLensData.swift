//
//  CameraLensData.swift
//  SwingCoach
//
//  Camera lens and intrinsic calibration data captured alongside a swing,
//  so downstream ball-flight and geometry code can compute focal length in
//  pixels for the recorded resolution instead of guessing field of view.
//

import Foundation
import simd
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(CoreMedia)
import CoreMedia
#endif
#if canImport(CoreVideo)
import CoreVideo
#endif

/// Lens geometry and optional per-frame intrinsic matrix recorded with a swing.
nonisolated struct CameraLensData: Codable, Equatable, Sendable {
    /// Camera intrinsic matrix sampled from `kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix`.
    /// Entries are in pixels of `referenceWidth × referenceHeight` (the raw sample buffer).
    nonisolated struct IntrinsicMatrix: Codable, Equatable, Sendable {
        let fx: Double
        let fy: Double
        let cx: Double
        let cy: Double
        let referenceWidth: Int
        let referenceHeight: Int
        let lensPosition: Double?
    }

    nonisolated enum FocalLengthSource: String, Codable, Equatable, Sendable {
        case intrinsicMatrix
        case fieldOfViewFallback
    }

    let cameraType: String?
    /// Active camera format dimensions (sensor orientation, before rotation).
    let formatWidth: Int
    let formatHeight: Int
    /// Recorded clip's upright pixel dimensions (after cardinal capture rotation).
    let recordedWidth: Int
    let recordedHeight: Int
    /// Cardinal capture rotation applied to the recording (0, 90, 180, 270).
    let videoRotationAngle: Double?
    /// `AVCaptureDevice.Format.videoFieldOfView` in degrees (along the format's long edge at 1× zoom).
    let videoFieldOfView: Double
    /// `AVCaptureDevice.videoZoomFactor` at capture time.
    let videoZoomFactor: Double
    let geometricDistortionCorrectionEnabled: Bool?
    let intrinsicMatrixDeliverySupported: Bool?
    let intrinsicMatrix: IntrinsicMatrix?
    /// Focal length in pixels for `recordedWidth × recordedHeight`.
    let focalLengthPixels: Double
    let focalLengthSource: FocalLengthSource

    /// Computes recorded dimensions and focal length in pixels from format and optional intrinsics.
    static func make(
        cameraType: String?,
        formatWidth: Int,
        formatHeight: Int,
        videoRotationAngle: Double?,
        videoFieldOfView: Double,
        videoZoomFactor: Double,
        geometricDistortionCorrectionEnabled: Bool?,
        intrinsicMatrixDeliverySupported: Bool?,
        intrinsicMatrix: IntrinsicMatrix?
    ) -> CameraLensData? {
        guard formatWidth > 0, formatHeight > 0 else { return nil }
        let quarterTurn = isQuarterTurn(videoRotationAngle)
        let recordedWidth = quarterTurn ? formatHeight : formatWidth
        let recordedHeight = quarterTurn ? formatWidth : formatHeight

        let focalLength: Double
        let source: FocalLengthSource
        if let intrinsic = intrinsicMatrix,
           let computed = focalLengthFromIntrinsic(intrinsic, recordedWidth: recordedWidth, recordedHeight: recordedHeight) {
            focalLength = computed
            source = .intrinsicMatrix
        } else if let computed = focalLengthFromFieldOfView(
            videoFieldOfView,
            zoomFactor: videoZoomFactor,
            recordedWidth: recordedWidth,
            recordedHeight: recordedHeight
        ) {
            focalLength = computed
            source = .fieldOfViewFallback
        } else {
            return nil
        }

        return CameraLensData(
            cameraType: cameraType,
            formatWidth: formatWidth,
            formatHeight: formatHeight,
            recordedWidth: recordedWidth,
            recordedHeight: recordedHeight,
            videoRotationAngle: videoRotationAngle,
            videoFieldOfView: videoFieldOfView,
            videoZoomFactor: videoZoomFactor,
            geometricDistortionCorrectionEnabled: geometricDistortionCorrectionEnabled,
            intrinsicMatrixDeliverySupported: intrinsicMatrixDeliverySupported,
            intrinsicMatrix: intrinsicMatrix,
            focalLengthPixels: focalLength,
            focalLengthSource: source
        )
    }

    /// Scales `focalLengthPixels` to an arbitrary pixel resolution (e.g. a resized analysis frame).
    func focalLengthPixels(forWidth width: Int, height: Int) -> Double {
        let baseLong = Double(max(recordedWidth, recordedHeight))
        let targetLong = Double(max(width, height))
        guard baseLong > 0, targetLong > 0 else { return focalLengthPixels }
        return focalLengthPixels * (targetLong / baseLong)
    }

    /// Short human-readable summary for Swing Info and review sheets.
    var summaryText: String {
        let px = Int(focalLengthPixels.rounded())
        switch focalLengthSource {
        case .intrinsicMatrix:
            return "\(px) px (intrinsic)"
        case .fieldOfViewFallback:
            return String(format: "%d px (%.1f° FOV)", px, videoFieldOfView)
        }
    }

    var diagnosticValues: [String: Double] {
        var values: [String: Double] = [
            "focalLengthPixels": focalLengthPixels,
            "videoFieldOfView": videoFieldOfView,
            "videoZoomFactor": videoZoomFactor,
            "formatWidth": Double(formatWidth),
            "formatHeight": Double(formatHeight),
            "recordedWidth": Double(recordedWidth),
            "recordedHeight": Double(recordedHeight)
        ]
        if let gdc = geometricDistortionCorrectionEnabled {
            values["geometricDistortionCorrection"] = gdc ? 1 : 0
        }
        if let supported = intrinsicMatrixDeliverySupported {
            values["intrinsicSupported"] = supported ? 1 : 0
        }
        if let intrinsic = intrinsicMatrix {
            values["intrinsicFx"] = intrinsic.fx
            values["intrinsicFy"] = intrinsic.fy
            values["intrinsicCx"] = intrinsic.cx
            values["intrinsicCy"] = intrinsic.cy
            values["intrinsicRefWidth"] = Double(intrinsic.referenceWidth)
            values["intrinsicRefHeight"] = Double(intrinsic.referenceHeight)
            if let lensPos = intrinsic.lensPosition {
                values["intrinsicLensPosition"] = lensPos
            }
        }
        return values
    }

    var diagnosticState: [String: String] {
        var state: [String: String] = ["focalLengthSource": focalLengthSource.rawValue]
        if let cameraType { state["camera"] = cameraType }
        return state
    }

    private static func isQuarterTurn(_ angle: Double?) -> Bool {
        guard let angle, angle.isFinite else { return false }
        let normalized = Int(angle.rounded()) % 180
        return abs(normalized) == 90
    }

    static func focalLengthFromIntrinsic(
        _ intrinsic: IntrinsicMatrix,
        recordedWidth: Int,
        recordedHeight: Int
    ) -> Double? {
        guard intrinsic.fx.isFinite, intrinsic.fy.isFinite,
              intrinsic.fx > 0, intrinsic.fy > 0,
              intrinsic.referenceWidth > 0, intrinsic.referenceHeight > 0,
              recordedWidth > 0, recordedHeight > 0
        else { return nil }

        let refLong = Double(max(intrinsic.referenceWidth, intrinsic.referenceHeight))
        let refShort = Double(min(intrinsic.referenceWidth, intrinsic.referenceHeight))
        let recLong = Double(max(recordedWidth, recordedHeight))
        let recShort = Double(min(recordedWidth, recordedHeight))
        let fLongRef = intrinsic.referenceWidth >= intrinsic.referenceHeight ? intrinsic.fx : intrinsic.fy
        let fShortRef = intrinsic.referenceWidth >= intrinsic.referenceHeight ? intrinsic.fy : intrinsic.fx
        let fLong = fLongRef * (recLong / refLong)
        let fShort = fShortRef * (recShort / refShort)
        let mean = (fLong + fShort) * 0.5
        return mean.isFinite && mean > 0 ? mean : nil
    }

    static func focalLengthFromFieldOfView(
        _ fovDegrees: Double,
        zoomFactor: Double,
        recordedWidth: Int,
        recordedHeight: Int
    ) -> Double? {
        guard fovDegrees.isFinite, fovDegrees > 0, fovDegrees < 180,
              zoomFactor.isFinite, zoomFactor > 0,
              recordedWidth > 0, recordedHeight > 0
        else { return nil }

        let halfRad = (fovDegrees * .pi / 180.0) * 0.5
        let tanHalf = tan(halfRad)
        guard tanHalf.isFinite, tanHalf > 0 else { return nil }
        let recordedLong = Double(max(recordedWidth, recordedHeight))
        let f = (recordedLong * 0.5 / tanHalf) * zoomFactor
        return f.isFinite && f > 0 ? f : nil
    }

    /// Parses a `simd_float3x3` intrinsic matrix from raw bytes (column-major, 48 bytes).
    static func intrinsicMatrix(
        fromData data: Data,
        referenceWidth: Int,
        referenceHeight: Int,
        lensPosition: Double? = nil
    ) -> IntrinsicMatrix? {
        guard data.count >= MemoryLayout<simd_float3x3>.size,
              referenceWidth > 0, referenceHeight > 0
        else { return nil }

        let matrix = data.withUnsafeBytes { raw in
            raw.loadUnaligned(as: simd_float3x3.self)
        }
        let fx = Double(matrix.columns.0.x)
        let fy = Double(matrix.columns.1.y)
        let cx = Double(matrix.columns.2.x)
        let cy = Double(matrix.columns.2.y)
        guard fx.isFinite, fy.isFinite, cx.isFinite, cy.isFinite,
              fx > 0, fy > 0
        else { return nil }

        return IntrinsicMatrix(
            fx: fx,
            fy: fy,
            cx: cx,
            cy: cy,
            referenceWidth: referenceWidth,
            referenceHeight: referenceHeight,
            lensPosition: lensPosition
        )
    }

    #if canImport(CoreMedia) && canImport(CoreVideo)
    /// Extracts the per-frame camera intrinsic matrix attached to a `CMSampleBuffer`, if present.
    static func extractIntrinsicMatrix(
        from sampleBuffer: CMSampleBuffer,
        lensPosition: Double? = nil
    ) -> IntrinsicMatrix? {
        guard let raw = CMGetAttachment(
            sampleBuffer,
            key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
            attachmentModeOut: nil
        ) as? Data else {
            return nil
        }

        let width: Int
        let height: Int
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            width = CVPixelBufferGetWidth(pixelBuffer)
            height = CVPixelBufferGetHeight(pixelBuffer)
        } else if let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let dims = CMVideoFormatDescriptionGetDimensions(format)
            width = Int(dims.width)
            height = Int(dims.height)
        } else {
            return nil
        }

        return intrinsicMatrix(
            fromData: raw,
            referenceWidth: width,
            referenceHeight: height,
            lensPosition: lensPosition
        )
    }
    #endif

    #if os(iOS) && canImport(AVFoundation)
    /// Snapshots the active camera format's lens data and combines it with the latest intrinsic matrix.
    static func capture(
        device: AVCaptureDevice,
        videoRotationAngle: CGFloat,
        intrinsicMatrixDeliverySupported: Bool?,
        intrinsicMatrix: IntrinsicMatrix?
    ) -> CameraLensData? {
        let format = device.activeFormat
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let gdcEnabled = device.isGeometricDistortionCorrectionSupported
            ? device.isGeometricDistortionCorrectionEnabled
            : false
        return make(
            cameraType: device.deviceType.rawValue,
            formatWidth: Int(dims.width),
            formatHeight: Int(dims.height),
            videoRotationAngle: Double(videoRotationAngle),
            videoFieldOfView: Double(format.videoFieldOfView),
            videoZoomFactor: Double(device.videoZoomFactor),
            geometricDistortionCorrectionEnabled: gdcEnabled,
            intrinsicMatrixDeliverySupported: intrinsicMatrixDeliverySupported,
            intrinsicMatrix: intrinsicMatrix
        )
    }
    #endif
}
