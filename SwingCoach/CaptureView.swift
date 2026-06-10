//
//  CaptureView.swift
//  SwingCoach
//
//  Created by Ruari Craig on 01/11/2025.
//

import SwiftUI
import UIKit
import AVKit
import Combine
import AVFoundation
import Photos
import ImageIO

enum SloMoMode {
    case normal      // 30 fps @ 1080p
    case smooth      // 60 fps @ 1080p
    case standard    // 120 fps @ 1080p
    case ultra       // 240 fps @ 1080p

    var targetFPS: Double {
        switch self {
        case .normal: return 30.0
        case .smooth: return 60.0
        case .standard: return 120.0
        case .ultra: return 240.0
        }
    }

    var targetResolution: (width: Int32, height: Int32) {
        switch self {
        case .normal, .smooth, .standard, .ultra:
            return (1920, 1080)
        }
    }

    var displayName: String {
        switch self {
        case .normal: return "30fps HD"
        case .smooth: return "60fps HD"
        case .standard: return "120fps HD"
        case .ultra: return "240fps HD"
        }
    }

    var shortName: String {
        switch self {
        case .normal: return "30"
        case .smooth: return "60"
        case .standard: return "120"
        case .ultra: return "240"
        }
    }

    /// Playback rate to achieve slow-motion (recorded FPS / playback FPS)
    var slowMotionRate: Float {
        Float(30.0 / targetFPS)
    }

    var sourceTimeScale: Double {
        targetFPS / 30.0
    }

    var exportSlowMotionFactor: Double? {
        sourceTimeScale > 1.0 ? sourceTimeScale : nil
    }
}

enum CaptureWorkflowMode: String, CaseIterable, Identifiable {
    case manual
    case auto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .auto: return "Auto"
        }
    }
}

struct AutoCaptureStatus: Equatable {
    var isActive: Bool
    var savedSwingCount: Int
    var pendingSwingCount: Int
    var message: String
    var lastErrorMessage: String?

    static let idle = AutoCaptureStatus(
        isActive: false,
        savedSwingCount: 0,
        pendingSwingCount: 0,
        message: "Auto capture off",
        lastErrorMessage: nil
    )
}

