# Pipeline Stage 2: Video Annotations

## Goal

Generate visual proof for coaching by rendering analysis overlays and replay artifacts.

## What Is Implemented

### 2D annotated video

- Renderer: [artifact_renderer.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/artifact_renderer.py)
- Overlay engine: [visualizer.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/visualizer.py)
- Exporter: [video_exporter.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/video_exporter.py)

Current overlay layers available:
- Skeleton (coaching-focused; face and finger landmarks are suppressed)
- Reference lines
- Swing path
- Club plane (confidence-gated from fused 2D club shaft/head data near address)
- Ball/contact evidence (cheap luma-change check around the likely address ball/contact zone)
- Phase markers (P1-P10 from dense event detection)
- Confidence evidence (phase confidence and impact/speed availability)
- Speed overlay

The unified renderer writes `base.mp4`, `annotation_metadata.json`, and `annotation_tracks.json` beside `annotated.mp4`. The app-facing `annotated_video` payload includes:
- `base_key` / `base_url` for a clean dense-window video when client-side overlays are available
- the rendered layer list (`name`, `color`, `description`, `enabled`)
- `tracks_key` / `tracks_url` for normalized, machine-readable overlay tracks, including top-level `phase_markers[]` and `confidence_evidence`
- top-level `ball_contact` when contact-zone evidence can be anchored from clubhead data

The annotated MP4 remains as a flattened compatibility render. True layer toggles should use `base_url` plus `tracks_url`, so disabling a layer removes the client-rendered overlay instead of leaving a burned-in server layer visible.

Contract coverage:
- [test_annotation_tracks.py](/Users/ruari/Documents/Startups/SwingCoach/backend/test_annotation_tracks.py) verifies normalized skeleton/reference/path/club-plane/ball-contact layers, phase marker source-frame mapping, confidence evidence generation, and the artifact boundary where `base.mp4`, `annotated.mp4`, `annotation_metadata.json`, and `annotation_tracks.json` are written together.
- [test_annotation_visuals.py](/Users/ruari/Documents/Startups/SwingCoach/backend/test_annotation_visuals.py) verifies the fallback rendered overlay path at pixel level for skeleton, reference lines, club plane, and swing path, including layer-off behavior.
- `annotation_metadata.layers[]` is the UI layer contract. Every frame-level track layer and top-level toggle layer (`phase_markers`, `confidence`) should either appear there or be intentionally treated as a client-only fallback. `speed` is emitted as metadata when speed samples exist.

Frame extraction hardening:
- `FrameExtractor` now uses sequential frame numbering (not PTS-based naming) with numeric file sorting to preserve chronological order during PNG extraction.

### 3D replay artifact

- Body 3D detection: [body_3d.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/body_3d.py)
- 3D runner: [body3d_runner.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/body3d_runner.py)
- GLTF export: [animation_exporter.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/animation_exporter.py)

Output files:
- `base.mp4`
- `annotated.mp4`
- `annotation_metadata.json`
- `annotation_tracks.json`
- `swing_3d.gltf` (when valid 3D poses exist)

## Current Gaps

1. Club-plane overlay is a first pass based on the best confident fused shaft direction near address; it is not yet validated against a dedicated address shaft mask.
2. iOS can now download and draw overlay tracks over `base.mp4`; the flattened MP4 is still the fallback compatibility playback surface.
3. Ball/contact evidence is heuristic-only: it anchors from clubhead-at-address evidence and measures ball-region luma change near impact. It does not replace validated ball tracking.
4. The track contract covers skeleton, reference lines, club plane, ball/contact evidence, swing path, phase markers, confidence evidence, and speed. Club masks and richer shot/ball flight evidence still need explicit track data.
5. Pixel-level visual QA now covers deterministic overlay colors for core layers, but does not yet compare full rendered-frame golden images or real swing fixtures.

## Next Development Tasks

1. Validate club-plane rendering against real address shaft masks and tune confidence thresholds.
2. Replace or augment cheap ball/contact evidence with validated ball detections where the ball is visible.
3. Add club masks as optional track data and decide whether iOS should draw masks or request separate server renders.
4. Expand deterministic visual regression from color-count checks to full golden-image fixtures for representative DTL and FO swings.
5. Evaluate SAM 3.1 for server-side club/person/ball masks, while keeping the current light on-device detector separate from heavy backend segmentation.

## Model Direction

Meta's current Segment Anything line has moved beyond the older SAM/SAM 2 assumptions. SAM 3 added open-vocabulary concept detection, segmentation, and tracking for images and videos from text, exemplar, and visual prompts. SAM 3.1 is positioned by Meta as a drop-in SAM 3 replacement with faster multi-object video tracking through object multiplexing.

For SwingCoach, the practical path is:
- Use SAM 3.1 server-side for annotation-quality masks when GPU resources are available.
- Keep lightweight on-device detection separate; do not try to run heavy SAM-class segmentation in the live capture loop.
- Treat golf-specific prompts (`club shaft`, `golf club`, `golfer`, `golf ball`) as candidates that need validation against real range footage before relying on them for coaching claims.

## Key Files

- [analysis/artifact_renderer.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/artifact_renderer.py)
- [analysis/visualizer.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/visualizer.py)
- [analysis/frame_extractor.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/frame_extractor.py)
- [analysis/animation_exporter.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/animation_exporter.py)
- [test_full_annotation.py](/Users/ruari/Documents/Startups/SwingCoach/backend/test_full_annotation.py)
