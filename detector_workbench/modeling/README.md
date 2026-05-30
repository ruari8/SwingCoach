# Detector Modeling Tools

These scripts prepare and inspect the golf-object model training data.

Typical flow from the repository root:

```bash
./backend/venv/bin/python detector_workbench/modeling/build_swing_frame_dataset.py
./backend/venv/bin/python detector_workbench/modeling/mlx_sam3_relabel_frame_dataset.py --resume
./backend/venv/bin/python detector_workbench/modeling/build_detector_training_dataset.py --overwrite
```

The scripts read and write ignored artifacts under `detector_model/`; the scripts themselves are tracked because they define the reproducible modeling pipeline.
