# Pipeline Stage 1: Metrics

## Current Status

Generated metrics are intentionally disabled while the annotation and detection contract is rebuilt.

The reset pipeline writes `metrics.json` with an empty `cards` array and `raw.metrics_enabled = false`. App-facing `metrics[]` is empty. This avoids publishing unstable biomechanical or club-delivery values before the source detections are agreed and validated.

## Disabled Work

The current default pipeline does not run:

- 2D pose-derived biomechanical metrics
- 3D body recovery
- 3D club fusion
- tempo/head/spine/turn metric cards
- club delivery metrics

## Re-Enable Criteria

Before metrics return to the app, define:

1. The exact coaching metric names and visual/user-facing meaning.
2. The detector source required for each metric.
3. The calibration assumptions.
4. The confidence threshold for publish vs. omit.
5. Fixture videos or labeled references that prove the metric is directionally correct.

## Key Files

- [analysis/pipeline_3d.py](../../analysis/pipeline_3d.py)
- [analysis/metrics.py](../../analysis/metrics.py)
- [analysis/metrics_engine.py](../../analysis/metrics_engine.py)
- [output/runs/](../../output/runs)
