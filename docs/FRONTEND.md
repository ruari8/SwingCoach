# Frontend Documentation (iOS)

## Scope

The frontend is a SwiftUI app in [SwingCoach/](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach) with three production tabs:
- Library
- Capture
- Coach (analysis)

DEBUG builds also include a Replay Debug tab for detector development.

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
- Live DTL-focused on-device capture guard using Vision body pose sampling to warn when the golfer is not framed for analysis. The first pass checks head, hands, feet, body size, and edge margins without blocking recording.
- Capture setup includes an on-preview DTL framing guide and optional spoken guidance for solo setup when the phone screen is not visible from the hitting position.
- Live auto swing-detection prototype runs while recording. It samples the camera feed, uses Vision body pose to estimate takeaway/swing timing, searches a pose-derived address ROI for a stable compact bright ball candidate, and treats ball disappearance/movement in the predicted impact window as hit evidence.
- During recording, the capture badge switches from framing readiness to live auto-detection state (`Finding ball`, `Ball locked`, `Swing started`, `Impact detected`, or detected count).
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
- Captured recordings pass live-detected swing timestamps into trim immediately; captured trim does not run a post-stop scan before showing the editor.
- Imported/library videos can still use on-device Vision body-pose swing detection against the local preview asset when trim opens. Candidate full-swing windows are preselected as clips without calling the backend.
- Auto-detected clips can be reviewed one at a time by tapping their thumbnail, adjusted with the existing start/end trim handles, updated in place, or discarded with the clip delete control.
- The first-pass imported-video detector uses conservative hand-motion, pose-coverage, body-stability, and duration heuristics to reject low-confidence or practice-like motion. The live capture prototype adds lightweight ball-movement evidence, but it is not yet validated enough to guarantee practice-swing rejection.
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
- Show swing metadata and local analysis status inside the original swing disclosure.
- Run the current R2-backed analysis flow for a single swing, with retry controls reserved for failed analysis attempts.
- Attach completed analysis to the swing through `AnalysisLibrary`.
- Render annotated video, metrics, coach notes, and recommendations with the shared [AnalysisResultView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/AnalysisResultView.swift).

## 6. Replay Debug Tab

File: [DebugReplayView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/DebugReplayView.swift)

Implemented feature set:
- DEBUG-only tab for home/range development of live swing detection.
- Selects a video from Photos, copies it into temporary app storage, and replays decoded frames through `LiveSwingDetector` as if they were arriving from the camera preview output.
- Shows replay progress, detector state, ball-lock/movement state, and detected swing windows while the replay runs.
- Opens trim with replay-detected timestamps preselected and disables the trim view's post-open detector scan, matching the intended capture path where detections are already known when recording stops.
- This tool is not a production import path. It exists to tune and validate live detector behavior with saved long-session videos without repeatedly recording fresh device-camera sessions.

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
- `annotated_video: {key, url}?`
- `drills: [{title, summary}]`

## Known Gaps and Risks

1. Async analysis lifecycle
- `/analyze` is still synchronous while the analysis pipeline can be expensive.
- A future `AnalysisRun` status model should let the app submit work, leave processing, and poll for completion.

2. Annotated video playback
- UI embeds the annotated video in the Coach result when available.
- Saved analyses persist artifact keys and refresh signed video URLs through `POST /artifact-url` when stale.

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
