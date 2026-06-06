# Pipeline Stage 2: Video Annotations

## Goal

Generate visual proof for coaching by rendering analysis overlays and replay artifacts.

## What Is Implemented

### 2D annotated video

- Renderer: [artifact_renderer.py](../../analysis/artifact_renderer.py)
- Overlay engine: [visualizer.py](../../analysis/visualizer.py)
- Exporter: [video_exporter.py](../../analysis/video_exporter.py)

Current overlay layers available:
- Skeleton (coaching-focused; face and finger landmarks are suppressed)
- Reference lines
- Swing path
- Club plane (confidence-gated from backend shaft-mask prompting near address, with fused 2D club data as fallback)
- Ball/contact evidence (cheap luma-change check around the likely address ball/contact zone)
- Phase markers (P1-P10 from dense event detection)
- Confidence evidence (phase confidence and impact/speed availability)
- Speed overlay
- Generic guide shapes for richer coaching checkpoints: `club_plane`, `shaft_checkpoints`, `clubhead_path`, `setup_geometry`, `head_reference`, `hip_depth`, `hand_depth`, `lead_arm_plane`, and `takeaway_checkpoint`

The unified renderer writes `base.mp4`, `annotation_metadata.json`, and `annotation_tracks.json` beside `annotated.mp4`. The app-facing `annotated_video` payload includes:
- `base_key` / `base_url` for a clean dense-window video when client-side overlays are available
- the rendered layer list (`name`, `color`, `description`, `enabled`)
- `tracks_key` / `tracks_url` for normalized, machine-readable overlay tracks, including top-level `phase_markers[]`, `confidence_evidence`, top-level `guide_layers[]`, and per-frame `layers.guides[]`
- top-level `ball_contact` when contact-zone evidence can be anchored from clubhead data

The annotated MP4 remains as a flattened compatibility render. True layer toggles should use `base_url` plus `tracks_url`, so disabling a layer removes the client-rendered overlay instead of leaving a burned-in server layer visible.

`layers.guides[]` is additive and uses normalized video coordinates so old clients can ignore it safely. Supported guide shape kinds are `line`, `arrow`, `polyline`, `rectangle`, `circle`, and `label`. Each guide carries an `id`, `layer`, optional display `label`, `color`, `confidence`, and the geometry fields needed for its shape. Low-confidence or unsupported detections should omit the affected guide shape instead of emitting an approximate coaching claim.

The guide builder is intentionally sparse. It samples shaft-mask work on key frames and clubhead path frames rather than running dense segmentation across the full video. Shaft and plane work must call `detect_shaft()` with prompt `"club shaft"`; broad `"golf club"` masks are not the source for shaft-plane claims. On local Apple Silicon, `EquipmentTracker` defaults to the MLX SAM3 image runtime when `detector_model/mlx_sam3` is available, with PyTorch SAM3 retained as the fallback.

Contract coverage:
- [test_annotation_tracks.py](../../test_annotation_tracks.py) verifies normalized skeleton/reference/path/club-plane/ball-contact layers, generic guides, phase marker source-frame mapping, confidence evidence generation, prompt-sourced shaft-plane preference, and the artifact boundary where `base.mp4`, `annotated.mp4`, `annotation_metadata.json`, and `annotation_tracks.json` are written together.
- [test_analysis_runs.py](../../test_analysis_runs.py) verifies async run progress events remain ordered and terminal state stores the analysis result.
- [test_event_detector.py](../../test_event_detector.py) verifies phase detection omits unavailable impact/downswing phases instead of indexing past the dense pose window.
- [test_annotation_visuals.py](../../test_annotation_visuals.py) verifies the fallback rendered overlay path at pixel level for skeleton, reference lines, club plane, and swing path, including layer-off behavior.
- `annotation_metadata.layers[]` is the UI layer contract. Every frame-level track layer, generic guide layer, and top-level toggle layer (`phase_markers`, `confidence`) should either appear there or be intentionally treated as a client-only fallback. `speed` is emitted as metadata when speed samples exist.

Frame extraction hardening:
- `FrameExtractor` now uses sequential frame numbering (not PTS-based naming) with numeric file sorting to preserve chronological order during PNG extraction.