final class CameraSession: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera.session.queue")
    private let qualityQueue = DispatchQueue(label: "camera.quality.queue")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()

    private var liveSwingDetector = SwingDetectorV2()
    private var recordingStartSampleTime: CMTime?
    private var recordingStartWallTime: Date?
    private var lastLiveSwingSampleTime = -Double.greatestFiniteMagnitude
    private var autoCaptureIsActive = false
    private var autoSavedSwingCount = 0
    private var autoPendingSwingCount = 0
    private var autoExportedDetectionIDs: Set<UUID> = []
    private let autoRollingBuffer = AutoRollingVideoBuffer()
    private let autoTrimmer = VideoTrimmer()

    @Published var lastRecordingURL: URL?
    @Published var lastRecordingSwingDetections: [DetectedSwing] = []
    @Published var lastRecordingSwingDetectionSummary: LiveSwingDetectionSnapshot?
    @Published var recordingError: Error?
    @Published var captureMode: SloMoMode = .ultra  // Default to 240 fps
    @Published var liveSwingDetection = LiveSwingDetectionSnapshot.idle
    @Published var autoCaptureStatus = AutoCaptureStatus.idle
    var isLiveSwingDetectionEnabled = true
    var liveModelDetectorSampleFPS = 8.0

    /// The mode that was active when recording started (for correct playback rate)
    private(set) var recordedMode: SloMoMode = .ultra

    override init() {
        super.init()
        configure()
    }

    private func configure() {
        session.beginConfiguration()
        // Note: We do NOT set sessionPreset — it would override our manual format selection

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }

        // Add input and output FIRST
        session.addInput(input)
        configureAudioInput()
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        configureQualityOutput()

        // Configure high FPS AFTER input/output are added to the session
        // Otherwise the session may override format settings when input is added
        configureHighFPS(device: device, mode: captureMode)

        session.commitConfiguration()
    }

    private func configureAudioInput() {
        guard let audioDevice = AVCaptureDevice.default(for: .audio),
              let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
              session.canAddInput(audioInput)
        else {
            return
        }

        session.addInput(audioInput)
    }

    private func configureQualityOutput() {
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoDataOutput.setSampleBufferDelegate(self, queue: qualityQueue)

        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }
    }

    private func configureHighFPS(device: AVCaptureDevice, mode: SloMoMode) {
        let targetFPS = mode.targetFPS
        let targetRes = mode.targetResolution

        // Find format matching our exact resolution and FPS requirements
        let matchingFormat = device.formats.first { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let resolutionMatches = dims.width == targetRes.width && dims.height == targetRes.height
            let fpsSupported = format.videoSupportedFrameRateRanges.contains { range in
                range.maxFrameRate >= targetFPS
            }
            return resolutionMatches && fpsSupported
        }

        guard let bestFormat = matchingFormat else {
            print("❌ No format found for \(mode.displayName) (\(targetRes.width)×\(targetRes.height) @ \(targetFPS) fps)")
            return
        }

        let dims = CMVideoFormatDescriptionGetDimensions(bestFormat.formatDescription)
        print("✅ Selected format: \(dims.width)×\(dims.height) @ \(targetFPS) fps (\(mode.displayName))")

        // Apply the format and lock frame rate
        do {
            try device.lockForConfiguration()
            device.activeFormat = bestFormat
            // Set min and max to same value = lock to exact FPS
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            device.unlockForConfiguration()
        } catch {
            print("❌ Failed to configure \(mode.displayName): \(error)")
        }
    }

    /// Switch capture mode without stopping the session (prevents errors)
    func switchMode(to mode: SloMoMode) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }

        session.beginConfiguration()
        captureMode = mode
        configureHighFPS(device: device, mode: mode)
        session.commitConfiguration()
    }

    /// Focus and expose at the given point (normalized 0-1 coordinates)
    func focus(at point: CGPoint) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }

        do {
            try device.lockForConfiguration()

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }

            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }

            device.unlockForConfiguration()
        } catch {
            print("❌ Failed to focus: \(error)")
        }
    }

    func start() {
        queue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func startRecording() {
        guard !movieOutput.isRecording else { return }

        // Capture the mode at recording start for correct playback rate
        recordedMode = captureMode
        resetLiveSwingDetection()

        let url = Self.tempURL()
        movieOutput.startRecording(to: url, recordingDelegate: self)
    }

    func stopRecording() {
        queue.async {
            guard self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    func startAutoCapture() {
        queue.async {
            guard !self.autoCaptureIsActive else { return }
            guard !self.movieOutput.isRecording else {
                DispatchQueue.main.async {
                    self.autoCaptureStatus = AutoCaptureStatus(
                        isActive: false,
                        savedSwingCount: self.autoSavedSwingCount,
                        pendingSwingCount: self.autoPendingSwingCount,
                        message: "Stop manual recording before Auto",
                        lastErrorMessage: nil
                    )
                }
                return
            }

            self.autoCaptureIsActive = true
            self.autoSavedSwingCount = 0
            self.autoPendingSwingCount = 0
            self.autoExportedDetectionIDs = []
            self.recordedMode = self.captureMode
            self.resetLiveSwingDetection()
            self.autoRollingBuffer.reset(preservingPendingExports: true)
            DispatchQueue.main.async {
                self.autoCaptureStatus = AutoCaptureStatus(
                    isActive: true,
                    savedSwingCount: 0,
                    pendingSwingCount: 0,
                    message: "Auto watching",
                    lastErrorMessage: nil
                )
            }
        }
    }

    func stopAutoCapture() {
        queue.async {
            self.autoCaptureIsActive = false
            self.autoRollingBuffer.reset(preservingPendingExports: true)
            DispatchQueue.main.async {
                self.autoCaptureStatus = AutoCaptureStatus(
                    isActive: false,
                    savedSwingCount: self.autoSavedSwingCount,
                    pendingSwingCount: self.autoPendingSwingCount,
                    message: "Auto capture off",
                    lastErrorMessage: nil
                )
            }
        }
    }

    private static func tempURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
        let filename = UUID().uuidString + ".mov"
        return directory.appendingPathComponent(filename)
    }

    private func resetLiveSwingDetection() {
        let detectorEnabled = isLiveSwingDetectionEnabled || autoCaptureIsActive
        qualityQueue.async {
            self.recordingStartSampleTime = nil
            self.recordingStartWallTime = nil
            self.lastLiveSwingSampleTime = -Double.greatestFiniteMagnitude
            self.liveSwingDetector = SwingDetectorV2(configuration: self.liveV2Configuration())
            self.liveSwingDetector.reset(enabled: detectorEnabled)
        }

        DispatchQueue.main.async {
            let configuration = self.liveV2Configuration()
            self.lastRecordingSwingDetections = []
            self.lastRecordingSwingDetectionSummary = nil
            self.liveSwingDetection = detectorEnabled ? LiveSwingDetectionSnapshot(
                status: .idle,
                primaryMessage: "V2 detect starting",
                detailMessage: "Scanning sampled frames while recording.",
                targetSampleFPS: configuration.lowSampleFPS,
                detectorConfigurationName: configuration.name
            ) : LiveSwingDetectionSnapshot(
                status: .disabled,
                primaryMessage: "Auto detect off",
                detailMessage: "Recording normally; trim manually after stop.",
                detectorConfigurationName: configuration.name
            )
        }
    }

    private func liveV2Configuration() -> SwingDetectorV2Configuration {
        // Live sample-buffer timestamps advance at wall-clock rate regardless of
        // capture FPS; the slow-motion timeline only exists after export retiming.
        // recordedMode.sourceTimeScale applies to playback rate and export only.
        SwingDetectorV2Configuration.live(
            sourceTimeScale: 1.0,
            lowSampleFPS: liveModelDetectorSampleFPS,
            burstSampleFPS: max(16.0, liveModelDetectorSampleFPS * 2.0)
        )
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        qualityQueue.async {
            let detectionResult: (items: [DetectedSwing], summary: LiveSwingDetectionSnapshot?)
            if self.isLiveSwingDetectionEnabled {
                let finished = self.finishLiveSwingDetection()
                detectionResult = (finished.items, finished.summary)
            } else {
                detectionResult = ([], nil)
            }

            DispatchQueue.main.async {
                guard error == nil else {
                    self.recordingError = error
                    self.lastRecordingURL = nil
                    self.lastRecordingSwingDetections = []
                    self.lastRecordingSwingDetectionSummary = nil
                    return
                }

                self.recordingError = nil
                self.lastRecordingSwingDetections = detectionResult.items
                self.lastRecordingSwingDetectionSummary = detectionResult.summary
                self.lastRecordingURL = outputFileURL
            }
        }
    }

    private func finishLiveSwingDetection() -> (items: [DetectedSwing], summary: LiveSwingDetectionSnapshot) {
        let recordingTime = lastLiveSwingSampleTime.isFinite ? lastLiveSwingSampleTime : nil
        let finalTime = recordingTime ?? 0

        func finalizedSummary(
            base snapshot: LiveSwingDetectionSnapshot,
            detections: [DetectedSwing],
            recordingTime: Double
        ) -> LiveSwingDetectionSnapshot {
            var snapshot = liveTelemetrySnapshot(base: snapshot, recordingTime: recordingTime)
            snapshot.detectedSwingCount = detections.count
            if detections.isEmpty {
                snapshot.primaryMessage = "No swings detected"
            } else {
                snapshot.status = .swingDetected
                snapshot.primaryMessage = "\(detections.count) swing\(detections.count == 1 ? "" : "s") detected"
            }
            return snapshot
        }

        let detections = liveSwingDetector.finish(recordingTime: recordingTime)
        return (
            detections,
            finalizedSummary(
                base: liveSwingDetector.currentSnapshot(),
                detections: detections,
                recordingTime: finalTime
            )
        )
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if movieOutput.isRecording, isLiveSwingDetectionEnabled || autoCaptureIsActive {
            processLiveModelSwingFrame(sampleBuffer)
        }
    }

    private func exportAutoDetectedSwing(
        detection: DetectedSwing,
        preparedClip: AutoRollingVideoBuffer.PreparedClip,
        recordedMode: SloMoMode
    ) async {
        let asset = AVURLAsset(url: preparedClip.sourceURL)
        var savedCount = 0
        var lastErrorMessage: String?

        do {
            let clip = SwingClip(
                startTime: preparedClip.startTime,
                endTime: preparedClip.endTime,
                vantage: .dtl,
                detectionImpactTime: detection.impactTime.map { $0 - preparedClip.sourceStartTime },
                detectionDeclaredAt: detection.declaredAt.map { $0 - preparedClip.sourceStartTime }
            )

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("auto_swing_\(clip.id.uuidString.prefix(8)).mp4")
            try await autoTrimmer.exportClip(
                from: asset,
                startTime: clip.startCMTime,
                endTime: clip.endCMTime,
                to: outputURL,
                slowMotionFactor: recordedMode.exportSlowMotionFactor
            )

            if let assetID = await PHPhotoLibrary.saveVideoAndGetID(url: outputURL) {
                let thumbnail = try? await autoTrimmer.generateThumbnail(for: asset, at: clip.startCMTime)
                await MainActor.run {
                        SwingLibrary.shared.addSwing(
                            photoAssetID: assetID,
                            vantage: clip.vantage,
                            duration: clip.duration * recordedMode.sourceTimeScale,
                            initialThumbnail: thumbnail,
                            localSourceURL: outputURL
                        )
                }
                savedCount = 1
            }

            try? FileManager.default.removeItem(at: outputURL)
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        await MainActor.run {
            self.autoSavedSwingCount += savedCount
            self.autoPendingSwingCount = max(0, self.autoPendingSwingCount - 1)
            self.autoCaptureStatus = AutoCaptureStatus(
                isActive: self.autoCaptureIsActive,
                savedSwingCount: self.autoSavedSwingCount,
                pendingSwingCount: self.autoPendingSwingCount,
                message: self.autoCaptureIsActive ? "Auto watching" : "Auto capture off",
                lastErrorMessage: lastErrorMessage
            )
        }

        qualityQueue.async {
            self.autoRollingBuffer.release(preparedClip)
        }
    }

    private func processLiveModelSwingFrame(_ sampleBuffer: CMSampleBuffer) {
        let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if recordingStartSampleTime == nil {
            recordingStartSampleTime = sampleTime
            recordingStartWallTime = Date()
        }

        guard let recordingStartSampleTime,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            return
        }

        let relativeTime = CMTimeGetSeconds(CMTimeSubtract(sampleTime, recordingStartSampleTime))
        guard relativeTime.isFinite else { return }
        lastLiveSwingSampleTime = relativeTime
        if autoCaptureIsActive {
            autoRollingBuffer.append(sampleBuffer: sampleBuffer, relativeTime: relativeTime)
        }

        let orientation: CGImagePropertyOrientation = .right
        let orientedImageSize = CGSize(
            width: CVPixelBufferGetHeight(pixelBuffer),
            height: CVPixelBufferGetWidth(pixelBuffer)
        )
        var snapshot = liveSwingDetector.process(
            sampleBuffer: sampleBuffer,
            recordingTime: relativeTime,
            orientation: orientation,
            orientedImageSize: orientedImageSize
        )
        snapshot = liveTelemetrySnapshot(base: snapshot, recordingTime: relativeTime)

        DispatchQueue.main.async {
            self.liveSwingDetection = snapshot
        }

        if autoCaptureIsActive {
            enqueueNewAutoDetections()
        }
    }

    private func enqueueNewAutoDetections() {
        let detections = liveSwingDetector.currentDetections()
        let newDetections = detections.filter { !autoExportedDetectionIDs.contains($0.id) }
        guard !newDetections.isEmpty else { return }

        for detection in newDetections {
            autoExportedDetectionIDs.insert(detection.id)
            autoRollingBuffer.prepareClip(for: detection) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let preparedClip):
                    DispatchQueue.main.async {
                        self.autoPendingSwingCount += 1
                        self.autoCaptureStatus = AutoCaptureStatus(
                            isActive: self.autoCaptureIsActive,
                            savedSwingCount: self.autoSavedSwingCount,
                            pendingSwingCount: self.autoPendingSwingCount,
                            message: "Saving swing",
                            lastErrorMessage: nil
                        )
                    }
                    let recordedMode = self.recordedMode
                    Task {
                        await self.exportAutoDetectedSwing(
                            detection: detection,
                            preparedClip: preparedClip,
                            recordedMode: recordedMode
                        )
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.autoCaptureStatus = AutoCaptureStatus(
                            isActive: self.autoCaptureIsActive,
                            savedSwingCount: self.autoSavedSwingCount,
                            pendingSwingCount: self.autoPendingSwingCount,
                            message: self.autoCaptureIsActive ? "Auto watching" : "Auto capture off",
                            lastErrorMessage: error.localizedDescription
                        )
                    }
                }
            }
        }
    }

    private func liveTelemetrySnapshot(
        base snapshot: LiveSwingDetectionSnapshot,
        recordingTime: Double
    ) -> LiveSwingDetectionSnapshot {
        var snapshot = snapshot
        if recordingTime > 0, snapshot.processedFrameCount > 0 {
            snapshot.effectiveSampleFPS = Double(snapshot.processedFrameCount) / recordingTime
        }
        if let recordingStartWallTime {
            let wallElapsed = Date().timeIntervalSince(recordingStartWallTime)
            snapshot.analysisLagMS = max(0, wallElapsed - recordingTime) * 1_000
        }
        return snapshot
    }

}

