//
//  LiveSwingDetecting.swift
//  SwingCoach
//
//  Shared live-detector interface so the app and offline evaluator can switch
//  between the legacy `LiveModelSwingDetector` and the new `SwingDetectorV2`
//  without the call sites knowing which concrete detector is in use.
//

import AVFoundation
import CoreGraphics

nonisolated protocol LiveSwingDetecting: AnyObject {
    func reset(enabled: Bool)

    @discardableResult
    func process(
        sampleBuffer: CMSampleBuffer,
        recordingTime: Double,
        orientation: CGImagePropertyOrientation,
        orientedImageSize: CGSize
    ) -> LiveSwingDetectionSnapshot

    func finish(recordingTime: Double?) -> [DetectedSwing]

    func currentSnapshot() -> LiveSwingDetectionSnapshot
}
