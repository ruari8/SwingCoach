# SwingCoach

SwingCoach is an AI golf coaching app with an iOS frontend and a Python backend.

The product goal is to deliver coachable feedback from phone video through four pipeline outcomes:
1. Accurate metrics
2. Visual annotations
3. Drill/feel recommendations
4. Teaching voice that ties the above together

## Repository Layout

```text
SwingCoach/
├── SwingCoach/                 # iOS SwiftUI app
├── SwingCoach.xcodeproj/       # Xcode project
├── backend/                    # FastAPI + analysis pipeline
├── docs/                       # Canonical project/frontend docs
└── AGENTS.md                   # LLM/operator instructions
```

## Canonical Documentation

- [Project Docs Index](docs/README.md)
- [Frontend Documentation](docs/FRONTEND.md)
- [Backend Overview](backend/README.md)
- [Backend Docs Index](backend/docs/README.md)
- [AGENTS Instructions](AGENTS.md)

## Quick Start

### iOS App

1. Open [SwingCoach.xcodeproj](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach.xcodeproj) in Xcode.
2. Build and run the `SwingCoach` target on device.
3. DEBUG builds default to the local backend at `http://127.0.0.1:8000` and real async analysis runs. Use Library > Experiments to switch to the deployed backend, a custom LAN URL, or mock analysis.

### Backend

```bash
cd backend
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
./venv/bin/python main.py
```

For Simulator, the default local app target reaches this server directly. For a physical iPhone, set a custom backend URL in Experiments using your Mac's LAN IP, for example `http://192.168.1.23:8000`.

Optional 3D stack:

```bash
cd backend
./venv/bin/pip install -r requirements-3d.txt
```

## Current State

- Frontend capture/library/trim flows are implemented, including experimental `SwingDetectorV2` YOLO/Core ML preselection of likely swing clips during capture and editable preselected clips in the trim editor. Capture, imported Trim detection, and DEBUG Replay Debug now use the same V2 detector core with configurable real-time low sample rates and V2-owned adaptive burst sampling.
- Backend unified pipeline (`/analysis-runs` + SSE progress + artifacts + `/chat`) is implemented, with legacy synchronous `/analyze` still available.
- Frontend analysis decoding uses the lightweight MVP analysis response: summary, display metrics, annotated/base video artifacts, normalized overlay tracks, and drills. Swing Detail can render server guide overlays over the clean base video and supports local manual drawing annotations for self-analysis.
