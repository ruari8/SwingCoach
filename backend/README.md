# SwingCoach Backend

Python FastAPI backend for the SwingCoach coaching pipeline.

## Purpose

Given one uploaded swing video, the backend returns:
1. Coachable metric cards with confidence
2. Visual artifacts (annotated video and optional 3D replay)
3. Coaching seed output (summary, priorities, drills)
4. Run-quality metadata (warnings, missing data, timings)

Primary orchestrator: [analysis/pipeline_3d.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/pipeline_3d.py)

## Canonical Backend Docs

- [Backend Docs Index](/Users/ruari/Documents/Startups/SwingCoach/backend/docs/README.md)
- [Pipeline Stage: Metrics](/Users/ruari/Documents/Startups/SwingCoach/backend/docs/pipeline/01-metrics.md)
- [Pipeline Stage: Video Annotations](/Users/ruari/Documents/Startups/SwingCoach/backend/docs/pipeline/02-video-annotations.md)
- [Pipeline Stage: Drills and Feels](/Users/ruari/Documents/Startups/SwingCoach/backend/docs/pipeline/03-drills-feels.md)
- [Pipeline Stage: Teaching Voice](/Users/ruari/Documents/Startups/SwingCoach/backend/docs/pipeline/04-teaching-voice.md)

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

## API Contract

Main server file: [main.py](/Users/ruari/Documents/Startups/SwingCoach/backend/main.py)

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

Request shape:
- `video_key: str`
- `vantage: "DTL" | "FO"`
- `fps: Optional[float]`

Response shape (`AnalyzeResponse`):
- `analysis_id`
- `summary`
- `metrics[]` (display rows with `key`, `name`, `value`)
- `annotated_video_url`
- `drills[]` (lightweight `title`, `summary` suggestions)

The pipeline still records richer internal data such as confidence, warnings, timings, 3D artifacts, and raw files. The mobile MVP contract intentionally exposes only the fields needed by the current Coach tab.

### `POST /mock/analyze`

Request shape:
- `video_key: str`
- `vantage: "DTL" | "FO"`

Response shape:
- Same `AnalyzeResponse` shape as `/analyze`

Mock analysis is for mobile MVP testing. It verifies the uploaded source `video_key` exists in R2, uploads `output/full_annotation.mp4` to `mock/full_annotation.mp4` if needed, and returns a signed R2 URL for that dummy annotated video without running the model pipeline.

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
4. Optional 3D body recovery (SAM 3D Body)
5. Club 2D/3D fusion
6. Metrics build (base + club delivery)
7. Artifact rendering (annotated MP4 + optional GLTF)
8. Coaching bundle generation
9. Persist run artifacts and timings

## Run Artifacts

Output location:
- [backend/output/runs/](/Users/ruari/Documents/Startups/SwingCoach/backend/output/runs)

Typical files per successful run:
- `input_meta.json`
- `events.json`
- `poses_2d.npz`
- `poses_3d.npz` (if 3D stage available)
- `club_2d.npz`
- `club_3d.npz`
- `metrics.json`
- `coach_summary.json`
- `annotated.mp4`
- `swing_3d.gltf` (if 3D available)
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

# SAM3 prompt diagnostics
python test_sam3_detection.py

# Temporal smoothing tests
python test_temporal_smoothing.py
```

## Known Reliability Notes

1. Some metrics are confidence-gated and may be absent if detection confidence is low.
2. Club and impact-related metrics depend on club tracking quality and event alignment.
3. `/analyze` is still synchronous and should move to an async analysis-run lifecycle before broader beta use.
