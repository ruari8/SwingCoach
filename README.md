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
3. Configure backend base URL in [SwingCoachAPI.swift](/Users/ruari/Documents/Startups/SwingCoach/SwingCoach/Models/SwingCoachAPI.swift) for your environment.

### Backend

```bash
cd backend
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
./venv/bin/python main.py
```

Optional 3D stack:

```bash
cd backend
./venv/bin/pip install -r requirements-3d.txt
```

## Current State

- Frontend capture/library/trim flows are implemented.
- Backend unified pipeline (`/analyze` + artifacts + `/chat`) is implemented.
- Frontend analysis decoding currently expects an older response model and still needs migration to backend `CoachableAnalysisResponse`.

