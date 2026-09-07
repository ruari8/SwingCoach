# Frontend Documentation (iOS)

For design iteration and showing native Simulator UI in the browser, use the
[persistent UI playground](./UI_PLAYGROUND.md).

## Scope

The frontend is a SwiftUI app in [SwingCoach/](../SwingCoach) with three production tabs:
- Library
- Capture
- Coach (analysis)

DEBUG builds can show a Replay Debug tab for detector development. The tab is controlled by the in-app Experiments settings.

Primary app root: [AppRootView.swift](../SwingCoach/AppRootView.swift)

## App Architecture

### Entry and Navigation

- App entry: [SwingCoachApp.swift](../SwingCoach/SwingCoachApp.swift)
- Tab coordinator: [AppRootView.swift](../SwingCoach/AppRootView.swift)
- Shared handoff state: `swingsToAnalyze` (passed from Library/Capture into Coach tab)

### Core Domains

- Capture and camera session: [CaptureView.swift](../SwingCoach/CaptureView.swift)
- Library and playback/import: [LibraryView.swift](../SwingCoach/LibraryView.swift)
- Trim workflow: [TrimView.swift](../SwingCoach/TrimView/TrimView.swift)
- Analysis UX: [AnalyseView.swift](../SwingCoach/AnalyseView.swift)
- DEBUG replay harness: [DebugReplayView.swift](../SwingCoach/DebugReplayView.swift)
- Experimental settings: [ExperimentalSettingsView.swift](../SwingCoach/ExperimentalSettingsView.swift)
- Swing detail workspace: [SwingDetailView.swift](../SwingCoach/SwingDetailView.swift)
- Shared analysis result rendering: [AnalysisResultView.swift](../SwingCoach/AnalysisResultView.swift)
- API client: [SwingCoachAPI.swift](../SwingCoach/Models/SwingCoachAPI.swift)
- Persistence: [SwingLibrary.swift](../SwingCoach/Models/SwingLibrary.swift)
- Local manual analysis drawings: [ManualAnnotationStore.swift](../SwingCoach/Models/ManualAnnotationStore.swift)

## Feature Inventory

## 1. Library Tab

File: [LibraryView.swift](../SwingCoach/LibraryView.swift)

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
- Development builds can install three local DTL reference videos from `SwingCoach/ReferenceSwings`, mark them as starred, and present them in a separate Reference swings section. The MP4 files are deliberately ignored and absent from a clean checkout; see the directory README for local setup. Reference entries use app-owned video files and do not count toward captured-swing statistics or Photos validation.
- `SavedSwing.isFavorite` persists starred state. Starred personal swings sort before other personal swings, display a yellow star, and can be toggled from the card context menu or the swing detail header.
- Swing detail is now video-first: opening an unanalyzed swing shows the original video across the usable area above the tab bar, with a bottom analyze action and an optional info sheet for metadata.
- Analyzed swings show a status indicator on their library card.
- Multi-select for batch analyze and batch delete. Library-only deletion removes the selected entries and app-owned copies in one collection update/save; it does not remove Photos assets. Single-item removal uses the same batch API.
- Multi-select can export selected swings by copying the underlying Photos video resources into a temporary SwingCoach export folder, adding one `metadata.json` manifest with app-level swing metadata, and presenting the iOS share sheet for AirDrop/Files transfer. The manifest is for dataset traceability and is shared alongside the selected videos, not embedded into each movie file.
- Playback with loading/error states and a shared in-frame scrubber plus gesture-driven transport on the video surface.
- Review and Trim use `SwingVideoPlayer`, an `AVPlayerViewController` with native controls and optional paused-frame analysis disabled. SwingCoach supplies its own controls; Live Text, subject copying, and Visual Look Up are not offered on these players. This prevents unused VisionKit requests from starting and being cancelled while paging. See [iOS console diagnostics](./IOS_CONSOLE_DIAGNOSTICS.md) for reproduction and remaining framework messages.
- Export/playback utilities integrated through app sheets.

## 2. Capture Tab

File: [CaptureView.swift](../SwingCoach/CaptureView.swift)

