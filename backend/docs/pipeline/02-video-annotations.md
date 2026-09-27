# Pipeline stage 2: visual evidence

The active renderer writes clean `base.mp4` and compatibility `annotated.mp4`,
plus normalized, timestamped `annotation_tracks.json`. The iOS player draws the
tracks and exposes layer toggles; annotation pixels are not baked into either MP4.

Two layers currently use the same confident body landmarks as the observations:

- `body_reference`: the current shoulder-to-hip midpoint line and a circle at
  the first reliable nose position. The circle is explicitly a first-visible
  reference, not an assumed address checkpoint.
- `hand_path`: a short trail of the midpoint of the two visible wrists. This is
  a hand path in the image, not a clubhead path or swing plane.

Landmarks need visibility >= 0.65 and normalized coordinates inside the frame.
Tracks appear near their sampled timestamp. A detector dropout clears the layer;
hand paths reset across gaps greater than 0.25 seconds. Source dimensions and
playback FPS remain in the contract. No generated phase markers, clubface,
shaft planes, contact points, speed badges or 3D replay are produced in this pass.

`annotation_metadata.json` lists the actual layers and `knowledge_coaching_v1`
mode. A run without accepted landmarks has an empty layer list. Clean video still
plays. The previous experimental annotation implementation remains at `abc12c4`.

The reference forms follow patterns catalogued in the coaching library. They
explain recorded movement; they do not establish that movement needs correction.
Future shaft work must use `detect_shaft()` with the `club shaft` prompt.

Main files: `analysis/video_observations.py`, `analysis/artifact_renderer.py`,
`analysis/pipeline_3d.py`, and the app's `AnalysisResultView.swift` overlay renderer.
