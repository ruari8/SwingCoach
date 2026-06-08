# SwingCoach Backend

Python FastAPI backend for the SwingCoach coaching pipeline.

## Purpose

Given one uploaded swing video, the backend returns:
1. Full-duration visual artifacts and normalized overlay tracks
2. Annotation-focused coaching seed output
3. Optional coachable metric cards with confidence when 3D metrics are enabled
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

Optional 3D dependencies:

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

Optional analysis flags:

- `SWINGCOACH_ENABLE_3D_METRICS=false` by default. Set to `true` to enable SAM 3D Body, club 3D fusion, metric cards, and GLTF replay export.
- `SWINGCOACH_EXPORT_BAKED_ANNOTATED_VIDEO=false` by default. Set to `true` only for debug/legacy review when a flattened server-rendered overlay MP4 is needed. Normal app playback uses `base_url` plus `tracks_url` so every annotation layer can be toggled.

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

The pipeline still records richer internal data such as confidence, warnings, timings, annotation metadata, and raw files. The mobile MVP contract exposes the fields needed by the current Coach tab plus annotation layer metadata, a full-duration clean base video, and a normalized overlay-track artifact for client-side toggles, including club plane, ball/contact evidence, P1-P10 phase markers, confidence evidence, and generic guide shapes for setup/head/hip/hand/shaft checkpoint overlays when detected. 3D artifacts and metric cards are emitted only when `SWINGCOACH_ENABLE_3D_METRICS=true`.

Phase detection is confidence and window gated. If the dense analysis window does not contain enough post-top motion to find impact/follow-through phases, those phases are omitted instead of raising an analysis failure.

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

1. Read video metadata
2. Sparse 2D pose scan and event estimate
3. Dense window selection and dense 2D pose
4. Full-frame extraction for artifact timeline preservation
5. 2D club/shaft annotation tracking
6. Optional 3D body recovery, club 3D fusion, and metrics when `SWINGCOACH_ENABLE_3D_METRICS=true`
7. Artifact rendering (full-duration clean base video, unbaked annotated MP4 fallback, normalized overlay tracks, optional GLTF)
8. Coaching bundle generation
9. Persist run artifacts and timings

## Run Artifacts

Output location:
- [backend/output/runs/](./output/runs)

Typical files per successful run:
- `input_meta.json`
- `events.json`
- `poses_2d.npz`
- `poses_3d.npz` (empty unless 3D metrics are enabled and available)
- `club_2d.npz`
- `club_3d.npz`
- `metrics.json`
- `coach_summary.json`
- `base.mp4`
- `annotated.mp4`
- `annotation_metadata.json`
- `annotation_tracks.json`
- `swing_3d.gltf` (if 3D metrics are enabled and valid 3D poses exist)
- `timings.json`

## Local Test Commands

```bash
cd backend
source venv/bin/activate

# Unified pipeline integration test
python test_pipeline_3d.py

# 2D pipeline test
python test_pipeline.py

# Full annotation export test
python test_full_annotation.py --sample

# Annotation track contract test
python test_annotation_tracks.py

# Async run lifecycle test
python test_analysis_runs.py

# Annotation rendered-overlay visual regression
python test_annotation_visuals.py

# SAM3 prompt diagnostics
python test_sam3_detection.py

# Temporal smoothing tests
python test_temporal_smoothing.py
```

## SAM3 Runtime Notes

For Mac-side pseudo-labeling and local annotation analysis, prefer the MLX SAM3 image path over the current Meta PyTorch SAM3 CPU path. Local testing found that the official PyTorch package is CUDA-first: selecting `mps` did not move model weights or the processor to Apple GPU, while forcing MPS required community patches and still fell back to CPU for unsupported operations.

`EquipmentTracker` now selects the runtime from `SAM3_RUNTIME`:
- `auto` (default): use MLX SAM3 when `detector_model/mlx_sam3` is present, otherwise fall back to PyTorch SAM3.
- `mlx`: require MLX SAM3 and fail fast if unavailable.
- `torch`: force the existing Meta PyTorch SAM3 path.

Useful MLX settings:
- `MLX_SAM3_REPO`: override the local MLX repo path.
- `MLX_SAM3_WEIGHTS_DIR`: override converted weight cache/download location.
- `MLX_SAM3_MAX_SIDE`: resize longest frame side before prompting, default `960`.

Current recommendation:

- MLX SAM3 image for Apple Silicon frame pseudo-labeling.
- SAM3.1 only as a separate video-tracking/mask-propagation experiment.
- Do not use SAM3/SAM3.1 as the planned live iPhone detector; train/export a small Core ML golf-object detector instead.
- Treat SAM3D separately. The MLX SAM3 image findings do not prove SAM3D performance or compatibility.

See [Experimental Swing Detector](../docs/EXPERIMENT_SWING_DETECTOR.md) for benchmark numbers and labeling strategy.

## Known Reliability Notes

1. Some metrics are confidence-gated and may be absent if detection confidence is low.
2. Club and impact-related metrics depend on club tracking quality and event alignment.
3. Async run state is currently in-memory; production deployment should persist run state if jobs need to survive process restarts.