Implemented feature set:
- AVFoundation recording session with video input and microphone input when available, so newly captured clips can carry audio for export and detector experiments.
- Camera access is requested before first use; after permission is granted, the session configures and starts without requiring an app relaunch.
- Audio configuration/activation failures and capture-session runtime errors are logged under subsystem `Pear.ai.SwingCoach`, category `Capture`. The configured-format message is emitted only after the format and frame durations have been applied. These diagnostics do not alter capture settings or recovery behavior.
- Capture mode support:
  - `30fps HD`
  - `60fps HD`
  - `120fps HD`
  - `240fps HD` (default)
- **Save to Photos** appears at the top of Library > gear > Experiments, under Video storage. It persists across launches and defaults to ON for new and existing users. OFF retains new Auto, Manual, and trimmed clips in app storage without requesting Photos add access or creating Photos items. Turning it on later affects future saves only.
- Local-only clips support Library and Auto review playback, deletion, batch sharing, and analysis upload preparation. Photos validation preserves them. Auto review deletes a local-only clip without Photos permission and labels the action “Delete from SwingCoach”. Local originals participate in device backup; Photos-backed copies and bundled references remain excluded per file.
- Both Trim range export and **Use Full Video** obey the preference. With ON, using an entire imported Photos video reuses that asset as before. With OFF, it stores a local copy and leaves the imported original in Photos. A save failure leaves Trim open with an error; clips saved before a batch failure remain in the library.
- Capture workflow support:
  - `Manual`: existing record/stop flow. Stopping a recording opens Trim with any V3 ranges collected live during that recording.
  - `Auto`: the Capture tab opens in Auto and arms immediately while visible. The app feeds the live camera stream to `SwingDetectorV3` continuously, keeps an overlapping rolling video buffer with `AVAssetWriter`, waits until the detector window's post-roll frames are buffered, and exports accepted detector swing windows directly to `SwingLibrary` and optionally Photos without a separate start/stop button or Trim handoff. Auto pauses when leaving Capture or switching back to Manual. The FPS menu remains available in Auto; changing it safely resets the active rolling chunks and detector timeline.
