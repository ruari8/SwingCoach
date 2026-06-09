# Pipeline Stage 2: Video Annotations

## Current Status

Generated video annotations are intentionally disabled.

The previous implementation was committed as `abc12c4` (`experimental: annotation impl`) before the reset. The current backend keeps the API/artifact contract stable while the annotation set is redesigned from scratch.

## Current Output

For each completed analysis run, the renderer writes:

- `base.mp4`: clean source-timeline playback video
- `annotated.mp4`: currently the same clean video, kept for legacy response compatibility
- `annotation_metadata.json`: empty layer metadata
- `annotation_tracks.json`: normalized track envelope with no generated layers

`annotation_metadata.json` currently reports:

```json
{
  "layers": [],
  "pipeline_mode": "annotation_reset",
  "annotations_enabled": false
}
```

`annotation_tracks.json` currently keeps per-frame timing records but each frame has an empty `layers` object. There are no phase markers, confidence badges, guide layers, ball/contact evidence, shaft planes, pose skeletons, or path overlays.

## Disabled Work

The reset pipeline does not run:

- MediaPipe pose estimation
- Event/phase detection
- SAM3 equipment prompts
- Club path/shaft tracking
- Body 3D recovery
- Metric cards
- GLTF replay export

This avoids spending runtime on annotation behavior that is not yet agreed.

## Next Step

Before re-enabling automatic overlays, define the annotation contract:

1. Which coaching annotations are required.
2. What visual geometry each annotation must show.
3. Which detector or model source is authoritative for each annotation.
4. What confidence threshold hides the annotation instead of drawing a misleading shape.
5. What fixture videos prove the annotation is correct.

## Key Files

- [analysis/pipeline_3d.py](../../analysis/pipeline_3d.py)
- [analysis/artifact_renderer.py](../../analysis/artifact_renderer.py)
- [test_annotation_tracks.py](../../test_annotation_tracks.py)