private final class AutoRollingVideoBuffer {
    struct PreparedClip {
        let sourceURL: URL
        let sourceStartTime: Double
        let startTime: CMTime
        let endTime: CMTime
        fileprivate let chunkID: UUID
    }

    enum BufferError: LocalizedError {
        case missingFormatDescription
        case writerCreationFailed(String)
        case clipUnavailable
        case invalidClipRange

        var errorDescription: String? {
            switch self {
            case .missingFormatDescription:
                return "Auto capture could not read the camera frame format."
            case .writerCreationFailed(let reason):
                return "Auto capture buffer failed: \(reason)"
            case .clipUnavailable:
                return "Auto capture buffer did not contain the full swing window."
            case .invalidClipRange:
                return "Auto capture received an invalid swing window."
            }
        }
    }

    private final class Chunk {
        let id = UUID()
        let url: URL
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let startRelativeTime: Double
        let startSampleTime: CMTime
        var endRelativeTime: Double
        var isFinishing = false
        var isFinished = false
        var pendingExports = 0
        var completionHandlers: [() -> Void] = []

        init(
            url: URL,
            writer: AVAssetWriter,
            input: AVAssetWriterInput,
            startRelativeTime: Double,
            startSampleTime: CMTime
        ) {
            self.url = url
            self.writer = writer
            self.input = input
            self.startRelativeTime = startRelativeTime
            self.startSampleTime = startSampleTime
            self.endRelativeTime = startRelativeTime
        }
    }

