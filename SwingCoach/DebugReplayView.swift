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

private enum DebugReplaySourceTiming: String, CaseIterable {
    case realtime
    case slowMotion120
    case slowMotion240

    var label: String {
        switch self {
        case .realtime: "30/1x"
        case .slowMotion120: "120/4x"
        case .slowMotion240: "240/8x"
        }
    }

    var sourceTimeScale: Double {
        switch self {
        case .realtime: 1.0
        case .slowMotion120: 4.0
        case .slowMotion240: 8.0
        }
    }

    var playbackSpeedMultiplier: Double {
        sourceTimeScale
    }
}

private struct DebugReplayResult {
    let detections: [DetectedSwing]
    let sourceDuration: Double
}

struct DebugReplayView: View {
    @StateObject private var model = DebugReplayViewModel()
    @AppStorage(ExperimentalSettingKey.liveModelDetectorSampleFPS) private var liveModelDetectorSampleFPS = 8.0
    @AppStorage(ExperimentalSettingKey.debugReplaySourceTiming) private var debugReplaySourceTimingRaw = DebugReplaySourceTiming.realtime.rawValue
    @State private var showsVideoPicker = false
    @State private var trimSource: TrimVideoSource?
    @State private var trimDetections: [DetectedSwing] = []
    @State private var previewDetection: DetectionPreview?
    @State private var showsAdvancedControls = false

    private let detectorSampleOptions = [2.0, 4.0, 8.0, 16.0]

    private var sourceTiming: DebugReplaySourceTiming {
        get { DebugReplaySourceTiming(rawValue: debugReplaySourceTimingRaw) ?? .realtime }
        nonmutating set { debugReplaySourceTimingRaw = newValue.rawValue }
    }

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
                    VStack(alignment: .leading, spacing: 8) {
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

                            Spacer()

                            if model.selectedVideoURL != nil {
                                replayPlayPauseButton
                            }
                        }

