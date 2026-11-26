# AGENTS.md - SwingCoach

## Mission

SwingCoach is a golf coaching app for iPhone. It captures swings, keeps them in a library, and coaches down-the-line swings on the phone. There is no backend.

This file is the operator/LLM quick guide. Detailed docs are listed below.

## Canonical Documentation

- [Root README](./README.md)
- [Docs Index](./docs/README.md)
- [Frontend Documentation](./docs/FRONTEND.md)
- [Coaching](./docs/COACHING.md)
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

Before calling an iOS change done, load the `verify-swingcoach` skill and run the checks it maps to the files you changed. Run only those: a check for an area the change cannot reach proves nothing. Reuse a green result until code it covers changes again. Docs-only and Git-only changes need no runtime checks.

### Physical iPhone

Device IDs, the signed build, install-over-existing, and app-data pulls are in the `verify-swingcoach` skill's [testing ladder](./.agents/skills/verify-swingcoach/references/testing-ladder.md#physical-iphone-recipe). Do not guess device IDs.

## Repository Map

```text
SwingCoach/
├── SwingCoach/                    # iOS app (flat; there is no Views/ folder)
│   ├── Models/                    # detectors, capture buffer, library, positions, coaching
│   ├── TrimView/
│   └── MLModels/                  # Core ML: SwingObjectsYOLO11n, SwingPositionTCN
├── SwingCoachTests/
├── SwingCoachUITests/             # UI tests; app state comes from DEBUG launch fixtures
├── TestPlans/                     # SwingCoach (default), Unit, OnRequest
├── detector_workbench/            # detector datasets, training, validation; legacy/ holds retired detectors
├── docs/
│   ├── evidence/                  # dated investigations; status index in README
│   ├── coaching-knowledge/        # sourced coaching cases, for future drills and explanations
│   ├── adr/  audits/  research/
│   └── agents/                    # issue tracker, triage, domain conventions
├── scripts/                       # verify.sh test runner, diagnostics, profiling, knowledge viewer
├── playgrounds/                   # UI playground
├── ui-council/                    # repeatable screenshot tour of the main screens (capture.sh)
├── tools/                         # knowledge viewer page; requirements.txt for the scripts' Python environment
├── .agents/skills/verify-swingcoach/   # verification skill + testing ladder
└── .claude/skills/                # links to .agents/skills so Claude Code finds them
```

## Where Things Live

### iOS screens

| Screen | File |
| --- | --- |
| Tab shell (Library, Capture, DEBUG Debug) | `SwingCoach/AppRootView.swift` |
| Library tab, import, batch actions, export | `SwingCoach/LibraryView.swift` |
| Settings (gear icon in Library; there is no `SettingsView`) | `SwingCoach/ExperimentalSettingsView.swift` |
| Shared look: accent colour, player chrome, player sheet style, library card sizes, position and low-confidence tags, wrapping layout | `SwingCoach/Theme.swift` |
| Swing detail | `SwingCoach/SwingDetailView.swift` |
| Lines drawn by hand on a swing | `SwingCoach/SwingLineAnnotations.swift`, `ManualAnnotationCanvas.swift` |
| Coaching in the player (Library and Auto): step card, drawings, club path, strip marks, Layers tool, every check | `SwingCoach/CoachingPlayerViews.swift` |
| Coaching colours and the session review | `SwingCoach/SwingCoachingViews.swift` |
| Coaching on the Auto camera screen: coach chip, recap, comparison | `SwingCoach/AutoCoachingViews.swift` |
| Left/right swing paging | `SwingCoach/SwingReviewPager.swift` |
| Capture tab, manual + Auto | `SwingCoach/CaptureView.swift` |
| Auto rolling recording buffer | `SwingCoach/Models/AutoRollingVideoBuffer.swift` |
| Review after Auto capture | `SwingCoach/AutoSwingReviewView.swift` |
| Trim | `SwingCoach/TrimView/TrimView.swift`, `TrimReviewView.swift` |
| Debug tab, replay through the detector | `SwingCoach/DebugReplayView.swift` |
| Saved library (`Documents/swing_library.json`) | `SwingCoach/Models/SwingLibrary.swift` |
| Swing pictures: each swing's small placeholder, the Library tiles' picture cache | `SwingCoach/Models/SwingPoster.swift` |

