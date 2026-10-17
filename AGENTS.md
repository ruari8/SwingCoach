# AGENTS.md - SwingCoach

## Mission

SwingCoach is an AI golf coaching system combining:
- iOS capture/library/analysis UI
- Python backend for observations, overlays, sourced coaching, and chat

This file is the operator/LLM quick guide. Detailed docs are listed below.

## Canonical Documentation

- [Root README](./README.md)
- [Docs Index](./docs/README.md)
- [Frontend Documentation](./docs/FRONTEND.md)
- [Backend README](./backend/README.md)
- [Backend Docs Index](./backend/docs/README.md)
- [Investigation status index](./docs/evidence/README.md)

## Documentation Maintenance Rule

When behavior changes in code, update the canonical docs in the same change.
Do not ship behavior changes without matching documentation updates.
When a file in this map is renamed, deleted, or stops being live, update this file too.

## Agent skills

### Issue tracker

Issues and specs are tracked in GitHub Issues for `ruari8/SwingCoach`. See `docs/agents/issue-tracker.md`.

### Triage labels

Triage uses the standard `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix` labels. See `docs/agents/triage-labels.md`.

### Domain docs

Domain documentation uses the single-context layout. See `docs/agents/domain.md`.

### UI playground and Simulator demos

For UI design iterations or showing Simulator work, read [UI playground](./docs/UI_PLAYGROUND.md). Ruari prefers the native browser mirror; preserve and extend the repo's reusable playground.

Default to one automated UI verification pass when the implementation is PR-ready, before committing. Reuse passing results. Run earlier or repeat only the affected checks when a specific bug, meaningful behavior change, or new evidence warrants it. Documentation edits, Git operations without behavior changes, and screenshot-capture adjustments do not justify rerunning the full suite.

### Physical iPhone

Device IDs, the signed build, install-over-existing, and app-data pulls are in the `verify-swingcoach` skill's [testing ladder](./.agents/skills/verify-swingcoach/references/testing-ladder.md#physical-iphone-recipe). Do not guess device IDs.

## Test Environment

- The test backend is the VPS at `https://swingcoach-api.ruari.dev` ([deployment](./docs/DEPLOYMENT.md)). Every endpoint except `/health` needs the `X-SwingCoach-Key` header.
- Coaching AI runs through the signed-in ChatGPT plan via `SWINGCOACH_COACH_PROVIDER=codex` (`backend/analysis/codex_client.py`), not OpenAI API billing. Do not suggest buying API credits or moving testing to a Mac-local backend unless asked.
- `scripts/run-local-backend.sh` starts a Mac backend the same way, for when local is explicitly wanted.

## Repository Map

```text
SwingCoach/
├── SwingCoach/                    # iOS app (flat; there is no Views/ folder)
│   ├── Models/                    # detectors, capture buffer, library, API client
│   ├── TrimView/
│   └── MLModels/                  # Core ML: SwingObjectsYOLO11n, SwingEventTCN
├── SwingCoachTests/
├── backend/
│   ├── main.py                    # FastAPI endpoints
│   ├── analysis/                  # live pipeline + legacy modules (see below)
│   ├── docs/pipeline/             # current per-stage pipeline docs
│   └── test_*.py                  # standalone scripts, not pytest
├── detector_workbench/            # detector datasets, training, validation
├── docs/
│   ├── evidence/                  # dated investigations; status index in README
│   ├── coaching-knowledge/        # sourced coaching cases used by the backend
│   ├── adr/  audits/  research/
│   └── agents/                    # issue tracker, triage, domain conventions
├── scripts/                       # verify-*.sh UI checks, diagnostics, profiling, knowledge viewer
├── playgrounds/                   # UI playground
├── tools/
└── .agents/skills/verify-swingcoach/   # verification skill + testing ladder
```

## Where Things Live

### iOS screens

