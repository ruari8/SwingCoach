//
//  DebugReplayView.swift
//  SwingCoach
//
//  Created by Codex on 18/05/2026.
//

#if DEBUG
import SwiftUI
import AVFoundation
import Combine
import Photos
import PhotosUI
import UniformTypeIdentifiers
import Vision

struct DebugReplayView: View {
    @StateObject private var model = DebugReplayViewModel()
    @AppStorage(ExperimentalSettingKey.debugReplaySpeedMultiplier) private var debugReplaySpeedMultiplier = 8.0
    @State private var showsVideoPicker = false
    @State private var trimSource: TrimVideoSource?
    @State private var trimDetections: [DetectedSwing] = []
    @State private var previewDetection: DetectionPreview?

    private let replaySpeedOptions = [1.0, 2.0, 4.0, 8.0]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                if let player = model.player {
                    DebugReplayPlayerSurface(player: player)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundColor(.white.opacity(0.86))
                        Text("Choose a video to replay through the live detector.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.84))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                    }
                }

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Button {
                            showsVideoPicker = true
                        } label: {
                            Label(model.selectedVideoURL == nil ? "Choose" : "Change", systemImage: "video.badge.plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.62)))
                        }

                        if let selectedVideoURL = model.selectedVideoURL {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedVideoURL.lastPathComponent)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)

                                HStack(spacing: 4) {
                                    ForEach(replaySpeedOptions, id: \.self) { speed in
                                        Button {
                                            debugReplaySpeedMultiplier = speed
                                        } label: {
                                            Text("\(Int(speed))x")
                                                .font(.caption2.weight(.bold))
                                                .foregroundColor(debugReplaySpeedMultiplier == speed ? .black : .white.opacity(0.78))
                                                .frame(width: 30, height: 20)
                                                .background(
                                                    Capsule()
                                                        .fill(debugReplaySpeedMultiplier == speed ? Color.yellow : Color.white.opacity(0.14))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(model.isReplaying)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.62)))

                            Spacer()

                            Button {
                                if model.isReplaying {
                                    model.togglePause(speedMultiplier: debugReplaySpeedMultiplier)
                                } else {
                                    model.startReplay(speedMultiplier: debugReplaySpeedMultiplier)
                                }
                            } label: {
                                Image(systemName: model.isPaused ? "play.circle.fill" : (model.isReplaying ? "pause.circle.fill" : "play.circle.fill"))
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundColor(.yellow)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                    Spacer()

                    replayOverlay
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                }
            }
            .navigationTitle("Replay Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.isReplaying {
                    Button("Cancel") {
                        model.cancelReplay()
                    }
                }
            }
            .sheet(isPresented: $showsVideoPicker) {
                DebugVideoFilePicker(
                    onCancel: {
                        showsVideoPicker = false
                    },
                    onVideoReady: { url in
                        showsVideoPicker = false
                        model.setSelectedVideo(url)
                    },
                    onError: { error in
                        showsVideoPicker = false
                        model.fail(error)
                    }
                )
            }
            .fullScreenCover(item: $trimSource) { source in
                TrimView(
                    source: source,
                    initialDetectedSwings: trimDetections,
                    runsPostRecordDetection: false,
                    onComplete: { _, _ in
                        trimSource = nil
                    },
                    onCancel: {
                        trimSource = nil
                    }
                )
            }
            .sheet(item: $previewDetection) { preview in
                DebugDetectionPreviewSheet(
                    videoURL: preview.videoURL,
                    detection: preview.detection,
                    index: preview.index
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var replayOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.76))
                Spacer()
                Label(model.snapshot.hasBallLock ? "Ball" : "No ball", systemImage: model.snapshot.hasBallLock ? "smallcircle.filled.circle" : "circle")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.76))
                Label(model.snapshot.hasBallMovement ? "Moved" : "Still", systemImage: model.snapshot.hasBallMovement ? "checkmark.circle.fill" : "circle")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.76))
            }

            ProgressView(value: model.progress)
                .tint(.yellow)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName(for: model.snapshot.status))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(iconColor(for: model.snapshot.status))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.snapshot.primaryMessage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(model.snapshot.detailMessage)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.74))
                        .lineLimit(2)
                }
            }

            debugEvidenceGrid(snapshot: model.snapshot)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.9))
            }

            Divider()
                .overlay(Color.white.opacity(0.16))

            HStack {
                Text(model.detections.isEmpty ? "No detected swings yet" : "\(model.detections.count) detected")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.82))
                Spacer()
                if !model.detections.isEmpty {
                    Button {
                        trimDetections = model.detections
                        trimSource = model.trimVideoSource
                    } label: {
                        Label("Open Trim", systemImage: "scissors")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.yellow))
                    }
                }
            }

            if !model.detections.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.detections.enumerated()), id: \.element.id) { index, detection in
                            Button {
                                if let videoURL = model.selectedVideoURL {
                                    previewDetection = DetectionPreview(
                                        videoURL: videoURL,
                                        detection: detection,
                                        index: index
                                    )
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Swing \(index + 1)")
                                        .font(.caption.weight(.bold))
                                    Text("\(formatTime(detection.startTime))-\(formatTime(detection.endTime))")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundColor(.white.opacity(0.72))
                                    Text("\(Int(detection.confidence * 100))%")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(.yellow)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.72))
        )
    }

    private func debugEvidenceGrid(snapshot: LiveSwingDetectionSnapshot) -> some View {
        let rows = [
            ("poses", "\(snapshot.poseObservationCount)"),
            ("speed", String(format: "%.2f", snapshot.handSpeed)),
            ("peak", String(format: "%.2f", snapshot.peakHandSpeed)),
            ("travel", String(format: "%.2f", snapshot.handTravel)),
            ("setup", String(format: "%.1fs", snapshot.setupDuration)),
            ("ball", snapshot.ballCandidateScore.map { String(format: "%.2f", $0) } ?? "-"),
            ("luma", snapshot.ballLumaDelta.map { String(format: "%.0f", $0) } ?? "-"),
            ("reject", snapshot.lastRejectionReason ?? "-")
        ]

        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.0.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.42))
                    Text(row.1)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundColor(.white.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
        }
    }

    private func iconName(for status: LiveSwingDetectionStatus) -> String {
        switch status {
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

    private func iconColor(for status: LiveSwingDetectionStatus) -> Color {
        switch status {
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

    private func formatTime(_ time: CMTime) -> String {
        String(format: "%.2fs", CMTimeGetSeconds(time))
    }
}

private struct DetectionPreview: Identifiable {
    let id = UUID()
    let videoURL: URL
    let detection: DetectedSwing
    let index: Int
}

private struct DebugDetectionPreviewSheet: View {
    let videoURL: URL
    let detection: DetectedSwing
    let index: Int

    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @State private var timeObserver: Any?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                DebugReplayPlayerSurface(player: player)
                    .ignoresSafeArea(edges: .bottom)

                VStack {
                    Spacer()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Swing \(index + 1)")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("\(formatTime(detection.startTime)) to \(formatTime(detection.endTime)) · \(Int(detection.confidence * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.white.opacity(0.76))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.72)))
                    .padding(14)
                }
            }
            .navigationTitle("Detected Swing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            startPreview()
        }
        .onDisappear {
            stopPreview()
        }
    }

    private func startPreview() {
        let item = AVPlayerItem(url: videoURL)
        player.replaceCurrentItem(with: item)
        player.seek(to: detection.startTime, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.08, preferredTimescale: 600),
            queue: .main
        ) { time in
            if CMTimeCompare(time, detection.endTime) >= 0 {
                player.seek(to: detection.startTime, toleranceBefore: .zero, toleranceAfter: .zero)
                player.play()
            }
        }
    }

    private func stopPreview() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.pause()
    }

    private func formatTime(_ time: CMTime) -> String {
        String(format: "%.2fs", CMTimeGetSeconds(time))
    }
}

