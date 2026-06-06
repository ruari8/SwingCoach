# SwingCoach

SwingCoach is an experimental AI golf coaching system for turning iPhone swing video into coachable feedback. It combines a native SwiftUI capture/library app with a FastAPI backend that runs analysis, renders video artifacts, and returns metrics, drills, and coaching notes.

This is an active prototype rather than a polished App Store product. The repo is useful as a full-stack product/ML engineering sample: native media workflows, on-device detection experiments, async backend jobs, cloud artifact storage, and confidence-gated coaching output.

## What It Does

- Captures or imports golf swing video on iOS, then trims one or more swing clips into a local library.
- Runs an experimental on-device `SwingDetectorV2` using a YOLO/Core ML golf-object model to preselect likely swing windows.
- Uploads clips to a Python backend through Cloudflare R2 pre-signed URLs.
- Queues asynchronous analysis runs and streams backend progress back to the app with Server-Sent Events.
- Produces clean and annotated video artifacts, normalized overlay tracks, metric cards, drill recommendations, and a coaching summary.
- Lets the app render server-side guide overlays over clean video and add local manual drawing annotations for self-analysis.

## System Shape

```text
iOS app
  Capture / Import / Trim / Library / Coach
        |
        | pre-signed upload
        v
Cloudflare R2
        |
        | video_key
        v
FastAPI backend
  /analysis-runs -> 2D pose -> optional 3D body -> club tracking -> metrics -> artifacts -> coaching bundle
        |
        | status + SSE progress + signed artifact URLs
        v
iOS Swing Detail
  original video, annotated video, overlay toggles, metrics, drills, coach notes
```

## Repository Layout

```text
SwingCoach/
├── SwingCoach/                 # SwiftUI iOS app
├── SwingCoach.xcodeproj/       # Xcode project
├── backend/                    # FastAPI API and analysis pipeline
├── detector_workbench/         # Detector dataset/modeling/validation tools
├── docs/                       # Project and frontend documentation
└── AGENTS.md                   # Local operator instructions
```

## iOS App

The app is built around three production tabs:

- `Library`: import videos from Photos, browse saved swings, batch analyze/delete/export, and open swing detail.
- `Capture`: record manual clips or use the experimental auto-capture path that writes accepted detector windows directly to the library.
- `Coach`: queue swings for analysis and review completed analysis results.

DEBUG builds also include tools for development:

- `Experiments`: backend target selection, mock analysis, detector sampling settings, and Replay Debug visibility.
- `Replay Debug`: feeds saved videos through the same detector core used by live capture so detector behavior can be validated without repeatedly recording fresh sessions.

See [docs/FRONTEND.md](docs/FRONTEND.md) for the detailed feature inventory.

## Backend

The backend is a FastAPI service. Its main mobile path is asynchronous:

1. `GET /upload-url`
2. Upload MP4 directly to R2
3. `POST /analysis-runs`
4. Stream `GET /analysis-runs/{run_id}/events`
5. Fetch `GET /analysis-runs/{run_id}` for the completed result

The pipeline currently covers video metadata, sparse and dense 2D pose, optional SAM 3D Body recovery, club tracking/fusion, metric cards, artifact rendering, drill selection, and coaching text. The app-facing response is intentionally lightweight: summary, display metrics, annotated/base video artifacts, overlay-track metadata, and drills.

See [backend/README.md](backend/README.md) and [backend/docs/README.md](backend/docs/README.md) for API details and pipeline notes.

## Quick Start

### iOS

1. Open [SwingCoach.xcodeproj](SwingCoach.xcodeproj) in Xcode.
2. Build and run the `SwingCoach` target on a device or simulator.
3. For local backend work, run the backend on `http://127.0.0.1:8000`.
4. In DEBUG builds, use `Library > Experiments` to switch between local, deployed, custom LAN, real analysis, and mock analysis modes.

The simulator can reach the local backend directly at `127.0.0.1`. A physical iPhone needs a custom backend URL using the Mac's LAN IP, for example `http://192.168.1.23:8000`.

### Backend

```bash
cd backend
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
cp .env.example .env
./venv/bin/python main.py
```

Configure `backend/.env` with Cloudflare R2 credentials before running real upload/analysis flows. Without R2 configuration, `/health` reports a degraded state and storage-backed endpoints will not complete.

Optional 3D dependencies:

```bash
cd backend
./venv/bin/pip install -r requirements-3d.txt
```

The optional 3D stack is intentionally separate because SAM/SAM 3D Body dependencies and model assets are heavy.

## Useful Checks

Backend smoke and regression checks:

```bash
cd backend
./venv/bin/python test_pipeline_3d.py
./venv/bin/python test_full_annotation.py --sample
./venv/bin/python test_annotation_tracks.py
./venv/bin/python test_analysis_runs.py
./venv/bin/python test_temporal_smoothing.py
```

Detector validation tooling:

```bash
python3 detector_workbench/validation/evaluate_swing_detector_v2.py --build --only test2
python3 detector_workbench/validation/evaluate_detector_video_data.py --force
```

Heavy local fixture videos, generated detector reports, model-training outputs, backend videos, and model weights are intentionally git-ignored.

## Current Status

- The iOS capture, library, trim, analysis queue, swing detail, annotated playback, and manual drawing workflows are implemented.
- The async backend analysis API is implemented, including progress events, R2 artifacts, `/chat`, and a legacy synchronous `/analyze` fallback.
- The on-device detector is still experimental. It is useful for clip preselection and auto-capture iteration, but it is not treated as a solved detection problem.
- Metrics and coaching output are confidence-gated. Low-quality detection should produce uncertainty or omitted metrics instead of overconfident claims.
- The current mobile product path is DTL-first. Face-on exists in the data model, but the most mature flows and validation focus on down-the-line swings.
- Async run state is currently in memory, so active jobs do not survive backend restarts.

## Documentation

- [Project docs index](docs/README.md)
- [Frontend documentation](docs/FRONTEND.md)
- [Backend overview](backend/README.md)
- [Backend docs index](backend/docs/README.md)
- [Detector tooling](detector_workbench/README.md)
- [Deployment notes](docs/DEPLOYMENT.md)
