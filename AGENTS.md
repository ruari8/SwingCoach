# AGENTS.md - SwingCoach AI Golf Coach

## Project Overview

SwingCoach is an AI-powered golf coaching application. Users record their swing on a phone, the backend pipeline performs visual analysis and physics calculations, detects swing faults, and recommends drills/feels to fix issues - replicating what a real golf coach does.

### Architecture

```
SwingCoach/
├── backend/                 # Python analysis pipeline
│   ├── analysis/            # Core analysis modules
│   ├── models/              # ML models (MediaPipe, SAM3)
│   ├── swingVideos/         # Test videos
│   ├── output/              # Generated outputs (gitignored)
│   └── test_*.py            # Test scripts
├── SwingCoach/              # iOS Swift app (Xcode)
└── SwingCoach.xcodeproj/    # Xcode project
```

---

## Build & Run Commands

### Backend Setup

```bash
cd backend
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
```

### Running Tests

```bash
cd backend

# Quick plane line test (single frame, ~15 sec)
./venv/bin/python test_plane_line.py

# Full annotation test - sampled (~15 sec, 12 frames)
./venv/bin/python test_full_annotation.py --sample

# Full annotation test - all frames (~2-3 min, 500+ frames)
./venv/bin/python test_full_annotation.py

# Pose/skeleton visualization test
./venv/bin/python test_visualizer.py

# SAM3 prompt comparison test
./venv/bin/python test_sam3_detection.py

# Pipeline test (pose + metrics + coach)
./venv/bin/python test_pipeline.py
```

### Output Files

| Test | Output |
|------|--------|
| test_plane_line.py | `output/plane_line.png` |
| test_full_annotation.py | `output/full_annotation.mp4` or `*_sampled.mp4` |
| test_visualizer.py | `output/skeleton_*.png` |
| test_sam3_detection.py | `output/sam3_diagnostic/*.png` |

---

## Backend Analysis Modules

### Working Features

| Module | Purpose | Status |
|--------|---------|--------|
| `pose_detector.py` | MediaPipe pose estimation (33 keypoints) | ✅ Working |
| `frame_extractor.py` | Extract frames, handles rotation metadata | ✅ Working |
| `club_analyzer.py` | PCA on shaft mask → angle + plane line | ✅ Working |
| `equipment_tracker.py` | SAM3 detection ("club shaft", "golf ball") | ✅ Working |
| `visualizer.py` | Draw skeleton, reference lines, plane line | ✅ Working |
| `video_exporter.py` | Export annotated frames to MP4 | ✅ Working |
| `event_detector.py` | Detect swing events (address, top, impact, finish) | ✅ Working |

### Needs Work

| Module | Purpose | Status |
|--------|---------|--------|
| `metrics.py` | Calculate swing metrics from poses | ⚠️ Unreliable |
| `coach.py` | LLM-based coaching feedback | ⚠️ Not tested |

### Deleted (restart fresh later)

- `swing_path_tracker.py` - clubhead tracking through frames

---

## Code Style Guidelines

### Python Version
- Python 3.11+ (tested on 3.13)

### Imports
```python
# Standard library first
import sys
import logging
from pathlib import Path
from typing import Optional, List, Tuple, Any

# Third-party second
import numpy as np
from PIL import Image

# Local imports last
from analysis import FrameExtractor, PoseDetector
from analysis.equipment_tracker import EquipmentTracker
```

### Naming Conventions
- Files: `snake_case.py`
- Classes: `PascalCase` (e.g., `ClubAnalyzer`, `SwingVisualizer`)
- Functions/methods: `snake_case` (e.g., `detect_shaft`, `get_extended_plane_line`)
- Constants: `UPPER_SNAKE_CASE` (e.g., `POSE_CONNECTIONS`, `COLORS`)
- Private methods: `_leading_underscore` (e.g., `_normalize_mask`)

### Type Hints
- Always use type hints for function signatures
- Use `Optional[T]` for nullable types
- Use `Any` sparingly (mainly for numpy arrays, PIL images)

```python
def detect_shaft(
    self,
    frame_bytes: bytes,
    frame_index: int = 0
) -> Optional[ShaftDetection]:
```

### Error Handling
- Return `None` for recoverable failures (e.g., no detection)
- Use logging for warnings/errors, don't print
- Use context managers for resources (`with EquipmentTracker() as tracker:`)

```python
if detection is None:
    logger.warning("No shaft detected in frame 0")
    return None
```

### Logging
- Use module-level logger: `logger = logging.getLogger(__name__)`
- Progress logs every 30 frames (not every frame)
- INFO for major steps, DEBUG for details, WARNING for recoverable issues

---

## Key Technical Details

### SAM3 Text Prompts
- `"club shaft"` - for plane line (detects shaft only, 0.77 confidence)
- `"golf club"` - detects full club including head (0.81 confidence)
- `"golf ball"` - ball detection (0.76 confidence)

**Important**: Use `detect_shaft()` for plane line, NOT `detect_club()`.

### Video Rotation
- Phone videos have rotation metadata (-90°, 90°, etc.)
- `frame_extractor.py` handles this automatically
- Dimensions are swapped when needed (1920x1080 → 1080x1920)

### Coordinate Systems
- Image coords: (0,0) top-left, y increases downward
- Normalized coords: (0-1, 0-1) for poses
- Pixel coords: (x, y) in pixels for drawing

### Plane Line Calculation
1. Detect shaft mask with SAM3 prompt "club shaft"
2. Run PCA on mask pixels to find principal axis
3. Find shaft endpoints (clubhead = bottom, hands = top)
4. Line starts at clubhead, extends past hands
5. Fixed from address frame (frame 0), drawn on all frames

---

## Common Pitfalls

1. **Wrong SAM3 prompt**: Use "club shaft" not "golf club" for plane line
2. **Video rotation**: Always use `get_video_info_from_file()` for correct dimensions
3. **Context managers**: Always use `with EquipmentTracker()` and `with PoseDetector()`
4. **Numpy warnings**: Use `np.errstate()` for expected numerical issues
5. **Frame sampling**: Use `sample_rate` param, not manual slicing

---

## iOS App (SwingCoach/)

Swift/SwiftUI app with:
- `CaptureView.swift` - Video recording
- `TrimView/` - Video trimming UI
- `AnalyseView.swift` - Analysis display
- `SwingCoachAPI.swift` - Backend communication
- `SwingLibrary.swift` - Local video storage

---

## Future Work

- [ ] Swing path tracking (clubhead trajectory through frames)
- [ ] Reliable metrics calculation
- [ ] LLM coaching integration
- [ ] Frontend layer toggling (skeleton, reference lines, plane line)
- [ ] Attack angle, club path, face angle calculations
