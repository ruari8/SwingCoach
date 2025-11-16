# Getting Started — AI Golf Coach (iOS v0)

This guide walks you from a new app to a working foundation: import/play videos, show a live camera preview, access frames for analysis, and run Apple's on‑device 2D body pose on throttled frames. It complements the full roadmap in `../ai.plan.md`.

## Tooling
- Use Xcode to create the project, manage signing, run on device/simulator, and use Instruments/Previews.
- Open the same folder in Cursor to edit Swift. Build/run still happens in Xcode.

## Prerequisites
- Xcode 15+
- iOS 17+ target; test on an A14+ device for smooth on‑device ML
- Apple ID signed into Xcode (free developer account works for device runs)

## Step 1 — Create the Xcode project
1. Xcode → File → New → Project… → App
2. Interface: SwiftUI. Language: Swift. Minimum iOS: 17.
3. Product Name: e.g., `SwingCoach`
4. Add these Info keys ("Privacy — ..." descriptions):
   - `NSCameraUsageDescription`
   - `NSMicrophoneUsageDescription`
   - `NSPhotoLibraryUsageDescription`
   - `NSPhotoLibraryAddUsageDescription`

Acceptance: Project builds and runs (blank screen).

## Step 2 — Scaffold two screens with a tab bar
Create a simple two‑tab shell: Library (import/play video) and Capture (camera preview).

```swift
import SwiftUI

struct AppRootView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "film") }
            CaptureView()
                .tabItem { Label("Capture", systemImage: "camera") }
        }
    }
}
```

Set `AppRootView()` as the initial content in your `...App.swift`.

Acceptance: Two tabs switch views.

## Step 3 — Import a video and play it
Start with import/playback so you have real assets to test later.

```swift
import SwiftUI
import PhotosUI
import AVKit

struct LibraryView: View {
    @State private var item: PhotosPickerItem?
    @State private var player: AVPlayer?

    var body: some View {
        VStack {
            PhotosPicker("Import Video", selection: $item, matching: .videos)
                .padding()
            if let player { VideoPlayer(player: player) }
        }
        .onChange(of: item) { _, newItem in
            Task {
                if let newItem, let data = try? await newItem.loadTransferable(type: Data.self) {
                    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                        .appendingPathComponent(UUID().uuidString + ".mov")
                    try? data.write(to: tmp)
                    player = AVPlayer(url: tmp)
                }
            }
        }
    }
}
```

Acceptance: You can import a clip from Photos and play it.

## Step 4 — Live camera preview (no slo‑mo yet)
Wire `AVCaptureSession` and show a preview.

```swift
import SwiftUI
import AVFoundation

final class CameraSession: NSObject, ObservableObject {
    let session = AVCaptureSession()

    func start() {
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { session.commitConfiguration(); return }
        session.addInput(input)
        session.commitConfiguration()
        session.startRunning()
    }

    func stop() { session.stopRunning() }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer)?.frame = uiView.bounds
    }
}

struct CaptureView: View {
    @StateObject private var camera = CameraSession()
    var body: some View {
        CameraPreview(session: camera.session)
            .onAppear { camera.start() }
            .onDisappear { camera.stop() }
    }
}
```

Acceptance: Live camera image renders on device.

## Step 5 — Enable high‑FPS (slo‑mo) capture
Most devices support 120 fps at 1080p or 240 fps at 720p. Pick the highest format that meets your target fps.

```swift
import AVFoundation

func configureHighFPS(on device: AVCaptureDevice, targetFPS: Double = 120) {
    guard let best = device.formats
        .filter { format in
            format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= targetFPS }
        }
        .sorted(by: { $0.formatDescription.dimensions.height > $1.formatDescription.dimensions.height })
        .first else { return }

    do {
        try device.lockForConfiguration()
        device.activeFormat = best
        let duration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        device.unlockForConfiguration()
    } catch { }
}
```

Call after creating the device, before `commitConfiguration()`.

Acceptance: Log `device.activeFormat` and frame durations to confirm.

## Step 6 — Access frames for analysis
Add `AVCaptureVideoDataOutput` with a sample buffer delegate and throttle callbacks (e.g., analyze every 2–3 frames).

```swift
final class CameraSession: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera.frames")

    func start() {
        session.beginConfiguration()
        // configure input as in Step 4...
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { session.commitConfiguration(); return }
        session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // TODO: throttle and enqueue for analysis
        _ = CMSampleBufferGetImageBuffer(sampleBuffer)
    }
}
```

Acceptance: Simple counter/log shows steady callbacks.

## Step 7 — Run Vision human body pose (on‑device)
Start on single frames, then move to throttled live frames.

```swift
import Vision

final class PoseEstimator {
    private let request = VNDetectHumanBodyPoseRequest()
    private let handlerQueue = DispatchQueue(label: "pose.handler")

    func estimate(from pixelBuffer: CVPixelBuffer, completion: @escaping ([VNRecognizedPointsObservation]) -> Void) {
        handlerQueue.async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([self.request])
                let observations = (self.request.results as? [VNRecognizedPointsObservation]) ?? []
                completion(observations)
            } catch {
                completion([])
            }
        }
    }
}
```

Acceptance: For a throttled frame, you receive 0–1 observations with recognized points.

## Step 8 — Overlays and annotations (v0)
Draw user‑placed guides (head box, plane line, ball/target line) over the preview or video using `ZStack` and simple `Path`/`Canvas`. Keep it manual first; automation comes in v1.

Acceptance: Lines/rects render in expected positions while previewing or playing a clip.

## DTL vs Face‑On (early handling)
- Let users pick vantage (DTL or FO) at capture; show a simple horizon/target guide suitable to the choice.
- Persist vantage on the asset so later metrics use the correct thresholds.

## Next steps (beyond v0 foundation)
- Event detection (address/top/impact/finish) from keypoint sequences
- Core metrics per vantage (head/pelvis sway, spine/shoulder tilt, shaft lean, plane deviation)
- Rule‑based coaching: map metric ranges to concise cues + drills

See `../ai.plan.md` for the full roadmap, hybrid backend addition (v1.5), and the v2 3D sandbox vision.
