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

enum DebugReplayDetectionMode: String, CaseIterable {
    case contact
    case impact
    case poseImpact
    case audioImpact
    case hybridImpact

    var label: String {
        switch self {
        case .contact: "contact"
        case .impact: "impact"
        case .poseImpact: "pose"
        case .audioImpact: "audio"
        case .hybridImpact: "hybrid"
        }
    }

    var emptyMessage: String {
        switch self {
        case .contact: "No contact swings detected"
        case .impact: "No impact swings detected"
        case .poseImpact: "No pose-gated swings detected"
        case .audioImpact: "No audio-gated swings detected"
        case .hybridImpact: "No hybrid swings detected"
        }
    }
}

private struct DebugReplayResult {
    let detections: [DetectedSwing]
    let candidateWindows: [ObjectSwingWindowDiagnostics]
    let sourceDuration: Double
}

private typealias DebugReplayPoseFeature = ObjectSwingPoseFeature

private struct DebugReplayAudioImpact {
    let time: Double
    let score: Double
}

struct DebugReplayView: View {
    @StateObject private var model = DebugReplayViewModel()
    @AppStorage(ExperimentalSettingKey.liveModelDetectorSampleFPS) private var liveModelDetectorSampleFPS = 8.0
    @AppStorage(ExperimentalSettingKey.hybridImpactConfirmationPostRoll) private var hybridImpactConfirmationPostRoll = 0.20
    @AppStorage(ExperimentalSettingKey.debugReplaySourceTiming) private var debugReplaySourceTimingRaw = DebugReplaySourceTiming.realtime.rawValue
    @AppStorage(ExperimentalSettingKey.debugReplayDetectionMode) private var debugReplayDetectionModeRaw = DebugReplayDetectionMode.hybridImpact.rawValue
    @State private var showsVideoPicker = false
    @State private var trimSource: TrimVideoSource?
    @State private var trimDetections: [DetectedSwing] = []
    @State private var previewDetection: DetectionPreview?
    @State private var showsAdvancedControls = false

    private let detectorSampleOptions = [2.0, 4.0, 8.0, 16.0]
    private let confirmationWaitOptions = [0.20, 0.28, 0.35, 0.55]

    private var sourceTiming: DebugReplaySourceTiming {
        get { DebugReplaySourceTiming(rawValue: debugReplaySourceTimingRaw) ?? .realtime }
        nonmutating set { debugReplaySourceTimingRaw = newValue.rawValue }
    }