- Capture uses an edge-to-edge camera preview behind the native tab bar, with dark appearance for readable controls over the preview. The top row contains the frame-rate menu and native `Auto / Manual` selector, with Auto first. Auto shows a compact bottom-left status with a red active dot and a bottom-right thumbnail/saved-count shortcut. The shortcut is disabled for an empty session. Saving and permission/detector failures remain visible in the status instead of a setup banner. Tapping the saved count opens a full-screen paged video carousel with a `Done` button. Opening review stops the capture session entirely (no camera indicator, no encode/inference load, no new detections mid-review); dismissing it restarts the session and resets the live detector/buffer timeline. Auto review and Library use the shared `SwingReviewPager` with native scroll snapping and a clipping boundary around each video. Only the selected Auto review video can play, and only the selected page accepts player input. Deleting the selected clip opens its next neighbour, or the previous clip at the end of the session. The carousel supports playback and permanent deletion from both SwingCoach and Photos, with the delete control in the player's bottom-right accessory slot so it never overlaps the player's own corner controls.
- Auto's rolling writer uses `AVCaptureDevice.RotationCoordinator` to preserve the actual device capture orientation per chunk: portrait stays portrait and either landscape orientation stays landscape. A cardinal-orientation change closes the current rolling chunk and starts a correctly transformed one. Manual recording applies the same capture angle through its movie-output track matrix. Buffer encoding and YOLO inference run on separate serial queues; inference coalesces backlog to the newest frame so model work cannot block the high-FPS capture delegate. Writer backpressure queues source frames until H.264 is ready instead of silently discarding them. Rolling chunks are 20 seconds with only a 2.6-second safety overlap, avoiding the previous design's near-continuous double encoding. Writer compression is configured with the selected 30/60/120/240 source rate.
- Real/contact swings remain the default acceptance mode. Library > Experiments includes an off-by-default `Capture practice swings` toggle. Practice detection uses the V3 Apple Vision pose pattern (`FullSwingPatternV3`): wrist-above-hip height in torso units must trace backswing top (>0.6) → fast dip through impact (≤0.45 at ≥1.5 torso/s) → held finish (>0.95 within 2.5s), with YOLO club detections anchored near the wrists and no ball-departure swing within 3s. Confirmation requires subsequent finish samples within 2.5s of impact. If contact confirmation is pending, practice fallback waits until contact resolves or its deadline expires, so the same stroke cannot be published first as practice and then as contact.
- Every accepted swing, including practice mode, now requires repeated confident human-pose frames from Apple Vision and repeated YOLO club detections. Ball/patch motion can create an internal candidate but cannot save a clip when the golfer or club is absent.
- Runtime mode switching without full session teardown.
- Tap-to-focus and exposure targeting.
- Model swing detection is experimental and can be turned off from Library > Experiments. When enabled, capture samples camera frames during recording and runs `SwingDetectorV3` with the bundled YOLO11n/Core ML golf-object model and Apple Vision pose on-device while the video is still being captured.
- When model detection is off, capture still records normally and the trim editor opens without generated ranges so the user can mark clips manually.
- During Manual recording, the frame-rate menu and mode selector are replaced by a centered timer in the top row. The timer uses the same system font as the controls with fixed-width digits. A bottom-left `Detecting swings` status shows the real detected count beside the centered stop button. Disabled or unavailable detection is stated explicitly while video recording continues. Stopping restores the settings after Trim is dismissed. The final timing snapshot still passes into Trim; the older Vision/bright-blob and legacy hybrid detector paths are not used for production trim ranges.
- Library > Experiments > Capture diagnostics includes `Show model stats`, persisted and off by default. When enabled, a small line beneath the Auto/recording status shows measured detector FPS and average model processing time, for example `8.0 fps / 56 ms`. These values come from `CameraSession.liveSwingDetection` in both modes, not the capture frame rate. Before the first processed frame it says `Waiting for model…`; disabled/unavailable detection never displays stale numeric stats. The preference only changes presentation, not inference or recording.
- Stopping a Manual recording opens Trim directly. Cancel discards the temporary recording and returns to Manual capture with the same FPS selection, ready to record again. Finishing export also returns to Manual. Trim dismissal clears the recording URL and live detection results after the editor closes; there is no intermediate recording player or scissors re-entry action.
- The record control exposes `Start recording` and `Stop recording` accessibility labels.
- Active manual recording and armed Auto capture disable the iOS idle timer so solo range sessions do not Auto-Lock while the golfer walks into frame, then restore the prior idle-timer state after stop, error, switching to Manual, or leaving capture. Auto also requests add-only Photos access when it arms so the permission prompt is handled before the golfer walks away from the tripod.
- Library review is the reference for shared player layout. The removed Manual post-stop player used different chrome options and insets; its controls were reported too high. Auto review already uses the shared chrome with the Library's edge-to-edge layout. Trim and DEBUG replay have editing and diagnostic controls respectively; their visual consistency has not been audited in this change.
- Run `./scripts/verify-capture-controls.sh` for the Capture layout, Auto-first ordering, model-stats default/persistence/on-off behavior in both modes, disabled/unavailable/waiting/error states, landscape controls, saved review playback/paging/deletion, and Manual → Trim → Cancel. It drives production UI with XCUITest in a scratch build, substituting deterministic detector snapshots and synthetic camera file output. Review uses bundled reference clips and deletion only removes fixture entries. Real camera/detector performance and Photos deletion remain device checks.
- Run `./scripts/verify-manual-trim-cancel.sh` to verify Auto → Manual → record → stop → Trim → Cancel twice, return through the tabs, and temporary-file cleanup. The script substitutes synthetic camera file output in a scratch build and drives the real recording callback and views with XCUITest. Physical camera capture remains a device check.
- Slow-motion rendering is deferred until explicit clip export instead of blocking the stop-record action.
- Integration path into library and optional analyze handoff.

## 3. Trim Workflow

Files:
- [TrimView.swift](../SwingCoach/TrimView/TrimView.swift)
- [ThumbnailTimeline.swift](../SwingCoach/TrimView/ThumbnailTimeline.swift)
- [VideoTrimmer.swift](../SwingCoach/Models/VideoTrimmer.swift)
- [SwingDetectorV3AssetDetector.swift](../SwingCoach/Models/SwingDetectorV3AssetDetector.swift)
- [SwingDetectionTypes.swift](../SwingCoach/Models/SwingDetectionTypes.swift)
- [GolfObjectDetector.swift](../SwingCoach/Models/GolfObjectDetector.swift)
- [SwingObjectsYOLO11n.mlpackage](../SwingCoach/MLModels/SwingObjectsYOLO11n.mlpackage)