    private var chunks: [Chunk] = []
    private let chunkDuration = 12.0
    private let chunkStartInterval = 6.0
    private let retentionDuration = 30.0
    private var nextChunkStartTime: Double?

    func reset(preservingPendingExports: Bool = false) {
        var preservedChunks: [Chunk] = []
        for chunk in chunks {
            if preservingPendingExports, chunk.pendingExports > 0 {
                finish(chunk)
                preservedChunks.append(chunk)
                continue
            }

            if !chunk.isFinishing && !chunk.isFinished {
                chunk.input.markAsFinished()
                chunk.writer.cancelWriting()
            }
            try? FileManager.default.removeItem(at: chunk.url)
        }
        chunks = preservedChunks
        nextChunkStartTime = nil
    }

    func append(sampleBuffer: CMSampleBuffer, relativeTime: Double) {
        guard relativeTime.isFinite else { return }
        let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard sampleTime.isValid else { return }

        if chunks.isEmpty {
            startChunk(sampleBuffer: sampleBuffer, relativeTime: relativeTime, sampleTime: sampleTime)
        }

        while let nextChunkStartTime, relativeTime >= nextChunkStartTime {
            startChunk(sampleBuffer: sampleBuffer, relativeTime: relativeTime, sampleTime: sampleTime)
        }

        for chunk in chunks where !chunk.isFinishing && !chunk.isFinished {
            guard relativeTime >= chunk.startRelativeTime else { continue }
            append(sampleBuffer, to: chunk, relativeTime: relativeTime)
            if relativeTime - chunk.startRelativeTime >= chunkDuration {
                finish(chunk)
            }
        }

        cleanupOldChunks(currentTime: relativeTime)
    }

