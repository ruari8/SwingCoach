# SwingCoach Coachable Backend System Blueprint

This document is the single source of truth for the SwingCoach backend pipeline.

## Product Goal

Input: one golf swing video.

Output: three coachable outputs.

1. Numbers: metrics with confidence.
2. Visual proof: annotated 2D video and 3D replay.
3. Coaching guidance: plain-English diagnosis, fixes, and drill suggestions.

## Coachable Info Contract

For every swing run, backend returns:

1. Metric cards.
- `name`, `value`, `unit`, `confidence`, `explanation`, `fix_hint`.

2. Visual artifacts.
- `annotated_video_url`.
- `swing_3d_url`.
- optional debug files.

3. Coaching seed.
- `summary`.
- `top_priorities`.
- `drills`.

## Layman Pipeline

1. Accept uploaded video.
2. Extract frames and read fps/dimensions.
3. Detect swing phases on sparse frames.
4. Select dense window around top-to-impact.
5. Run dense 2D pose.
6. Run 3D body in dense window.
7. Detect shaft/clubhead in 2D and fuse with 3D wrists.
8. Compute coach-core metrics with confidence.
9. Render annotated video and 3D replay.
10. Build coaching summary and chat-grounding context.
11. Return unified response.

## Current Tech Stack

1. FastAPI + Python.
2. ffmpeg/ffprobe frame extraction.
3. MediaPipe Pose for fast events.
4. SAM3 for shaft/clubhead masks.
5. SAM 3D Body for body mesh and 3D joints.
6. Kalman-style smoothing where useful.
7. OpenCV + constrained geometry for club 3D fusion.
8. GLTF export for 3D replay.
9. OpenAI-first coaching text.
10. Curated drill corpus for grounded suggestions.

## System Modules

- `analysis/pipeline_3d.py` orchestrator.
- `analysis/run_store.py` run directories + artifacts + timings.
- `analysis/event_window_selector.py` sparse-to-dense window selection.
- `analysis/body3d_runner.py` 3D body detection with ROI reuse.
- `analysis/club3d_fuser.py` 2D club + 3D wrist fusion.
- `analysis/metrics_engine.py` coachable metrics + confidence.
- `analysis/artifact_renderer.py` annotated video + 3D export.
- `analysis/coach_response_builder.py` summary/chat/drills.

## Run Artifact Standard

Store under `backend/output/runs/<run_id>/`:

1. `input_meta.json`
2. `events.json`
3. `poses_2d.npz`
4. `poses_3d.npz`
5. `club_2d.npz`
6. `club_3d.npz`
7. `metrics.json`
8. `annotated.mp4`
9. `swing_3d.gltf`
10. `coach_summary.json`
11. `timings.json`
12. `debug_overlays/`

## Speed Strategy

Two-pass flow:

1. Sparse pass for cheap event detection.
2. Dense pass for expensive 3D in key window.

Defaults:

- sparse sample rate: every 6-10 frames based on fps.
- dense window start: 0.35s before top.
- dense window end: 0.25s after impact.

Optimization:

- reuse person bbox between 3D frames.
- fallback to full frame when confidence drops.
- save stage timing for every run.

## Coach-Core Metrics (v0.x)

1. Tempo ratio.
2. Head sway.
3. Spine angle change.
4. Shoulder turn at top.
5. Hip turn at top.
6. Club speed estimate.
7. Swing plane deviation proxy.
8. Club path direction at impact zone.
9. Attack angle estimate (confidence-gated).

Rule: never publish a metric without confidence.

## API Contract

`POST /analyze` returns:

1. `run_id`
2. `metrics[]`
3. `coaching`
4. `artifacts`
5. `quality`

`POST /chat` returns grounded follow-up coaching based on a prior run.

## Coaching Strategy

- OpenAI-first.
- Hybrid style: proactive summary + user follow-up.
- Prompt inputs: metrics, confidence, timings, uncertainty warnings, curated drills.

## Validation Strategy

1. Visual QA set: 20 videos for consistency.
2. TrackMan subset validation where data exists.
3. Lesson-grade validation set for richer club metrics when available.

## Acceptance Criteria

1. One backend call returns numbers + visuals + coaching seed.
2. Pipeline uses one orchestrator path.
3. Run folder always includes artifacts and timings.
4. 3D replay includes body and club.
5. Metrics carry confidence and explanations.
6. Chat answers are grounded in run artifacts.