Implemented feature set:
- Timeline opens immediately with placeholder/progressive thumbnail loading.
- In-memory thumbnail caching for reopened trim sessions on the same source file.
- Library imports hand trim a lightweight Photos-backed source first, then load a fast preview asset in-editor and defer high-quality asset resolution until export.
- High-fps capture timelines display slow-playback timing while keeping selection mapped to the original source frames.
- Start/end range selection for clip creation.
- Captured recordings pass the V3 detections collected during recording into Trim, so candidate swing windows are preselected as soon as the editor opens. Imported/library videos run a local `SwingDetectorV3AssetDetector` post-pass against the preview asset when Trim opens, using the same V3 core as capture. Neither path calls the backend.
- Auto-detected clips can be reviewed one at a time by tapping their thumbnail, adjusted with the existing start/end trim handles, updated in place, or discarded with the clip delete control. Auto-detected clip thumbnails preserve detector impact/declaration timestamps and show `imp +Xs / end +Ys`, the delay from estimated impact and returned clip end to the moment the detector declared that swing. Captured recordings also show the final detector summary under the timeline, including detected count, effective sample FPS, model/pose processing cost, and final analysis lag.
- Captured recordings use the configurable V3 low sample rate (`8 fps` by default, adjustable in Experiments). V3 raises to its burst rate during startup grace and active swing evidence, then drops back after confirmation, timeout, or rejection. The live badge performance line is `target/effective fps · model last/avg ms · lag ms`; sustained effective FPS far below target or lag above a few hundred milliseconds means the device is not keeping up in real time.
- The camera delegate retains source frames for the rolling writer and returns quickly. Model inference is separately serialized and coalesces pending work to the latest camera frame, preventing detector latency from reducing saved-video cadence.
- The older Vision-only post-pass, live Vision/bright-blob detector, and legacy model-backed contact/impact/hybrid detector modes are not used as production fallbacks for trim ranges. If the model is missing or fails, captured recordings open Trim without generated ranges after the live badge reports the issue; imported/library videos report model detection unavailable in Trim and leave manual trim controls available.
- Apple Vision pose is a V3 production input for golfer-relative geometry and full-stroke evidence. Audio remains diagnostic and is not part of the app-wired acceptance path.
- When no clip ranges are marked, the footer offers an explicit full-video path so already-trimmed imports can be added as-is; Photos-backed imports reuse the existing asset instead of creating a duplicate.
- Multi-clip extraction from a long source video.
- MVP clip export defaults to down-the-line capture; face-on remains in the data model but is not exposed as an equal capture path in the trim header.
- Press-and-hold frame stepping with acceleration for faster long scrubs.
- Overview-only timeline for long-session trimming, with no separate precision toggle UI.
- A single primary export action in the footer.
- Export to MP4 clips for downstream storage/analysis, with captured high-fps sessions rendered to true slow-motion during export.
- Newly exported clips enter the library with an immediate frame thumbnail, then refresh from Photos in the background once the asset poster frame is available.
- Library swing thumbnails show selection, analyzed state, and a yellow star for favourites.

## 4. Coach Tab (Analysis)

File: [AnalyseView.swift](../SwingCoach/AnalyseView.swift)

Implemented feature set:
- Queue multiple swings for analysis.
- Show lightweight queue status (`pending`, `analyzing`, `failed`) without stacking full analysis cards.
- Show recent completed analyses as dashboard rows that link back to the swing detail workspace.
- Mark analyzed swings in local library.

## 5. Swing Detail

File: [SwingDetailView.swift](../SwingCoach/SwingDetailView.swift)

