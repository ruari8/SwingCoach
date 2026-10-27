#!/usr/bin/env python3
"""Compare the app's swing positions (harness.swift JSON) with the training
pipeline on the same clips: Vision pose on every frame (detectSwings
vision_pose_extract), dataset.py features, PyTorch tcn_vision_v2, monotonic
decode. Run with the detectSwings venv; see docs/SWING_POSITIONS.md.

  parity.py <detectSwings dir> <vision_pose_extract binary> <harness out-dir> <timeScale> <clip.mp4>...
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import torch

detect_swings, extractor, harness_out, time_scale = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]), float(sys.argv[4])
sys.path.insert(0, str(detect_swings / "event_model"))
from dataset import build_features, resample_indices  # noqa: E402
from model import TCNSpotter, decode_monotonic  # noqa: E402

# The app shifts P1 and P10 by these many 30 fps slots (SwingPositionAnalyzer).
OFFSETS = {1: -1.4, 10: 1.8}

ck = torch.load(detect_swings / "event_model/runs/tcn_vision_v2/best.pt", map_location="cpu", weights_only=False)
hidden, in_dim, _ = ck["state"]["proj.weight"].shape
model = TCNSpotter(in_dim=in_dim, hidden=hidden)
model.load_state_dict(ck["state"])
model.eval()

for clip in sys.argv[5:]:
    with tempfile.NamedTemporaryFile(suffix=".bin") as tmp:
        subprocess.run([extractor, clip, tmp.name], check=True, capture_output=True)
        raw = np.fromfile(tmp.name, dtype=np.float32).reshape(-1, 19, 3)
    lm = np.zeros((len(raw), 19, 4), np.float32)
    lm[:, :, :2] = raw[:, :, :2]
    lm[:, :, 3] = raw[:, :, 2]
    feats = build_features({"lm": lm, "ok": raw[:, :, 2].max(axis=1) > 0})
    idx = resample_indices(len(raw), 30.0, time_scale)
    with torch.no_grad():
        logits = model(torch.from_numpy(feats[idx][:, :in_dim]).unsqueeze(0))[0].numpy()
    reference = [int(x) for x in decode_monotonic(logits)]
    app = json.load(open(harness_out / f"{Path(clip).stem}.json"))["positions"]
    app_slots = [round(p["clipTime"] / time_scale * 30 - OFFSETS.get(p["number"], 0)) for p in app]
    print(Path(clip).name)
    print("  training pipeline:", reference)
    print("  app              :", app_slots)
    print("  difference       :", [a - b for a, b in zip(app_slots, reference)])
