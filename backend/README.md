# SwingCoach Backend

Python FastAPI backend for the SwingCoach coaching pipeline.

## Purpose

Given one uploaded swing video, the backend returns:
1. Full-duration clean video artifacts
2. Normalized body-reference and hand-path overlays with image-space metrics
3. Source-backed coaching, or an explicit model-unavailable result
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

The pipeline uses MediaPipe and `models/pose_landmarker_heavy.task` for 2D observations. Missing tracking dependencies produce an explicit warning. SAM3, event detection and 3D replay remain inactive. Configure `OPENAI_API_KEY` for the visual observer and smart coach; `SWINGCOACH_COACH_MODEL` defaults to `gpt-6.1-sol` and `SWINGCOACH_COACH_REASONING` to `low`. Deploy the committed coaching source JSON folder with the backend, or set `SWINGCOACH_KNOWLEDGE_DIR` to its location. Raw reference media is not needed by the API.

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
- `student_goal: Optional[str]`
- `golfer_context: Dict[str, str]`, such as club, handedness and reported outcome

Response shape (`AnalyzeResponse`):
- `analysis_id`
- `summary`
- `metrics[]` (display rows with `key`, `name`, `value`, optional `confidence` and `explanation`)
- `annotated_video` (`key`, fresh signed `url`, optional `base_key` / `base_url`, optional `tracks_key` / `tracks_url`, rendered `layers[]`)
- `drills[]` (one selected source intervention with `title`, `summary`)
- `coaching` (optional versioned focus, status, rationale, cue, reassessment, questions, evidence, source moments and limitations)

The pipeline records sampled landmarks and observations, numeric metrics, clean full-duration video and confidence-gated overlay tracks. The smart coach uses versioned prompts and the committed case library. With no model key or an invalid model response, the result keeps measured evidence and withholds drills. A whole-clip movement range is never treated as a phase-specific fault.

### `POST /analysis-runs`

Primary mobile analysis entry point. Queues a background analysis job and returns immediately.

Request shape:
- `video_key: str`
- `vantage: "DTL" | "FO"`
- `fps: Optional[float]`
- `student_goal: Optional[str]`
- `golfer_context: Dict[str, str]`, such as club, handedness and reported outcome

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

1. Read video metadata and retain the full source timeline.
2. Sample reliable 2D pose landmarks and calculate descriptive whole-clip metrics.
3. Render clean videos plus timed body-reference and hand-path overlay tracks.
4. Review sampled frames through the configured visual model, retrieve source cases,
   and validate the coach's evidence references and prerequisite checks.
5. Return one sourced focus, cue and reassessment, or explain missing evidence/model access.
6. Persist observations, coaching context, artifacts and timings for reopening and chat.

## Run Artifacts

Output location:
- [backend/output/runs/](./output/runs)

Typical files per successful run:
- `input_meta.json`
- `events.json`
- `metrics.json`
- `observations.json`
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

# Synthetic pipeline video, pixel, and output-contract checks
python test_pipeline_3d.py

# 2D pipeline test
python test_pipeline.py

# No-pose annotation contract test
python test_annotation_tracks.py

# Async run lifecycle test
python test_analysis_runs.py

# Seeded smoothing accuracy and jitter checks
python test_temporal_smoothing.py

# Decode exported animation timing and joint motion
python test_animation_export.py
```

## Knowledge coaching and limits

The current pipeline builds on the earlier clean-video reset. Its first measurements
are head position range and projected torso-angle range across the entire clip.
They are descriptive quantities, not automatic fault classifications. The body
reference and hand path overlays use reliable pose samples. There are no generated
swing phases, shaft lines, clubface angles, pressure estimates or calibrated 3D values.

The coach loads the same [source corpus](../docs/coaching-knowledge/README.md) as the
local viewer. `OPENAI_API_KEY` enables the two-stage visual review and coaching call;
`SWINGCOACH_COACH_MODEL` selects a vision/structured-output capable model. Without
model access, measurements remain available and no drill is selected. Structural
validation checks cited observations, source membership, confidence and all case
prerequisites. It does not independently prove the model's visual interpretation.

Async run state remains in memory; production jobs need durable state to survive
process restarts. Persisted run artifacts support reopening completed results.

The default `test_pipeline_3d.py` uses synthetic video with an injected no-pose
provider to verify source timing, decoded pixels and the empty-overlay fallback.
It needs no R2 credentials or model weights. `test_grounded_coaching.py` verifies
measurement geometry and coaching contracts with deterministic model responses.
Run both library and coach checks with:

```bash
python -m unittest test_knowledge_library test_grounded_coaching
```

From the repository root, `bash scripts/verify-coaching.sh` tests real local upload,
pose analysis, overlay controls and saved notes in a disposable Simulator. A clearly
labelled saved fixture checks sourced cue rendering; it is not a live model diagnosis.
See [implementation evidence](../docs/coaching-knowledge/implementation.md).

Synthetic smoothing and animation checks concern optional legacy components, not
active coaching behavior. The older experimental implementation is preserved in Git.
