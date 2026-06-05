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
- Local manual analysis drawings: [ManualAnnotationStore.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/Models/ManualAnnotationStore.swift)

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
- Multi-select can export selected swings by copying the underlying Photos video resources into a temporary SwingCoach export folder, adding one `metadata.json` manifest with app-level swing metadata, and presenting the iOS share sheet for AirDrop/Files transfer. The manifest is for dataset traceability and is shared alongside the selected videos, not embedded into each movie file.
- Playback with loading/error states and a shared in-frame scrubber plus gesture-driven transport on the video surface.
- Export/playback utilities integrated through app sheets.

## 2. Capture Tab

File: [CaptureView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/CaptureView.swift)

Implemented feature set:
- AVFoundation recording session with video input and microphone input when available, so newly captured clips can carry audio for export and detector experiments.
- Capture mode support:
  - `30fps HD`
  - `60fps HD`
  - `120fps HD`
  - `240fps HD`
- Capture workflow support:
  - `Manual`: existing record/stop flow. Stopping a recording opens Trim with any V2 ranges collected live during that recording.
  - `Auto`: selecting Auto arms capture immediately while the Capture tab is visible. The app feeds the live camera stream to `SwingDetectorV2` continuously, keeps an overlapping rolling video buffer with `AVAssetWriter`, and exports accepted detector swing windows directly to Photos and `SwingLibrary` without a separate start/stop button or Trim handoff. Auto pauses when leaving Capture or switching back to Manual.
- Runtime mode switching without full session teardown.
- Tap-to-focus and exposure targeting.
- Model swing detection is experimental and can be turned off from Library > Experiments. When enabled, capture samples camera frames during recording and runs `SwingDetectorV2` with the bundled YOLO11n/Core ML golf-object model on-device while the video is still being captured.
- When model detection is off, capture still records normally and the trim editor opens without generated ranges so the user can mark clips manually.
- During recording, the capture badge reflects the V2 state: address search/lock, swing evidence, detected swings, sampled-frame processing cost, effective sampled FPS, and camera-to-analysis lag. The final timing snapshot is passed into Trim for captured recordings so the golfer can inspect detector throughput after stopping. The older Vision/bright-blob and legacy hybrid detector paths are not used for production trim ranges.
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
- [ModelBackedSwingDetector.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/Models/ModelBackedSwingDetector.swift)
- [GolfObjectDetector.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/Models/GolfObjectDetector.swift)
- [SwingObjectsYOLO11n.mlpackage](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/MLModels/SwingObjectsYOLO11n.mlpackage)

