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
- Multi-select can export selected swings by copying the underlying Photos video resources into a temporary SwingCoach export folder, adding one `metadata.json` manifest with app-level swing metadata, and presenting the iOS share sheet for AirDrop/Files transfer. The manifest is for dataset traceability and is shared alongside the selected videos, not embedded into each movie file.
- Playback with loading/error states and a shared in-frame scrubber plus gesture-driven transport on the video surface.
- Export/playback utilities integrated through app sheets.

## 2. Capture Tab

File: [CaptureView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/CaptureView.swift)

Implemented feature set:
- AVFoundation recording session with video input and microphone input when available, so newly captured clips can carry audio for export and detector experiments.
- Capture mode support:
  - `120fps HD`
  - `240fps HD`
  - `60fps 4K` (ball-tracer future mode scaffold)
- Runtime mode switching without full session teardown.
- Tap-to-focus and exposure targeting.
- Model swing-detection is experimental and can be turned off from Library > Experiments. When enabled, capture samples camera frames during recording and runs the bundled YOLO11n/Core ML golf-object model on-device while the video is still being captured.
- Library > Experiments can choose the capture detector mode. New/old-default installs now migrate to `Hybrid` once because it is the best current live detector on the labelled V3 fixture set and exported library clips:
  - `Contact`: strict model/contact validation. This is the lower-recall, lower-noise path.
  - `Impact`: experimental fixed-window impact detection. This is higher-recall and noisier, intended for range testing.
  - `Hybrid`: experimental fixed-window impact detection with sparse Apple Vision pose gating and duplicate suppression. This is the best current local validation strategy, but it is heavier than model-only capture.
