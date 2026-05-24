# Frontend Documentation (iOS)

## Scope

The frontend is a SwiftUI app in [SwingCoach/](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach) with three production tabs:
- Library
- Capture
- Coach (analysis)

DEBUG builds can show a Replay Debug tab for detector development. The tab is controlled by the in-app Experiments settings.

Primary app root: [AppRootView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/AppRootView.swift)

## App Architecture

### Entry and Navigation

- App entry: [SwingCoachApp.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/SwingCoachApp.swift)
- Tab coordinator: [AppRootView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/AppRootView.swift)
- Shared handoff state: `swingsToAnalyze` (passed from Library/Capture into Coach tab)

### Core Domains

- Capture and camera session: [CaptureView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/CaptureView.swift)
- Library and playback/import: [LibraryView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/LibraryView.swift)
- Trim workflow: [TrimView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/TrimView/TrimView.swift)
- Analysis UX: [AnalyseView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/AnalyseView.swift)
- DEBUG replay harness: [DebugReplayView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/DebugReplayView.swift)
- Experimental settings: [ExperimentalSettingsView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/ExperimentalSettingsView.swift)
- Swing detail workspace: [SwingDetailView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/SwingDetailView.swift)
- Shared analysis result rendering: [AnalysisResultView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/AnalysisResultView.swift)
- API client: [SwingCoachAPI.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/Models/SwingCoachAPI.swift)
- Persistence: [SwingLibrary.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/Models/SwingLibrary.swift)

## Feature Inventory

## 1. Library Tab

File: [LibraryView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/LibraryView.swift)

Implemented feature set:
- Import videos from Photos (`PHPicker` flow with progress/cancel UI).
- Imported videos open trim immediately from the selected Photos asset identifier instead of blocking on an up-front full-video import step.
- Library shows explicit read-access guidance for `notDetermined` / `limited` / denied states instead of relying on the system's automatic limited-library alert.
- Full `readWrite` Photos access uses the fast `PHAsset` import path; limited access now also attempts the same path for already-authorized items before falling back.
- Limited-access imports present an explicit “continue / choose allowed videos / open settings” decision before the picker so the user understands why some videos reopen quickly and others do not.
- Limited-access fallback first tries an in-place picker file handoff for immediate trim editing, then copies into app temp storage only if the picker cannot provide a durable URL directly.
- Library asset validation only runs with full Photos access so limited mode cannot incorrectly prune saved swings that are merely outside the current allowed set.
- The Photos picker now fully dismisses before the trim editor is presented, avoiding a blank transition caused by overlapping sheet/full-screen presentations.
- Launch trim flow for imported source video.
- Persist swing metadata and thumbnails via `SwingLibrary`.
- Grid browsing with vantage filtering.
- Swing cards open a swing detail workspace instead of immediately presenting full-screen playback.
- Analyzed swings show a status indicator on their library card.
- Multi-select for batch analyze and batch delete (library-only delete, does not remove Photos asset).
- Playback with loading/error states and a shared in-frame scrubber plus gesture-driven transport on the video surface.
- Export/playback utilities integrated through app sheets.

## 2. Capture Tab

File: [CaptureView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/CaptureView.swift)

Implemented feature set:
- AVFoundation recording session.
- Capture mode support:
  - `120fps HD`
  - `240fps HD`
  - `60fps 4K` (ball-tracer future mode scaffold)