Implemented feature set:
- Timeline opens immediately with placeholder/progressive thumbnail loading.
- In-memory thumbnail caching for reopened trim sessions on the same source file.
- Library imports hand trim a lightweight Photos-backed source first, then load a fast preview asset in-editor and defer high-quality asset resolution until export.
- High-fps capture timelines display slow-playback timing while keeping selection mapped to the original source frames.
- Start/end range selection for clip creation.
- Captured recordings pass the V2 detections collected during recording into Trim, so candidate swing windows are preselected as soon as the editor opens. Imported/library videos run a local `SwingDetectorV2AssetDetector` post-pass against the preview asset when Trim opens, using the same V2 core as capture. Neither path calls the backend.
- Auto-detected clips can be reviewed one at a time by tapping their thumbnail, adjusted with the existing start/end trim handles, updated in place, or discarded with the clip delete control. Auto-detected clip thumbnails preserve detector impact/declaration timestamps and show `imp +Xs / end +Ys`, the delay from estimated impact and returned clip end to the moment the detector declared that swing. Captured recordings also show the final detector summary under the timeline, including detected count, effective sample FPS, model/pose processing cost, and final analysis lag.
- Captured recordings use the configurable V2 low sample rate (`8 fps` by default, adjustable in Experiments). V2 raises to its burst rate during startup grace and active swing evidence, then drops back after confirmation, timeout, or rejection. The live badge performance line is `target/effective fps · model last/avg ms · lag ms`; sustained effective FPS far below target or lag above a few hundred milliseconds means the device is not keeping up in real time.
- Live capture currently keeps recording stable by letting AVFoundation discard late video-data frames when the detector queue falls behind. This avoids long post-stop catch-up delays, but it is a known detector gap because dropped frames are not state-aware. A future V2 scheduler should use `analysisLagMS` to reduce idle/cooldown sampling pressure before sacrificing swing/impact burst evidence.
- The older Vision-only post-pass, live Vision/bright-blob detector, and legacy model-backed contact/impact/hybrid detector modes are not used as production fallbacks for trim ranges. If the model is missing or fails, captured recordings open Trim without generated ranges after the live badge reports the issue; imported/library videos report model detection unavailable in Trim and leave manual trim controls available.
- Audio and Apple Vision pose remain research/debug inputs described in detector experiment notes; they are not part of the current V2 app-wired capture path.
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
- For backend results that include `annotated_video.base_url` and `annotated_video.tracks_url`, the annotated video card plays the clean base video and draws/toggles skeleton, reference-line, swing-path, club-plane, ball-contact, phase-marker, confidence, speed, and generic guide overlays over playback. Generic guide toggles currently include shaft checkpoints, clubhead path, setup geometry, head reference, hip depth, hand depth, lead-arm plane, and takeaway checkpoint. If no base video is available, it falls back to the flattened annotated MP4. The selected overlay state is preserved when the annotated player opens full-screen.
- Annotated playback includes a local Manual layer and canvas mode for self-analysis. Tools are line, arrow, freehand, rectangle, circle, text label, eraser, undo, and clear; controls use icon buttons, color swatches, and a full-swing/moment scope selector. Drawings are stored as normalized video coordinates with timestamp/scope/color/stroke/tool metadata in app Documents through `ManualAnnotationStore`; they are not synced to the backend.
- Show swing metadata and local analysis status inside the original swing disclosure.
- Run the current R2-backed analysis flow for a single swing, with retry controls reserved for failed analysis attempts.
- Attach completed analysis to the swing through `AnalysisLibrary`.
- Render annotated video, metrics, coach notes, and recommendations with the shared [AnalysisResultView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/AnalysisResultView.swift).

## 6. Replay Debug Tab

File: [DebugReplayView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/DebugReplayView.swift)

Implemented feature set:
- DEBUG-only tab for home/range development of live swing detection, controlled from Library > Experiments.
- Selects a video from Photos, copies it into temporary app storage, and displays the video as the primary replay surface using a custom player layer so iOS default playback controls do not overlap detector instrumentation.
- Replays decoded frames through the same YOLO/Core ML `SwingDetectorV2` used by capture, on a paced clock so the selected video behaves like a substitute camera feed instead of an offline batch job.
- Uses one in-screen footage selector for replay timing: `30/1x`, `120/4x`, or `240/8x`. This simultaneously sets the visible playback speed and the detector source-time scale, so a 240-fps slow-motion range session is replayed at `8x` and fed to the detector as real-time swing motion.
- Keeps detector low sample-rate selection (`2`, `4`, `8`, or `16` YOLO samples per real-time second) under an Advanced disclosure. V2 owns burst sampling internally.
- Shows visible replay source time as `elapsed/total` seconds and detected-swing count as an overlay on the video while replay runs. The timer/progress is tied to the visible `AVPlayer`, while detector events still use the same source-video timestamp range shown on detected chips. If visible playback gets more than a few source seconds ahead of the detector reader, Replay Debug pauses playback until the detector catches up, so detections do not appear minutes after the user watched the swing.
- Replay Debug includes a source-time scrubber before replay starts. Moving it to a later timestamp starts both detector processing and visible playback from that source time, which makes late-session failures debuggable without waiting through the full recording.
- Shows stable V2 evidence fields in the replay overlay: target/effective sample FPS, processed frames, average model processing time, current motion score, current club-motion score, current ball score, and lag/rejection only when those fields are available.
- The replay pause control pauses both visible video playback and detector pacing.
- Detector overlay updates are throttled so fast state churn does not flicker continuously during long range videos.
- Detected swing chips can be tapped to open a looping preview sheet for that exact timestamp range while the main replay/detector continues behind the sheet. Detected swing chips show confidence plus `imp +Xs / end +Ys` when the detector can report when that window was declared; slow-motion sources display these as real-time detector delays rather than stretched source-timeline delays.
- Opens trim with replay-detected timestamps preselected and disables the trim view's post-open detector scan, matching the intended capture path where detections are already known when recording stops.
- This tool is not a production import path. It exists to tune and validate live detector behavior with saved long-session videos without repeatedly recording fresh device-camera sessions.