    func prepareClip(
        for detection: DetectedSwing,
        completion: @escaping (Result<PreparedClip, Error>) -> Void
    ) {
        let start = CMTimeGetSeconds(detection.startTime)
        let end = CMTimeGetSeconds(detection.endTime)
        guard start.isFinite, end.isFinite, end > start else {
            completion(.failure(BufferError.invalidClipRange))
            return
        }

        guard let chunk = chunks
            .filter({ $0.startRelativeTime <= start && $0.endRelativeTime >= end })
            .sorted(by: { lhs, rhs in
                let lhsMargin = min(start - lhs.startRelativeTime, lhs.endRelativeTime - end)
                let rhsMargin = min(start - rhs.startRelativeTime, rhs.endRelativeTime - end)
                return lhsMargin > rhsMargin
            })
            .first
        else {
            completion(.failure(BufferError.clipUnavailable))
            return
        }

        chunk.pendingExports += 1
        let preparedClip = PreparedClip(
            sourceURL: chunk.url,
            sourceStartTime: chunk.startRelativeTime,
            startTime: CMTime(seconds: start - chunk.startRelativeTime, preferredTimescale: 600),
            endTime: CMTime(seconds: end - chunk.startRelativeTime, preferredTimescale: 600),
            chunkID: chunk.id
        )

        let complete = {
            completion(.success(preparedClip))
        }

        if chunk.isFinished {
            complete()
        } else {
            chunk.completionHandlers.append(complete)
            finish(chunk)
        }
    }

    func release(_ preparedClip: PreparedClip) {
        guard let chunk = chunks.first(where: { $0.id == preparedClip.chunkID }) else { return }
        chunk.pendingExports = max(0, chunk.pendingExports - 1)
        cleanupOldChunks(currentTime: chunks.map(\.endRelativeTime).max() ?? chunk.endRelativeTime)
    }

    private func startChunk(sampleBuffer: CMSampleBuffer, relativeTime: Double, sampleTime: CMTime) {
        do {
            guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                throw BufferError.missingFormatDescription
            }

            let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
            let outputSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(dimensions.width),
                AVVideoHeightKey: Int(dimensions.height)
            ]
            let url = Self.tempURL()
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: outputSettings,
                sourceFormatHint: formatDescription
            )
            input.expectsMediaDataInRealTime = true

            guard writer.canAdd(input) else {
                throw BufferError.writerCreationFailed("Video input could not be added.")
            }

            writer.add(input)
            guard writer.startWriting() else {
                throw BufferError.writerCreationFailed(writer.error?.localizedDescription ?? "Writer did not start.")
            }
            writer.startSession(atSourceTime: .zero)

            let chunk = Chunk(
                url: url,
                writer: writer,
                input: input,
                startRelativeTime: relativeTime,
                startSampleTime: sampleTime
            )
            chunks.append(chunk)
            nextChunkStartTime = relativeTime + chunkStartInterval
        } catch {
            print("❌ Auto rolling buffer failed to start: \(error.localizedDescription)")
        }
    }

    private func append(_ sampleBuffer: CMSampleBuffer, to chunk: Chunk, relativeTime: Double) {
        guard chunk.input.isReadyForMoreMediaData,
              let retimedBuffer = Self.copy(sampleBuffer, relativeTo: chunk.startSampleTime)
        else {
            return
        }

        if chunk.input.append(retimedBuffer) {
            chunk.endRelativeTime = relativeTime
        } else if let error = chunk.writer.error {
            print("❌ Auto rolling buffer append failed: \(error.localizedDescription)")
            finish(chunk)
        }
    }

    private func finish(_ chunk: Chunk) {
        guard !chunk.isFinishing, !chunk.isFinished else { return }
        chunk.isFinishing = true
        chunk.input.markAsFinished()
        chunk.writer.finishWriting { [weak chunk] in
            guard let chunk else { return }
            chunk.isFinished = true
            chunk.isFinishing = false
            let handlers = chunk.completionHandlers
            chunk.completionHandlers = []
            for handler in handlers {
                handler()
            }
        }
    }

    private func cleanupOldChunks(currentTime: Double) {
        chunks.removeAll { chunk in
            guard chunk.isFinished,
                  chunk.pendingExports == 0,
                  currentTime - chunk.endRelativeTime > retentionDuration
            else {
                return false
            }
            try? FileManager.default.removeItem(at: chunk.url)
            return true
        }
    }

    private static func copy(_ sampleBuffer: CMSampleBuffer, relativeTo startTime: CMTime) -> CMSampleBuffer? {
        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard sampleCount > 0 else { return nil }

        var timingInfo = Array(
            repeating: CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: .invalid,
                decodeTimeStamp: .invalid
            ),
            count: sampleCount
        )
        var timingCount = 0
        let timingStatus = CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: sampleCount,
            arrayToFill: &timingInfo,
            entriesNeededOut: &timingCount
        )
        guard timingStatus == noErr else { return nil }

        for index in timingInfo.indices {
            if timingInfo[index].presentationTimeStamp.isValid {
                timingInfo[index].presentationTimeStamp = CMTimeSubtract(
                    timingInfo[index].presentationTimeStamp,
                    startTime
                )
            }
            if timingInfo[index].decodeTimeStamp.isValid {
                timingInfo[index].decodeTimeStamp = CMTimeSubtract(
                    timingInfo[index].decodeTimeStamp,
                    startTime
                )
            }
        }

        var copiedBuffer: CMSampleBuffer?
        let copyStatus = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: timingInfo.count,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &copiedBuffer
        )
        guard copyStatus == noErr else { return nil }
        return copiedBuffer
    }

    private static func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("auto_buffer_\(UUID().uuidString).mov")
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    /// Convert a tap point to camera coordinates (0-1 normalized)
    func cameraPoint(from viewPoint: CGPoint) -> CGPoint {
        previewLayer.captureDevicePointConverted(fromLayerPoint: viewPoint)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: ((CGPoint, CGPoint) -> Void)?  // (viewPoint, cameraPoint)

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)

        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.previewView = uiView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    class Coordinator: NSObject {
        var onTap: ((CGPoint, CGPoint) -> Void)?
        weak var previewView: CameraPreviewView?

        init(onTap: ((CGPoint, CGPoint) -> Void)?) {
            self.onTap = onTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = previewView else { return }
            let viewPoint = gesture.location(in: view)
            let cameraPoint = view.cameraPoint(from: viewPoint)
            onTap?(viewPoint, cameraPoint)
        }
    }
}