private struct DebugReplayPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }
    }
}

@MainActor
final class DebugReplayViewModel: ObservableObject {
    @Published var selectedVideoURL: URL?
    @Published var player: AVPlayer?
    @Published var isReplaying = false
    @Published var isPaused = false
    @Published var progress = 0.0
    @Published var snapshot = LiveSwingDetectionSnapshot.idle
    @Published var detections: [DetectedSwing] = []
    @Published var errorMessage: String?

    private var replayTask: Task<Void, Never>?
    private var replayControl: DebugReplayControl?
    private var lastProgressUpdateAt = Date.distantPast

    var statusText: String {
        if isReplaying {
            return "\(Int(progress * 100))%"
        }

        if selectedVideoURL == nil {
            return "No video selected"
        }

        return detections.isEmpty ? "Ready" : "Replay complete"
    }

    var trimVideoSource: TrimVideoSource? {
        selectedVideoURL.map { .localFile(url: $0) }
    }

    func setSelectedVideo(_ url: URL) {
        cancelReplay()
        selectedVideoURL = url
        player = AVPlayer(url: url)
        progress = 0
        snapshot = .idle
        detections = []
        errorMessage = nil
        lastProgressUpdateAt = .distantPast
    }

    func startReplay(speedMultiplier: Double) {
        guard let selectedVideoURL else { return }

        cancelReplay()
        let control = DebugReplayControl()
        replayControl = control
        isReplaying = true
        isPaused = false
        progress = 0
        snapshot = LiveSwingDetectionSnapshot(
            status: .searchingBall,
            primaryMessage: "Preparing replay",
            detailMessage: "Opening video frames for detector replay."
        )
        detections = []
        errorMessage = nil
        lastProgressUpdateAt = .distantPast
        player?.seek(to: .zero)
        player?.playImmediately(atRate: Float(max(1, min(8, speedMultiplier))))

        let stream = DebugLiveSwingReplayRunner.eventStream(
            for: selectedVideoURL,
            speedMultiplier: speedMultiplier,
            control: control
        )

        replayTask = Task {
            for await event in stream {
                switch event {
                case .progress(let progressValue, let newSnapshot, let currentDetections):
                    applyProgress(
                        progressValue,
                        snapshot: newSnapshot,
                        detections: currentDetections
                    )
                case .finished(let newDetections):
                    detections = newDetections
                    progress = 1
                    isReplaying = false
                    isPaused = false
                    player?.pause()
                    snapshot = LiveSwingDetectionSnapshot(
                        status: newDetections.isEmpty ? .idle : .swingDetected,
                        primaryMessage: newDetections.isEmpty ? "No swings detected" : "\(newDetections.count) swing\(newDetections.count == 1 ? "" : "s") detected",
                        detailMessage: newDetections.isEmpty ? "Try another video or tune detector thresholds." : "Open trim to inspect detected ranges.",
                        detectedSwingCount: newDetections.count,
                        hasBallLock: snapshot.hasBallLock,
                        hasBallMovement: snapshot.hasBallMovement
                    )
                case .failed(let message):
                    isReplaying = false
                    isPaused = false
                    player?.pause()
                    errorMessage = message
                    snapshot = LiveSwingDetectionSnapshot(
                        status: .unavailable,
                        primaryMessage: "Replay failed",
                        detailMessage: message
                    )
                }
            }
        }
    }

