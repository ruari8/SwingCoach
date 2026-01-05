# SAM3 Setup Instructions for macOS (Apple Silicon)

This guide documents how to set up SAM3 (Meta's Segment Anything Model 3) on macOS with Apple Silicon, which required several patches to work without CUDA/Triton.

## Background

SAM3 was designed for Linux + NVIDIA GPUs. It has hard dependencies on:
- **Triton** - NVIDIA's GPU kernel compiler (not available on macOS)
- **CUDA** - hardcoded device references throughout the code
- **decord** - video library without macOS wheels

We've patched the installed SAM3 package to work on macOS. These patches are applied directly to the `venv/lib/python3.13/site-packages/sam3/` directory.

---

## Step 1: Initial Setup (Already Done)

The following was already completed:

```bash
cd /Users/n1642006/personal-docs/SwingCoach/backend
python3 -m venv venv
source venv/bin/activate

# Install base dependencies
pip install torch torchvision
pip install mediapipe opencv-python Pillow

# Install SAM3 from GitHub
pip install 'git+https://github.com/facebookresearch/sam3.git'

# Install additional required dependencies
pip install einops scipy pycocotools psutil
```

---

## Step 2: Apply macOS Patches (Already Done)

The following files were patched in `venv/lib/python3.13/site-packages/sam3/`:

### 2.1 `model/edt.py` - Triton fallback
- Made triton import conditional with `HAS_TRITON` flag
- Added `edt_cpu_fallback()` using scipy's `distance_transform_edt`
- Modified `edt_triton()` to use CPU fallback when triton unavailable

### 2.2 `train/data/sam3_image_dataset.py` - decord fallback
- Made decord import conditional with `HAS_DECORD` flag

### 2.3 `model/position_encoding.py` - CUDA → auto-detect
- Changed `device="cuda"` to auto-detect: `device = "cuda" if torch.cuda.is_available() else "cpu"`

### 2.4 `model/decoder.py` - CUDA → auto-detect
- Same fix for hardcoded CUDA device

### 2.5 `model/sam3_image_processor.py` - CUDA → auto-detect
- Changed `device="cuda"` default to `device=None` with auto-detection

### 2.6 `model/vl_combiner.py` - CUDA → auto-detect
- Fixed both `forward_text()` and `_forward_text_no_ack_ckpt()` methods

### 2.7 `model/geometry_encoders.py` - pin_memory fix
- Added conditional for `pin_memory()` which only works on CUDA:
```python
if boxes_xyxy.device.type == "cuda":
    scale = scale.pin_memory().to(device=boxes_xyxy.device, non_blocking=True)
else:
    scale = scale.to(device=boxes_xyxy.device)
```

---

## Step 3: Download Model Weights (TO DO)

SAM3 model weights (~2-3GB) need to be downloaded from HuggingFace.

### Option A: Direct Download (if HuggingFace accessible)

1. Go to: https://huggingface.co/facebook/sam3
2. Download the model files (look for `.pt` or `.pth` files)
3. Save to: `backend/models/sam3/`

### Option B: Using huggingface-cli

```bash
source venv/bin/activate
pip install huggingface_hub

# Login if needed (for gated models)
huggingface-cli login

# Download the model
huggingface-cli download facebook/sam3 --local-dir ./models/sam3
```

### Option C: Python download

```python
from huggingface_hub import snapshot_download

snapshot_download(
    repo_id="facebook/sam3",
    local_dir="./models/sam3",
    local_dir_use_symlinks=False
)
```

---

## Step 4: Test SAM3 Import

After setup, verify the import works:

```bash
cd backend
source venv/bin/activate
python -c "from sam3.model_builder import build_sam3_image_model; print('SAM3 import successful!')"
```

Expected output:
```
SAM3 import successful!
```

(Ignore the `pkg_resources` deprecation warning and CUDA availability warning)

---

## Step 5: Load Model with Local Weights

Once weights are downloaded, load the model:

```python
import torch
from sam3.model_builder import build_sam3_image_model
from sam3.model.sam3_image_processor import Sam3Processor

# Detect device (MPS for Apple Silicon, CPU as fallback)
device = "mps" if torch.backends.mps.is_available() else "cpu"
print(f"Using device: {device}")

# Build model - may need to specify checkpoint path
model = build_sam3_image_model(device=device)

# Create processor for inference
processor = Sam3Processor(model, device=device)
```

---

## Step 6: Basic Inference Test

```python
from PIL import Image

# Load test image
image = Image.open("path/to/golf_frame.jpg")

# Set image
state = processor.set_image(image)

# Segment with text prompt
state = processor.set_text_prompt("golf club", state)

# Get results
masks = state["masks"]
boxes = state["boxes"]
scores = state["scores"]

print(f"Found {len(masks)} objects")
```

---

## Troubleshooting

### SSL Certificate Errors
If you get SSL errors downloading from HuggingFace:
```bash
# Install/update certificates
pip install --upgrade certifi

# On macOS, you may need to run:
/Applications/Python\ 3.13/Install\ Certificates.command
```

Or set environment variables:
```python
import os
import certifi
os.environ['SSL_CERT_FILE'] = certifi.where()
os.environ['REQUESTS_CA_BUNDLE'] = certifi.where()
```

### Memory Issues on MPS
Apple Silicon has unified memory, but you may still hit limits:
```python
# Use smaller resolution
processor = Sam3Processor(model, resolution=512, device=device)  # default is 1008
```

### "CUDA not available" warnings
These are expected and harmless on macOS. SAM3 will still work with MPS/CPU.

---

## File Structure After Setup

```
backend/
├── venv/
│   └── lib/python3.13/site-packages/sam3/  # Patched SAM3
├── models/
│   ├── pose_landmarker_heavy.task          # MediaPipe model
│   └── sam3/                               # SAM3 weights (to download)
│       ├── config.json
│       └── *.pt                            # Model weights
├── analysis/
│   ├── visualizer.py                       # Our skeleton visualizer
│   └── equipment_tracker.py                # TODO: SAM3 club tracking
└── SAM3_SETUP.md                           # This file
```

---

## Next Steps

1. Download SAM3 weights on a device with HuggingFace access
2. Test model loading and basic inference
3. Create `equipment_tracker.py` that uses SAM3 to:
   - Detect and track the golf club head
   - Detect and track the golf ball
   - Calculate club plane angles
4. Integrate with existing `SwingVisualizer` to overlay club tracking

---

## References

- SAM3 GitHub: https://github.com/facebookresearch/sam3
- SAM3 HuggingFace: https://huggingface.co/facebook/sam3
- macOS compatibility issue: https://github.com/facebookresearch/sam3/issues/179
- Original patch source: GitHub issue #179 comment by @benjaminleroy