| Screen | File |
| --- | --- |
| Tab shell (Library, Capture, Coach, DEBUG Debug) | `SwingCoach/AppRootView.swift` |
| Library tab, import, batch actions, export | `SwingCoach/LibraryView.swift` |
| Settings (gear icon in Library; there is no `SettingsView`) | `SwingCoach/ExperimentalSettingsView.swift` |
| Swing detail, analyzed video, coach notes | `SwingCoach/SwingDetailView.swift`; result subviews (`AnnotatedAnalysisVideo`, `GroundedCoachingView`) are in `AnalysisResultView.swift` |
| Left/right swing paging | `SwingCoach/SwingReviewPager.swift` |
| Capture tab, manual + Auto | `SwingCoach/CaptureView.swift` |
| Auto rolling recording buffer | `SwingCoach/Models/AutoRollingVideoBuffer.swift` |
| Review after Auto capture | `SwingCoach/AutoSwingReviewView.swift` |
| Trim | `SwingCoach/TrimView/TrimView.swift`, `TrimReviewView.swift` |
| Coach tab (queue + results) | `SwingCoach/AnalyseView.swift` |
| Debug tab, replay through the detector | `SwingCoach/DebugReplayView.swift` |
| Backend client | `SwingCoach/Models/SwingCoachAPI.swift` |
| Saved library (`Documents/swing_library.json`) | `SwingCoach/Models/SwingLibrary.swift` |

### Swing detection

The live detector is `SwingCoach/Models/SwingDetectorV3/` (used by `CaptureView`, `DebugReplayView`, and `SwingDetectorV3AssetDetector`). `SwingDetectorV2/` and `ModelBackedSwingDetector.swift` are legacy and not on any live path. Current design: [SWING_DETECTOR_V3.md](./docs/SWING_DETECTOR_V3.md); older detector docs are marked historical.

### Backend live path

`main.py` → `analysis/pipeline_3d.py` (`SwingCoachPipeline3D`, a 2D knowledge-backed pipeline despite the name) → `video_observations.py`, `metrics_engine.py`, `frame_extractor.py`, `pose_detector.py`, `artifact_renderer.py` + `video_exporter.py`, `knowledge_library.py`, `coach_response_builder.py`, `coaching_contract.py`, `codex_client.py`. Async runs: `run_status.py`, `run_store.py`. Stage docs: `backend/docs/pipeline/`.

Legacy, used only by legacy `test_*.py` scripts: `coach.py` (old gpt-4o-mini coach), `equipment_tracker.py`, `body_3d.py`, `club_analyzer.py`, `temporal_smoother.py`, `visualizer.py`, `visualization_3d.py`, `animation_exporter.py`, `velocity_estimator.py`, `metrics.py`, `event_detector.py`. Do not edit these to change app behavior.

## Fast Command Reference

### Backend setup

```bash
cd backend
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
```

Use `backend/venv/bin/python` for repo scripts; the system `python3` lacks PIL and other dependencies.

### Run backend

```bash
cd backend
./venv/bin/python main.py
```

### Key backend tests

Each runs in about a second without network access.

```bash
cd backend
./venv/bin/python test_grounded_coaching.py
./venv/bin/python test_knowledge_library.py
./venv/bin/python test_analysis_runs.py
./venv/bin/python test_annotation_tracks.py
./venv/bin/python test_pipeline_3d.py
```

The other `test_*.py` scripts exercise the legacy SAM3/3D modules.

### Shell notes

The shell is zsh on macOS: quote globs in flags (`grep -r --include='*.py'`), and there is no `timeout` command.

## Current Status

- Backend: 2D observations, reference overlays, and coaching retrieved from the knowledge library; the AI visual review and coach pick one source-backed focus. Shaft, impact, pressure, calibrated 3D, and ball-flight measurements are unavailable. See `backend/docs/pipeline/`.
- iOS: capture, Auto capture, trim, library, analysis queue, and swing detail are implemented. Auto-capture frame cadence is still under investigation; see the [evidence index](./docs/evidence/README.md).

## Technical Guardrails

1. Treat confidence as first-class output. If confidence is low, communicate uncertainty explicitly.
2. Do not make calibrated 3D, shaft, or impact claims from the current pipeline.
3. Phone performance claims need a physical-device run; Simulator results do not prove camera, cadence, or detector timing.