- Runtime mode switching without full session teardown.
- Tap-to-focus and exposure targeting.
- Live auto swing-detection is experimental and can be turned off from Library > Experiments. When enabled, it samples the camera feed, scores multiple Vision body-pose observations to keep tracking the primary golfer, smooths Vision hand-speed jitter, uses a rolling address-to-takeaway state machine, searches a pose-derived address ROI for a stable compact bright ball candidate, and treats ball disappearance, ball-region luma change, or strong full-swing pose motion as swing evidence with lower confidence when impact is not confirmed.
- When live auto-detection is off, capture still records normally and the trim editor opens without generated ranges so the user can mark clips manually.
- When live auto-detection is enabled but no live swing windows are found during recording, captured trim runs the local on-device post-pass as a fallback before asking the user to mark ranges manually.
- During recording, the capture badge shows live auto-detection state (`Finding ball`, `Ball locked`, `Swing started`, `Impact detected`, or detected count).
- Recording state handling with immediate post-stop playback of the captured high-fps asset.
- Stopping a new recording opens the trim editor automatically instead of requiring the post-stop scissors action.
- Active recording disables the iOS idle timer so solo range sessions do not Auto-Lock while the golfer walks into frame, then restores the prior idle-timer state after stop, error, or leaving capture.
- Post-stop review now uses the app's own playback chrome instead of the default `VideoPlayer` controls, with the scrubber integrated into the video frame, tap-to-play/pause, hold-left/hold-right stepping, and capture trim exposed as a floating scissors action.
- Slow-motion rendering is deferred until explicit clip export instead of blocking the stop-record action.
- Integration path into library and optional analyze handoff.

## 3. Trim Workflow

Files:
- [TrimView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/TrimView/TrimView.swift)
- [ThumbnailTimeline.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/TrimView/ThumbnailTimeline.swift)
- [VideoTrimmer.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/Models/VideoTrimmer.swift)
- [OnDeviceSwingDetector.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/Models/OnDeviceSwingDetector.swift)
- [LiveSwingDetector.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/Models/LiveSwingDetector.swift)

Implemented feature set:
- Timeline opens immediately with placeholder/progressive thumbnail loading.
- In-memory thumbnail caching for reopened trim sessions on the same source file.
- Library imports hand trim a lightweight Photos-backed source first, then load a fast preview asset in-editor and defer high-quality asset resolution until export.
- High-fps capture timelines display slow-playback timing while keeping selection mapped to the original source frames.
- Start/end range selection for clip creation.
- Captured recordings pass live-detected swing timestamps into trim immediately. If live detection is enabled and returns no ranges, captured trim runs the local on-device detector as a fallback; if the experiment is disabled, captured trim opens for manual marking only.
- Imported/library videos can still use on-device Vision body-pose swing detection against the local preview asset when trim opens. Candidate full-swing windows are preselected as clips without calling the backend.
- Auto-detected clips can be reviewed one at a time by tapping their thumbnail, adjusted with the existing start/end trim handles, updated in place, or discarded with the clip delete control.
- The imported-video detector uses adaptive hand-speed thresholds plus hand-travel, pose-coverage, body-stability, and duration heuristics to find candidate full-swing windows without calling the backend. The live capture/debug detector adds lightweight primary-golfer tracking and ball-region impact evidence, but the feature remains experimental and editable because messy range footage can still produce likely-swing detections without confirmed ball contact.
- When no clip ranges are marked, the footer offers an explicit full-video path so already-trimmed imports can be added as-is; Photos-backed imports reuse the existing asset instead of creating a duplicate.
- Multi-clip extraction from a long source video.
- MVP clip export defaults to down-the-line capture; face-on remains in the data model but is not exposed as an equal capture path in the trim header.
- Press-and-hold frame stepping with acceleration for faster long scrubs.
- Overview-only timeline for long-session trimming, with no separate precision toggle UI.
- A single primary export action in the footer.
- Export to MP4 clips for downstream storage/analysis, with captured high-fps sessions rendered to true slow-motion during export.
- Newly exported clips enter the library with an immediate frame thumbnail, then refresh from Photos in the background once the asset poster frame is available.
- Library swing thumbnails stay visually clean, with only selection and analyzed-status overlays.

## 4. Coach Tab (Analysis)

File: [AnalyseView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/AnalyseView.swift)

Implemented feature set:
- Queue multiple swings for analysis.
- Show lightweight queue status (`pending`, `analyzing`, `failed`) without stacking full analysis cards.
- Show recent completed analyses as dashboard rows that link back to the swing detail workspace.
- Mark analyzed swings in local library.

## 5. Swing Detail