struct CaptureView: View {
    var onAnalyzeSwings: (([SavedSwing]) -> Void)? = nil

    @StateObject private var camera = CameraSession()
    @AppStorage(ExperimentalSettingKey.liveAutoSwingDetectionEnabled) private var liveAutoSwingDetectionEnabled = true
    @AppStorage(ExperimentalSettingKey.liveModelDetectorSampleFPS) private var liveModelDetectorSampleFPS = 8.0
    @State private var workflowMode: CaptureWorkflowMode = .manual
    @State private var isRecording = false
    @State private var previewPlayerItem: AVPlayerItem?
    @State private var currentRecordingURL: URL?
    @State private var currentRecordingMode: SloMoMode?
    @State private var previousIdleTimerDisabled: Bool?

    // Focus indicator state
    @State private var focusPoint: CGPoint? = nil
    @State private var showFocusIndicator = false

    // Recording timer
    @State private var recordingStartTime: Date? = nil
    @State private var recordingDuration: TimeInterval = 0
    @State private var timerCancellable: AnyCancellable? = nil

    // Recording finalization state
    @State private var isProcessing = false

    // Trim view presentation
    @State private var showTrimView = false

    var body: some View {
        VStack(spacing: 0) {
            // Camera preview area (majority of screen, not full screen)
            ZStack {
                // Camera preview with tap-to-focus
                CameraPreview(session: camera.session) { viewPoint, cameraPoint in
                    handleFocusTap(viewPoint: viewPoint, cameraPoint: cameraPoint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

                // Focus indicator (yellow square)
                if showFocusIndicator, let point = focusPoint {
                    FocusIndicatorView()
                        .position(point)
                }

                // Video playback overlay
                if let previewPlayerItem {
                    PlaybackChromeView(
                        playerItem: previewPlayerItem,
                        initialPlaybackRate: currentRecordingMode?.slowMotionRate ?? 1.0,
                        playbackEnabled: !showTrimView,
                        showsSpeedControls: false
                    ) {
                        HStack {
                            Button {
                                saveToPhotoLibrary()
                            } label: {
                                Image(systemName: "square.and.arrow.down.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(Color.black.opacity(0.54)))
                                    .shadow(radius: 4)
                            }
                            .padding(.leading, -6)

                            Spacer()

                            Button {
                                clearCurrentRecording()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(Color.black.opacity(0.54)))
                                    .shadow(radius: 4)
                            }
                            .padding(.trailing, -6)
                        }
                        .padding(.top, -2)
                        .padding(.horizontal, 6)
                    } overlayAccessory: {
                        Button {
                            showTrimView = true
                        } label: {
                            Image(systemName: "scissors")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 50, height: 50)
                                .background(Circle().fill(Color.yellow))
                            .shadow(radius: 4)
                        }
                    }
                }

                // Processing overlay
                if isProcessing {
                    Color.black.opacity(0.7)
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Finalizing recording...")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                }

                // Camera controls overlay (when not playing back)
                if previewPlayerItem == nil && !isProcessing {
                    VStack {
                        // Top controls: FPS toggle and recording timer
                        HStack {
                            // FPS mode picker (left)
                            Menu {
                                Button("30fps HD") {
                                    camera.switchMode(to: .normal)
                                }
                                Button("60fps HD") {
                                    camera.switchMode(to: .smooth)
                                }
                                Button("120fps HD") {
                                    camera.switchMode(to: .standard)
                                }
                                Button("240fps HD") {
                                    camera.switchMode(to: .ultra)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(camera.captureMode.shortName)
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.black.opacity(0.5))
                                )
                            }
                            .disabled(isRecording || workflowMode == .auto)
                            .opacity((isRecording || workflowMode == .auto) ? 0.5 : 1.0)

                            Spacer()

                            // Recording indicator (center)
                            if isRecording {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                    Text(formatDuration(recordingDuration))
                                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.black.opacity(0.5))
                                    )
                            }

                            Spacer()

                            Picker("Capture", selection: $workflowMode) {
                                ForEach(CaptureWorkflowMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 144)
                            .disabled(isRecording)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        if isRecording || workflowMode == .auto {
                            LiveSwingDetectionBadge(snapshot: camera.liveSwingDetection)
                                .padding(.top, 10)
                                .padding(.horizontal, 16)
                        }

                        if workflowMode == .auto {
                            AutoCaptureStatusBadge(status: camera.autoCaptureStatus)
                                .padding(.top, 8)
                                .padding(.horizontal, 16)
                        }

                        Spacer()

                        // Bottom: Record button
                        if workflowMode == .manual {
                            RecordButton(isRecording: isRecording) {
                                toggleRecording()
                            }
                            .padding(.bottom, 8)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
        }
        .onAppear {
            ExperimentalDetectorDefaults.migrateIfNeeded()
            camera.isLiveSwingDetectionEnabled = liveAutoSwingDetectionEnabled
            camera.liveModelDetectorSampleFPS = liveModelDetectorSampleFPS
            camera.start()
        }
        .onChange(of: liveAutoSwingDetectionEnabled) { _, isEnabled in
            camera.isLiveSwingDetectionEnabled = isEnabled
        }
        .onChange(of: liveModelDetectorSampleFPS) { _, sampleFPS in
            camera.liveModelDetectorSampleFPS = sampleFPS
        }
        .onChange(of: workflowMode) { _, mode in
            switch mode {
            case .manual:
                camera.stopAutoCapture()
                restoreIdleTimer()
            case .auto:
                clearCurrentRecording()
                isProcessing = false
                preventIdleTimer()
                camera.startAutoCapture()
            }
        }
        .onDisappear {
            camera.stopAutoCapture()
            camera.stop()
            timerCancellable?.cancel()
            restoreIdleTimer()
        }
        .onReceive(camera.$lastRecordingURL) { url in
            guard let url else { return }

            isRecording = false
            stopRecordingTimer()
            restoreIdleTimer()

            let recordedMode = camera.recordedMode
            previewPlayerItem = AVPlayerItem(url: url)
            currentRecordingURL = url
            currentRecordingMode = recordedMode
            isProcessing = false
            showTrimView = true
        }
        .onReceive(camera.$recordingError) { error in
            guard error != nil else { return }
            isRecording = false
            stopRecordingTimer()
            restoreIdleTimer()
            isProcessing = false
        }
        .fullScreenCover(isPresented: $showTrimView) {
            if let url = currentRecordingURL {
                TrimView(
                    source: .capturedFile(url: url),
                    sourceCaptureMode: currentRecordingMode,
                    initialDetectedSwings: liveAutoSwingDetectionEnabled ? camera.lastRecordingSwingDetections : [],
                    detectorSummary: liveAutoSwingDetectionEnabled ? camera.lastRecordingSwingDetectionSummary : nil,
                    runsPostRecordDetection: false,
                    onComplete: { clips, exportedURLs in
                        // Handle exported clips
                        print("✅ Exported \(clips.count) clips:")
                        for (clip, url) in zip(clips, exportedURLs) {
                            print("   - \(clip.vantage.shortName) \(clip.durationFormatted): \(url.lastPathComponent)")
                        }
                        showTrimView = false
                        clearCurrentRecording()
                    },
                    onCancel: {
                        showTrimView = false
                    },
                    onExportAndAnalyze: onAnalyzeSwings != nil ? { _ in } : nil
                )
            }
        }
    }

    // MARK: - Actions

    private func handleFocusTap(viewPoint: CGPoint, cameraPoint: CGPoint) {
        guard !isRecording else { return }

        // Trigger focus
        camera.focus(at: cameraPoint)

        // Show focus indicator
        focusPoint = viewPoint
        showFocusIndicator = true

        // Hide after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.2)) {
                showFocusIndicator = false
            }
        }
    }

    private func toggleRecording() {
        if isRecording {
            isProcessing = true
            camera.stopRecording()
            stopRecordingTimer()
            restoreIdleTimer()
        } else {
            clearCurrentRecording()
            isProcessing = false
            preventIdleTimer()
            camera.startRecording()
            startRecordingTimer()
        }
        currentRecordingURL = nil
        isRecording.toggle()
    }

    private func preventIdleTimer() {
        if previousIdleTimerDisabled == nil {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func restoreIdleTimer() {
        guard let previousIdleTimerDisabled else { return }
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        self.previousIdleTimerDisabled = nil
    }

    private func clearCurrentRecording() {
        previewPlayerItem = nil
        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentRecordingURL = nil
        currentRecordingMode = nil
        camera.lastRecordingURL = nil
        camera.lastRecordingSwingDetectionSummary = nil
    }

    private func saveToPhotoLibrary() {
        guard let url = currentRecordingURL else { return }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized else {
                print("❌ Photo library access denied")
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                if success {
                    print("✅ Video saved to Photos")
                } else {
                    print("❌ Failed to save video: \(error?.localizedDescription ?? "unknown")")
                }
            }
        }
    }

    // MARK: - Timer

    private func startRecordingTimer() {
        recordingStartTime = Date()
        recordingDuration = 0
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                if let start = recordingStartTime {
                    recordingDuration = Date().timeIntervalSince(start)
                }
            }
    }

    private func stopRecordingTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        recordingStartTime = nil
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

}

// MARK: - Supporting Views

struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 80, height: 80)

                // Inner shape (circle when idle, rounded square when recording)
                if isRecording {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red)
                        .frame(width: 32, height: 32)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 64, height: 64)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isRecording)
    }
}

