# SwingCoach Backend

Backend API for golf swing analysis using Cloudflare R2 storage, MediaPipe pose detection, and SAM3 object segmentation.

## Quick Start (macOS Apple Silicon)

```bash
cd backend

# 1. Create virtual environment
python3 -m venv venv
source venv/bin/activate

# 2. Install dependencies
pip install -r requirements.txt

# 3. Install SAM3 (for club/ball tracking)
pip install 'git+https://github.com/facebookresearch/sam3.git'
pip install einops scipy pycocotools psutil

# 4. Patch SAM3 for macOS compatibility
python patch_sam3.py

# 5. Download SAM3 model weights (see SAM3_SETUP.md)

# 6. Configure R2 credentials
cp .env.example .env
# Edit .env with your Cloudflare R2 credentials

# 7. Run the server
python main.py
```

## SAM3 Setup (macOS)

SAM3 requires patching to work on macOS (no CUDA/Triton). After installing:

```bash
python patch_sam3.py
```

This patches 7 files to:
- Replace Triton GPU kernels with scipy CPU fallback
- Auto-detect device (MPS/CPU) instead of hardcoding CUDA
- Fix `pin_memory()` calls that fail on non-CUDA devices

See [SAM3_SETUP.md](SAM3_SETUP.md) for detailed instructions including model weight download.

---

## Setup (Full Instructions)

### 1. Install Python dependencies

```bash
cd backend
python3 -m venv venv
source venv/bin/activate  # On macOS/Linux
pip install -r requirements.txt
```

### 2. Install SAM3 for club/ball tracking (optional)

```bash
# Install SAM3 from GitHub
pip install 'git+https://github.com/facebookresearch/sam3.git'

# Install additional dependencies
pip install einops scipy pycocotools psutil

# Patch for macOS compatibility
python patch_sam3.py

# Download model weights - see SAM3_SETUP.md
```

### 3. Configure R2 credentials

```bash
cp .env.example .env
# Edit .env and add your Cloudflare R2 credentials
```

Get credentials from: https://dash.cloudflare.com → R2 → Manage R2 API Tokens

### 4. Run the server

```bash
python main.py
# Or use uvicorn directly:
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### 5. Test the API

```bash
# Health check
curl http://localhost:8000/health

# Get upload URL
curl http://localhost:8000/upload-url
```

---

## API Endpoints

### `GET /health`
Health check - verifies R2 is configured.

### `GET /upload-url`
Returns a pre-signed URL for uploading a video to R2.

Response:
```json
{
  "upload_url": "https://...presigned-url...",
  "video_key": "swings/abc-123.mp4"
}
```

### `POST /analyze`
Analyzes a swing video that has been uploaded to R2.

Request:
```json
{
  "video_key": "swings/abc-123.mp4",
  "vantage": "DTL"
}
```

Response:
```json
{
  "summary": "Your swing shows early extension...",
  "metrics": {
    "Head Sway": "4.2 inches",
    "Hip Slide": "2.1 inches"
  },
  "drill_links": [
    {
      "title": "Fix Early Extension",
      "url": "https://youtube.com/...",
      "platform": "youtube"
    }
  ]
}
```

---

## Architecture

```
iOS App
  ↓
  1. GET /upload-url  →  Backend generates pre-signed URL
  ↓
  2. PUT <video>  →  Directly to R2 (not through backend)
  ↓
  3. POST /analyze  →  Backend downloads from R2, analyzes, returns results
```

### Analysis Pipeline

```
Video → Frame Extraction → Pose Detection → Event Detection → Metrics → Coaching
         (OpenCV)          (MediaPipe)       (P1-P10)         (angles)   (rules)
                                ↓
                           SAM3 (optional)
                           Club/Ball Tracking
```

---

## Project Structure

```
backend/
├── analysis/
│   ├── __init__.py
│   ├── coach.py              # Coaching recommendations
│   ├── event_detector.py     # Swing phase detection
│   ├── frame_extractor.py    # Video frame extraction
│   ├── metrics.py            # Biomechanical calculations
│   ├── pose_detector.py      # MediaPipe pose detection
│   └── visualizer.py         # Skeleton/reference line overlay
├── models/
│   ├── pose_landmarker_heavy.task  # MediaPipe model
│   └── sam3/                       # SAM3 weights (download separately)
├── output/                   # Generated visualizations
├── main.py                   # FastAPI app and endpoints
├── models.py                 # Pydantic schemas
├── r2_client.py              # Cloudflare R2 storage client
├── patch_sam3.py             # SAM3 macOS compatibility patches
├── test_pipeline.py          # Full analysis pipeline test
├── test_visualizer.py        # Visualization test
├── requirements.txt          # Python dependencies
├── SAM3_SETUP.md             # SAM3 setup instructions
├── .env                      # Configuration (not committed)
└── .env.example              # Template for .env
```

---

## Development

The server runs on `0.0.0.0:8000` by default. To connect from your iOS device:

1. Make sure your Mac and iPhone are on the same WiFi
2. Find your Mac's IP: `ipconfig getifaddr en0`
3. In your iOS app, use `http://<your-mac-ip>:8000`

### Running Tests

```bash
source venv/bin/activate

# Test visualization
python test_visualizer.py

# Test full pipeline
python test_pipeline.py
```

---

## Features Implemented

- [x] Frame extraction (OpenCV)
- [x] Pose detection (MediaPipe)
- [x] Event detection (address, top, impact)
- [x] DTL metrics calculation (hip sway, shoulder tilt, spine angle)
- [x] Skeleton overlay visualization
- [x] Reference line visualization (shoulder plane, spine)
- [x] SAM3 macOS compatibility patches
- [ ] SAM3 club/ball tracking
- [ ] Annotated video export
- [ ] Full P1-P10 swing phases

---

## Troubleshooting

### SAM3 Import Errors

If you get `ModuleNotFoundError: No module named 'triton'`:
```bash
python patch_sam3.py
```

### SSL Certificate Errors (HuggingFace)

If downloading SAM3 weights fails with SSL errors:
```bash
# On macOS, install certificates:
/Applications/Python\ 3.13/Install\ Certificates.command

# Or download weights manually from browser
```

### MediaPipe Not Found

```bash
pip install mediapipe
```