Implemented feature set:
- Treat a saved swing as the primary product object.
- Show the original swing as a full-screen playback surface by default, with metadata moved behind a top-right info button and no persistent title/metadata caption over the video.
- Once analysis exists, keep Original, Annotated, and Coach Notes behind explicit top buttons so changing the analysis view does not compete with library navigation.
- Display original and analyzed swing playback using the shared playback chrome, including timeline, compact cycle-through playback speed control, and full-screen viewing.
- Generated backend annotations are currently reset. When `annotated_video.layers` and track data are empty, the analyzed-video slide plays clean video and hides the annotation/manual rail.
- Show swing metadata and local analysis status in the detail info sheet or video overlay instead of reserving persistent space beside the footage.
- Run the current R2-backed analysis flow for a single swing, with retry controls reserved for failed analysis attempts.
- Attach completed analysis to the swing through `AnalysisLibrary`.
- Analysis requests and progress belong to the submitted swing. Moving to another video keeps the first request running without moving its result or progress to the new video. Swiping back to a video with a pending request shows that request and prevents duplicate submission; failed requests remain retryable.
- Render analyzed video and coach notes with the shared [AnalysisResultView.swift](../SwingCoach/AnalysisResultView.swift).
- Drag left or right across the original-video surface to move between library videos without returning to the grid. The shared `SwingReviewPager` uses stable swing IDs and viewport-sized clipped pages. Its scroll-target behavior advances when the projected displacement reaches a quarter-page, and always targets the previous/current/next page relative to `context.originalTarget`, the position at the start of the gesture. Release velocity contributes to that projection, so a short flick can advance; a small slow drag returns to the current page. `ScrollTargetBehaviorProperties.limitsScrolls` enables shorter native scrolling motion so the page settles promptly after release. Restricting the destination to an adjacent page prevents a hard flick from skipping multiple videos in Library or Auto review. ScrollView still handles dragging, cancellation, and deceleration without a timed offset reset. The app keeps the previous/current/next playback items prepared to avoid a black loading handoff. Timeline dragging and stationary edge holds control playback; a moving finger cancels an edge hold. `PlaybackTransportGesture` shares the touch with the pager and distinguishes taps from holds, so releasing a hold stops frame steps without hiding the controls. Drawing mode disables horizontal paging. The header shows the current library position.
- The review player stays fixed while its video content pages horizontally. `PlaybackChromeView` publishes only the selected page's controls to a `SwingReviewPager` overlay outside the scroll strip. Metadata, playback speed, timeline, transport buttons, feedback, gradients, and accessories stay in place in Library and Auto review. Video and its drawn annotations move together. Each page retains its playback state; fixed controls update to act on the selected swing. In Library, star, info, and playback speed form one top-right column of 38-point buttons with 10-point gaps. Info and speed stay available with the star when transport controls hide. Standalone players keep their controls inline.
- Swiping follows the collection opened from Library: personal videos retain the selected vantage filter and starred-first order; reference videos stay in their own collection. The order stays fixed until returning to Library, so changing a star during review does not move the current video. Opening a result from Coach reviews that one swing.
- The mid-left pencil rail pauses playback and enables a straight-line canvas over the visible video. In drawing mode the rail expands in place with Done, Undo, and Clear actions, away from the bottom-right player lock. Yellow guide lines persist per swing in `manual_annotations.json` and remain visible during playback. Drawing coordinates follow the displayed video rectangle rather than the surrounding letterbox.
- The drawing tool loads the video track's dimensions and orientation before becoming available. Lines follow the visible video when rotating or resizing the screen, and strokes beginning in the letterbox are ignored. Lines saved before this correction may need clearing and redrawing once because the old format did not record the viewport needed to repair their coordinates.

Review regression checks:
- Run `scripts/verify-review.sh` on macOS with Xcode and FFmpeg. It creates synthetic media and a disposable Simulator, tests per-video analysis ownership and retries, verifies oriented video dimensions, and drives Library filtering, starred order, reference navigation, and drawing across layouts. It preserves logs, XCTest results and screenshots in `.verification-artifacts/review-fixes/` and removes its Simulator afterward. It then verifies bulk deletion and relaunch persistence, including preserved reference entries and local-file cleanup. No phone, Photos originals, private reference assets, backend or upload is needed.

## 6. Replay Debug Tab

File: [DebugReplayView.swift](../SwingCoach/DebugReplayView.swift)

