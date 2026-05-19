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
    @State private var showsVideoPicker = false
    @State private var trimSource: TrimVideoSource?
    @State private var trimDetections: [DetectedSwing] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showsVideoPicker = true
                    } label: {
                        Label("Choose Replay Video", systemImage: "video.badge.plus")
                    }

                    if let selectedVideoURL = model.selectedVideoURL {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(selectedVideoURL.lastPathComponent)
                                .font(.subheadline.weight(.semibold))
                            Text(selectedVideoURL.path)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        Button {
                            model.startReplay()
                        } label: {
                            Label("Replay Through Live Detector", systemImage: "play.circle.fill")
                        }
                        .disabled(model.isReplaying)
                    }
                } header: {
                    Text("Input")
                } footer: {
                    Text("This DEBUG-only tool copies a selected video to temp storage, replays its frames through the live capture detector, then opens trim with the detected timestamps.")
                }

                Section("Replay State") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(model.statusText)
                            .foregroundColor(.secondary)
                    }

                    ProgressView(value: model.progress)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.snapshot.primaryMessage)
                            .font(.subheadline.weight(.semibold))
                        Text(model.snapshot.detailMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label(model.snapshot.hasBallLock ? "Ball locked" : "No ball lock", systemImage: model.snapshot.hasBallLock ? "smallcircle.filled.circle" : "circle")
                        Spacer()
                        Label(model.snapshot.hasBallMovement ? "Ball moved" : "No movement", systemImage: model.snapshot.hasBallMovement ? "checkmark.circle.fill" : "circle")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Section("Detected Swings") {
                    if model.detections.isEmpty {
                        Text(model.isReplaying ? "Waiting for detections..." : "No detected swings yet.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(model.detections.enumerated()), id: \.element.id) { index, detection in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Swing \(index + 1)")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(formatTime(detection.startTime)) to \(formatTime(detection.endTime)) · confidence \(Int(detection.confidence * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Button {
                            trimDetections = model.detections
                            trimSource = model.trimVideoSource
                        } label: {
                            Label("Open Trim With Detections", systemImage: "scissors")
                        }
                    }
                }

                if let errorMessage = model.errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Replay Debug")
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
        }
    }

    private func formatTime(_ time: CMTime) -> String {
        String(format: "%.2fs", CMTimeGetSeconds(time))
    }
}

@MainActor
final class DebugReplayViewModel: ObservableObject {
    @Published var selectedVideoURL: URL?
    @Published var isReplaying = false
    @Published var progress = 0.0
    @Published var snapshot = LiveSwingDetectionSnapshot.idle
    @Published var detections: [DetectedSwing] = []
    @Published var errorMessage: String?

    private var replayTask: Task<Void, Never>?

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
        progress = 0
        snapshot = .idle
        detections = []
        errorMessage = nil
    }

    func startReplay() {
        guard let selectedVideoURL else { return }

        cancelReplay()
        isReplaying = true
        progress = 0
        snapshot = LiveSwingDetectionSnapshot(
            status: .searchingBall,
            primaryMessage: "Preparing replay",
            detailMessage: "Opening video frames for detector replay."
        )
        detections = []
        errorMessage = nil

        let stream = DebugLiveSwingReplayRunner.eventStream(for: selectedVideoURL)

        replayTask = Task {
            for await event in stream {
                switch event {
                case .progress(let progressValue, let newSnapshot):
                    progress = progressValue
                    snapshot = newSnapshot
                case .finished(let newDetections):
                    detections = newDetections
                    progress = 1
                    isReplaying = false
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
        isReplaying = false
    }

    func fail(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

private enum DebugReplayEvent {
    case progress(Double, LiveSwingDetectionSnapshot)
    case finished([DetectedSwing])
    case failed(String)
}

private enum DebugLiveSwingReplayRunner {
    static func eventStream(for url: URL) -> AsyncStream<DebugReplayEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let detections = try await replay(url: url) { progress, snapshot in
                        continuation.yield(.progress(progress, snapshot))
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
        onProgress: @escaping (Double, LiveSwingDetectionSnapshot) -> Void
    ) async throws -> [DetectedSwing] {
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
        var lastProcessedTime = -Double.greatestFiniteMagnitude
        var lastRelativeTime = 0.0

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()

            let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if firstSampleTime == nil {
                firstSampleTime = sampleTime
            }

            guard let firstSampleTime else { continue }

            let relativeTime = CMTimeGetSeconds(CMTimeSubtract(sampleTime, firstSampleTime))
            guard relativeTime.isFinite, relativeTime - lastProcessedTime >= 0.10 else { continue }

            lastProcessedTime = relativeTime
            lastRelativeTime = relativeTime

            let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
            try handler.perform([request])

            let snapshot = detector.process(
                sampleBuffer: sampleBuffer,
                observation: request.results?.first,
                recordingTime: relativeTime
            )
            onProgress(min(1, max(0, relativeTime / durationSeconds)), snapshot)
        }

        if reader.status == .failed {
            throw reader.error ?? VideoTrimmer.TrimmerError.assetLoadFailed
        }

        return detector.finish(recordingTime: lastRelativeTime)
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
