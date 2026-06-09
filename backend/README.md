# SwingCoach Backend

Python FastAPI backend for the SwingCoach coaching pipeline.

## Purpose

Given one uploaded swing video, the backend returns:
1. Full-duration clean video artifacts
2. An empty normalized overlay-track contract
3. Reset-state coaching output
4. Run-quality metadata (warnings, missing data, timings)

Primary orchestrator: [analysis/pipeline_3d.py](./analysis/pipeline_3d.py)

## Canonical Backend Docs

- [Backend Docs Index](./docs/README.md)
- [Pipeline Stage: Metrics](./docs/pipeline/01-metrics.md)
- [Pipeline Stage: Video Annotations](./docs/pipeline/02-video-annotations.md)
- [Pipeline Stage: Drills and Feels](./docs/pipeline/03-drills-feels.md)
- [Pipeline Stage: Teaching Voice](./docs/pipeline/04-teaching-voice.md)

## Quick Start

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python main.py
```

Dormant optional 3D dependencies:

```bash
cd backend
source venv/bin/activate
pip install -r requirements-3d.txt
```

## Environment

Create `.env` from `.env.example` and configure Cloudflare R2 credentials.

```bash
cd backend
cp .env.example .env
```

R2 HTTPS certificate verification is enabled by default. If a local machine has a temporary certificate-store problem, set `R2_VERIFY_SSL=false` in `backend/.env`; do not use that setting for deployed backends.

Generated annotations, SAM3 equipment prompting, pose/event detection, 3D replay export, and metric cards are disabled in the reset pipeline; the optional 3D dependencies are retained only for future experiments.

## API Contract

Main server file: [main.py](./main.py)

### `GET /health`

Response shape:
- `status`
- `r2_configured`
- `analysis_ready`

### `GET /upload-url`

Response shape:
- `upload_url`
- `video_key`

### `POST /analyze`

Legacy synchronous endpoint. The iOS app now uses async analysis runs for real analysis so the request does not need to stay open for the full model/render/upload pipeline.

Request shape:
- `video_key: str`
- `vantage: "DTL" | "FO"`
- `fps: Optional[float]`

Response shape (`AnalyzeResponse`):
- `analysis_id`
- `summary`
- `metrics[]` (display rows with `key`, `name`, `value`)
- `annotated_video` (`key`, fresh signed `url`, optional `base_key` / `base_url`, optional `tracks_key` / `tracks_url`, rendered `layers[]`)
- `drills[]` (lightweight `title`, `summary` suggestions)

The reset pipeline records warnings, timings, a full-duration clean base video, and an empty overlay-track artifact. `annotated_video.layers` is empty, and generated phase markers, club planes, pose skeletons, paths, confidence badges, metrics, and drills are omitted by design.

### `POST /analysis-runs`

Primary mobile analysis entry point. Queues a background analysis job and returns immediately.

Request shape:
- `video_key: str`
- `vantage: "DTL" | "FO"`
- `fps: Optional[float]`

Response shape:
- `run_id`
- `status`
- `status_url`
- `events_url`

### `GET /analysis-runs/{run_id}`

Returns the current run state:
- `status`: `queued`, `running`, `succeeded`, or `failed`
- `stage`
- `progress` from `0.0` to `1.0`
- `message`
- `error` when failed
- `result` when succeeded, using the same `AnalyzeResponse` shape as `/analyze`

### `GET /analysis-runs/{run_id}/events`

Streams Server-Sent Events for run progress. Events contain `run_id`, `sequence`, `status`, `stage`, `progress`, `message`, and optional `error`. The terminal SSE event does not carry the full result; clients fetch `GET /analysis-runs/{run_id}` when `status == "succeeded"`.

### `POST /mock/analyze`

Request shape:
- `video_key: str`
- `vantage: "DTL" | "FO"`

Response shape:
- Same `AnalyzeResponse` shape as `/analyze`

Mock analysis is for mobile MVP testing. It verifies the uploaded source `video_key` exists in R2, uploads `output/full_annotation.mp4` to `mock/full_annotation.mp4` if needed, and returns a signed R2 URL for that dummy annotated video without running the model pipeline.

The iOS DEBUG app defaults to a local backend URL and real async analysis runs. Library > Experiments can switch the app to the deployed backend, a custom LAN URL, or `/mock/analyze`.

### `POST /artifact-url`

Request shape:
- `key: str`

Response shape:
- `key`
- `url`

Returns a fresh signed R2 URL for a stored artifact key. The app persists artifact keys locally and refreshes signed URLs when saved analysis results are reopened after URL expiry.

### `POST /chat`

Request shape:
- `run_id`
- `question`
- `student_goal` (optional)

Response shape:
- `run_id`
- `answer`

## Pipeline Outline

1. Read video metadata.
2. Extract the full source timeline.
3. Render `base.mp4` and clean compatibility `annotated.mp4`.
4. Write empty `annotation_metadata.json` and `annotation_tracks.json`.
5. Write empty metrics plus reset coaching summary.
6. Persist run artifacts and timings.

## Run Artifacts

Output location:
- [backend/output/runs/](./output/runs)

Typical files per successful run:
- `input_meta.json`
- `events.json`
- `poses_2d.npz`
- `poses_3d.npz`
- `club_2d.npz`
- `club_3d.npz`
- `metrics.json`
- `coach_summary.json`
- `base.mp4`
- `annotated.mp4`
- `annotation_metadata.json`
- `annotation_tracks.json`
- `timings.json`

## Local Test Commands

```bash
cd backend
source venv/bin/activate

# Unified pipeline integration test
python test_pipeline_3d.py

# 2D pipeline test
python test_pipeline.py

# Annotation reset contract test
python test_annotation_tracks.py

# Async run lifecycle test
python test_analysis_runs.py

# Temporal smoothing tests
python test_temporal_smoothing.py
```

## Annotation Reset Notes

The previous experimental annotation implementation is preserved in git commit `abc12c4` (`experimental: annotation impl`). Do not re-enable SAM3, pose/event, or metric stages until the next annotation contract is agreed and covered by fixture-level visual validation.

## Known Reliability Notes

1. Generated annotations and metrics are currently absent by design.
2. The overlay-track artifact is present for API compatibility but has no generated layers.
3. Async run state is currently in-memory; production deployment should persist run state if jobs need to survive process restarts.