Implemented feature set:
- DEBUG-only tab for home/range development of live swing detection, controlled from Library > Experiments.
- Selects a video from Photos, copies it into temporary app storage, and displays the video as the primary replay surface using a custom player layer so iOS default playback controls do not overlap detector instrumentation.
- Replays decoded frames through the same YOLO/Core ML and Vision `SwingDetectorV3` used by capture, on a paced clock so the selected video behaves like a substitute camera feed instead of an offline batch job.
- Uses one in-screen footage selector for replay timing: `30/1x`, `120/4x`, or `240/8x`. This simultaneously sets the visible playback speed and the detector source-time scale, so a 240-fps slow-motion range session is replayed at `8x` and fed to the detector as real-time swing motion.
- Defaults to impact-only detection independently of Capture. Advanced includes a separate, persisted `Detect practice swings` toggle, off by default; the Capture preference is not copied into it. Changing the Debug toggle stops and clears the active replay, as changing source timing does. The collapsed controls show `impact only` or `+ practice` so the active mode stays visible.
- Keeps detector low sample-rate selection (`2`, `4`, `8`, or `16` YOLO samples per real-time second) under an Advanced disclosure. V3 owns burst sampling internally.
- Shows visible replay source time as `elapsed/total` seconds and detected-swing count as an overlay on the video while replay runs. The timer/progress is tied to the visible `AVPlayer`, while detector events still use the same source-video timestamp range shown on detected chips. If visible playback gets more than a few source seconds ahead of the detector reader, Replay Debug pauses playback until the detector catches up, so detections do not appear minutes after the user watched the swing.
- Replay Debug's source-time scrubber remains interactive before, during, and after replay. Dragging it stops the active run, discards that segment's partial detector state and detections, seeks the video, and makes the selected source timestamp the start of a fresh detector session. This supports checking separate swings in a long range recording without processing every interval between them; seek a few seconds before the swing so V3 can observe address evidence.
- Changing `30/1x`, `120/4x`, `240/8x`, or the detector sample rate stops and clears the current run at its current timestamp because evidence produced under the previous timing configuration is not comparable. The restart control immediately starts a clean run from zero, and Play automatically returns to zero after a completed replay.
- Shows stable V3 evidence fields in the replay overlay: target/effective sample FPS, processed frames, average model processing time, current motion score, current club-motion score, current ball score, and lag/rejection only when those fields are available.
- The replay pause control pauses both visible video playback and detector pacing.
- Detector overlay updates are throttled so fast state churn does not flicker continuously during long range videos.
- Detected swing chips can be tapped to open a looping preview sheet for that exact timestamp range while the main replay/detector continues behind the sheet. Detected swing chips show confidence plus `imp +Xs / end +Ys` when the detector can report when that window was declared; slow-motion sources display these as real-time detector delays rather than stretched source-timeline delays.
- Opens trim with replay-detected timestamps preselected and disables the trim view's post-open detector scan, matching the intended capture path where detections are already known when recording stops.
- This tool is not a production import path. It exists to tune and validate live detector behavior with saved long-session videos without repeatedly recording fresh device-camera sessions.

Local detector fixture workflow:
- Keep source fixture videos in ignored `.detectorTestV3/`; keep generated evaluator binaries and reports in ignored `.videos/`.
- V3 test metadata lives in `detector_workbench/validation/labels/detector_test_v3_labels.json`. Impact labels are rough one-second source-timeline buckets from QuickTime review; slow-motion real-time equivalents are source seconds divided by each video's `source_time_scale`.
- Run `python3 detector_workbench/validation/evaluate_swing_detector_v3.py --build --only test2` for a quick V3 compile/smoke test, or omit `--only` to run the 54-impact fixture gate.
- Add `--contact-sheets` when debugging a miss or false positive; the V3 workflow pairs candidate and decision traces with annotated sampled-frame sheets.
- Run `python3 detector_workbench/validation/evaluate_detector_video_data.py --force` to evaluate every exported clip in `detector_model/video_data`. The harness reads `detector_model/video_data/metadata.json`, infers source timing from visible duration, and writes `.videos/detector_video_data_eval/results/detector_video_data_report.json`. Review overrides live in `detector_workbench/validation/labels/detector_video_data_labels.json`; `swingcoach_043_dtl_20260321_221006.mp4` is excluded because it ends at impact without enough post-impact ball-departure evidence for V2 acceptance.
- Current V3 acceptance relies on persistent ball identity, repeated club association, golfer-relative target geometry, a frozen target during the swing, target-patch departure, club sweep/arc/sequence, and full-stroke pose travel when pose is readable. It does not use scene-wide ball counts or an absolute image-height line.
- Run `python3 detector_workbench/validation/analyze_audio_impacts.py` to rescore audio transients on the current `test4` fixture. Audio remains diagnostic, not production capture behavior.
- Historical V2, Vision/bright-blob, and legacy model-backed findings remain in `docs/EXPERIMENT_SWING_DETECTOR.md`; current reruns should use the V3 command above.