- When model detection is off, capture still records normally and the trim editor opens without generated ranges so the user can mark clips manually.
- During recording, the capture badge reflects the live model state: scanning, club/ball visible, swing motion, detected swings, sampled-frame processing cost, effective sampled FPS, sparse pose cost, and camera-to-analysis lag. In `Hybrid` mode, the badge recomputes the shared hybrid selector on each sampled frame and shows hybrid detection count, latest impact time, impact-to-declaration delay, returned-window-end delay, and sparse pose sample count. The final timing snapshot is also passed into Trim for captured recordings so the golfer can inspect detector throughput after stopping. The older Vision/bright-blob live fallback is not used for production trim ranges.
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
- Captured recordings pass the live model detections collected during recording into Trim, so candidate swing windows are preselected as soon as the editor opens. Imported/library videos run a local model-backed post-pass against the preview asset when Trim opens, using the same Experiments detector mode/sample-rate/confirmation-wait settings as capture (`Hybrid` by default). Neither path calls the backend.
- Auto-detected clips can be reviewed one at a time by tapping their thumbnail, adjusted with the existing start/end trim handles, updated in place, or discarded with the clip delete control. Auto-detected clip thumbnails preserve detector impact/declaration timestamps and show `imp +Xs / end +Ys`, the delay from estimated impact and returned clip end to the moment the detector declared that swing. Captured recordings also show the final detector summary under the timeline, including detected count, effective sample FPS, model/pose processing cost, and final analysis lag.
- Captured recordings use the configurable live detector sample rate (`8 fps` by default, adjustable in Experiments). `16 fps` remains selectable for debugging, but the default is capped at `8 fps` because higher live sample rates can fall behind real-time capture on target hardware. The default `Hybrid` capture mode samples Apple Vision pose sparsely while recording and applies the shared hybrid pose/cadence gate to model-confirmed addressed-ball impact events when recording stops. Confirmed impact events wait for the configurable impact-confirmation time (`0.20s` by default, adjustable in Experiments and Replay Debug), then keep the fixed pre/post impact trim window for review. The live badge performance line is `target/effective fps · model last/avg ms · pose last/avg ms · lag ms`; sustained effective FPS far below target or lag above a few hundred milliseconds means the device is not keeping up in real time. `Contact` proposes object/motion windows, confirms them through lower-strike-area ball disappearance plus club-motion/path-span guards, estimates impact from sustained ball disappearance, and trims the suggested clip around that impact estimate. `Impact` now starts from addressed-ball disappearance rather than motion peaks, then requires club contact at that anchor and local strike motion. Imported/library post-pass detection follows the selected Experiments mode.
- The older Vision-only post-pass and live Vision/bright-blob detector are not used as production fallbacks for trim ranges. If the model is missing or fails, captured recordings open Trim without generated ranges after the live badge reports the issue; imported/library videos report model detection unavailable in Trim and leave manual trim controls available.
- Audio confirmation remains a research/debug detector input exposed in Replay Debug and the local evaluator; it is not part of the current production capture path. Apple Vision pose is now used by the experimental `Hybrid` capture mode.
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
- Replays decoded frames through the same YOLO/Core ML `LiveModelSwingDetector` used by capture, on a paced clock so the selected video behaves like a substitute camera feed instead of an offline batch job.
- Uses one in-screen footage selector for replay timing: `30/1x`, `120/4x`, or `240/8x`. This simultaneously sets the visible playback speed and the detector source-time scale, so a 240-fps slow-motion range session is replayed at `8x` and fed to the detector as real-time swing motion.
- Keeps detector sample-rate selection (`2`, `4`, `8`, or `16` YOLO samples per real-time second) and impact-confirmation wait under an Advanced disclosure. The current default is `8fps / 0.20s`.
- Supports an in-screen detector mode selector:
  - `contact`: current strict model/contact detector. Motion candidates must pass ball-disappearance/contact validation before they become detections.
  - `impact`: experimental addressed-ball impact detector. It starts from sustained ball departure, then requires club contact at that same anchor and local strike motion before emitting a fixed pre/post impact clip window. If ball/contact evidence cannot be proven, it emits nothing.
  - `pose`: experimental Apple Vision-gated impact detector. Replay samples Vision body pose sparsely and only keeps impact windows with plausible primary-golfer hand motion/address-to-finish change.
  - `audio`: experimental audio-gated impact detector. Replay extracts audio transients from the selected asset, then only keeps model impact windows once a matching impact-like audio peak has occurred on the replay timeline. This simulates real-time gating but still does an up-front debug audio scan.
  - `hybrid`: experimental pose/cadence impact detector. It starts from pose-gated impact windows, suppresses nearby weaker pose duplicates, and has a narrow low-pose/cadence fallback for real swings where Apple Vision sees very little hand movement. The same decision layer is available as a live capture mode.
- Shows visible replay source time as `elapsed/total` seconds, detected-swing count, motion-candidate count, and separate motion-candidate windows as an overlay on the video while replay runs. The timer/progress is tied to the visible `AVPlayer`, while detector events still use the same source-video timestamp range shown on detected chips. If visible playback gets more than a few source seconds ahead of the detector reader, Replay Debug pauses playback until the detector catches up, so detections do not appear minutes after the user watched the swing. The older percent-only progress label, fast-changing detector status copy, and contact-only Ball/Still chips are hidden because they were misleading in Hybrid mode.
- Replay Debug labels these as motion candidates because they are broad model/motion windows, not confirmed impact candidates. Impact mode can confirm a swing even when the motion-candidate list is empty, and motion candidates can appear when no addressed-ball impact was found.
- Shows stable detector evidence fields in the replay overlay: target/effective sample FPS, processed frames, average model processing time, average pose processing time, current motion score, current club-motion score, current ball score, and lag/rejection only when those fields are available.
- The replay pause control pauses both visible video playback and detector pacing.
- Detector overlay updates are throttled so fast state churn does not flicker continuously during long range videos.
- Detected swing chips and motion-candidate chips can be tapped to open a looping preview sheet for that exact timestamp range while the main replay/detector continues behind the sheet. Detected swing chips show confidence plus `imp +Xs / end +Ys` when the detector can report when that window was declared; slow-motion sources display these as real-time detector delays rather than stretched source-timeline delays.
- Opens trim with replay-detected timestamps preselected and disables the trim view's post-open detector scan, matching the intended capture path where detections are already known when recording stops.
- This tool is not a production import path. It exists to tune and validate live detector behavior with saved long-session videos without repeatedly recording fresh device-camera sessions.

