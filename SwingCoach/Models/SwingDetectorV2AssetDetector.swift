//
//  SwingDetectorV2AssetDetector.swift
//  SwingCoach
//
//  Offline asset reader that drives the same SwingDetectorV2 loop used by live
//  capture. Trim/import should not use a separate detector implementation.
//

import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo

actor SwingDetectorV2AssetDetector {
    enum DetectionError: Error {
        case invalidDuration
        case noVideoTrack
        case readerSetupFailed
        case modelUnavailable
    }

    private let configuration: SwingDetectorV2Configuration

    init(configuration: SwingDetectorV2Configuration) {
        self.configuration = configuration
    }

    func detectSwings(in asset: AVAsset) async throws -> [DetectedSwing] {
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw DetectionError.invalidDuration
        }

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw DetectionError.noVideoTrack
        }

        let transform = try await videoTrack.load(.preferredTransform)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let orientation = Self.orientation(for: transform)
        let orientedSize = Self.orientedSize(naturalSize: naturalSize, orientation: orientation)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
        )
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw DetectionError.readerSetupFailed
        }
        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? DetectionError.readerSetupFailed
        }

        let detector = SwingDetectorV2(configuration: configuration)
        detector.reset(enabled: true)
        guard detector.currentSnapshot().status != .unavailable else {
            throw DetectionError.modelUnavailable
        }

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()

            let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            guard time.isFinite else { continue }

            _ = detector.process(
                sampleBuffer: sampleBuffer,
                recordingTime: time,
                orientation: orientation,
                orientedImageSize: orientedSize
            )
        }

        if reader.status == .failed {
            throw reader.error ?? DetectionError.readerSetupFailed
        }

        return detector.finish(recordingTime: durationSeconds)
    }

    private static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let epsilon = 0.001

        func equals(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
            abs(lhs - rhs) < epsilon
        }

        if equals(transform.a, 0), equals(transform.b, 1), equals(transform.c, -1), equals(transform.d, 0) {
            return .right
        }

        if equals(transform.a, 0), equals(transform.b, -1), equals(transform.c, 1), equals(transform.d, 0) {
            return .left
        }

        if equals(transform.a, -1), equals(transform.d, -1) {
            return .down
        }

        return .up
    }

    private static func orientedSize(naturalSize: CGSize, orientation: CGImagePropertyOrientation) -> CGSize {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: naturalSize.height, height: naturalSize.width)
        default:
            return naturalSize
        }
    }
}
