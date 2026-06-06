# AGENTS.md - SwingCoach

## Mission

SwingCoach is an AI golf coaching system combining:
- iOS capture/library/analysis UI
- Python backend for metrics, annotations, drills, and coaching summaries

This file is the operator/LLM quick guide. Detailed docs are listed below.

## Canonical Documentation

- [Root README](./README.md)
- [Docs Index](./docs/README.md)
- [Frontend Documentation](./docs/FRONTEND.md)
- [Backend README](./backend/README.md)
- [Backend Docs Index](./backend/docs/README.md)

## Documentation Maintenance Rule

When behavior changes in code, update the canonical docs in the same change.
Do not ship behavior changes without matching documentation updates.

## Repository Map

```text
SwingCoach/
├── SwingCoach/               # iOS app
├── SwingCoach.xcodeproj/
├── backend/                  # API + analysis pipeline
│   ├── analysis/
│   ├── data/
│   ├── output/
│   └── test_*.py
├── docs/                     # Canonical project/frontend docs
└── AGENTS.md
```

## Fast Command Reference

### Backend setup

```bash
cd backend
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
```

### Run backend

```bash
cd backend
./venv/bin/python main.py
```

### Key backend tests

```bash
cd backend
./venv/bin/python test_pipeline_3d.py
./venv/bin/python test_full_annotation.py --sample
./venv/bin/python test_temporal_smoothing.py
```

## Pipeline Stage Status (High-level)

1. Metrics
- Implemented in unified pipeline; still needs stronger calibration/validation before high-confidence claims.

2. Video annotations
- Annotated MP4 and optional 3D replay are implemented; overlay consistency and plane rendering need more hardening.

3. Drills/feels
- Basic curated corpus and mapping logic exist; content depth and personalization are early-stage.

4. Teaching voice
- Summary and chat are implemented with fallback behavior; pedagogy logic is still lightweight.

## Technical Guardrails

1. Use `detect_shaft()` with prompt `"club shaft"` when the goal is shaft/plane work.
2. Use context managers for heavy detectors (`with PoseDetector()`, `with EquipmentTracker()`, `with Body3DDetector()` patterns).
3. Treat confidence as first-class output. If confidence is low, communicate uncertainty explicitly.