## 7. Experimental Settings

File: [ExperimentalSettingsView.swift](../SwingCoach/ExperimentalSettingsView.swift)

Implemented feature set:
- Library toolbar gear opens Experiments.
- Toggle model swing detection on/off for capture recordings and imported Trim sessions.
- Toggle `Show model stats` under Capture diagnostics to expose measured detector FPS / average model milliseconds beneath the Auto and Manual recording status. This display preference defaults to off and persists across launches.
- Configure the YOLO/Core ML V3 low sample rate used by capture, imported Trim detection, and Replay Debug.
- Toggle ball-independent practice-swing detection for Auto capture and Manual recording's detected trim ranges; real ball-departure capture remains the default. This preference does not affect Replay Debug's separate Advanced toggle or imported-video Trim detection, which remains impact-only.
- Toggle the DEBUG Replay Debug tab on/off.
- Replay Debug visible playback speed and source timing are configured inside the Replay Debug tab, not in the shared Experiments screen.
- Capture records microphone audio when the session can add the audio input, but live audio-fused capture detection is still experimental. Audio fusion is currently exposed in Replay Debug and the local evaluator, not as the production capture trim path.

## Data and Models

### Swing metadata

- `SavedSwing` model: [SwingLibrary.swift](../SwingCoach/Models/SwingLibrary.swift)
- Fields include: `photoAssetID`, `vantage`, `duration`, timestamps, notes, analyzed flag, favourite state, reference state, optional title, and local video filename.
- Persisted to app Documents as `swing_library.json`.

### Vantage model

- Enum in [SwingClip.swift](../SwingCoach/Models/SwingClip.swift)
- Values: `DTL`, `Face-On`

## Backend Integration Contract

File: [SwingCoachAPI.swift](../SwingCoach/Models/SwingCoachAPI.swift)

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

`annotated_video.layers` is currently expected to be empty from the reset backend pipeline. `base_url` points to the clean full-duration analyzed video, while `url` remains the compatibility MP4. `tracks_url` may point to a normalized JSON envelope on the same source timeline, but current frames contain empty `layers` objects and no guide layers or markers.

## Known Gaps and Risks

1. Async analysis lifecycle
- Run status is currently server-memory-backed. If the backend restarts while a run is active, the app will lose that run and should show the backend error.
- SSE is one-way progress only. Cancellation, resumable background processing, and persisted run history are future work.

2. Analyzed video playback
- UI embeds the analyzed video artifact in the Coach result when available.
- Saved analyses persist artifact keys and refresh signed video and track URLs through `POST /artifact-url` when stale.
- Generated overlays are disabled until the next annotation contract is agreed.

3. Trim-to-analyze handoff
- The capture trim footer currently shows a single primary action.
- Automatic analyze handoff after clip export is intentionally left as future work.

4. Environment setup
- DEBUG backend target and mock/real analysis mode are configurable from Experiments. Release remains fixed to the deployed backend until a production environment selector or build configuration is needed.

5. Swing auto-detection validation
- On-device detection is intentionally conservative and editable, but needs device/video validation with real range sessions before it should be treated as a high-confidence practice-swing filter.
- The live path uses `SwingDetectorV3`: YOLO object observations, Apple Vision pose, golfer/club/target relationships, and target-specific contact evidence. It should be tested heavily on irons, mats, grass, marker and downrange balls, glare, partial target occlusion, changed framing, and physical-device timing. The retired bright-blob path remains historical material only.

## Recommended Next Frontend Documentation Additions

