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

For UI design iterations, read [UI playground](./docs/UI_PLAYGROUND.md); preserve and extend the repo's reusable playground. To show Simulator work, open it in T3's Device panel (`device_open`) when T3 device tools are available, otherwise use the playground's browser mirror.

### Verifying changes

Before calling an iOS change done, load the `verify-swingcoach` skill and run the checks it maps to the files you changed. Run only those: a check for an area the change cannot reach proves nothing. Reuse a green result until code it covers changes again. Backend changes run the backend tests below; docs-only and Git-only changes need no runtime checks.

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
│   └── MLModels/                  # Core ML: SwingObjectsYOLO11n, SwingPositionTCN
├── SwingCoachTests/
├── backend/
│   ├── main.py                    # FastAPI endpoints
│   ├── analysis/                  # live analysis pipeline (see below)
│   ├── docs/pipeline/             # current per-stage pipeline docs
│   └── test_*.py                  # standalone scripts, not pytest
├── detector_workbench/            # detector datasets, training, validation; legacy/ holds retired detectors
├── docs/
│   ├── evidence/                  # dated investigations; status index in README
│   ├── coaching-knowledge/        # sourced coaching cases used by the backend
│   ├── adr/  audits/  research/
│   └── agents/                    # issue tracker, triage, domain conventions
├── scripts/                       # verify-*.sh UI checks, diagnostics, profiling, knowledge viewer
├── playgrounds/                   # UI playground
├── tools/
├── .agents/skills/verify-swingcoach/   # verification skill + testing ladder
└── .claude/skills/                # links to .agents/skills so Claude Code finds them
```

## Where Things Live

### iOS screens

| Screen | File |
| --- | --- |
| Tab shell (Library, Capture, Coach, DEBUG Debug) | `SwingCoach/AppRootView.swift` |
| Library tab, import, batch actions, export | `SwingCoach/LibraryView.swift` |
| Settings (gear icon in Library; there is no `SettingsView`) | `SwingCoach/ExperimentalSettingsView.swift` |
| Swing detail, analyzed video, coach notes | `SwingCoach/SwingDetailView.swift`; result subviews are `AnnotatedAnalysisVideo.swift` and `GroundedCoachingView.swift` |
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

The live detector is `SwingCoach/Models/SwingDetectorV3/` (used by `CaptureView`, `DebugReplayView`, and `SwingDetectorV3AssetDetector`). Candidate scoring and traces (`SwingEvidence.swift`, `SwingCandidateTrace.swift`) live in that folder too. The retired V2 detector and `ModelBackedSwingDetector.swift` are outside the app target in `detector_workbench/legacy/`, used only by workbench evaluators. Current design: [SWING_DETECTOR_V3.md](./docs/SWING_DETECTOR_V3.md); older detector docs are marked historical.

### Swing positions

After an Auto save, `SwingCoach/Models/SwingPositions/` finds P1–P10 on the phone with `SwingPositionTCN` (detectSwings `tcn_vision_v2`, Apple Vision pose in) and stores them on the swing; Swing Info lists them. Down-the-line only. Design, accuracy and the parity harness: [SWING_POSITIONS.md](./docs/SWING_POSITIONS.md).

### Backend live path

`main.py` → `analysis/pipeline_3d.py` (`SwingCoachPipeline3D`, a 2D knowledge-backed pipeline despite the name) → `video_observations.py`, `metrics_engine.py`, `frame_extractor.py`, `pose_detector.py`, `artifact_renderer.py` + `video_exporter.py`, `knowledge_library.py`, `coach_response_builder.py`, `coaching_contract.py`, `codex_client.py`. Async runs: `run_status.py`, `run_store.py`. Stage docs: `backend/docs/pipeline/`.

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

### Backend tests

These are all the backend tests. Each runs in about a second without network access.

```bash
cd backend
./venv/bin/python test_grounded_coaching.py
./venv/bin/python test_knowledge_library.py
./venv/bin/python test_analysis_runs.py
./venv/bin/python test_annotation_tracks.py
./venv/bin/python test_pipeline_3d.py
./venv/bin/python test_artifact_upload.py
```

### Shell notes

The shell is zsh on macOS: quote globs in flags (`grep -r --include='*.py'`), and there is no `timeout` command.

## Current Status

- Backend: 2D observations, reference overlays, and coaching retrieved from the knowledge library; the AI visual review and coach pick one source-backed focus. Shaft, impact, pressure, calibrated 3D, and ball-flight measurements are unavailable. See `backend/docs/pipeline/`.
- iOS: capture, Auto capture, trim, library, analysis queue, and swing detail are implemented. Auto-capture frame cadence is still under investigation; see the [evidence index](./docs/evidence/README.md).

## Technical Guardrails

1. Treat confidence as first-class output. If confidence is low, communicate uncertainty explicitly.
2. Do not make calibrated 3D, shaft, or impact claims from the current pipeline.
3. Phone performance claims need a physical-device run; Simulator results do not prove camera, cadence, or detector timing.