    private var detectionMode: DebugReplayDetectionMode {
        get { DebugReplayDetectionMode(rawValue: debugReplayDetectionModeRaw) ?? .hybridImpact }
        nonmutating set { debugReplayDetectionModeRaw = newValue.rawValue }
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
            .onAppear {
                if let debugReplayModeRaw = ExperimentalDetectorDefaults.migrateIfNeeded().debugReplayModeRaw {
                    debugReplayDetectionModeRaw = debugReplayModeRaw
                }
            }
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
                    detectorSampleFPS: liveModelDetectorSampleFPS,
                    impactConfirmationPostRoll: hybridImpactConfirmationPostRoll,
                    detectionMode: detectionMode
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

            HStack(spacing: 6) {
                debugRowTitle("mode")
                ForEach(DebugReplayDetectionMode.allCases, id: \.rawValue) { mode in
                    debugChip(mode.label, isSelected: detectionMode == mode, minWidth: 36) {
                        detectionMode = mode
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

                Text("\(Int(liveModelDetectorSampleFPS))fps · \(String(format: "%.2fs", hybridImpactConfirmationPostRoll))")
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

                HStack(spacing: 6) {
                    debugRowTitle("confirm")
                    ForEach(confirmationWaitOptions, id: \.self) { wait in
                        debugChip(String(format: "%.2fs", wait), isSelected: hybridImpactConfirmationPostRoll == wait, minWidth: 44) {
                            hybridImpactConfirmationPostRoll = wait
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
                Text("\(model.detections.count) swings · \(model.candidateWindows.count) motion")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.64))
            }

            ProgressView(value: model.progress)
                .tint(.yellow)

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
                Text(model.candidateWindows.isEmpty ? "No motion candidates" : "\(model.candidateWindows.count) motion candidates")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.66))
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

            if !model.candidateWindows.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.candidateWindows.enumerated()), id: \.offset) { index, candidate in
                            Button {
                                if let videoURL = model.selectedVideoURL {
                                    previewDetection = DetectionPreview(
                                        videoURL: videoURL,
                                        detection: detectedSwing(from: candidate),
                                        index: index
                                    )
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Motion candidate \(index + 1)")
                                        .font(.caption.weight(.bold))
                                    Text("\(formatTime(candidate.start))-\(formatTime(candidate.end))")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundColor(.white.opacity(0.72))
                                    Text("ball \(Int(candidate.ballFrameRatio * 100))%")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(.white.opacity(0.66))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
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

    private func detectedSwing(from diagnostics: ObjectSwingWindowDiagnostics) -> DetectedSwing {
        DetectedSwing(
            startTime: CMTime(seconds: diagnostics.start, preferredTimescale: 600),
            endTime: CMTime(seconds: diagnostics.end, preferredTimescale: 600),
            confidence: min(0.95, max(0.20, diagnostics.peakMotion / 2.0))
        )
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
    @Published var detectorSourceTime = 0.0
    @Published var snapshot = LiveSwingDetectionSnapshot.idle
    @Published var detections: [DetectedSwing] = []
    @Published var candidateWindows: [ObjectSwingWindowDiagnostics] = []
    @Published var errorMessage: String?

    private var replayTask: Task<Void, Never>?
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

    var trimVideoSource: TrimVideoSource? {
        selectedVideoURL.map { .localFile(url: $0) }
    }

    func setSelectedVideo(_ url: URL) {
        cancelReplay()
        clearPlayerTimeObserver()
        let newPlayer = AVPlayer(url: url)
        selectedVideoURL = url
        player = newPlayer
        attachPlayerTimeObserver(to: newPlayer)
        progress = 0
        replaySourceTime = 0
        replayDuration = 0
        detectorSourceTime = 0
        snapshot = .idle
        detections = []
        candidateWindows = []
        errorMessage = nil
        lastProgressUpdateAt = .distantPast
    }

    func startReplay(
        speedMultiplier: Double,
        sourceTimeScale: Double,
        detectorSampleFPS: Double,
        impactConfirmationPostRoll: Double,
        detectionMode: DebugReplayDetectionMode
    ) {
        guard let selectedVideoURL else { return }

        cancelReplay()
        let configuration = ObjectSwingDetectorConfiguration.liveObjectModel(
            sampleFPS: detectorSampleFPS,
            timelineScale: 8.0,
            impactConfirmationPostRoll: impactConfirmationPostRoll
        )
        let control = DebugReplayControl()
        replayControl = control
        activePlaybackSpeedMultiplier = max(1, min(8, speedMultiplier))
        visibleReplayStarted = false
        playerHeldForDetectorCatchup = false
        isReplaying = true
        isPaused = false
        progress = 0
        replaySourceTime = 0
        replayDuration = 0
        detectorSourceTime = 0
        snapshot = LiveSwingDetectionSnapshot(
            status: .searchingBall,
            primaryMessage: "Preparing replay",
            detailMessage: "Opening video frames for detector replay.",
            targetSampleFPS: configuration.targetSampleFPS,
            detectorConfigurationName: configuration.name
        )
        detections = []
        candidateWindows = []
        errorMessage = nil
        lastProgressUpdateAt = .distantPast
        player?.seek(to: .zero)
        player?.pause()

        let stream = DebugLiveSwingReplayRunner.eventStream(
            for: selectedVideoURL,
            speedMultiplier: speedMultiplier,
            sourceTimeScale: sourceTimeScale,
            detectionMode: detectionMode,
            detectorConfiguration: configuration,
            control: control
        )

        replayTask = Task {
            for await event in stream {
                switch event {
                case .progress(let progressValue, let sourceTime, let sourceDuration, let newSnapshot, let currentDetections, let currentCandidates):
                    applyProgress(
                        progressValue,
                        sourceTime: sourceTime,
                        sourceDuration: sourceDuration,
                        snapshot: newSnapshot,
                        detections: currentDetections,
                        candidateWindows: currentCandidates
                    )
                case .finished(let result):
                    detections = result.detections
                    candidateWindows = result.candidateWindows
                    replayDuration = result.sourceDuration
                    replaySourceTime = result.sourceDuration
                    detectorSourceTime = result.sourceDuration
                    playerHeldForDetectorCatchup = false
                    progress = 1
                    isReplaying = false
                    isPaused = false
                    player?.pause()
                    let hasCandidates = !result.candidateWindows.isEmpty
                    snapshot = LiveSwingDetectionSnapshot(
                        status: result.detections.isEmpty ? .idle : .swingDetected,
                        primaryMessage: result.detections.isEmpty ? detectionMode.emptyMessage : "\(result.detections.count) swing\(result.detections.count == 1 ? "" : "s") detected",
                        detailMessage: result.detections.isEmpty
                            ? emptyReplayDetail(hasCandidates: hasCandidates, detectionMode: detectionMode)
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
        _ progressValue: Double,
        sourceTime: Double,
        sourceDuration: Double,
        snapshot newSnapshot: LiveSwingDetectionSnapshot,
        detections currentDetections: [DetectedSwing],
        candidateWindows currentCandidateWindows: [ObjectSwingWindowDiagnostics]
    ) {
        let now = Date()
        let detectionsChanged = currentDetections.count != detections.count
        let candidatesChanged = currentCandidateWindows.count != candidateWindows.count
        let statusChanged = newSnapshot.status != snapshot.status
        let enoughTimePassed = now.timeIntervalSince(lastProgressUpdateAt) >= 0.25

        detectorSourceTime = max(0, sourceTime)
        replayDuration = max(0, sourceDuration)
        if !visibleReplayStarted {
            startVisibleReplayIfNeeded()
        }
        syncVisiblePlaybackToDetector()
        if replaySourceTime <= 0 {
            progress = progressValue
        }

        guard detectionsChanged || candidatesChanged || statusChanged || enoughTimePassed else { return }

        snapshot = newSnapshot
        detections = currentDetections
        candidateWindows = currentCandidateWindows
        lastProgressUpdateAt = now
    }

    private func emptyReplayDetail(
        hasCandidates: Bool,
        detectionMode: DebugReplayDetectionMode
    ) -> String {
        switch detectionMode {
        case .contact:
            return hasCandidates ? "Motion candidates were rejected by contact validation." : "No motion candidates cleared the model gate."
        case .impact:
            return hasCandidates ? "Motion candidates did not produce a stable impact window." : "No motion candidates cleared the model gate."
        case .poseImpact:
            return hasCandidates ? "Impact windows were rejected by the pose gate." : "No motion candidates cleared the model gate."
        case .audioImpact:
            return hasCandidates ? "Impact windows did not align with an audio impact." : "No motion candidates cleared the model gate."
        case .hybridImpact:
            return hasCandidates ? "Impact windows were rejected by the hybrid pose/cadence gate." : "No motion candidates cleared the model gate."
        }
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
        replaySourceTime = 0
        progress = 0
        player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
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
    case progress(Double, Double, Double, LiveSwingDetectionSnapshot, [DetectedSwing], [ObjectSwingWindowDiagnostics])
    case finished(DebugReplayResult)
    case failed(String)
}

private enum DebugLiveSwingReplayRunner {
    static func eventStream(
        for url: URL,
        speedMultiplier: Double,
        sourceTimeScale: Double,
        detectionMode: DebugReplayDetectionMode,
        detectorConfiguration: ObjectSwingDetectorConfiguration,
        control: DebugReplayControl
    ) -> AsyncStream<DebugReplayEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let result = try await replay(
                        url: url,
                        speedMultiplier: speedMultiplier,
                        sourceTimeScale: sourceTimeScale,
                        detectionMode: detectionMode,
                        detectorConfiguration: detectorConfiguration,
                        control: control
                    ) { progress, sourceTime, sourceDuration, snapshot, detections, candidateWindows in
                        continuation.yield(.progress(progress, sourceTime, sourceDuration, snapshot, detections, candidateWindows))
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
        sourceTimeScale: Double,
        detectionMode: DebugReplayDetectionMode,
        detectorConfiguration: ObjectSwingDetectorConfiguration,
        control: DebugReplayControl,
        onProgress: @escaping (Double, Double, Double, LiveSwingDetectionSnapshot, [DetectedSwing], [ObjectSwingWindowDiagnostics]) -> Void
    ) async throws -> DebugReplayResult {
        let clampedSpeedMultiplier = max(1, min(8, speedMultiplier))
        let clampedSourceTimeScale = max(1, min(8, sourceTimeScale))
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

        let detector = LiveModelSwingDetector(configuration: detectorConfiguration)
        detector.reset(enabled: true, configuration: detectorConfiguration)
        let audioImpacts = detectionMode == .audioImpact
            ? (try? await audioImpactCandidates(in: asset)) ?? []
            : []
        let poseRequest = VNDetectHumanBodyPoseRequest()
        var lastPoseDetectorTime = -Double.greatestFiniteMagnitude
        var poseAttemptTimes: [Double] = []
        var poseFeatures: [DebugReplayPoseFeature] = []
        var poseProcessingTotalMS = 0.0
        var poseProcessingSampleCount = 0
        var lastPoseProcessingTimeMS = 0.0
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

            let detectorTime = videoRelativeTime / clampedSourceTimeScale
            guard detectorTime - lastProcessedDetectorTime >= detectorConfiguration.targetSampleInterval else { continue }

            let realElapsed = await control.activeElapsed(since: replayStartedAt)
            let targetReplayElapsed = videoRelativeTime / clampedSpeedMultiplier
            if targetReplayElapsed > realElapsed {
                let delay = targetReplayElapsed - realElapsed
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            lastProcessedDetectorTime = detectorTime
            lastDetectorTime = detectorTime

            let orientedImageSize = Self.orientedImageSize(from: sampleBuffer)
            var snapshot = detector.process(
                sampleBuffer: sampleBuffer,
                recordingTime: detectorTime,
                orientation: .up,
                orientedImageSize: orientedImageSize
            )
            if (detectionMode == .poseImpact || detectionMode == .hybridImpact),
               detectorTime - lastPoseDetectorTime >= max(0.12, detectorConfiguration.targetSampleInterval * 2.0) {
                lastPoseDetectorTime = detectorTime
                poseAttemptTimes.append(detectorTime)
                let poseStartedAt = Date()
                if let poseFeature = Self.poseFeature(
                    from: sampleBuffer,
                    at: detectorTime,
                    request: poseRequest
                ) {
                    poseFeatures.append(poseFeature)
                }
                lastPoseProcessingTimeMS = Date().timeIntervalSince(poseStartedAt) * 1_000
                poseProcessingTotalMS += lastPoseProcessingTimeMS
                poseProcessingSampleCount += 1
            }
            snapshot.poseObservationCount = poseFeatures.count
            snapshot.lastPoseProcessingTimeMS = lastPoseProcessingTimeMS
            if poseProcessingSampleCount > 0 {
                snapshot.averagePoseProcessingTimeMS = poseProcessingTotalMS / Double(poseProcessingSampleCount)
            }
            onProgress(
                min(1, max(0, videoRelativeTime / durationSeconds)),
                videoRelativeTime,
                durationSeconds,
                snapshot,
                selectedDetections(
                    mode: detectionMode,
                    detector: detector,
                    videoDuration: detectorTime,
                    declaredAt: detectorTime,
                    timeScale: clampedSourceTimeScale,
                    poseAttemptTimes: poseAttemptTimes,
                    poseFeatures: poseFeatures,
                    audioImpacts: audioImpacts
                ),
                sourceTimelineDiagnostics(
                    detector.currentCandidateDiagnostics(),
                    timeScale: clampedSourceTimeScale
                )
            )
        }

        if reader.status == .failed {
            throw reader.error ?? VideoTrimmer.TrimmerError.assetLoadFailed
        }

        let detections = detector.finish(recordingTime: lastDetectorTime)
        return DebugReplayResult(
            detections: selectedDetections(
                mode: detectionMode,
                detector: detector,
                fallbackContactDetections: detections,
                videoDuration: lastDetectorTime,
                declaredAt: lastDetectorTime,
                timeScale: clampedSourceTimeScale,
                poseAttemptTimes: poseAttemptTimes,
                poseFeatures: poseFeatures,
                audioImpacts: audioImpacts
            ),
            candidateWindows: sourceTimelineDiagnostics(
                detector.currentCandidateDiagnostics(),
                timeScale: clampedSourceTimeScale
            ),
            sourceDuration: durationSeconds
        )
    }

    private static func selectedDetections(
        mode: DebugReplayDetectionMode,
        detector: LiveModelSwingDetector,
        fallbackContactDetections: [DetectedSwing]? = nil,
        videoDuration: Double,
        declaredAt: Double,
        timeScale: Double,
        poseAttemptTimes: [Double],
        poseFeatures: [DebugReplayPoseFeature],
        audioImpacts: [DebugReplayAudioImpact]
    ) -> [DetectedSwing] {
        switch mode {
        case .contact:
            return sourceTimelineDetections(
                fallbackContactDetections ?? detector.currentDetections(),
                timeScale: timeScale
            )
        case .impact:
            return sourceTimelineImpactDetections(
                detector.currentImpactCenteredDetections(
                    videoDuration: videoDuration,
                    declaredAt: declaredAt
                ),
                timeScale: timeScale
            )
        case .audioImpact:
            return sourceTimelineAudioImpactDetections(
                modelCandidates: detector.currentImpactCenteredDetections(
                    videoDuration: videoDuration,
                    declaredAt: declaredAt
                ),
                audioImpacts: audioImpacts,
                declaredAt: declaredAt,
                timeScale: timeScale
            )
        case .poseImpact:
            return sourceTimelineImpactDetections(
                poseGatedImpactCandidates(
                    detector.currentImpactCenteredDetections(
                        videoDuration: videoDuration,
                        declaredAt: declaredAt
                    ),
                    attemptTimes: poseAttemptTimes,
                    poseFeatures: poseFeatures
                ),
                timeScale: timeScale
            )
        case .hybridImpact:
            return sourceTimelineImpactDetections(
                hybridImpactCandidates(
                    detector.currentImpactCenteredDetections(
                        videoDuration: videoDuration,
                        declaredAt: declaredAt
                    ),
                    attemptTimes: poseAttemptTimes,
                    poseFeatures: poseFeatures
                ),
                timeScale: timeScale
            )
        }
    }

    private static func sourceTimelineAudioImpactDetections(
        modelCandidates: [ObjectSwingImpactCandidate],
        audioImpacts: [DebugReplayAudioImpact],
        declaredAt: Double,
        timeScale: Double
    ) -> [DetectedSwing] {
        let declaredSourceTime = declaredAt * timeScale
        let sourceCandidates = modelCandidates.map { candidate in
            (
                start: candidate.start * timeScale,
                end: candidate.end * timeScale,
                impactTime: candidate.impactTime * timeScale,
                declaredAt: candidate.declaredAt * timeScale,
                confidence: candidate.confidence
            )
        }
        var detections: [DetectedSwing] = []

        for impact in audioImpacts where impact.time <= declaredSourceTime {
            guard let candidate = sourceCandidates.first(where: {
                impact.time >= $0.start - 0.4 && impact.time <= $0.end + 0.4
            }) else {
                continue
            }

            let confidence = min(0.96, max(candidate.confidence, 0.45 + impact.score / 20.0))
            let detection = DetectedSwing(
                startTime: CMTime(seconds: max(0, candidate.start), preferredTimescale: 600),
                endTime: CMTime(seconds: max(candidate.start, candidate.end), preferredTimescale: 600),
                confidence: confidence,
                impactTime: impact.time,
                declaredAt: max(impact.time, candidate.declaredAt)
            )
            if let last = detections.last,
               CMTimeGetSeconds(detection.startTime) <= CMTimeGetSeconds(last.endTime) + 0.35 {
                if detection.confidence > last.confidence {
                    detections[detections.count - 1] = detection
                }
            } else {
                detections.append(detection)
            }
        }

        return detections
    }

    private static func audioImpactCandidates(in asset: AVURLAsset) async throws -> [DebugReplayAudioImpact] {
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            return []
        }

        let sampleRate = 8_000
        let windowSampleCount = max(1, sampleRate / 50)
        let output = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        )
        output.alwaysCopiesSampleData = false

        let reader = try AVAssetReader(asset: asset)
        guard reader.canAdd(output) else { return [] }
        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? VideoTrimmer.TrimmerError.assetLoadFailed
        }

        var rmsWindows: [(time: Double, rms: Double)] = []
        var globalSampleIndex = 0
        var windowStartSample = 0
        var squaredSum = 0.0
        var samplesInWindow = 0

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            guard length >= 2 else { continue }

            var data = Data(count: length)
            let copied = data.withUnsafeMutableBytes { rawBuffer -> OSStatus in
                guard let baseAddress = rawBuffer.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
                return CMBlockBufferCopyDataBytes(
                    blockBuffer,
                    atOffset: 0,
                    dataLength: length,
                    destination: baseAddress
                )
            }
            guard copied == noErr else { continue }

            data.withUnsafeBytes { rawBuffer in
                var offset = 0
                while offset + 1 < rawBuffer.count {
                    if samplesInWindow == 0 {
                        windowStartSample = globalSampleIndex
                    }
                    let bitPattern = UInt16(rawBuffer[offset]) | (UInt16(rawBuffer[offset + 1]) << 8)
                    let sample = Double(Int16(bitPattern: bitPattern)) / 32768.0
                    squaredSum += sample * sample
                    samplesInWindow += 1
                    globalSampleIndex += 1

                    if samplesInWindow == windowSampleCount {
                        rmsWindows.append(
                            (
                                time: Double(windowStartSample) / Double(sampleRate),
                                rms: sqrt(squaredSum / Double(windowSampleCount))
                            )
                        )
                        squaredSum = 0
                        samplesInWindow = 0
                    }
                    offset += 2
                }
            }
        }

        if reader.status == .failed {
            throw reader.error ?? VideoTrimmer.TrimmerError.assetLoadFailed
        }

        guard rmsWindows.count >= 3 else { return [] }
        let halfWindow = 25
        let scores = rmsWindows.indices.map { index in
            let lower = max(0, index - halfWindow)
            let upper = min(rmsWindows.count - 1, index + halfWindow)
            let baseline = median(rmsWindows[lower...upper].map(\.rms))
            return rmsWindows[index].rms / (baseline + 0.00001)
        }

        var peaks: [DebugReplayAudioImpact] = []
        for index in 1..<(scores.count - 1) {
            guard scores[index] >= scores[index - 1],
                  scores[index] >= scores[index + 1],
                  scores[index] > 2.5
            else {
                continue
            }
            peaks.append(DebugReplayAudioImpact(time: rmsWindows[index].time, score: scores[index]))
        }

        let strongest = peaks.sorted { $0.score > $1.score }
        var kept: [DebugReplayAudioImpact] = []
        for peak in strongest {
            guard kept.allSatisfy({ abs($0.time - peak.time) > 0.35 }) else { continue }
            kept.append(peak)
            if kept.count >= 32 { break }
        }
        return kept.sorted { $0.time < $1.time }
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func poseGatedImpactCandidates(
        _ detections: [ObjectSwingImpactCandidate],
        attemptTimes: [Double],
        poseFeatures: [DebugReplayPoseFeature]
    ) -> [ObjectSwingImpactCandidate] {
        ObjectSwingImpactSelector.poseGatedImpactCandidates(
            detections,
            attemptTimes: attemptTimes,
            poseFeatures: poseFeatures
        )
    }

    private static func hybridImpactCandidates(
        _ detections: [ObjectSwingImpactCandidate],
        attemptTimes: [Double],
        poseFeatures: [DebugReplayPoseFeature]
    ) -> [ObjectSwingImpactCandidate] {
        ObjectSwingImpactSelector.hybridImpactCandidates(
            detections,
            attemptTimes: attemptTimes,
            poseFeatures: poseFeatures
        )
    }

    private static func poseFeature(
        from sampleBuffer: CMSampleBuffer,
        at time: Double,
        request: VNDetectHumanBodyPoseRequest
    ) -> DebugReplayPoseFeature? {
        ObjectSwingImpactSelector.poseFeature(
            from: sampleBuffer,
            at: time,
            orientation: .up,
            request: request
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

    private static func sourceTimelineDetections(
        _ detections: [DetectedSwing],
        timeScale: Double
    ) -> [DetectedSwing] {
        detections.map { detection in
            DetectedSwing(
                startTime: CMTimeMultiplyByFloat64(detection.startTime, multiplier: timeScale),
                endTime: CMTimeMultiplyByFloat64(detection.endTime, multiplier: timeScale),
                confidence: detection.confidence,
                impactTime: detection.impactTime.map { $0 * timeScale },
                declaredAt: detection.declaredAt.map { $0 * timeScale }
            )
        }
    }

    private static func sourceTimelineImpactDetections(
        _ detections: [ObjectSwingImpactCandidate],
        timeScale: Double
    ) -> [DetectedSwing] {
        detections.map { detection in
            DetectedSwing(
                startTime: CMTime(seconds: detection.start * timeScale, preferredTimescale: 600),
                endTime: CMTime(seconds: detection.end * timeScale, preferredTimescale: 600),
                confidence: detection.confidence,
                impactTime: detection.impactTime * timeScale,
                declaredAt: detection.declaredAt * timeScale
            )
        }
    }

    private static func sourceTimelineDiagnostics(
        _ diagnostics: [ObjectSwingWindowDiagnostics],
        timeScale: Double
    ) -> [ObjectSwingWindowDiagnostics] {
        diagnostics.map { diagnostic in
            ObjectSwingWindowDiagnostics(
                start: diagnostic.start * timeScale,
                end: diagnostic.end * timeScale,
                peakMotion: diagnostic.peakMotion,
                strongMotionFrameCount: diagnostic.strongMotionFrameCount,
                meanClubMotion: diagnostic.meanClubMotion,
                clubPathSpan: diagnostic.clubPathSpan,
                clubTopY: diagnostic.clubTopY,
                clubFrameRatio: diagnostic.clubFrameRatio,
                ballFrameRatio: diagnostic.ballFrameRatio
            )
        }
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