### Swing detection

The live detector is `SwingCoach/Models/SwingDetectorV3/` (used by `CaptureView`, `DebugReplayView`, and `SwingDetectorV3AssetDetector`). Candidate scoring and traces (`SwingEvidence.swift`, `SwingCandidateTrace.swift`) live in that folder too. The retired V2 detector and `ModelBackedSwingDetector.swift` are outside the app target in `detector_workbench/legacy/`, used only by workbench evaluators. Current design: [SWING_DETECTOR_V3.md](./docs/SWING_DETECTOR_V3.md); older detector docs are marked historical.

### Coaching (on-device)

`SwingCoach/Models/Coaching/` measures a down-the-line swing on the phone: evidence from Vision pose, person segmentation and the club detector at P1–P10, 21 metrics with zones and levels, a drawing per metric, one pointer per swing, recaps every few swings and session themes. Chips, moved cameras and unclear positions are measured but not judged. The club checks are judged only when the camera placement read off the address frame passes (on the hand line at hand height; unsure is not a pass); the readings are saved on the swing. Every Auto swing is queued and its clip read when Auto pauses or stops; a setting (off by default) adds a first reading of the body checks while Auto records, from the live copies of the frames. A swing opens paused on the coach's first step with its drawing up, and a card walks the other faults in swing order (`CoachingWalkthrough.swift`). UI is `SwingCoach/CoachingPlayerViews.swift`, `SwingCoach/SwingCoachingViews.swift` and `SwingCoach/AutoCoachingViews.swift`. No backend. Zones come from 96 pro swings. Run on an iPhone 17 with range footage: a clip takes about 9 s, the first reading during Auto about 1 s with no extra dropped frames; not yet at the range. Design, metric table and the Mac review harness: [COACHING.md](./docs/COACHING.md).

### Swing positions

During Auto, `SwingCoach/Models/SwingPositions/` finds P1–P10 on the phone from live frames, about 0.8 s after impact (saved clip as fallback), with `SwingPositionTCN` (detectSwings `tcn_vision_v2`, Apple Vision pose in) and stores them on the swing; Swing Info lists them. Down-the-line only. Design, accuracy and the parity harness: [SWING_POSITIONS.md](./docs/SWING_POSITIONS.md).

## Fast Command Reference

### Python for repo scripts

```bash
python3 -m venv tools/venv
tools/venv/bin/pip install -r tools/requirements.txt
```

Use `tools/venv/bin/python` for repo scripts that read or draw images (review sheets, the playground's media export, the detector workbench); the system `python3` lacks PIL and other dependencies. `scripts/verify.sh` needs only the system `python3`.

### Verify the app

```bash
scripts/verify.sh --help
scripts/verify.sh coaching
```

### Shell notes

The shell is zsh on macOS: quote globs in flags (`grep -r --include='*.py'`), and there is no `timeout` command.

## Current Status

- On-device coaching: metrics, drawings, per-swing verdicts, recaps on the Auto camera screen and a session review for down-the-line swings, checked on a Mac against range sessions. Club checks are held unless the swing's camera placement passes (57 of 170 range swings pass). Run on an iPhone 17 with range footage (16 Nov 2026), not yet at the range. Measuring while Auto records is off by default. See [COACHING.md](./docs/COACHING.md).
- The server-side coaching (a FastAPI backend, the Coach tab, Analyze Swing) was removed in November 2026; it is in the git history. Voice, drills and written explanations are not built.
- iOS: capture, Auto capture, trim, library and swing detail are implemented. Auto-capture frame cadence is still under investigation; see the [evidence index](./docs/evidence/README.md).

## Technical Guardrails

1. Treat confidence as first-class output. If confidence is low, communicate uncertainty explicitly.
2. Do not make calibrated 3D, clubface, impact-quality or ball-flight claims: coaching measures 2D positions from one camera.
3. Phone performance claims need a physical-device run; Simulator results do not prove camera, cadence, or detector timing.