struct FocusIndicatorView: View {
    @State private var scale: CGFloat = 1.5
    @State private var opacity: Double = 1.0

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(Color.yellow, lineWidth: 2)
            .frame(width: 70, height: 70)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) {
                    scale = 1.0
                }
                withAnimation(.easeOut(duration: 0.8).delay(0.7)) {
                    opacity = 0.5
                }
            }
    }
}

struct AutoCaptureStatusBadge: View {
    let status: AutoCaptureStatus

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(iconColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(status.message)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    if status.savedSwingCount > 0 {
                        Text("\(status.savedSwingCount) saved")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green))
                    }
                }

                Text(detailText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(detailColor)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.54))
        )
    }

    private var iconName: String {
        if status.lastErrorMessage != nil {
            return "exclamationmark.triangle.fill"
        }
        if status.pendingSwingCount > 0 {
            return "square.and.arrow.down.fill"
        }
        return status.isActive ? "dot.radiowaves.left.and.right" : "pause.circle.fill"
    }

    private var iconColor: Color {
        if status.lastErrorMessage != nil {
            return .yellow
        }
        if status.pendingSwingCount > 0 {
            return .green
        }
        return status.isActive ? .yellow : .white.opacity(0.68)
    }

    private var detailText: String {
        if let error = status.lastErrorMessage {
            return error
        }
        if status.pendingSwingCount > 0 {
            return "\(status.pendingSwingCount) clip\(status.pendingSwingCount == 1 ? "" : "s") exporting to Library"
        }
        return "Saved swings appear in Library"
    }

    private var detailColor: Color {
        status.lastErrorMessage == nil ? .white.opacity(0.70) : .yellow.opacity(0.92)
    }
}