                        if let selectedVideoURL = model.selectedVideoURL {
                            replayControlPanel(selectedVideoURL: selectedVideoURL)
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
            .onAppear { ExperimentalDetectorDefaults.migrateIfNeeded() }
        }
    }

    private var replayPlayPauseButton: some View {
        Button {
            if model.isReplaying {
                model.togglePause(speedMultiplier: sourceTiming.playbackSpeedMultiplier)
            } else {
                model.startReplay(
                    speedMultiplier: sourceTiming.playbackSpeedMultiplier,
                    sourceTimeScale: sourceTiming.sourceTimeScale,
                    detectorSampleFPS: liveModelDetectorSampleFPS
                )
            }
        } label: {
            Image(systemName: model.isPaused ? "play.circle.fill" : (model.isReplaying ? "pause.circle.fill" : "play.circle.fill"))
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(.yellow)
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
    }

    private func replayControlPanel(selectedVideoURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedVideoURL.lastPathComponent)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 6) {
                debugRowTitle("footage")
                ForEach(DebugReplaySourceTiming.allCases, id: \.rawValue) { timing in
                    debugChip(
                        timing.label,
                        isSelected: sourceTiming == timing,
                        minWidth: 62
                    ) {
                        sourceTiming = timing
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    showsAdvancedControls.toggle()
                } label: {
                    Label(showsAdvancedControls ? "Less" : "Advanced", systemImage: showsAdvancedControls ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white.opacity(0.78))
                }
                .buttonStyle(.plain)
                .disabled(model.isReplaying)

                Spacer()

                Text("\(Int(liveModelDetectorSampleFPS))fps · V2")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundColor(.white.opacity(0.52))
                    .lineLimit(1)
            }

            if showsAdvancedControls {
                HStack(spacing: 6) {
                    debugRowTitle("model")
                    ForEach(detectorSampleOptions, id: \.self) { sampleFPS in
                        debugChip("\(Int(sampleFPS))fps", isSelected: liveModelDetectorSampleFPS == sampleFPS, minWidth: 48) {
                            liveModelDetectorSampleFPS = sampleFPS
                        }
                    }
                }

            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.62)))
    }

    private func debugRowTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(.white.opacity(0.54))
            .frame(width: 44, alignment: .leading)
    }

    private func debugChip(
        _ title: String,
        isSelected: Bool,
        minWidth: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(isSelected ? .black : .white.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(minWidth: minWidth, minHeight: 20)
                .padding(.horizontal, 4)
                .background(Capsule().fill(isSelected ? Color.yellow : Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .disabled(model.isReplaying)
    }

    private var replayOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.progressText)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.76))
                Spacer()
                Text("\(model.detections.count) swings")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.64))
            }

            ProgressView(value: model.progress)
                .tint(.yellow)

            replayScrubber

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
                                    Text(detectionEvidenceText(detection))
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

    private var replayScrubber: some View {
        HStack(spacing: 8) {
            Text(formatTime(model.replayStartSourceTime))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundColor(.white.opacity(0.58))
                .frame(width: 54, alignment: .leading)

            GeometryReader { geometry in
                let width = max(1, geometry.size.width)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.24))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.yellow)
                        .frame(width: model.scrubberOffset(in: width), height: 4)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 13, height: 13)
                        .shadow(color: .black.opacity(0.28), radius: 3)
                        .offset(x: model.scrubberOffset(in: width) - 6.5)
                }
                .frame(height: 28)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !model.isReplaying else { return }
                            let fraction = max(0, min(1, value.location.x / width))
                            model.setReplayStartFraction(Double(fraction))
                        }
                )
            }
            .frame(height: 28)
            .opacity(model.selectedVideoURL == nil || model.isReplaying ? 0.45 : 1)

            Text(model.replayDuration > 0 ? formatTime(model.replayDuration) : "--")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundColor(.white.opacity(0.46))
                .frame(width: 54, alignment: .trailing)
        }
    }

    private func debugEvidenceGrid(snapshot: LiveSwingDetectionSnapshot) -> some View {
        var rows = [
            ("fps", String(format: "%.0f/%.1f", snapshot.targetSampleFPS, snapshot.effectiveSampleFPS)),
            ("frames", "\(snapshot.processedFrameCount)"),
            ("model", String(format: "%.0fms", snapshot.averageProcessingTimeMS)),
            ("pose", snapshot.averagePoseProcessingTimeMS > 0 ? String(format: "%.0fms", snapshot.averagePoseProcessingTimeMS) : "-"),
            ("motion", String(format: "%.2f", snapshot.peakHandSpeed)),
            ("club", String(format: "%.2f", snapshot.handTravel)),
            ("ball", snapshot.ballCandidateScore.map { String(format: "%.2f", $0) } ?? "-")
        ]
        if snapshot.analysisLagMS > 0 {
            rows.append(("lag", String(format: "%.0fms", snapshot.analysisLagMS)))
        }
        if let rejection = snapshot.lastRejectionReason, !rejection.isEmpty {
            rows.append(("reject", rejection))
        }

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

    private func formatTime(_ time: CMTime) -> String {
        String(format: "%.2fs", CMTimeGetSeconds(time))
    }

    private func formatTime(_ time: Double) -> String {
        String(format: "%.2fs", time)
    }

    private func detectionEvidenceText(_ detection: DetectedSwing) -> String {
        let confidence = "\(Int(detection.confidence * 100))%"
        guard let declaredAt = detection.declaredAt else {
            return confidence
        }

        let timeScale = max(1.0, sourceTiming.sourceTimeScale)
        let suffix = timeScale > 1.0 ? "rt" : ""
        let lag = max(0, declaredAt - CMTimeGetSeconds(detection.endTime)) / timeScale
        if let impactTime = detection.impactTime {
            let impactLag = max(0, declaredAt - impactTime) / timeScale
            return "\(confidence) imp +\(String(format: "%.1f", impactLag))s\(suffix) end +\(String(format: "%.1f", lag))s\(suffix)"
        }
        return "\(confidence) end +\(String(format: "%.1f", lag))s\(suffix)"
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
    @Published var replaySourceTime = 0.0
    @Published var replayDuration = 0.0
    @Published var replayStartSourceTime = 0.0
    @Published var detectorSourceTime = 0.0
    @Published var snapshot = LiveSwingDetectionSnapshot.idle
    @Published var detections: [DetectedSwing] = []
    @Published var errorMessage: String?

    private var replayTask: Task<Void, Never>?
    private var durationLoadTask: Task<Void, Never>?
    private var replayControl: DebugReplayControl?
    private var playerTimeObserver: Any?
    private var lastProgressUpdateAt = Date.distantPast
    private var activePlaybackSpeedMultiplier = 1.0
    private var visibleReplayStarted = false
    private var playerHeldForDetectorCatchup = false
    private let replayLeadPauseThreshold = 3.0
    private let replayLeadResumeThreshold = 1.0

    var progressText: String {
        if isReplaying {
            guard replayDuration > 0 else { return "Preparing replay" }
            let timer = "video \(Self.formatReplayTimer(elapsed: replaySourceTime, duration: replayDuration))"
            let lead = replaySourceTime - detectorSourceTime
            if lead > replayLeadResumeThreshold {
                return "\(timer) · det \(Int(detectorSourceTime.rounded(.down)))s"
            }
            return timer
        }

        if selectedVideoURL == nil {
            return "No video selected"
        }

        if replayDuration > 0, progress >= 1 {
            return "\(Self.formatReplayTimer(elapsed: replayDuration, duration: replayDuration)) complete"
        }

        return detections.isEmpty ? "Ready" : "Replay complete"
    }

    func setReplayStartSourceTime(_ sourceTime: Double) {
        guard !isReplaying else { return }
        let clamped = max(0, replayDuration > 0 ? min(sourceTime, replayDuration) : sourceTime)
        replayStartSourceTime = clamped
        replaySourceTime = clamped
        progress = replayDuration > 0 ? min(1, max(0, clamped / replayDuration)) : 0
        player?.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func setReplayStartFraction(_ fraction: Double) {
        guard replayDuration > 0 else { return }
        setReplayStartSourceTime(replayDuration * max(0, min(1, fraction)))
    }

    func scrubberOffset(in width: CGFloat) -> CGFloat {
        guard replayDuration > 0 else { return 0 }
        let fraction = max(0, min(1, replayStartSourceTime / replayDuration))
        return CGFloat(fraction) * width
    }

    var trimVideoSource: TrimVideoSource? {
        selectedVideoURL.map { .localFile(url: $0) }
    }

    func setSelectedVideo(_ url: URL) {
        cancelReplay()
        durationLoadTask?.cancel()
        clearPlayerTimeObserver()
        let newPlayer = AVPlayer(url: url)
        selectedVideoURL = url
        player = newPlayer
        attachPlayerTimeObserver(to: newPlayer)
        progress = 0
        replaySourceTime = 0
        replayDuration = 0
        replayStartSourceTime = 0
        detectorSourceTime = 0
        snapshot = .idle
        detections = []
        errorMessage = nil
        lastProgressUpdateAt = .distantPast

        durationLoadTask = Task {
            let asset = AVURLAsset(url: url)
            guard let duration = try? await asset.load(.duration) else { return }
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite, seconds > 0 else { return }
            await MainActor.run {
                guard self.selectedVideoURL == url else { return }
                self.replayDuration = seconds
            }
        }
    }

    func startReplay(
        speedMultiplier: Double,
        sourceTimeScale: Double,
        detectorSampleFPS: Double
    ) {
        guard let selectedVideoURL else { return }

        cancelReplay()
        let configuration = SwingDetectorV2Configuration.live(
            sourceTimeScale: sourceTimeScale,
            lowSampleFPS: detectorSampleFPS,
            burstSampleFPS: max(16.0, detectorSampleFPS * 2.0)
        )
        let control = DebugReplayControl()
        replayControl = control
        activePlaybackSpeedMultiplier = max(1, min(8, speedMultiplier))
        let startSourceTime = max(0, replayStartSourceTime)
        visibleReplayStarted = false
        playerHeldForDetectorCatchup = false
        isReplaying = true
        isPaused = false
        progress = replayDuration > 0 ? min(1, max(0, startSourceTime / replayDuration)) : 0
        replaySourceTime = startSourceTime
        detectorSourceTime = startSourceTime
        snapshot = LiveSwingDetectionSnapshot(
            status: .searchingBall,
            primaryMessage: "Preparing replay",
            detailMessage: "Opening video frames for detector replay.",
            targetSampleFPS: configuration.lowSampleFPS,
            detectorConfigurationName: configuration.name
        )
        detections = []
        errorMessage = nil
        lastProgressUpdateAt = .distantPast
        player?.seek(
            to: CMTime(seconds: startSourceTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        player?.pause()

        let stream = DebugLiveSwingReplayRunner.eventStream(
            for: selectedVideoURL,
            speedMultiplier: speedMultiplier,
            startSourceTime: startSourceTime,
            detectorConfiguration: configuration,
            control: control
        )

        replayTask = Task {
            for await event in stream {
                switch event {
                case .progress(let sourceTime, let sourceDuration, let newSnapshot, let currentDetections):
                    applyProgress(
                        sourceTime: sourceTime,
                        sourceDuration: sourceDuration,
                        snapshot: newSnapshot,
                        detections: currentDetections
                    )
                case .finished(let result):
                    detections = result.detections
                    replayDuration = result.sourceDuration
                    replaySourceTime = result.sourceDuration
                    detectorSourceTime = result.sourceDuration
                    playerHeldForDetectorCatchup = false
                    progress = 1
                    isReplaying = false
                    isPaused = false
                    player?.pause()
                    snapshot = LiveSwingDetectionSnapshot(
                        status: result.detections.isEmpty ? .idle : .swingDetected,
                        primaryMessage: result.detections.isEmpty ? "No V2 swings detected" : "\(result.detections.count) swing\(result.detections.count == 1 ? "" : "s") detected",
                        detailMessage: result.detections.isEmpty
                            ? "No V2 detections cleared the detector gates."
                            : "Open trim to inspect detected ranges.",
                        detectedSwingCount: result.detections.count,
                        hasBallLock: snapshot.hasBallLock,
                        hasBallMovement: snapshot.hasBallMovement,
                        processedFrameCount: snapshot.processedFrameCount,
                        skippedFrameCount: snapshot.skippedFrameCount,
                        targetSampleFPS: snapshot.targetSampleFPS,
                        averageProcessingTimeMS: snapshot.averageProcessingTimeMS,
                        lastProcessingTimeMS: snapshot.lastProcessingTimeMS,
                        detectorConfigurationName: snapshot.detectorConfigurationName
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
        visibleReplayStarted = false
        playerHeldForDetectorCatchup = false
        player?.pause()
        player?.seek(
            to: CMTime(seconds: replayStartSourceTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func togglePause(speedMultiplier: Double) {
        guard isReplaying, let replayControl else { return }

        isPaused.toggle()
        Task {
            await replayControl.setPaused(isPaused)
        }

        if isPaused {
            player?.pause()
        } else if visibleReplayStarted {
            syncVisiblePlaybackToDetector()
            guard !playerHeldForDetectorCatchup else { return }
            player?.playImmediately(atRate: Float(max(1, min(8, speedMultiplier))))
        }
    }

    func fail(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    private func applyProgress(
        sourceTime: Double,
        sourceDuration: Double,
        snapshot newSnapshot: LiveSwingDetectionSnapshot,
        detections currentDetections: [DetectedSwing]
    ) {
        let now = Date()
        let detectionsChanged = currentDetections.count != detections.count
        let statusChanged = newSnapshot.status != snapshot.status
        let enoughTimePassed = now.timeIntervalSince(lastProgressUpdateAt) >= 0.25

        detectorSourceTime = max(0, sourceTime)
        replayDuration = max(0, sourceDuration)
        if !visibleReplayStarted {
            startVisibleReplayIfNeeded()
        }
        syncVisiblePlaybackToDetector()

        guard detectionsChanged || statusChanged || enoughTimePassed else { return }

        snapshot = newSnapshot
        detections = currentDetections
        lastProgressUpdateAt = now
    }

    private static func formatReplayTimer(elapsed: Double, duration: Double) -> String {
        let safeDuration = max(0, duration)
        let elapsedSeconds = Int(max(0, min(elapsed, safeDuration)).rounded(.down))
        let durationSeconds = Int(safeDuration.rounded(.up))
        return "\(elapsedSeconds)/\(durationSeconds)s"
    }

    private func attachPlayerTimeObserver(to player: AVPlayer) {
        playerTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.08, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.updateVisibleReplayTime(time)
            }
        }
    }

    private func clearPlayerTimeObserver() {
        if let playerTimeObserver {
            player?.removeTimeObserver(playerTimeObserver)
            self.playerTimeObserver = nil
        }
    }

    private func startVisibleReplayIfNeeded() {
        guard !visibleReplayStarted else { return }

        visibleReplayStarted = true
        replaySourceTime = replayStartSourceTime
        progress = replayDuration > 0 ? min(1, max(0, replayStartSourceTime / replayDuration)) : 0
        player?.seek(
            to: CMTime(seconds: replayStartSourceTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        if !isPaused {
            player?.playImmediately(atRate: Float(activePlaybackSpeedMultiplier))
        }
    }

    private func updateVisibleReplayTime(_ time: CMTime) {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite else { return }

        replaySourceTime = max(0, seconds)
        if replayDuration > 0, isReplaying {
            progress = min(1, max(0, replaySourceTime / replayDuration))
        }
        syncVisiblePlaybackToDetector()
    }

    private func syncVisiblePlaybackToDetector() {
        guard isReplaying, visibleReplayStarted, !isPaused else { return }

        let lead = replaySourceTime - detectorSourceTime
        if lead > replayLeadPauseThreshold {
            playerHeldForDetectorCatchup = true
            player?.pause()
            return
        }

        if playerHeldForDetectorCatchup, lead <= replayLeadResumeThreshold {
            playerHeldForDetectorCatchup = false
            player?.playImmediately(atRate: Float(activePlaybackSpeedMultiplier))
        }
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
    case progress(Double, Double, LiveSwingDetectionSnapshot, [DetectedSwing])
    case finished(DebugReplayResult)
    case failed(String)
}

private enum DebugLiveSwingReplayRunner {
    static func eventStream(
        for url: URL,
        speedMultiplier: Double,
        startSourceTime: Double,
        detectorConfiguration: SwingDetectorV2Configuration,
        control: DebugReplayControl
    ) -> AsyncStream<DebugReplayEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let result = try await replay(
                        url: url,
                        speedMultiplier: speedMultiplier,
                        startSourceTime: startSourceTime,
                        detectorConfiguration: detectorConfiguration,
                        control: control
                    ) { sourceTime, sourceDuration, snapshot, detections in
                        continuation.yield(.progress(sourceTime, sourceDuration, snapshot, detections))
                    }
                    continuation.yield(.finished(result))
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
        startSourceTime: Double,
        detectorConfiguration: SwingDetectorV2Configuration,
        control: DebugReplayControl,
        onProgress: @escaping (Double, Double, LiveSwingDetectionSnapshot, [DetectedSwing]) -> Void
    ) async throws -> DebugReplayResult {
        let clampedSpeedMultiplier = max(1, min(8, speedMultiplier))
        let clampedStartSourceTime = max(0, startSourceTime)
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
        let startTime = CMTime(seconds: min(clampedStartSourceTime, durationSeconds), preferredTimescale: 600)
        let remainingDuration = CMTimeSubtract(duration, startTime)
        if CMTimeCompare(remainingDuration, .zero) > 0 {
            reader.timeRange = CMTimeRange(start: startTime, duration: remainingDuration)
        }

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

        let detector = SwingDetectorV2(configuration: detectorConfiguration)
        detector.reset(enabled: true)
        var lastDetectorSourceTime = 0.0
        let replayStartedAt = Date()
        let trackTimeRange = try await videoTrack.load(.timeRange)
        let trackStart = trackTimeRange.start

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            try await control.waitIfPaused()

            let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let videoRelativeTime = CMTimeGetSeconds(CMTimeSubtract(sampleTime, trackStart))
            guard videoRelativeTime.isFinite else { continue }

            let realElapsed = await control.activeElapsed(since: replayStartedAt)
            let targetReplayElapsed = max(0, videoRelativeTime - clampedStartSourceTime) / clampedSpeedMultiplier
            if targetReplayElapsed > realElapsed {
                let delay = targetReplayElapsed - realElapsed
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            lastDetectorSourceTime = videoRelativeTime

            let orientedImageSize = Self.orientedImageSize(from: sampleBuffer)
            let snapshot = detector.process(
                sampleBuffer: sampleBuffer,
                recordingTime: videoRelativeTime,
                orientation: .up,
                orientedImageSize: orientedImageSize
            )
            onProgress(
                videoRelativeTime,
                durationSeconds,
                snapshot,
                detector.currentDetections()
            )
        }

        if reader.status == .failed {
            throw reader.error ?? VideoTrimmer.TrimmerError.assetLoadFailed
        }

        let detections = detector.finish(recordingTime: lastDetectorSourceTime)
        return DebugReplayResult(
            detections: detections,
            sourceDuration: durationSeconds
        )
    }

    private static func orientedImageSize(from sampleBuffer: CMSampleBuffer) -> CGSize {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return .zero
        }

        return CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
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
