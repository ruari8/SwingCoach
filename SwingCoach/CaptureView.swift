//
//  CaptureView.swift
//  SwingCoach
//
//  Created by Ruari Craig on 01/11/2025.
//

import SwiftUI
import UIKit
import Combine
import AVFoundation
import Photos
import ImageIO
import OSLog

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
    case auto
    case manual

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
    private static let logger = Logger(subsystem: "Pear.ai.SwingCoach", category: "Capture")
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera.session.queue")
    /// The AVCapture delegate must return immediately or the camera drops source
    /// frames. Encoding and model inference therefore live on separate queues.
    private let qualityQueue = DispatchQueue(label: "camera.capture-output.queue")
    private let analysisQueue = DispatchQueue(label: "camera.swing-analysis.queue")
    private let bufferQueue = DispatchQueue(label: "camera.auto-buffer.queue")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var recordingAudioInput: AVCaptureDeviceInput?
    private let recordingAudioSession = CaptureRecordingAudioSession()
    // Remains true until the file delegate finishes, even after stopRecording().
    private var manualRecordingIsPending = false
    private var isConfigured = false
    private var captureOutputIsPaused = false
    // These counters are owned by qualityQueue, independent of detector UI stats.
    private var captureCadence = CaptureCadenceWindow()
    private var nextCadenceReport = 0.0
    private var droppedFrameReasons: [String: Int] = [:]
    private var coalescedAnalysisFrames = 0
    private var diagnosticDevice: AVCaptureDevice?

    private struct PendingAnalysisFrame {
        let sampleBuffer: CMSampleBuffer
        let relativeTime: Double
        let rotationAngle: CGFloat
    }

    private var analysisIsInFlight = false
    private var pendingAnalysisFrame: PendingAnalysisFrame?

    private var liveSwingDetector = SwingDetectorV3()
    private var recordingStartSampleTime: CMTime?
    private var recordingStartWallTime: Date?
    private var lastLiveSwingSampleTime = -Double.greatestFiniteMagnitude
    private var autoCaptureIsActive = false
    private var autoCaptureIsPausedForReview = false
    // Review identity and counters are owned by the main actor.
    private var autoReviewSessionID = UUID()
    // Captured with detector work on analysisQueue; never read by UI callbacks.
    private var autoDetectionReviewSessionID = UUID()
    private var autoSavedSwingCount = 0
    private var autoPendingSwingCount = 0
    private var autoExportedDetectionIDs: Set<UUID> = []
    private lazy var autoRollingBuffer = AutoRollingVideoBuffer(writerQueue: bufferQueue)
    private let autoTrimmer = VideoTrimmer()

    @Published var lastRecordingURL: URL?
    @Published var lastRecordingSwingDetections: [DetectedSwing] = []
    @Published var lastRecordingSwingDetectionSummary: LiveSwingDetectionSnapshot?
    @Published var recordingError: Error?
    @Published var captureMode: SloMoMode = .ultra
    @Published var liveSwingDetection = LiveSwingDetectionSnapshot.idle
    @Published var autoCaptureStatus = AutoCaptureStatus.idle
    @Published private(set) var autoSessionSwings: [SavedSwing] = []
    var isLiveSwingDetectionEnabled = true
    var liveModelDetectorSampleFPS = 8.0
    var capturesPracticeSwings = false

    /// The mode that was active when recording started (for correct playback rate)
    private(set) var recordedMode: SloMoMode = .ultra

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(captureSessionRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification, object: session
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func captureSessionRuntimeError(_ notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else { return }
        Self.logger.error("Capture session failed: \(error.domain, privacy: .public) (\(error.code)): \(error.localizedDescription, privacy: .public)")
    }

    private func configure() {
        guard !isConfigured else { return }

        // Preview and Auto's video-only rolling writer never need the microphone.
        // Keep AVFoundation from changing the shared audio policy on tab entry.
        session.automaticallyConfiguresApplicationAudioSession = false

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
        diagnosticDevice = device
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        configureQualityOutput()

        // Configure high FPS AFTER input/output are added to the session
        // Otherwise the session may override format settings when input is added
        configureHighFPS(device: device, mode: captureMode)

        session.commitConfiguration()
        isConfigured = true
    }

    private func beginRecordingAudio() {
        guard let audioDevice = AVCaptureDevice.default(for: .audio),
              let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
              session.canAddInput(audioInput)
        else { return }

        do {
            try recordingAudioSession.begin()
        } catch {
            Self.logger.error("Recording audio activation failed: \(String(describing: error), privacy: .public)")
            endRecordingAudio()
            return
        }

        session.beginConfiguration()
        session.addInput(audioInput)
        recordingAudioInput = audioInput
        // Input changes can reset the manually selected camera format/cadence.
        if let device = rotationCoordinator?.device {
            configureHighFPS(device: device, mode: recordedMode)
        }
        session.commitConfiguration()
    }

    private func endRecordingAudio() {
        if let input = recordingAudioInput {
            session.beginConfiguration()
            session.removeInput(input)
            recordingAudioInput = nil
            if let device = rotationCoordinator?.device {
                configureHighFPS(device: device, mode: captureMode)
            }
            session.commitConfiguration()
        }
        do {
            try recordingAudioSession.end()
        } catch {
            Self.logger.error("Recording audio release failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func configureQualityOutput() {
        // The delegate only fans frames out to dedicated queues. Keeping this
        // false preserves the high-FPS source cadence used by the rolling writer.
        videoDataOutput.alwaysDiscardsLateVideoFrames = false
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
        // Apply the format and lock frame rate
        do {
            try device.lockForConfiguration()
            device.activeFormat = bestFormat
            // Set min and max to same value = lock to exact FPS
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            device.unlockForConfiguration()
            Self.logger.info("Configured camera: \(dims.width)×\(dims.height) @ \(targetFPS) fps (\(mode.displayName, privacy: .public))")
        } catch {
            Self.logger.error("Camera format configuration failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Switch capture mode without stopping the session (prevents errors)
    func switchMode(to mode: SloMoMode) {
        queue.async {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }

            self.captureOutputIsPaused = true
            if self.autoCaptureIsActive {
                self.bufferQueue.sync {
                    self.autoRollingBuffer.reset(preservingPendingExports: true)
                }
            }

            self.session.beginConfiguration()
            DispatchQueue.main.async {
                self.captureMode = mode
            }
            self.recordedMode = mode
            self.configureHighFPS(device: device, mode: mode)
            self.session.commitConfiguration()
            self.resetLiveSwingDetection()
            self.captureOutputIsPaused = false
        }
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
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                self.configureAndStartSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    guard let self else { return }
                    guard granted else {
                        self.reportCameraAccessUnavailable()
                        return
                    }
                    self.queue.async {
                        self.configureAndStartSession()
                    }
                }
            case .denied, .restricted:
                self.reportCameraAccessUnavailable()
                return
            @unknown default:
                return
            }
        }
    }

    private func configureAndStartSession() {
        configure()
        guard isConfigured, !session.isRunning else { return }
        session.startRunning()
    }

    private func reportCameraAccessUnavailable() {
        DispatchQueue.main.async {
            self.liveSwingDetection = LiveSwingDetectionSnapshot(
                status: .unavailable,
                primaryMessage: "Camera access needed",
                detailMessage: "Enable Camera access in Settings, then reopen Capture."
            )
            self.autoCaptureStatus = AutoCaptureStatus(
                isActive: false,
                savedSwingCount: self.autoSavedSwingCount,
                pendingSwingCount: self.autoPendingSwingCount,
                message: "Auto capture unavailable",
                lastErrorMessage: "Camera access is disabled."
            )
        }
    }

    func reportPhotosAccessUnavailable() {
        DispatchQueue.main.async {
            self.autoCaptureStatus = AutoCaptureStatus(
                isActive: self.autoCaptureIsActive,
                savedSwingCount: self.autoSavedSwingCount,
                pendingSwingCount: self.autoPendingSwingCount,
                message: "Photos access needed",
                lastErrorMessage: "Enable Photos add access in Settings before the range session."
            )
        }
    }

    @MainActor
    func deleteAutoCapturedSwing(_ swing: SavedSwing) async throws {
        try await SwingLibrary.shared.deleteSwingAndPhoto(swing)
        autoSessionSwings.removeAll { $0.id == swing.id }
        autoSavedSwingCount = autoSessionSwings.count
        autoCaptureStatus = AutoCaptureStatus(
            isActive: autoCaptureIsActive,
            savedSwingCount: autoSavedSwingCount,
            pendingSwingCount: autoPendingSwingCount,
            message: autoCaptureIsActive ? "Auto watching" : "Auto capture off",
            lastErrorMessage: nil
        )
    }

    func stop() {
        queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            // An in-flight movie owns audio until its delegate has finalized it.
            if !self.manualRecordingIsPending {
                self.endRecordingAudio()
            }
        }
    }

    func startRecording() {
        queue.async {
            guard !self.manualRecordingIsPending, !self.movieOutput.isRecording else { return }
            guard self.session.isRunning else {
                DispatchQueue.main.async {
                    self.recordingError = NSError(
                        domain: AVFoundationErrorDomain, code: AVError.deviceNotConnected.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: "Camera is not ready to record."]
                    )
                }
                return
            }
            self.manualRecordingIsPending = true
            self.recordedMode = self.captureMode
            self.beginRecordingAudio()
            self.resetLiveSwingDetection()
            let rotationAngle = self.currentCardinalCaptureRotationAngle()
            if let connection = self.movieOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }

            let url = Self.tempURL()
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
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
            guard !self.manualRecordingIsPending, !self.movieOutput.isRecording else {
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
            self.autoCaptureIsPausedForReview = false
            self.recordedMode = self.captureMode
            let reviewSessionID = UUID()
            DispatchQueue.main.async {
                self.beginAutoReviewSession(id: reviewSessionID)
                self.autoCaptureStatus = AutoCaptureStatus(
                    isActive: true,
                    savedSwingCount: 0,
                    pendingSwingCount: 0,
                    message: "Auto watching",
                    lastErrorMessage: nil
                )
            }
            self.resetLiveSwingDetection(reviewSessionID: reviewSessionID)
            self.bufferQueue.async {
                self.autoRollingBuffer.reset(preservingPendingExports: true)
            }
        }
    }

    func stopAutoCapture() {
        queue.async {
            self.autoCaptureIsActive = false
            self.autoCaptureIsPausedForReview = false
            self.bufferQueue.async {
                self.autoRollingBuffer.reset(preservingPendingExports: true)
            }
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

    private func resetLiveSwingDetection(reviewSessionID: UUID? = nil) {
        let detectorEnabled = isLiveSwingDetectionEnabled || autoCaptureIsActive
        qualityQueue.async {
            CaptureCadenceDiagnostics.shared.emit("camera-reset", cadence: self.captureCadence.takeSummary())
            self.captureCadence = CaptureCadenceWindow()
            self.droppedFrameReasons = [:]
            self.coalescedAnalysisFrames = 0
            self.nextCadenceReport = 0
            self.recordingStartSampleTime = nil
            self.recordingStartWallTime = nil
            self.lastLiveSwingSampleTime = -Double.greatestFiniteMagnitude
            self.analysisIsInFlight = false
            self.pendingAnalysisFrame = nil
        }
        analysisQueue.async {
            if let reviewSessionID { self.autoDetectionReviewSessionID = reviewSessionID }
            self.autoExportedDetectionIDs = []
            self.liveSwingDetector = SwingDetectorV3(configuration: self.liveV3Configuration())
            self.liveSwingDetector.reset(enabled: detectorEnabled)
        }

        DispatchQueue.main.async {
            let configuration = self.liveV3Configuration()
            self.lastRecordingSwingDetections = []
            self.lastRecordingSwingDetectionSummary = nil
            self.liveSwingDetection = detectorEnabled ? LiveSwingDetectionSnapshot(
                status: .idle,
                primaryMessage: "V3 detect starting",
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

    private func liveV3Configuration() -> SwingDetectorV3Configuration {
        // Live sample-buffer timestamps advance at wall-clock rate regardless of
        // capture FPS; the slow-motion timeline only exists after export retiming.
        // recordedMode.sourceTimeScale applies to playback rate and export only.
        SwingDetectorV3Configuration.live(
            sourceTimeScale: 1.0,
            lowSampleFPS: liveModelDetectorSampleFPS,
            burstSampleFPS: max(16.0, liveModelDetectorSampleFPS * 2.0),
            allowsPracticeSwings: capturesPracticeSwings
        )
    }

    func restartAutoDetection() {
        guard autoCaptureIsActive else { return }
        resetLiveSwingDetection()
    }

    func pauseAutoCaptureForReview() {
        queue.async {
            guard self.autoCaptureIsActive else { return }
            self.autoCaptureIsPausedForReview = true
            self.bufferQueue.async {
                self.autoRollingBuffer.reset(preservingPendingExports: true)
            }
        }
    }

    func resumeAutoCaptureAfterReview() {
        queue.async {
            guard self.autoCaptureIsActive, self.autoCaptureIsPausedForReview else { return }
            self.autoCaptureIsPausedForReview = false
            self.recordedMode = self.captureMode
            self.resetLiveSwingDetection()
            self.bufferQueue.async {
                self.autoRollingBuffer.reset(preservingPendingExports: true)
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        queue.async {
            self.endRecordingAudio()
            self.manualRecordingIsPending = false
            self.finishRecording(outputFileURL: outputFileURL, error: error)
        }
    }

    private func finishRecording(outputFileURL: URL, error: Error?) {
        analysisQueue.async {
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
        let shouldProcessAuto = autoCaptureIsActive && !autoCaptureIsPausedForReview
        guard !captureOutputIsPaused,
              shouldProcessAuto || (movieOutput.isRecording && isLiveSwingDetectionEnabled)
        else { return }

        let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if shouldProcessAuto {
            captureCadence.record(pts: sampleTime.seconds, expectedFPS: captureMode.targetFPS)
            reportCaptureCadence(connection: connection)
        }
        if recordingStartSampleTime == nil {
            recordingStartSampleTime = sampleTime
            recordingStartWallTime = Date()
        }

        guard let recordingStartSampleTime else { return }
        let relativeTime = CMTimeGetSeconds(CMTimeSubtract(sampleTime, recordingStartSampleTime))
        guard relativeTime.isFinite else { return }
        lastLiveSwingSampleTime = relativeTime

        let rotationAngle = currentCardinalCaptureRotationAngle()
        if shouldProcessAuto {
            let sourceFPS = captureMode.targetFPS
            let enqueuedAt = ProcessInfo.processInfo.systemUptime
            bufferQueue.async {
                self.autoRollingBuffer.append(
                    sampleBuffer: sampleBuffer,
                    relativeTime: relativeTime,
                    videoRotationAngle: rotationAngle,
                    sourceFPS: sourceFPS,
                    queueDelay: ProcessInfo.processInfo.systemUptime - enqueuedAt
                )
            }
        }
        enqueueAnalysis(
            sampleBuffer: sampleBuffer,
            relativeTime: relativeTime,
            rotationAngle: rotationAngle
        )
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard autoCaptureIsActive, !autoCaptureIsPausedForReview, !captureOutputIsPaused else { return }
        let reason = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_DroppedFrameReason, attachmentModeOut: nil)
        let name: String
        let rawReason = reason as? String
        if rawReason == (kCMSampleBufferDroppedFrameReason_FrameWasLate as String) {
            name = "late"
        } else if rawReason == (kCMSampleBufferDroppedFrameReason_OutOfBuffers as String) {
            name = "outOfBuffers"
        } else if rawReason == (kCMSampleBufferDroppedFrameReason_Discontinuity as String) {
            name = "discontinuity"
        } else {
            name = "unknown"
        }
        droppedFrameReasons[name, default: 0] += 1
        reportCaptureCadence(connection: connection)
    }

    private func reportCaptureCadence(connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= nextCadenceReport else { return }
        nextCadenceReport = now + 1
        var values: [String: Double] = [
            "requestedFPS": captureMode.targetFPS,
            "coalescedAnalysisFrames": Double(coalescedAnalysisFrames),
            "thermalState": Double(ProcessInfo.processInfo.thermalState.rawValue),
            "stabilizationMode": Double(connection.activeVideoStabilizationMode.rawValue)
        ]
        for (reason, count) in droppedFrameReasons { values["dropped_" + reason] = Double(count) }
        var state: [String: String] = [:]
        if let device = diagnosticDevice {
            let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            values["width"] = Double(dimensions.width)
            values["height"] = Double(dimensions.height)
            values["minFrameSeconds"] = device.activeVideoMinFrameDuration.seconds
            values["maxFrameSeconds"] = device.activeVideoMaxFrameDuration.seconds
            values["exposureSeconds"] = device.exposureDuration.seconds
            values["iso"] = Double(device.iso)
            values["lensPosition"] = Double(device.lensPosition)
            values["adjustingFocus"] = device.isAdjustingFocus ? 1 : 0
            values["adjustingExposure"] = device.isAdjustingExposure ? 1 : 0
            state["pressure"] = device.systemPressureState.level.rawValue
            state["camera"] = device.deviceType.rawValue
        }
        CaptureCadenceDiagnostics.shared.emit("camera", cadence: captureCadence.takeSummary(), values: values, state: state)
        droppedFrameReasons = [:]
        coalescedAnalysisFrames = 0
    }

    private func currentCardinalCaptureRotationAngle() -> CGFloat {
        let rawAngle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 0
        let normalized = rawAngle.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        let cardinal = (positive / 90).rounded() * 90
        return cardinal >= 360 ? 0 : cardinal
    }

    private func exportAutoDetectedSwing(
        detection: DetectedSwing,
        preparedClip: AutoRollingVideoBuffer.PreparedClip,
        recordedMode: SloMoMode,
        reviewSessionID: UUID
    ) async {
        let diagnosticID = preparedClip.chunkID.uuidString
        CaptureCadenceDiagnostics.shared.emit("export-start", id: diagnosticID, values: [
            "chunkStart": preparedClip.sourceStartTime,
            "start": preparedClip.startTime.seconds, "end": preparedClip.endTime.seconds,
            "slowMotionFactor": recordedMode.sourceTimeScale
        ], state: ["detection": detection.id.uuidString])
        var savedSwingForReview: SavedSwing?
        var lastErrorMessage: String?

        do {
            let asset = try await preparedClip.makeAsset()
            let clip = SwingClip(
                startTime: preparedClip.startTime,
                endTime: preparedClip.endTime,
                vantage: .dtl,
                detectionImpactTime: detection.impactTime.map { $0 - preparedClip.sourceStartTime },
                detectionDeclaredAt: detection.declaredAt.map { $0 - preparedClip.sourceStartTime }
            )

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("auto_swing_\(clip.id.uuidString.prefix(8)).mp4")
            defer { try? FileManager.default.removeItem(at: outputURL) }
            try await autoTrimmer.exportClip(
                from: asset,
                startTime: clip.startCMTime,
                endTime: clip.endCMTime,
                to: outputURL,
                slowMotionFactor: recordedMode.exportSlowMotionFactor
            )

            CaptureCadenceDiagnostics.shared.emit("export-written", id: diagnosticID,
                state: ["file": outputURL.lastPathComponent])
            let thumbnail = try? await autoTrimmer.generateThumbnail(for: asset, at: clip.startCMTime)
            let savedSwing = try await SwingLibrary.shared.saveExportedSwing(
                from: outputURL,
                vantage: clip.vantage,
                duration: clip.duration * recordedMode.sourceTimeScale,
                initialThumbnail: thumbnail
            )
            // Library batch export renames files but preserves SavedSwing.id in
            // metadata.json. Keep that stable join plus the exact source range.
            CaptureCadenceDiagnostics.shared.emit("swing-saved", id: diagnosticID, values: [
                "chunkStart": preparedClip.sourceStartTime,
                "start": preparedClip.startTime.seconds, "end": preparedClip.endTime.seconds,
                "slowMotionFactor": recordedMode.sourceTimeScale
            ], state: ["swingID": savedSwing.id.uuidString, "file": outputURL.lastPathComponent])
            savedSwingForReview = savedSwing
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        await MainActor.run {
            self.finishAutoReviewRequest(sessionID: reviewSessionID, savedSwing: savedSwingForReview,
                                         errorMessage: lastErrorMessage)
        }

        CaptureCadenceDiagnostics.shared.emit("export-end", id: diagnosticID,
            values: ["saved": savedSwingForReview == nil ? 0 : 1], state: ["error": lastErrorMessage ?? "none"])
        bufferQueue.async {
            self.autoRollingBuffer.release(preparedClip)
        }
    }

    private func enqueueAnalysis(
        sampleBuffer: CMSampleBuffer,
        relativeTime: Double,
        rotationAngle: CGFloat
    ) {
        let frame = PendingAnalysisFrame(
            sampleBuffer: sampleBuffer,
            relativeTime: relativeTime,
            rotationAngle: rotationAngle
        )
        guard !analysisIsInFlight else {
            // Coalesce backlog to the newest frame. The detector samples by
            // timestamp, so stale queued frames only create lag and heat.
            coalescedAnalysisFrames += 1
            pendingAnalysisFrame = frame
            return
        }

        analysisIsInFlight = true
        processAnalysis(frame)
    }

    private func processAnalysis(_ frame: PendingAnalysisFrame) {
        analysisQueue.async {
            self.processLiveModelSwingFrame(
                frame.sampleBuffer,
                relativeTime: frame.relativeTime,
                rotationAngle: frame.rotationAngle
            )
            self.qualityQueue.async {
                if let pending = self.pendingAnalysisFrame {
                    self.pendingAnalysisFrame = nil
                    self.processAnalysis(pending)
                } else {
                    self.analysisIsInFlight = false
                }
            }
        }
    }

    private func processLiveModelSwingFrame(
        _ sampleBuffer: CMSampleBuffer,
        relativeTime: Double,
        rotationAngle: CGFloat
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Match the device orientation so YOLO and the pose gate see upright
        // golfers in landscape too, not just portrait.
        let orientation: CGImagePropertyOrientation
        switch Int(rotationAngle.rounded()) % 360 {
        case 90: orientation = .right
        case 180: orientation = .down
        case 270: orientation = .left
        default: orientation = .up
        }
        let bufferSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        let orientedImageSize = (orientation == .right || orientation == .left)
            ? CGSize(width: bufferSize.height, height: bufferSize.width)
            : bufferSize
        var snapshot = liveSwingDetector.process(
            sampleBuffer: sampleBuffer,
            recordingTime: relativeTime,
            orientation: orientation,
            orientedImageSize: orientedImageSize
        )
        snapshot = liveTelemetrySnapshot(base: snapshot, recordingTime: relativeTime)

        if !autoCaptureIsActive || movieOutput.isRecording {
            DispatchQueue.main.async {
                self.liveSwingDetection = snapshot
            }
        }

        if autoCaptureIsActive, !autoCaptureIsPausedForReview {
            enqueueNewAutoDetections()
        }
    }

    private func enqueueNewAutoDetections() {
        let detections = liveSwingDetector.currentDetections()
        let newDetections = detections.filter { !autoExportedDetectionIDs.contains($0.id) }
        guard !newDetections.isEmpty else { return }

        for detection in newDetections {
            autoExportedDetectionIDs.insert(detection.id)
            prepareAutoClip(detection)
        }
    }

    /// Snapshot the clip context once per accepted detection. The buffer completes
    /// this request when its last frame arrives, or with available footage on stop.
    private func prepareAutoClip(_ detection: DetectedSwing) {
        let range = SwingClipContext.load().range(for: detection)
        let mode = recordedMode
        let reviewSessionID = autoDetectionReviewSessionID
        DispatchQueue.main.async {
            self.beginAutoReviewRequest(sessionID: reviewSessionID)
        }
        bufferQueue.async {
            self.autoRollingBuffer.prepareClip(in: range) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let preparedClip):
                    Task {
                        await self.exportAutoDetectedSwing(
                            detection: detection, preparedClip: preparedClip, recordedMode: mode,
                            reviewSessionID: reviewSessionID
                        )
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.finishAutoReviewRequest(sessionID: reviewSessionID, savedSwing: nil,
                                                     errorMessage: error.localizedDescription)
                    }
                }
            }
        }
    }

    @MainActor
    func beginAutoReviewSession(id: UUID) {
        autoReviewSessionID = id
        autoSavedSwingCount = 0
        autoPendingSwingCount = 0
        autoSessionSwings = []
    }

    @MainActor
    func beginAutoReviewRequest(sessionID: UUID) {
        guard sessionID == autoReviewSessionID else { return }
        autoPendingSwingCount += 1
        autoCaptureStatus = AutoCaptureStatus(
            isActive: autoCaptureIsActive, savedSwingCount: autoSavedSwingCount,
            pendingSwingCount: autoPendingSwingCount,
            message: "Collecting swing footage", lastErrorMessage: nil
        )
    }

    /// An old session still saves to Library, but cannot change a newer review.
    @MainActor
    func finishAutoReviewRequest(sessionID: UUID, savedSwing: SavedSwing?, errorMessage: String?) {
        guard sessionID == autoReviewSessionID else { return }
        if let savedSwing {
            autoSessionSwings.append(savedSwing)
            autoSavedSwingCount += 1
        }
        autoPendingSwingCount = max(0, autoPendingSwingCount - 1)
        autoCaptureStatus = AutoCaptureStatus(
            isActive: autoCaptureIsActive, savedSwingCount: autoSavedSwingCount,
            pendingSwingCount: autoPendingSwingCount,
            message: autoCaptureIsActive ? "Auto watching" : "Auto capture off",
            lastErrorMessage: errorMessage
        )
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
    @AppStorage(ExperimentalSettingKey.capturePracticeSwings) private var capturePracticeSwings = false
    @AppStorage(ExperimentalSettingKey.showCaptureModelStats) private var showCaptureModelStats = false
    @State private var workflowMode: CaptureWorkflowMode = .auto
    @State private var isRecording = false
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
    @State private var autoReviewPresentation: AutoSwingReviewPresentation?

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session) { viewPoint, cameraPoint in
                handleFocusTap(viewPoint: viewPoint, cameraPoint: cameraPoint)
            }
            .overlay {
                if showFocusIndicator, let point = focusPoint {
                    FocusIndicatorView()
                        .position(point)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
            .background(.black)

            LinearGradient(stops: [
                .init(color: .black.opacity(0.52), location: 0),
                .init(color: .clear, location: 0.27),
                .init(color: .clear, location: 0.64),
                .init(color: .black.opacity(0.70), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if isProcessing {
                Color.black.opacity(0.7)
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.5).tint(.white)
                    Text("Finalizing recording...")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                }
            } else if currentRecordingURL == nil {
                captureControls
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            ExperimentalDetectorDefaults.migrateIfNeeded()
            camera.isLiveSwingDetectionEnabled = liveAutoSwingDetectionEnabled
            camera.liveModelDetectorSampleFPS = liveModelDetectorSampleFPS
            camera.capturesPracticeSwings = capturePracticeSwings
            camera.start()
            if workflowMode == .auto {
                preventIdleTimer()
                requestAutoCapturePhotosAccess()
                camera.startAutoCapture()
            }
        }
        .onChange(of: liveAutoSwingDetectionEnabled) { _, isEnabled in
            camera.isLiveSwingDetectionEnabled = isEnabled
        }
        .onChange(of: liveModelDetectorSampleFPS) { _, sampleFPS in
            camera.liveModelDetectorSampleFPS = sampleFPS
        }
        .onChange(of: capturePracticeSwings) { _, isEnabled in
            camera.capturesPracticeSwings = isEnabled
            camera.restartAutoDetection()
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
        .fullScreenCover(isPresented: $showTrimView, onDismiss: clearCurrentRecording) {
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
                    },
                    onCancel: {
                        showTrimView = false
                    },
                    onAnalyzeSwings: onAnalyzeSwings
                )
            }
        }
        .fullScreenCover(item: $autoReviewPresentation) { _ in
            AutoSwingReviewView(swings: camera.autoSessionSwings, onDelete: camera.deleteAutoCapturedSwing)
                .onDisappear {
                    camera.resumeAutoCaptureAfterReview()
                    camera.start()
                }
        }
    }

    private var captureControls: some View {
        VStack(spacing: 0) {
            Group {
                if isRecording {
                    HStack(spacing: 7) {
                        Circle().fill(.red).frame(width: 7, height: 7)
                        Text(formatDuration(recordingDuration))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .accessibilityIdentifier("capture-recording-timer")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        frameRateMenu
                        Spacer()
                        Picker("Capture", selection: $workflowMode) {
                            ForEach(CaptureWorkflowMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 172)
                        .accessibilityIdentifier("capture-mode")
                    }
                }
            }
            .frame(height: 44)
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.2), value: isRecording)

            Spacer(minLength: 16)

            if workflowMode == .auto {
                HStack(alignment: .center, spacing: 12) {
                    CaptureStatusLabel(
                        title: autoStatusTitle,
                        detail: autoStatusDetail,
                        indicator: autoStatusIndicator,
                        modelSnapshot: showCaptureModelStats && camera.autoCaptureStatus.isActive
                            ? camera.liveSwingDetection : nil
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    savedSwingsButton
                }
                .padding(.bottom, 22)
            } else {
                HStack(spacing: 8) {
                    Group {
                        if isRecording {
                            CaptureStatusLabel(
                                title: manualStatusTitle,
                                detail: manualStatusDetail,
                                modelSnapshot: showCaptureModelStats ? camera.liveSwingDetection : nil
                            )
                        } else {
                            Color.clear.frame(height: 1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    RecordButton(isRecording: isRecording, action: toggleRecording)
                    Color.clear.frame(maxWidth: .infinity).frame(height: 1)
                }
                .padding(.bottom, 20)
            }
        }
        .padding(.horizontal, 22)
        .foregroundStyle(.white)
    }

    private var frameRateMenu: some View {
        Menu {
            Button("30fps HD") { camera.switchMode(to: .normal) }
            Button("60fps HD") { camera.switchMode(to: .smooth) }
            Button("120fps HD") { camera.switchMode(to: .standard) }
            Button("240fps HD") { camera.switchMode(to: .ultra) }
        } label: {
            HStack(spacing: 5) {
                Text("\(camera.captureMode.shortName) fps")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier("capture-frame-rate")
        .accessibilityLabel("Frame rate, \(camera.captureMode.shortName) frames per second")
    }

    private var savedSwingsButton: some View {
        let count = camera.autoSessionSwings.count
        return Button(action: openAutoReview) {
            HStack(spacing: 9) {
                Group {
                    if let thumbnail = camera.autoSessionSwings.last?.thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(0.12))
                    }
                }
                .frame(width: 32, height: 42)
                .clipShape(.rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white.opacity(0.5), lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(count) saved").font(.subheadline.weight(.medium))
                    Text("This session").font(.caption2).foregroundStyle(.white.opacity(0.7))
                }
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .opacity(count == 0 ? 0.55 : 1)
        .accessibilityLabel("Review \(count) saved swings")
        .accessibilityIdentifier("capture-saved-swings")
    }

    private var autoStatusTitle: String {
        if camera.autoCaptureStatus.lastErrorMessage != nil { return "Auto needs attention" }
        if camera.liveSwingDetection.status == .unavailable { return "Detection unavailable" }
        return camera.autoCaptureStatus.isActive ? "Auto is on" : "Auto is off"
    }

    private var autoStatusDetail: String {
        if let error = camera.autoCaptureStatus.lastErrorMessage { return error }
        if camera.liveSwingDetection.status == .unavailable {
            return camera.liveSwingDetection.primaryMessage
        }
        let pending = camera.autoCaptureStatus.pendingSwingCount
        if pending > 0 { return "Saving \(pending) swing\(pending == 1 ? "" : "s")…" }
        return camera.autoCaptureStatus.isActive ? "Swings save automatically" : "Capture is paused"
    }

    private var autoStatusIndicator: Color {
        if camera.autoCaptureStatus.lastErrorMessage != nil || camera.liveSwingDetection.status == .unavailable {
            return .orange
        }
        return camera.autoCaptureStatus.isActive ? .red : .gray
    }

    private var manualStatusTitle: String {
        switch camera.liveSwingDetection.status {
        case .disabled: return "Detection off"
        case .unavailable: return "Detection unavailable"
        default: return "Detecting swings"
        }
    }

    private var manualStatusDetail: String {
        switch camera.liveSwingDetection.status {
        case .disabled, .unavailable: return "Recording video"
        default:
            let count = camera.liveSwingDetection.detectedSwingCount
            return count == 0 ? "No swings yet" : "\(count) detected"
        }
    }

    private func openAutoReview() {
        guard !camera.autoSessionSwings.isEmpty else { return }
        camera.pauseAutoCaptureForReview()
        // Reviewing fully stops the camera, encoder and inference work.
        camera.stop()
        autoReviewPresentation = AutoSwingReviewPresentation()
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

    private func requestAutoCapturePhotosAccess() {
        guard ClipStoragePreference.savesToPhotos else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized else {
                camera.reportPhotosAccessUnavailable()
                return
            }
        }
    }

    private func restoreIdleTimer() {
        guard let previousIdleTimerDisabled else { return }
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        self.previousIdleTimerDisabled = nil
    }

    private func clearCurrentRecording() {
        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentRecordingURL = nil
        currentRecordingMode = nil
        camera.lastRecordingURL = nil
        camera.lastRecordingSwingDetections = []
        camera.lastRecordingSwingDetectionSummary = nil
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
                    .strokeBorder(Color.white, lineWidth: 3)
                    .frame(width: 76, height: 76)

                // Inner shape (circle when idle, rounded square when recording)
                if isRecording {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.red)
                        .frame(width: 29, height: 29)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 62, height: 62)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isRecording)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
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

private struct CaptureStatusLabel: View {
    let title: String
    let detail: String
    var indicator: Color? = nil
    var modelSnapshot: LiveSwingDetectionSnapshot? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                if let indicator {
                    Circle().fill(indicator).frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("capture-status-title")
            }
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("capture-status-detail")

            if let snapshot = modelSnapshot,
               snapshot.status != .disabled, snapshot.status != .unavailable {
                Text(snapshot.processedFrameCount > 0
                     ? String(format: "%.1f fps / %.0f ms", snapshot.effectiveSampleFPS, snapshot.averageProcessingTimeMS)
                     : "Waiting for model…")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.65))
                    .accessibilityIdentifier("capture-model-stats")
            }
        }
    }
}

#Preview {
    CaptureView(onAnalyzeSwings: nil)
}
