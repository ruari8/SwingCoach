# Pipeline stage 1: video observations and metrics

The active `knowledge_coaching_v1` pipeline runs MediaPipe body pose and calculates
three descriptive image-space quantities in `analysis/video_observations.py`:

| Key | Calculation | Unit |
|---|---|---|
| `head_x_range_pct` | Maximum minus minimum visible nose x across the clip | Percent of frame width |
| `head_y_range_pct` | Maximum minus minimum visible nose y across the clip | Percent of frame height |
| `torso_image_angle_range_deg` | Range of the shoulder-midpoint to hip-midpoint angle from vertical, using image pixel aspect ratio | Degrees in the image |

These ranges include setup and follow-through. They are not address-to-impact
measurements, fault scores, physical distances or 3D rotation. Camera motion,
multiple swings and detector errors can make them unsuitable for comparison.
The coaching model receives these limits explicitly. There is no magnitude-based
priority ranking or automatic “too much movement” threshold.

The pipeline samples at approximately 15 Hz, with a maximum of 180 samples spread
across the full clip. A landmark must be inside the image with visibility at least
0.65. A quantity needs four usable samples. Reported tracking confidence is mean
landmark visibility capped at 0.85; it is not calibrated diagnostic confidence.
Low-confidence or missing quantities are omitted. Missing MediaPipe/model files
produce a warning while preserving clean playback and the remaining evidence.

`observations.json` records all sampled frame indices, accepted landmarks, metric
observations, methods and limits. `metrics.json` preserves numeric values,
confidence and explanations. The app displays explanations and confidence beside
formatted metrics. File FPS governs timestamps and playback; a different caller
capture FPS produces a warning instead of silently changing the timeline.

Clubface, shaft, pressure, mobility, ball flight, club speed, 3D angles and validated
swing phases remain unavailable. The old metric/event modules are dormant. The
legacy event module's P numbering must not be reused for coaching P4/P7 labels.

Tests: `test_grounded_coaching.py` checks known image geometry and confidence
omission; `test_pipeline_3d.py` checks the complete no-pose pipeline and decoded
video. Real-video and iOS evidence is recorded by `scripts/verify-coaching.sh`.
