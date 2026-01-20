//
//  CaptureView.swift
//  SwingCoach
//
//  Created by Ruari Craig on 01/11/2025.
//

import SwiftUI
import AVKit
import Combine
import AVFoundation
import Photos

enum SloMoMode {
    case standard    // 120 fps @ 1080p
    case ultra       // 240 fps @ 1080p
    case ballTracer  // 60 fps @ 4K (for future shot tracer feature)
    
    var targetFPS: Double {
        switch self {
        case .standard: return 120.0
        case .ultra: return 240.0
        case .ballTracer: return 60.0
        }
    }
    
    var targetResolution: (width: Int32, height: Int32) {
        switch self {
        case .standard, .ultra:
            return (1920, 1080)
        case .ballTracer:
            return (3840, 2160)
        }
    }
    
    var displayName: String {
        switch self {
        case .standard: return "120fps HD"
        case .ultra: return "240fps HD"
        case .ballTracer: return "60fps 4K"
        }
    }
    
    /// Playback rate to achieve slow-motion (recorded FPS / playback FPS)
    var slowMotionRate: Float {
        Float(30.0 / targetFPS)
    }
}

final class CameraSession: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera.session.queue")
    private let movieOutput = AVCaptureMovieFileOutput()
    @Published var lastRecordingURL: URL?
    @Published var captureMode: SloMoMode = .ultra  // Default to 240 fps
    
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
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        
        // Configure high FPS AFTER input/output are added to the session
        // Otherwise the session may override format settings when input is added
        configureHighFPS(device: device, mode: captureMode)
        
        session.commitConfiguration()
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
        // Capture the mode at recording start for correct playback rate
        recordedMode = captureMode
        
        queue.async {
            guard !self.movieOutput.isRecording else { return }
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

    private static func tempURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
        let filename = UUID().uuidString + ".mov"
        return directory.appendingPathComponent(filename)
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            guard error == nil else {
                self.lastRecordingURL = nil
                return
            }
            self.lastRecordingURL = outputFileURL
        }
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
    @State private var isRecording = false
    @State private var player: AVPlayer?
    @State private var currentRecordingURL: URL?
    
    // Focus indicator state
    @State private var focusPoint: CGPoint? = nil
    @State private var showFocusIndicator = false
    
    // Recording timer
    @State private var recordingStartTime: Date? = nil
    @State private var recordingDuration: TimeInterval = 0
    @State private var timerCancellable: AnyCancellable? = nil
    
    // Trim view presentation
    @State private var showTrimView = false
    @State private var analyzeAfterExport = false

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
                if let player {
                    Color.black.opacity(0.4)
                    VideoPlayer(player: player)
                        .onTapGesture {
                            self.player = nil
                        }
                    VStack {
                        HStack {
                            // Save button
                            Button {
                                saveToPhotoLibrary()
                            } label: {
                                Image(systemName: "square.and.arrow.down.fill")
                                    .resizable()
                                    .frame(width: 28, height: 34)
                                    .foregroundColor(.white)
                                    .shadow(radius: 4)
                            }
                            .padding()
                            
                            Spacer()
                            
                            // Close button
                            Button {
                                clearCurrentRecording()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .resizable()
                                    .frame(width: 36, height: 36)
                                    .foregroundColor(.white)
                                    .shadow(radius: 4)
                            }
                            .padding()
                        }
                        Spacer()
                        
                        // Trim button (bottom center)
                        Button {
                            showTrimView = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "scissors")
                                Text("Trim Swings")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(Color.yellow)
                            .cornerRadius(25)
                            .shadow(radius: 4)
                        }
                        .padding(.bottom, 30)
                    }
                }

                // Camera controls overlay (when not playing back)
                if player == nil {
                    VStack {
                        // Top controls: FPS toggle and recording timer
                        HStack {
                            // FPS toggle (left)
                            Button {
                                toggleFPSMode()
                            } label: {
                                Text(camera.captureMode == .standard ? "120" : "240")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(.yellow)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.black.opacity(0.5))
                                    )
                            }
                            .disabled(isRecording)
                            .opacity(isRecording ? 0.5 : 1.0)
                            
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
                            
                            // Placeholder for symmetry
                            Color.clear
                                .frame(width: 50, height: 30)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        
                        Spacer()
                        
                        // Bottom: Record button
                        RecordButton(isRecording: isRecording) {
                            toggleRecording()
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
        }
        .onAppear {
            camera.start()
        }
        .onDisappear {
            camera.stop()
            timerCancellable?.cancel()
        }
        .onReceive(camera.$lastRecordingURL) { url in
            guard let url else { return }
            
            isRecording = false
            stopRecordingTimer()
            
            // Use original video directly - no re-encoding needed!
            // Small async delay to let the camera UI settle before showing video
            Task { @MainActor in
                let newPlayer = AVPlayer(url: url)
                // Play at slow-mo rate (e.g., 0.125 for 240fps = 8x slower)
                newPlayer.rate = camera.recordedMode.slowMotionRate
                player = newPlayer
                currentRecordingURL = url
            }
        }
        .fullScreenCover(isPresented: $showTrimView) {
            if let url = currentRecordingURL {
                TrimView(
                    sourceURL: url,
                    playbackRate: camera.recordedMode.slowMotionRate,
                    onComplete: { clips, exportedURLs in
                        // Handle exported clips
                        print("✅ Exported \(clips.count) clips:")
                        for (clip, url) in zip(clips, exportedURLs) {
                            print("   - \(clip.vantage.shortName) \(clip.durationFormatted): \(url.lastPathComponent)")
                        }
                        showTrimView = false
                        
                        // If analyze was requested, get the newly saved swings and send to coach
                        if analyzeAfterExport, let onAnalyze = onAnalyzeSwings {
                            // Get the most recent swings (the ones we just added)
                            let recentSwings = Array(SwingLibrary.shared.swings.prefix(clips.count))
                            onAnalyze(recentSwings)
                        }
                        analyzeAfterExport = false
                        clearCurrentRecording()
                    },
                    onCancel: {
                        showTrimView = false
                        analyzeAfterExport = false
                    },
                    onExportAndAnalyze: onAnalyzeSwings != nil ? { clips in
                        analyzeAfterExport = true
                    } : nil
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
            camera.stopRecording()
            stopRecordingTimer()
        } else {
            player = nil
            camera.startRecording()
            startRecordingTimer()
        }
        currentRecordingURL = nil
        isRecording.toggle()
    }
    
    private func toggleFPSMode() {
        let newMode: SloMoMode = camera.captureMode == .standard ? .ultra : .standard
        camera.switchMode(to: newMode)
    }

    private func clearCurrentRecording() {
        player?.pause()
        player = nil
        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentRecordingURL = nil
        camera.lastRecordingURL = nil
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

#Preview {
    CaptureView(onAnalyzeSwings: nil)
}

