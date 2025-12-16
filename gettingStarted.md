# Getting Started — AI Golf Coach (iOS v0)

This guide walks you from a new app to a working foundation: import/play videos, show a live camera preview, access frames for analysis, and run Apple's on‑device 2D body pose on throttled frames. It complements the full roadmap in `ai.plan.md`.

For detailed code implementations, refer to the Swift files in the SwingCoach project.

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

Create an `AppRootView` with a `TabView` containing:
- LibraryView with "film" icon
- CaptureView with "camera" icon

Set `AppRootView()` as the initial content in your `SwingCoachApp.swift`.

Acceptance: Two tabs switch views.

## Step 3 — Import a video and play it
Start with import/playback so you have real assets to test later.

Implement `LibraryView` with:
- `PhotosPicker` for video selection from Photos library
- `AVPlayer` and `VideoPlayer` for playback
- Load selected video data and write to temp directory
- Create AVPlayer instance with video URL

Key imports: SwiftUI, PhotosUI, AVKit

Acceptance: You can import a clip from Photos and play it.

## Step 4 — Live camera preview (no slo‑mo yet)
Wire `AVCaptureSession` and show a preview.

Create `CameraSession` class:
- Initialize `AVCaptureSession` with `.high` preset
- Add back camera device as input
- Start/stop session methods

Create `CameraPreview` UIViewRepresentable:
- Wrap `AVCaptureVideoPreviewLayer`
- Set video gravity to `.resizeAspectFill`
- Update layer frame on layout changes

Wire up in `CaptureView`:
- Use `@StateObject` for camera session
- Start session on appear, stop on disappear

Key imports: SwiftUI, AVFoundation

Acceptance: Live camera image renders on device.

## Step 5 — Enable high‑FPS (slo‑mo) capture
Most devices support 120 fps at 1080p or 240 fps at 720p. Pick the highest format that meets your target fps.

Create a `configureHighFPS` function:
- Filter device formats by target FPS capability
- Sort by resolution (highest first)
- Lock device for configuration
- Set active format and frame durations
- Use `CMTime` for precise frame timing

Call this function after creating the camera device, before calling `session.commitConfiguration()`.

Target 120 fps as a good balance between smoothness and device compatibility.

Acceptance: Log `device.activeFormat` and frame durations to confirm high FPS mode.

## Step 6 — Access frames for analysis
Add `AVCaptureVideoDataOutput` with a sample buffer delegate and throttle callbacks (e.g., analyze every 2–3 frames).

Extend `CameraSession` to implement `AVCaptureVideoDataOutputSampleBufferDelegate`:
- Create dedicated dispatch queue for frame processing
- Add `AVCaptureVideoDataOutput` to session
- Enable `alwaysDiscardsLateVideoFrames` to maintain real-time performance
- Implement `captureOutput` delegate method
- Extract `CVPixelBuffer` from `CMSampleBuffer`

Add throttling logic to analyze every 2-3 frames (reduces CPU load while maintaining smooth analysis).

Acceptance: Simple counter/log shows steady frame callbacks.

## Step 7 — Run Vision human body pose (on‑device)
Start on single frames, then move to throttled live frames.

Create `PoseEstimator` class:
- Use `VNDetectHumanBodyPoseRequest` from Vision framework
- Create dedicated handler queue for processing
- Implement `estimate` method that takes `CVPixelBuffer`
- Create `VNImageRequestHandler` and perform request
- Extract `VNRecognizedPointsObservation` results
- Return results via completion handler

Each observation contains body keypoints (joints) with confidence scores.

Key import: Vision

Acceptance: For a throttled frame, you receive 0–1 observations with recognized body keypoints.

## Step 8 — Overlays and annotations (v0)
Draw user‑placed guides (head box, plane line, ball/target line) over the preview or video.

Use SwiftUI drawing tools:
- `ZStack` to layer annotations over video
- `Path` or `Canvas` for drawing lines and shapes
- Store annotation coordinates relative to video dimensions
- Allow user tap/drag gestures to position guides

Keep it manual first (user positions everything); automation comes in v1.

Common annotations:
- Head box (rectangle tracking head position)
- Swing plane line (shows ideal club path)
- Ball position marker
- Target line (alignment reference)

Acceptance: Lines/rects render in expected positions while previewing or playing a clip.

## DTL vs Face‑On (early handling)
- Let users pick vantage (DTL or FO) at capture; show a simple horizon/target guide suitable to the choice.
- Persist vantage on the asset so later metrics use the correct thresholds.

## Next steps (beyond v0 foundation)
- Event detection (address/top/impact/finish) from keypoint sequences
- Core metrics per vantage (head/pelvis sway, spine/shoulder tilt, shaft lean, plane deviation)
- Rule‑based coaching: map metric ranges to concise cues + drills

See `ai.plan.md` for the full roadmap, hybrid backend addition (v1.5), and the v2 3D sandbox vision.
