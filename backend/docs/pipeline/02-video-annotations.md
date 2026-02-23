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
- Speed overlay
- Club plane API exists but is not fully wired in unified render path

Frame extraction hardening:
- `FrameExtractor` now uses sequential frame numbering (not PTS-based naming) with numeric file sorting to preserve chronological order during PNG extraction.

### 3D replay artifact

- Body 3D detection: [body_3d.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/body_3d.py)
- 3D runner: [body3d_runner.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/body3d_runner.py)
- GLTF export: [animation_exporter.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/animation_exporter.py)

Output files:
- `annotated.mp4`
- `swing_3d.gltf` (when valid 3D poses exist)

## Current Gaps

1. Unified path currently leaves persistent club-plane overlay disabled.
2. Frame index consistency issues can affect speed/path overlays.
3. Annotation layer metadata for frontend control is still minimal.
4. Visual QA baseline set is not yet formalized.

## Next Development Tasks

1. Re-enable robust club-plane rendering in unified artifacts.
2. Add event markers and confidence badges into overlays.
3. Create deterministic visual regression test set (same inputs, expected overlays).
4. Expose layer toggles and metadata contract for frontend playback controls.

## Key Files

- [analysis/artifact_renderer.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/artifact_renderer.py)
- [analysis/visualizer.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/visualizer.py)
- [analysis/frame_extractor.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/frame_extractor.py)
- [analysis/animation_exporter.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/animation_exporter.py)
- [test_full_annotation.py](/Users/ruari/Documents/Startups/SwingCoach/backend/test_full_annotation.py)