File: [SwingDetailView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/SwingDetailView.swift)

Implemented feature set:
- Treat a saved swing as the primary product object.
- Show the original swing as a collapsed thumbnail disclosure by default, with playback and metadata available after expansion.
- Display original and annotated swing playback using the shared playback chrome, including timeline, compact cycle-through playback speed control, and full-screen viewing.
- For backend results that include `annotated_video.base_url` and `annotated_video.tracks_url`, the annotated video card plays the clean base video and draws/toggles skeleton, reference-line, swing-path, phase-marker, confidence, and speed overlays over playback. If no base video is available, it falls back to the flattened annotated MP4. The selected overlay state is preserved when the annotated player opens full-screen.
- Show swing metadata and local analysis status inside the original swing disclosure.
- Run the current R2-backed analysis flow for a single swing, with retry controls reserved for failed analysis attempts.
- Attach completed analysis to the swing through `AnalysisLibrary`.
- Render annotated video, metrics, coach notes, and recommendations with the shared [AnalysisResultView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/AnalysisResultView.swift).

## 6. Replay Debug Tab

File: [DebugReplayView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/DebugReplayView.swift)

Implemented feature set:
- DEBUG-only tab for home/range development of live swing detection, controlled from Library > Experiments.
- Selects a video from Photos, copies it into temporary app storage, and displays the video as the primary replay surface using a custom player layer so iOS default playback controls do not overlap detector instrumentation.
- Replays decoded frames through `LiveSwingDetector` on a paced clock so the selected video behaves like a substitute camera feed instead of an offline batch job.
- Supports in-screen configurable replay speed (`1x`, `2x`, `4x`, `8x`; default `8x`) for faster long-session review while detector timestamps remain on the selected video's source timeline.
- Shows replay progress, detector state, ball-lock/movement state, and detected swing windows as an overlay on the video while replay runs.
- Shows detector evidence fields in the replay overlay: Vision pose count, current/peak hand speed, normalized hand travel, stable setup duration, ball-candidate score, ball-region luma shift, and the latest rejection reason.
- The replay pause control pauses both visible video playback and detector pacing.
- Detector overlay updates are throttled so fast state churn does not flicker continuously during long range videos.
- Detected swing chips can be tapped to open a looping preview sheet for that detected window while the main replay/detector continues behind the sheet.
- Opens trim with replay-detected timestamps preselected and disables the trim view's post-open detector scan, matching the intended capture path where detections are already known when recording stops.
- This tool is not a production import path. It exists to tune and validate live detector behavior with saved long-session videos without repeatedly recording fresh device-camera sessions.

Local detector fixture workflow:
- Keep heavy videos and generated clips in ignored `.videos/`.
- Compile the local evaluator with `xcrun swiftc -parse-as-library -framework AVFoundation -framework Vision -framework CoreGraphics -framework ImageIO SwingCoach/Models/OnDeviceSwingDetector.swift tools/evaluate_on_device_detector.swift -o .videos/bin/evaluate_on_device_detector`.
- Compile the live-detector comparison harness with `xcrun swiftc -parse-as-library -framework AVFoundation -framework Vision -framework CoreGraphics -framework CoreVideo -framework ImageIO SwingCoach/Models/OnDeviceSwingDetector.swift SwingCoach/Models/LiveSwingDetector.swift tools/evaluate_live_detector.swift -o .videos/bin/evaluate_live_detector`.
- Store rough labels beside the local video, for example `.videos/IMG_2592.labels.json`.
- Run `python3 tools/evaluate_detector_fixtures.py --limit 3` to trim labelled windows, execute the same post-pass detector, and write `.videos/detector_eval/results/detector_fixture_report.json`.
- Use `--evaluator .videos/bin/evaluate_live_detector --output-dir .videos/live_detector_eval` to score the live state machine against the same fixtures. This is a comparison harness, not a production import path.
- The fixture report includes positive-window recall, detections outside the positive labels, and sampled negative-gap false positives. Practice swings in negative gaps are expected to expose the limitation of pose-only detection; imported-video detection still needs a validated ball/contact cue before it can reliably reject practice swings.

