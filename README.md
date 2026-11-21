# SwingCoach

SwingCoach is an experimental golf coaching app for iPhone. It records swings, saves each one as a clip, and measures down-the-line swings on the phone: where the body and club were at ten swing positions, how that compares with tour pros, and the one thing worth working on.

This is an active prototype, not a polished App Store product. Everything runs on the phone; there is no server.

## What It Does

- Captures or imports golf swing video, then trims one or more swing clips into a local library.
- **Auto** watches the camera and saves each swing by itself, using on-device `SwingDetectorV3`: the YOLO/Core ML golf-object model, Apple Vision pose, persistent target relationships and target-specific contact outcomes.
- Finds swing positions P1–P10 on each down-the-line swing, about 0.8 s after impact during Auto.
- Coaches each down-the-line swing: up to 21 measurements with a drawing each, one verdict per swing, a recap every few swings on the camera screen, and a session review in the Library.

## Repository Layout

```text
SwingCoach/
├── SwingCoach/                 # SwiftUI iOS app
├── SwingCoach.xcodeproj/       # Xcode project
├── SwingCoachTests/            # unit tests
├── SwingCoachUITests/          # UI tests, driven by DEBUG launch fixtures
├── detector_workbench/         # detector datasets, modeling and validation tools
├── docs/                       # project documentation
├── playgrounds/                # UI playground
├── scripts/                    # verification, diagnostics, profiling, knowledge viewer
├── tools/                      # knowledge viewer page, Python requirements for scripts
└── AGENTS.md                   # agent quick guide and file map
```

## iOS App

The app has two tabs:

- `Library`: import videos from Photos, browse and star saved swings by session, open locally supplied DTL reference swings, batch delete or export, and open a swing. A swing opens in a player with left/right navigation, straight-line guides you draw yourself, the coaching verdict and its drawings. A session header opens that session's coaching review.
- `Capture`: record manual clips, or use Auto, which saves detected swings straight to the library and can show the last verdict or a recap of the last few swings.

DEBUG builds also include:

- `Settings` (the gear in Library): detector sampling settings, coaching settings and Replay Debug visibility.
- `Replay Debug`: feeds saved videos through the same detector core used by live capture, so detector behaviour can be checked without recording fresh sessions.

See [docs/FRONTEND.md](docs/FRONTEND.md) for the feature inventory and [docs/COACHING.md](docs/COACHING.md) for how coaching works and what has been checked.

## Quick Start

1. Open [SwingCoach.xcodeproj](SwingCoach.xcodeproj) in Xcode.
2. Build and run the `SwingCoach` target on a device or simulator.

The project uses Xcode 26.2 recommended settings. App and test targets inherit the development team from the project; change signing teams at the project level. String-catalog symbol generation is enabled for the project, with test targets opting out.

The Simulator has no camera and cannot run Vision body pose, so capture, swing positions and coaching measurements need a phone. UI tests replace them with fixtures.

## Useful Checks

App verification on a disposable Simulator:

```bash
scripts/verify.sh --help
scripts/verify.sh coaching
```

Repo scripts that draw or read images need a Python environment:

```bash
python3 -m venv tools/venv
tools/venv/bin/pip install -r tools/requirements.txt
```

Detector validation tooling:

```bash
python3 detector_workbench/validation/evaluate_swing_detector_v3.py --build --only test2
python3 detector_workbench/validation/evaluate_detector_video_data.py --force
```

Coaching on real clips, on a Mac:

```bash
detector_workbench/validation/coaching/run.sh ~/Downloads/<session folder> /tmp/coaching --limit 10
```

Heavy local fixture videos, raw detector outputs, model-training outputs and local model weights are intentionally git-ignored. Small reviewed label manifests and evidence reports may be committed under `detector_workbench/validation/` when they form part of a reproducible regression record.

## Current Status

- Capture, Auto capture, trim, library and swing review are implemented.
- On-device coaching is implemented for down-the-line swings and has been checked on a Mac against range sessions. It has not run on a phone yet.
- The on-device detector is still experimental. It is useful for clip preselection and Auto, but it is not treated as a solved detection problem.
- The product path is DTL-first. Face-on exists in the data model, but coaching, swing positions and validation are down-the-line only.
- Voice, drills and written explanations are not built.
- An earlier server-side coaching pipeline (a FastAPI backend, a Coach tab and "Analyze Swing") was removed in November 2026. It is in the git history before that.

## Documentation

- [Project docs index](docs/README.md)
- [Frontend documentation](docs/FRONTEND.md)
- [Coaching](docs/COACHING.md)
- [Detector tooling](detector_workbench/README.md)

## Coaching knowledge

Run `python3 scripts/knowledge_viewer.py` to browse the 30 sources and 145 cases at <http://127.0.0.1:8769>. The [library](docs/coaching-knowledge/README.md) preserves transcripts, source reasoning, prerequisites and local visual evidence. Nothing in the app reads it yet; it is the intended source for drills and written explanations.