Local detector fixture workflow:
- Keep source fixture videos in ignored `.detectorTestV3/`; keep generated evaluator binaries and reports in ignored `.videos/`.
- Compile the YOLO live-detector comparison harness with `xcrun swiftc -parse-as-library -framework AVFoundation -framework CoreML -framework Vision -framework CoreGraphics -framework CoreVideo -framework ImageIO SwingCoach/Models/OnDeviceSwingDetector.swift SwingCoach/Models/LiveSwingDetector.swift SwingCoach/Models/GolfObjectDetector.swift SwingCoach/Models/ModelBackedSwingDetector.swift tools/evaluate_live_model_detector.swift -o .videos/bin/evaluate_live_model_detector`.
- V3 test metadata lives in `tools/detector_test_v3_labels.json`. Impact labels are rough one-second source-timeline buckets from QuickTime review; slow-motion real-time equivalents are source seconds divided by each video's `source_time_scale`.
- Run `python3 tools/evaluate_detector_test_v3_performance.py --reuse-reports` to rescore existing V3 detector outputs against the current labels without rerunning Core ML, or omit `--reuse-reports` to run the app-style Core ML evaluator.
- The live model evaluator now accepts optional compute units (`all`, `cpuOnly`, `cpuAndGPU`, or `cpuAndNeuralEngine`) and a detector-time declaration polling interval after the impact confirmation wait. It uses the same oriented video-composition reader path as Replay Debug, reports decoded versus processed frames, model pipeline ms/sample, Vision pose ms/sample, effective detector FPS, detector throughput FPS, wall-clock elapsed, realtime ratio, lag growth samples, and `declaredAt - impactTime`. Hybrid evaluation keeps pose timestamps in detector time until after the shared pose/cadence selector runs, then maps accepted windows back to source-video time for reporting, matching Replay Debug and capture.
- Evaluator JSON now includes `impactDebugReports`, which explains why each tracked ball anchor did or did not become an impact: no anchor, no sustained departure, pending confirmation wait, insufficient post frames, unconfirmed ball departure, no club contact, low local strike motion, low window motion, or confirmed.
- Live model sampling allows a 1ms timestamp tolerance at the target interval so fractional source rates such as `1.5fps` for `12fps / 8x` slow-motion tests do not accidentally undersample every other frame because of timestamp rounding.
- Run `python3 tools/evaluate_test5_performance.py --input proxy --compute cpuAndNeuralEngine --sample-fps 8 --declaration-poll-interval 0.20` to reproduce the targeted `.detectorTestV3/test5` performance experiment. The script builds a source-rate proxy matching the requested detector sample rate so the run measures detector throughput instead of decoding every unused frame in a stretched slow-motion file.
- The V3 performance runner evaluates clips shortest-to-longest by actual video duration, subtracts a small end-time margin for the app-style video-composition reader, and keeps iteration fast on the small fixtures before the long range sessions.
- In the narrowed V3 iteration, `test1`, `test3`, and `test6` are siloed under `.detectorTestV3/.silo` and excluded from `tools/detector_test_v3_labels.json`. `test1` and `test3` are yellow-ball object-model coverage cases; `test6` is an Instagram screen recording with poor framing and UI components covering or contaminating ball evidence. At `8fps / 8x / 0.20s` with CPU/Neural Engine compute, the active hybrid V3 set returns the expected counts for `test2` (`1`), `test4` (`18`), `test5` (`4`), and `test7` (`11`). `test4` broad-window scoring is `18/18` with zero false positives.
- Run `python3 tools/evaluate_detector_video_data.py --force` to evaluate every exported clip in `detector_model/video_data` with the live model detector. The harness reads `detector_model/video_data/metadata.json`, infers source timing from visible duration (`<=3.75s` as real time, `<=10.5s` as 4x/120fps slow motion, longer clips as 8x/240fps slow motion), uses `8fps / 8x / 0.20s` by default, and writes `.videos/detector_video_data_eval/results/detector_video_data_report.json`. Review overrides live in `tools/detector_video_data_labels.json`; files not listed there default to one expected swing, while `swingcoach_009_dtl_20260401_143143.mp4` is labelled as a zero-swing negative after manual review showed only a standing golfer and foreground gesture/occlusion. The current final run reports `59/59` expected outcomes, zero missed swings, and zero extra detections at the live default sample rate.
- The impact-centered detector now treats addressed-ball departure plus strike attribution as the primary proof of impact. Direct club/ball contact must also have strike-like local motion and a reliable pre-impact address-ball presence, which rejects address/clubhead-covering occlusions and extreme edge/UI ball candidates while still allowing valid strike-area balls close to the right side of the frame. If exact club contact is missed at a lower sample rate, a very clean lower-strike ball departure can still pass when the returned impact window has coherent swing-shaped club/motion evidence. Persisted impact candidates are also merged by overlapping returned windows so the same swing cannot survive as two nearby detector-time peaks.
- Hybrid impact selection keeps the original early-impact suppression for longer recordings, but relaxes it for short/truncated evaluated clips where the observed detector duration is at most `3.6s`. If a detected ball departure is close to the trim end, the impact confirmer can use the post-impact samples that actually exist instead of requiring a full post-roll frame count. If a short clipped video has strong club/motion evidence but no reliable ball anchor or post-impact ball proof, a low-confidence motion-backed impact candidate can be emitted; this fallback is gated to short clips touching a trim boundary and now requires stronger club path and mean club motion so non-swing foreground movement does not pass.
- On the app-style original `test5` replay at `8fps`, `240/8x`, `0.20s`, and CPU/Neural Engine compute, impact mode returns exactly four windows near `204s`, `764.03s`, `1245.10s`, and `1723.13s`. The `1109-1126s` address-cover and `1475-1492s` dispenser/non-address-ball false positives are rejected by the stricter strike-motion gate.
- Live confirmed impact events are persisted as they are found, separately from the rolling sampled-frame feature buffer. This prevents long recordings from losing early events when old frame features age out before the user stops recording.
- Each impact refresh now evaluates recent ball anchors and can emit every confirmed disappearance for a reused address location, instead of only the first disappearance for that anchor. This prevents later swings in a long range session from being suppressed when the golfer repeatedly addresses balls in roughly the same image region.
- For normal-speed test files, pass source timing `1` and detector timeline scale `8`, for example `.videos/bin/evaluate_live_model_detector <video> SwingCoach/MLModels/SwingObjectsYOLO11n.mlpackage 16 1 18000 "" 2 0.05 0.32 0.58 8`. The evaluator output includes both contact-confirmed detections and motion-candidate diagnostics.
- Run `python3 tools/analyze_audio_impacts.py` to rescore audio transients on the current `test4` fixture. Audio remains diagnostic, not production capture behavior.
- Historical V2 and old Vision/bright-blob detector harnesses were removed during detector cleanup. Their summarized findings remain in `docs/EXPERIMENT_SWING_DETECTOR.md`, but current reruns should use the V3 and exported-video harnesses above.

## 7. Experimental Settings

File: [ExperimentalSettingsView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/ExperimentalSettingsView.swift)

Implemented feature set:
- Library toolbar gear opens Experiments.
- Toggle model swing detection on/off for capture recordings and imported Trim sessions.
- Configure the capture detector mode used when a new recording stops (`Hybrid` by default, plus `Contact` and experimental `Impact` for comparison).
- Configure the YOLO/Core ML live detector sample rate used by capture and Replay Debug.
- Configure the hybrid impact confirmation wait used by capture and Replay Debug (`0.20s`, `0.28s`, `0.35s`, or `0.55s`).
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