## 7. Experimental Settings

File: [ExperimentalSettingsView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/ExperimentalSettingsView.swift)

Implemented feature set:
- Library toolbar gear opens Experiments.
- Toggle live auto swing detection on/off for capture recordings.
- Toggle the DEBUG Replay Debug tab on/off.
- Configure Replay Debug speed multiplier for normal-speed and slow-motion source videos.

## Data and Models

### Swing metadata

- `SavedSwing` model: [SwingLibrary.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/Models/SwingLibrary.swift)
- Fields include: `photoAssetID`, `vantage`, `duration`, timestamps, notes, analyzed flag.
- Persisted to app Documents as `swing_library.json`.

### Vantage model

- Enum in [SwingClip.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/Models/SwingClip.swift)
- Values: `DTL`, `Face-On`

## Backend Integration Contract

File: [SwingCoachAPI.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/Models/SwingCoachAPI.swift)

Current flow:
1. `GET /upload-url`
2. Upload MP4 directly to R2 pre-signed URL
3. `POST /analyze` with `video_key` + `vantage`
4. Decode analysis result into frontend `AnalysisResponse`

In DEBUG builds, `SwingCoachAPI.useMockAnalysis` is enabled. The app still exports the swing and uploads it to R2, then calls `POST /mock/analyze` instead of the heavy pipeline. The mock endpoint verifies the uploaded R2 object and returns the same lightweight response with a signed dummy annotated-video URL.

Current frontend `AnalysisResponse` expectation:
- `analysis_id: String`
- `summary: String`
- `metrics: [{key, name, value}]`
- `annotated_video: {key, url, base_key?, base_url?, tracks_key?, tracks_url?, layers?}?`
- `drills: [{title, summary}]`

`annotated_video.layers` is metadata for the rendered annotation layers and should list every server-backed toggle layer, including dynamic layers such as `speed` when samples exist. `base_url` points to a clean dense-window video for true client-side toggles, while `url` remains the flattened annotated MP4 fallback. `tracks_url` points to normalized JSON overlay tracks; saved analysis results persist the video key/URL, base key/URL, track key/URL, and layer metadata. The current track decoder supports `skeleton`, `reference_lines`, `club_plane`, `ball_contact`, `swing_path`, top-level `phase_markers`, top-level `confidence_evidence`, and `speed`.

## Known Gaps and Risks

1. Async analysis lifecycle
- `/analyze` is still synchronous while the analysis pipeline can be expensive.
- A future `AnalysisRun` status model should let the app submit work, leave processing, and poll for completion.

2. Annotated video playback
- UI embeds the annotated video in the Coach result when available.
- Saved analyses persist artifact keys and refresh signed video and track URLs through `POST /artifact-url` when stale.
- Track overlays are a first pass. They cover skeleton, reference lines, club plane, ball/contact evidence, swing path, phase markers, confidence evidence, and speed, but not club masks, ball-flight tracking, or 3D replay controls yet.

3. Trim-to-analyze handoff
- The capture trim footer currently shows a single primary action.
- Automatic analyze handoff after clip export is intentionally left as future work.

4. Environment setup
- `baseURL` in [SwingCoachAPI.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/Models/SwingCoachAPI.swift) is still hardcoded and should be environment-configurable.

5. Swing auto-detection validation
- On-device detection is intentionally conservative and editable, but needs device/video validation with real range sessions before it should be treated as a high-confidence practice-swing filter.
- The live prototype's ball detector is heuristic-only: pose-derived ROI + compact bright blob stability + disappearance/movement near predicted impact. It should be tested heavily on irons, mats, grass, range balls in the background, glare, and partial ball occlusion.

## Recommended Next Frontend Documentation Additions

1. Add API migration checklist once `/analyze` response mapping is updated.
2. Add screen-by-screen state diagrams for capture -> trim -> analyze.
3. Add QA matrix (permissions, iCloud assets, missing assets, offline behavior).