struct LiveSwingDetectionBadge: View {
    let snapshot: LiveSwingDetectionSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(iconColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(snapshot.primaryMessage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    if snapshot.detectedSwingCount > 0 {
                        Text("\(snapshot.detectedSwingCount)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.yellow))
                    }
                }

                Text(snapshot.detailMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.78))
                    .lineLimit(2)

                if let performanceLine {
                    Text(performanceLine)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(performanceColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.58))
        )
    }

    private var iconName: String {
        switch snapshot.status {
        case .idle:
            return "scope"
        case .disabled:
            return "scope.slash"
        case .searchingBall:
            return "magnifyingglass"
        case .ballLocked:
            return "smallcircle.filled.circle"
        case .swingInProgress:
            return "figure.golf"
        case .hitDetected, .swingDetected:
            return "checkmark.circle.fill"
        case .unavailable:
            return "exclamationmark.triangle.fill"
        }
    }

    private var performanceLine: String? {
        guard snapshot.targetSampleFPS > 0, snapshot.processedFrameCount > 0 else { return nil }

        var parts = [
            String(format: "%.0f/%.1ffps", snapshot.targetSampleFPS, snapshot.effectiveSampleFPS),
            String(format: "model %.0f/%.0fms", snapshot.lastProcessingTimeMS, snapshot.averageProcessingTimeMS)
        ]

        if snapshot.averagePoseProcessingTimeMS > 0 {
            parts.append(String(format: "pose %.0f/%.0fms", snapshot.lastPoseProcessingTimeMS, snapshot.averagePoseProcessingTimeMS))
        }

        if snapshot.analysisLagMS >= 50 {
            parts.append(String(format: "lag %.0fms", snapshot.analysisLagMS))
        }

        return parts.joined(separator: " · ")
    }

    private var performanceColor: Color {
        let sampleRateRatio = snapshot.targetSampleFPS > 0
            ? snapshot.effectiveSampleFPS / snapshot.targetSampleFPS
            : 1
        if snapshot.analysisLagMS > 500 || sampleRateRatio < 0.70 {
            return .red.opacity(0.86)
        }
        if snapshot.analysisLagMS > 180 || sampleRateRatio < 0.88 {
            return .yellow.opacity(0.90)
        }
        return .white.opacity(0.58)
    }

    private var iconColor: Color {
        switch snapshot.status {
        case .disabled:
            return .white.opacity(0.68)
        case .idle, .searchingBall:
            return .white.opacity(0.84)
        case .ballLocked, .swingInProgress:
            return .yellow
        case .hitDetected, .swingDetected:
            return .green
        case .unavailable:
            return .yellow
        }
    }
}

#Preview {
    CaptureView(onAnalyzeSwings: nil)
}
