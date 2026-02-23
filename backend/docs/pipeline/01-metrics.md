# Pipeline Stage 1: Metrics

## Goal

Produce coachable metrics with explicit confidence, not raw calculations without quality gating.

## What Is Implemented

### Inputs

- 2D dense poses from [pose_detector.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/pose_detector.py)
- Event frames from [event_detector.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/event_detector.py)
- Club 3D fused track from [club3d_fuser.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/club3d_fuser.py)

### Metric computation layers

1. Base biomechanical metrics in [metrics.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/metrics.py)
   - tempo ratio
   - head sway/dip
   - spine angle change
   - shoulder/hip turn proxies
2. Coachable metric cards in [metrics_engine.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/metrics_engine.py)
   - unified card format
   - confidence bounds
   - explanations and fix hints
3. Pipeline persistence in [pipeline_3d.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/pipeline_3d.py)
   - writes `metrics.json`
   - includes `quality.missing_data` and warnings

## Current Output Shape

Each metric card includes:
- `key`
- `name`
- `value`
- `unit`
- `confidence`
- `explanation`
- `fix_hint`

## Current Gaps

1. Absolute metric accuracy remains uneven, especially club delivery metrics.
2. Scale and calibration assumptions are still coarse for phone-only capture.
3. Event/frame alignment can degrade impact-dependent calculations.
4. Ball metrics are not yet integrated into the unified metrics stage.

## Next Development Tasks

1. Fix event/frame index consistency across sparse/dense scans before deeper metric tuning.
2. Add benchmark harness against labeled swings or launch-monitor subsets.
3. Introduce calibration checks and stricter confidence gating for publish/no-publish decisions.
4. Expand metric set to include validated body, club, and ball categories with explicit confidence thresholds.

## Key Files

- [analysis/metrics.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/metrics.py)
- [analysis/metrics_engine.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/metrics_engine.py)
- [analysis/pipeline_3d.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/pipeline_3d.py)
- [output/runs/](/Users/ruari/Documents/Startups/SwingCoach/backend/output/runs)