### 3D replay artifact

- Body 3D detection: [body_3d.py](../../analysis/body_3d.py)
- 3D runner: [body3d_runner.py](../../analysis/body3d_runner.py)
- GLTF export: [animation_exporter.py](../../analysis/animation_exporter.py)

Output files:
- `base.mp4`
- `annotated.mp4`
- `annotation_metadata.json`
- `annotation_tracks.json`
- `swing_3d.gltf` (when valid 3D poses exist)

## Current Gaps

1. Club-plane overlay now prefers a dedicated `"club shaft"` prompt mask near address, but still needs real-video threshold tuning and fixture validation.
2. iOS can now download and draw overlay tracks over `base.mp4`; the flattened MP4 is still the fallback compatibility playback surface.
3. Ball/contact evidence is heuristic-only: it anchors from clubhead-at-address evidence and measures ball-region luma change near impact. It does not replace validated ball tracking.
4. The track contract covers skeleton, reference lines, club plane, ball/contact evidence, swing path, phase markers, confidence evidence, speed, and generic guide shapes. Club masks, clubface orientation, force/pressure claims, and richer shot/ball flight evidence still need validated data before UI exposure.
5. Pixel-level visual QA now covers deterministic overlay colors for core layers, but does not yet compare full rendered-frame golden images or real swing fixtures.

## Next Development Tasks

1. Validate club-plane and shaft-checkpoint rendering against real address shaft masks and tune confidence thresholds.
2. Replace or augment cheap ball/contact evidence with validated ball detections where the ball is visible.
3. Add club masks as optional track data only when their semantics are useful to the coaching surface; keep mask-heavy work backend-only.
4. Expand deterministic visual regression from color-count checks to full golden-image fixtures for representative DTL and FO swings.
5. Evaluate SAM 3.1 for server-side club/person/ball masks, while keeping the current light on-device detector separate from heavy backend segmentation.

## Model Direction

Meta's current Segment Anything line has moved beyond the older SAM/SAM 2 assumptions. SAM 3 added open-vocabulary concept detection, segmentation, and tracking for images and videos from text, exemplar, and visual prompts. SAM 3.1 is positioned by Meta as a drop-in SAM 3 replacement with faster multi-object video tracking through object multiplexing.

For SwingCoach, the practical path is:
- Use MLX SAM3 image on Apple Silicon for Mac-side pseudo-labeling and sparse backend annotation prompts when the task is independent image prompting.
- Evaluate SAM 3.1 separately if the task needs temporally consistent video-propagated masks or multi-object tracking.
- Keep lightweight on-device detection separate; do not try to run heavy SAM-class segmentation in the live capture loop.
- Treat golf-specific prompts (`club shaft`, `golf club`, `golfer`, `golf ball`) as candidates that need validation against real range footage before relying on them for coaching claims.

Local SAM3 runtime finding:

- Meta's official PyTorch `sam3` package is CUDA-first. In the current local setup, selecting `mps` did not move model weights or the processor off CPU.
- A community MPS patch can run image inference with `PYTORCH_ENABLE_MPS_FALLBACK=1`, but unsupported operations still fall back to CPU.
- MLX SAM3 image was the fastest tested Mac route for frame pseudo-labeling: 46.0s for 20 hard frames versus 237.6s for the CPU PyTorch route, with the same class-count outcome.
- Hugging Face Transformers SAM3 on MPS ran but reported missing text encoder weights and had severe runtime stalls; do not adopt it without another investigation.
- SAM3D is a separate model family and needs its own Apple Silicon/runtime validation.

Detailed findings live in [Experimental Swing Detector](../../../docs/EXPERIMENT_SWING_DETECTOR.md).

## Key Files

- [analysis/artifact_renderer.py](../../analysis/artifact_renderer.py)
- [analysis/visualizer.py](../../analysis/visualizer.py)
- [analysis/frame_extractor.py](../../analysis/frame_extractor.py)
- [analysis/animation_exporter.py](../../analysis/animation_exporter.py)
- [test_full_annotation.py](../../test_full_annotation.py)