    func cancelReplay() {
        replayTask?.cancel()
        replayTask = nil
        replayControl = nil
        isReplaying = false
        isPaused = false
        player?.pause()
    }

    func togglePause(speedMultiplier: Double) {
        guard isReplaying, let replayControl else { return }

        isPaused.toggle()
        Task {
            await replayControl.setPaused(isPaused)
        }

        if isPaused {
            player?.pause()
        } else {
            player?.playImmediately(atRate: Float(max(1, min(8, speedMultiplier))))
        }
    }

    func fail(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    private func applyProgress(
        _ progressValue: Double,
        snapshot newSnapshot: LiveSwingDetectionSnapshot,
        detections currentDetections: [DetectedSwing]
    ) {
        let now = Date()
        let detectionsChanged = currentDetections.count != detections.count
        let statusChanged = newSnapshot.status != snapshot.status
        let enoughTimePassed = now.timeIntervalSince(lastProgressUpdateAt) >= 0.25

        progress = progressValue

        guard detectionsChanged || statusChanged || enoughTimePassed else { return }

        snapshot = newSnapshot
        detections = currentDetections
        lastProgressUpdateAt = now
    }
}

private actor DebugReplayControl {
    private var isPaused = false
    private var pausedAt: Date?
    private var totalPausedDuration: TimeInterval = 0

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }

        isPaused = paused
        if paused {
            pausedAt = Date()
        } else if let pausedAt {
            totalPausedDuration += Date().timeIntervalSince(pausedAt)
            self.pausedAt = nil
        }
    }

    func waitIfPaused() async throws {
        while isPaused {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 80_000_000)
        }
    }

    func activeElapsed(since startDate: Date) -> TimeInterval {
        var pausedDuration = totalPausedDuration
        if let pausedAt {
            pausedDuration += Date().timeIntervalSince(pausedAt)
        }
        return Date().timeIntervalSince(startDate) - pausedDuration
    }
}

private enum DebugReplayEvent {
    case progress(Double, LiveSwingDetectionSnapshot, [DetectedSwing])
    case finished([DetectedSwing])
    case failed(String)
}