1. Add API migration checklist once async analysis-run persistence/cancellation is designed.
2. Add screen-by-screen state diagrams for capture -> trim -> analyze.
3. Add QA matrix (permissions, iCloud assets, missing assets, offline behavior).

## Local performance verification

See [Foundation performance](./FOUNDATION_PERFORMANCE.md) for measured Library/decode improvements, repeatable isolated probes, generated-fixture limits, and outstanding phone measurements.

## Code cleanup, September 2026

`SwingDetectionTypes.swift` owns the shared detection result and live status types.
Capture and Replay Debug use `SwingDetectorV3`; Trim uses `SwingDetectorV3AssetDetector`.
The unused on-device, bright-blob, model-backed asset, and V2 asset implementations
have been removed. The V2 and legacy live-model evaluators remain available under
`detector_workbench/validation` with updated build commands.

Library cards continue to open swing detail. The abandoned direct-playback cover,
old analysis card, unused transferable import wrapper, and template screen were
removed. The active Photos picker and shared playback controls are unchanged.
Saved analysis video URLs retain the 45-minute refresh rule, now owned by
`SavedAnalysisVideo.needsArtifactRefresh`.

## Review paging verification

`SwingCoachUITests/LibraryPagingUITests.swift` checks repeated slow and fast swipes, short drags, and first/last-page boundaries. `testQuarterPageDragCommitsAndSmallDragReturns` checks that a deliberate 30% drag advances in both directions while a 5% drag returns; `scripts/verify-media-playback.sh` includes this regression. `testPlayerControlsStayOutsideMovingPages` checks that controls are outside the moving pages in Library and Auto review, retain their positions, and operate on the newly selected video. Each settled position must expose exactly one full-width video whose title matches the selected swing. The suite also checks opening a middle swing, timeline scrubbing, drawing mode, hold-to-swipe handoff, and stopping frame steps after a hold ends. The suite also checks Auto review deletion with three optional local reference videos from `SwingCoach/ReferenceSwings/README.md`.

For high-velocity flicks, run `./scripts/verify-fast-swipes.sh`. It seeds 171 synthetic videos into a disposable simulator and runs `FastSwipePagingUITests` in Library and Auto review. Each immediate-release swipe at 1,500, 3,000, and 6,000 points per second must settle on exactly the adjacent video in both directions, and swiping backwards at the first video must stay there. No private videos or Photos access are needed. The script preserves screenshots and XCTest results under `.verification-artifacts/fast-swipes/` and removes its simulator and scratch build.

This regression reproduced a 6,000-point/second flick from video 9 landing on video 11 with the previous `.viewAligned(limitBehavior: .alwaysByOne)` behavior. The older three-video tests could not expose that case: their fast forward swipes began next to the last video, and their drag helper paused before releasing, reducing momentum. The explicit destination clamp fixes the failing long-list test while retaining native gesture handling.

The DEBUG launch argument `-ui-testing-auto-review` opens the production Auto review view with an in-memory session of local reference clips. Deletion removes a fixture from that session only. It does not delete files or Photos assets, and it does not exercise capture or detection.

Run the suite on an owned simulator with the local fixtures installed:

```bash
xcodebuild -project SwingCoach.xcodeproj -scheme SwingCoach \
  -destination "platform=iOS Simulator,id=<simulator-uuid>" \
  -parallel-testing-enabled NO \
  -only-testing:SwingCoachUITests/LibraryPagingUITests test
```

Coach results use explicit Original, Annotated, and Coach Notes buttons. The remaining drag controls edit annotation tools, scrub or trim timelines, or dismiss full-screen playback; they do not page between videos.

### Save to Photos verification

Run `scripts/verify-save-photos.sh` for an isolated Simulator check. It substitutes camera video and detector windows in a scratch build, then uses real Auto and Trim exporters, app persistence, and PhotoKit. The OFF phase runs with Photos denied and checks local playback after relaunch, Auto review deletion, and zero Photos items. The ON phase grants Simulator Photos access and checks one Photos item for each Manual full-video, Trim range, and Auto export. Unit tests cover local copy failure, asset validation, thumbnails, playback, deletion, and analysis upload preparation. Evidence stays under `.verification-artifacts/save-photos/`. Real camera capture and physical-iPhone Photos interoperability still require a device check.