Local detector fixture workflow:
- Keep source fixture videos in ignored `.detectorTestV3/`; keep generated evaluator binaries and reports in ignored `.videos/`.
- V3 test metadata lives in `detector_workbench/validation/labels/detector_test_v3_labels.json`. Impact labels are rough one-second source-timeline buckets from QuickTime review; slow-motion real-time equivalents are source seconds divided by each video's `source_time_scale`.
- Run `python3 detector_workbench/validation/evaluate_swing_detector_v2.py --build --only test2` for a quick V2 compile/smoke test, or omit `--only` to run the fixture suite.
- Add `--contact-sheets` when debugging a miss or false positive; the V2 workflow pairs candidate traces with annotated sampled-frame sheets.
- Run `python3 detector_workbench/validation/evaluate_detector_video_data.py --force` to evaluate every exported clip in `detector_model/video_data`. The harness reads `detector_model/video_data/metadata.json`, infers source timing from visible duration, and writes `.videos/detector_video_data_eval/results/detector_video_data_report.json`. Review overrides live in `detector_workbench/validation/labels/detector_video_data_labels.json`; `swingcoach_043_dtl_20260321_221006.mp4` is excluded because it ends at impact without enough post-impact ball-departure evidence for V2 acceptance.
- Current V2 acceptance relies on addressed-ball lock, club-sweep evidence, target-patch departure, and low strike-area ball-inventory change. Startup grace handles clips or recordings that begin after address or during takeaway, but the normal address-lock path still runs from the first frame and remains authoritative when it succeeds.
- Run `python3 detector_workbench/validation/analyze_audio_impacts.py` to rescore audio transients on the current `test4` fixture. Audio remains diagnostic, not production capture behavior.
- Historical old Vision/bright-blob and legacy model-backed detector harness findings remain in `docs/EXPERIMENT_SWING_DETECTOR.md`; current reruns should use the V2 commands above.

## 7. Experimental Settings

File: [ExperimentalSettingsView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/ExperimentalSettingsView.swift)

Implemented feature set:
- Library toolbar gear opens Experiments.
- Toggle model swing detection on/off for capture recordings and imported Trim sessions.
- Configure the YOLO/Core ML V2 low sample rate used by capture, imported Trim detection, and Replay Debug.
- Toggle the DEBUG Replay Debug tab on/off.
- Replay Debug visible playback speed and source timing are configured inside the Replay Debug tab, not in the shared Experiments screen.
- Capture records microphone audio when the session can add the audio input, but live audio-fused capture detection is still experimental. Audio fusion is currently exposed in Replay Debug and the local evaluator, not as the production capture trim path.

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
3. `POST /analysis-runs` with `video_key` + `vantage`
4. Stream `GET /analysis-runs/{run_id}/events` as Server-Sent Events for stage/progress updates
5. Fetch `GET /analysis-runs/{run_id}` when the stream reports success, then decode `result` into frontend `AnalysisResponse`

