# Frontend Documentation (iOS)

## Scope

The frontend is a SwiftUI app in [SwingCoach/](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach) with three tabs:
- Library
- Capture
- Coach (analysis)

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
- Multi-select for batch analyze and batch delete (library-only delete, does not remove Photos asset).
- Playback with loading/error states.
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
- Recording state handling with immediate post-stop playback of the captured high-fps asset.
- Post-stop review now uses the app's own playback chrome instead of the default `VideoPlayer` controls, reusing the library-style play/pause, frame step, scrubber, and time UI.
- Slow-motion rendering is deferred until explicit clip export instead of blocking the stop-record action.
- Integration path into library and optional analyze handoff.

## 3. Trim Workflow

Files:
- [TrimView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/TrimView/TrimView.swift)
- [ThumbnailTimeline.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/TrimView/ThumbnailTimeline.swift)
- [VideoTrimmer.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/Models/VideoTrimmer.swift)

Implemented feature set:
- Timeline opens immediately with placeholder/progressive thumbnail loading.
- In-memory thumbnail caching for reopened trim sessions on the same source file.
- Library imports hand trim a lightweight Photos-backed source first, then load a fast preview asset in-editor and defer high-quality asset resolution until export.
- High-fps capture timelines display slow-playback timing while keeping selection mapped to the original source frames.
- Start/end range selection for clip creation.
- Multi-clip extraction from a long source video.
- Per-clip vantage assignment and clip list management.
- Press-and-hold frame stepping with acceleration for faster long scrubs.
- Overview-only timeline for long-session trimming, with no separate precision toggle UI.
- A single primary export action in the footer.
- Export to MP4 clips for downstream storage/analysis, with captured high-fps sessions rendered to true slow-motion during export.
- Newly exported clips enter the library with an immediate frame thumbnail, then refresh from Photos in the background once the asset poster frame is available.

## 4. Coach Tab (Analysis)

File: [AnalyseView.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/AnalyseView.swift)

Implemented feature set:
- Queue multiple swings for analysis.
- Show card-based analysis status (`pending`, `analyzing`, `complete`, `failed`).
- Render returned summary, metrics dictionary, and drill links.
- Mark analyzed swings in local library.

Important implementation note:
- This view currently uses a legacy client response model (`summary`, `metrics`, `drill_links`) and not the new backend `CoachableAnalysisResponse` contract.

## Data and Models

### Swing metadata

- `SavedSwing` model: [SwingLibrary.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/Models/SwingLibrary.swift)
- Fields include: `photoAssetID`, `vantage`, `duration`, timestamps, notes, analyzed flag.
- Persisted to app Documents as `swing_library.json`.

### Vantage model

- Enum in [SwingClip.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/Models/SwingClip.swift)
- Values: `DTL`, `Face-On`

## Backend Integration Contract (Current Frontend Expectation)

File: [SwingCoachAPI.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/Models/SwingCoachAPI.swift)

Current flow:
1. `GET /upload-url`
2. Upload MP4 directly to R2 pre-signed URL
3. `POST /analyze` with `video_key` + `vantage`
4. Decode analysis result into frontend `AnalysisResponse`

Current frontend `AnalysisResponse` expectation:
- `summary: String`
- `metrics: [String: String]`
- `drill_links: [{title, url, platform}]`
- `raw_response: String?`

## Known Gaps and Risks

1. API contract mismatch
- Backend now returns `run_id`, metric cards, coaching bundle, artifacts, and quality metadata.
- Frontend decode model has not yet been migrated.

2. Coach tab data richness
- UI currently renders summary/metrics/drills only.
- Does not yet consume annotated video URL, 3D artifact URL, confidence/warnings.

3. Trim-to-analyze handoff
- The capture trim footer currently shows a single primary action.
- Automatic analyze handoff after clip export is intentionally left as future work.

4. Environment setup
- `baseURL` in [SwingCoachAPI.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/Models/SwingCoachAPI.swift) is still hardcoded and should be environment-configurable.

## Recommended Next Frontend Documentation Additions

1. Add API migration checklist once `/analyze` response mapping is updated.
2. Add screen-by-screen state diagrams for capture -> trim -> analyze.
3. Add QA matrix (permissions, iCloud assets, missing assets, offline behavior).
