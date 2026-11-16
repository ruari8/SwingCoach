# Detector Modeling Tools

These scripts prepare and inspect the golf-object model training data.

Typical flow from the repository root:

```bash
tools/venv/bin/python detector_workbench/modeling/build_swing_frame_dataset.py
tools/venv/bin/python detector_workbench/modeling/mlx_sam3_relabel_frame_dataset.py --resume
tools/venv/bin/python detector_workbench/modeling/build_detector_training_dataset.py --overwrite
```

The relabel step runs MLX SAM3 from a clone, which brings its own packages (mlx, torchvision and others) on top of `tools/requirements.txt`:

```bash
git clone https://github.com/Deekshith-Dade/mlx_sam3.git detector_model/mlx_sam3
tools/venv/bin/pip install -e detector_model/mlx_sam3
```

The scripts read and write ignored artifacts under `detector_model/`; the scripts themselves are tracked because they define the reproducible modeling pipeline.