private enum DebugLiveSwingReplayRunner {
    static func eventStream(
        for url: URL,
        speedMultiplier: Double,
        control: DebugReplayControl
    ) -> AsyncStream<DebugReplayEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let detections = try await replay(
                        url: url,
                        speedMultiplier: speedMultiplier,
                        control: control
                    ) { progress, snapshot, detections in
                        continuation.yield(.progress(progress, snapshot, detections))
                    }
                    continuation.yield(.finished(detections))
                } catch is CancellationError {
                    continuation.finish()
                    return
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func replay(
        url: URL,
        speedMultiplier: Double,
        control: DebugReplayControl,
        onProgress: @escaping (Double, LiveSwingDetectionSnapshot, [DetectedSwing]) -> Void
    ) async throws -> [DetectedSwing] {
        let clampedSpeedMultiplier = max(1, min(8, speedMultiplier))
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw VideoTrimmer.TrimmerError.assetLoadFailed
        }

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoTrimmer.TrimmerError.noVideoTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
        )
        output.alwaysCopiesSampleData = false
        output.videoComposition = try await orientedVideoComposition(for: videoTrack, duration: duration)

        guard reader.canAdd(output) else {
            throw VideoTrimmer.TrimmerError.assetLoadFailed
        }

        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? VideoTrimmer.TrimmerError.assetLoadFailed
        }

        let detector = LiveSwingDetector()
        let request = VNDetectHumanBodyPoseRequest()
        var firstSampleTime: CMTime?
        var lastProcessedDetectorTime = -Double.greatestFiniteMagnitude
        var lastDetectorTime = 0.0
        let replayStartedAt = Date()

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            try await control.waitIfPaused()

            let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if firstSampleTime == nil {
                firstSampleTime = sampleTime
            }

            guard let firstSampleTime else { continue }

            let videoRelativeTime = CMTimeGetSeconds(CMTimeSubtract(sampleTime, firstSampleTime))
            guard videoRelativeTime.isFinite else { continue }

            let detectorTime = videoRelativeTime
            guard detectorTime - lastProcessedDetectorTime >= 0.10 else { continue }

            let realElapsed = await control.activeElapsed(since: replayStartedAt)
            let targetReplayElapsed = videoRelativeTime / clampedSpeedMultiplier
            if targetReplayElapsed > realElapsed {
                let delay = targetReplayElapsed - realElapsed
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            lastProcessedDetectorTime = detectorTime
            lastDetectorTime = detectorTime

            let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
            try handler.perform([request])

            let snapshot = detector.process(
                sampleBuffer: sampleBuffer,
                observations: request.results ?? [],
                recordingTime: detectorTime
            )
            onProgress(
                min(1, max(0, videoRelativeTime / durationSeconds)),
                snapshot,
                detector.currentDetections()
            )
        }

        if reader.status == .failed {
            throw reader.error ?? VideoTrimmer.TrimmerError.assetLoadFailed
        }

        return detector.finish(recordingTime: lastDetectorTime)
    }

    private static func orientedVideoComposition(for track: AVAssetTrack, duration: CMTime) async throws -> AVVideoComposition {
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let renderSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let renderTransform = preferredTransform.concatenating(
            CGAffineTransform(
                translationX: -transformedRect.minX,
                y: -transformedRect.minY
            )
        )

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.setTransform(renderTransform, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layerInstruction]

        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(max(30, Int32(nominalFrameRate.rounded())))
        )
        composition.instructions = [instruction]
        return composition
    }
}

private struct DebugVideoFilePicker: UIViewControllerRepresentable {
    let onCancel: () -> Void
    let onVideoReady: (URL) -> Void
    let onError: (Error) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: DebugVideoFilePicker

        init(_ parent: DebugVideoFilePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true) {
                guard let result = results.first else {
                    DispatchQueue.main.async {
                        self.parent.onCancel()
                    }
                    return
                }

                self.copySelectedVideo(result)
            }
        }

        private func copySelectedVideo(_ result: PHPickerResult) {
            let itemProvider = result.itemProvider
            guard itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                DispatchQueue.main.async {
                    self.parent.onError(DebugVideoPickerError.notMovie)
                }
                return
            }

            _ = itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                if let error {
                    DispatchQueue.main.async {
                        self.parent.onError(error)
                    }
                    return
                }

                guard let url else {
                    DispatchQueue.main.async {
                        self.parent.onError(DebugVideoPickerError.noFileURL)
                    }
                    return
                }

                do {
                    let destinationURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("debug_replay_\(UUID().uuidString)")
                        .appendingPathExtension(url.pathExtension.isEmpty ? "mov" : url.pathExtension)
                    try FileManager.default.copyItem(at: url, to: destinationURL)

                    DispatchQueue.main.async {
                        self.parent.onVideoReady(destinationURL)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.parent.onError(error)
                    }
                }
            }
        }
    }
}

private enum DebugVideoPickerError: Error, LocalizedError {
    case notMovie
    case noFileURL

    var errorDescription: String? {
        switch self {
        case .notMovie:
            return "The selected item is not a movie."
        case .noFileURL:
            return "The picker did not provide a video file URL."
        }
    }
}
#endif