The legacy synchronous `POST /analyze` endpoint remains available, but the app uses async runs for real analysis so the request no longer has to stay open through the full model/render/upload pipeline.
If a selected backend does not yet expose `/analysis-runs` and returns `404` or `405`, the client falls back to legacy `POST /analyze` for rollout compatibility.

In DEBUG builds, Library > Experiments exposes backend controls:
- `Backend target`: `Local` (`http://127.0.0.1:8000`), `Deployed` (`https://swingcoach-api.ruari.dev`), or `Custom`.
- `Mock analysis`: when enabled the app still exports/uploads the swing but calls `POST /mock/analyze`; when disabled it creates a real async analysis run.

DEBUG defaults are `Local` and real analysis so local backend changes can be tested without deploying the VPS. The local target works directly from Simulator. On a physical iPhone, use `Custom` with the Mac's LAN URL, for example `http://192.168.1.23:8000`.

Release builds use the deployed backend and real async analysis runs.

Current frontend `AnalysisResponse` expectation:
- `analysis_id: String`
- `summary: String`
- `metrics: [{key, name, value}]`
- `annotated_video: {key, url, base_key?, base_url?, tracks_key?, tracks_url?, layers?}?`
- `drills: [{title, summary}]`

`annotated_video.layers` is metadata for the rendered annotation layers and should list every server-backed toggle layer, including dynamic layers such as `speed` when samples exist. `base_url` points to a clean dense-window video for true client-side toggles, while `url` remains the flattened annotated MP4 fallback. `tracks_url` points to normalized JSON overlay tracks; saved analysis results persist the video key/URL, base key/URL, track key/URL, and layer metadata. The current track decoder supports `skeleton`, `reference_lines`, `club_plane`, `ball_contact`, `swing_path`, top-level `phase_markers`, top-level `confidence_evidence`, `speed`, top-level `guide_layers`, and per-frame `layers.guides`.

`layers.guides` is a generic shape layer in normalized video space. Supported guide shape kinds are `line`, `arrow`, `polyline`, `rectangle`, `circle`, and `label`; shapes are filtered by their `layer` field against the same toggle set as the legacy overlay layers. When both a generic `club_plane` or `clubhead_path` guide and the legacy track are present, the client prefers the guide drawing to avoid duplicate overlays.

## Known Gaps and Risks

1. Async analysis lifecycle
- Run status is currently server-memory-backed. If the backend restarts while a run is active, the app will lose that run and should show the backend error.
- SSE is one-way progress only. Cancellation, resumable background processing, and persisted run history are future work.

2. Annotated video playback
- UI embeds the annotated video in the Coach result when available.
- Saved analyses persist artifact keys and refresh signed video and track URLs through `POST /artifact-url` when stale.
- Track overlays are a first pass. They cover skeleton, reference lines, club plane, ball/contact evidence, swing path, phase markers, confidence evidence, speed, and generic guide shapes, but not club masks, clubface orientation, ball-flight tracking, force/pressure claims, or 3D replay controls yet.

3. Trim-to-analyze handoff
- The capture trim footer currently shows a single primary action.
- Automatic analyze handoff after clip export is intentionally left as future work.

4. Environment setup
- DEBUG backend target and mock/real analysis mode are configurable from Experiments. Release remains fixed to the deployed backend until a production environment selector or build configuration is needed.

5. Swing auto-detection validation
- On-device detection is intentionally conservative and editable, but needs device/video validation with real range sessions before it should be treated as a high-confidence practice-swing filter.
- The live prototype's ball detector is heuristic-only: pose-derived ROI + compact bright blob stability + disappearance/movement near predicted impact. It should be tested heavily on irons, mats, grass, range balls in the background, glare, and partial ball occlusion.

## Recommended Next Frontend Documentation Additions

1. Add API migration checklist once async analysis-run persistence/cancellation is designed.
2. Add screen-by-screen state diagrams for capture -> trim -> analyze.
3. Add QA matrix (permissions, iCloud assets, missing assets, offline behavior).
