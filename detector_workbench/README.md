# Detector Tooling

Tracked detector tooling is split by responsibility:

- `modeling/`: model/data pipeline scripts for frame extraction, pseudo-labeling, YOLO dataset construction, and model visual QA.
- `validation/`: runtime detector validation scripts, labels, and the Swift/Core ML evaluator source.

Ignored heavy workspaces stay outside these tracked folders:

- `detector_model/`: exported videos, extracted frames, pseudo-label outputs, YOLO datasets, and model runs.
- `.detectorTestV3/`: local validation fixture videos and generated performance reports.
- `.videos/`: generated evaluator binaries, temporary clips, audio extracts, and reports.
