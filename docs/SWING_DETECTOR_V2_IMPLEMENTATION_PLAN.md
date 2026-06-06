# Swing Detector V2 Implementation Plan

This is the working plan for building `SwingDetectorV2`. It preserves the fixture-gated sequence agreed during the detector restart so the milestone order does not get lost across context compaction.

The design source of truth remains [Swing Detector Restart Design](./SWING_DETECTOR_DESIGN.md). This file is the execution plan: what to build, what to run, and when to stop.

## Context

The shipping swing detector, `LiveModelSwingDetector` in [ModelBackedSwingDetector.swift](../SwingCoach/Models/ModelBackedSwingDetector.swift), has become hard to reason about because its accept decision is a set of interacting boolean rescue branches. Tuning one branch can silently change which branch wins on another clip.

`SwingDetectorV2` restarts from first principles:

- lock the addressed-ball patch first
- detect impact as `ball present -> club sweeps through -> ball gone and stays gone`
- use one flat evidence vector of continuous scores
- let only the scorer threshold the final evidence
- let the state machine own timing and adaptive sampling
- run one real-time pass, with all durations defined in real swing-time and scaled by `source_time_scale`
- de-duplicate by time, not screen location
- treat missing audio or pose as neutral, not zero

## Locked Decisions

- Reuse `GolfObjectDetector` unchanged for per-frame YOLO objects.
- Patch Watcher v1 is YOLO-only inside the locked patch, with a lower in-patch ball threshold than global detection.
- Do not add classical luma/template patch fallback unless YOLO-only recall proves insufficient.
- Keep the legacy detector source intact as a fallback reference until V2 has enough on-device mileage to delete it safely.
- Wire the app directly to V2 once the offline fixture gates are proven; do not keep a product-facing old/new detector flag.
- Advance one fixture at a time. If a case fails, stop and debug the conflict between the trace and the visible frames before moving on.

## Reused Types And Tools

- [GolfObjectDetector.swift](../SwingCoach/Models/GolfObjectDetector.swift): reused object detector.
- [OnDeviceSwingDetector.swift](../SwingCoach/Models/OnDeviceSwingDetector.swift): `DetectedSwing` output type.
- [LiveSwingDetector.swift](../SwingCoach/Models/LiveSwingDetector.swift): live status snapshot/status types.
- [generate_model_detection_contact_sheet.swift](../detector_workbench/modeling/generate_model_detection_contact_sheet.swift): contact sheet renderer.
- [detector_test_v3_labels.json](../detector_workbench/validation/labels/detector_test_v3_labels.json): fixture labels and `source_time_scale`.

## New V2 Module

All new Swift detector code lives under [SwingDetectorV2](../SwingCoach/Models/SwingDetectorV2/SwingDetectorV2.swift).

| File | Responsibility |
| --- | --- |
| `SwingDetectorV2Configuration.swift` | Tunables, timeline scaling, low/burst sampling rates. |
| `AddressMonitor.swift` | Lock a stationary low ball with nearby club association. |
| `PatchWatcher.swift` | Report `ballPresent` and `clubOverlapsPatch` for the locked patch. |
| `ClubTracker.swift` | Emit continuous club proximity, speed, takeaway, sweep, and arc scores. |
| `SwingStateMachine.swift` | Own `Idle -> Addressed -> Swinging -> ImpactCandidate -> Cooldown`, burst sampling, and candidate timing. |
| `SwingEvidence.swift` | Flat evidence vector and weighted scorer. |
| `SwingCandidateTrace.swift` | Debug-only candidate traces with evidence, score, state, lock, and primary failure. |
| `SwingDetectorV2.swift` | Driver that feeds YOLO objects, motion, trackers, state machine, scorer, detections, and traces. |

The shared interface is [LiveSwingDetecting.swift](../SwingCoach/Models/LiveSwingDetecting.swift). `SwingDetectorV2` is the app-wired implementation; the legacy detector remains in source for reference/evaluator comparison only.

## Offline Dev Loop

Primary command:

```bash
python3 detector_workbench/validation/evaluate_swing_detector_v2.py --build --only test2
```

Contact-sheet command:

```bash
python3 detector_workbench/validation/evaluate_swing_detector_v2.py --only test2 --contact-sheets
```

Artifacts are written under `.detectorTestV3/perf_v2/`:

- `summary.json`
- per-case `result.json`
- candidate traces
- contact-sheet JPEGs and detection JSON when requested

The evaluator must fail fast on model-load failure or contact-sheet generation failure. A missing model must never look like a valid zero-detection run.

## Milestones

### M0: Scaffolding

Build:

- V2 module skeleton
- shared detector protocol
- config and source-time scaling
- trace types
- scorer skeleton
- Swift evaluator
- Python wrapper
- contact-sheet path

Gate:

- project builds
- V2 evaluator compiles
- harness runs on `test2`
- contact sheets render
- traces are produced even when detections are empty
- legacy detector remains untouched

Current status: implemented and verified.

### M1: `test2` Green

Build:

- `AddressMonitor`
- `PatchWatcher`
- `ClubTracker`
- `SwingStateMachine`
- `EvidenceVector`
- `SwingScorer`
- accepted/rejected candidate traces

Gate:

- `test2` returns exactly 1 detected swing
- detected impact is inside `[2.0, 3.0]`
- no false positives
- trace shows address lock, departure after sweep, and aligned club-sweep evidence
- contact sheet visually agrees with the trace

Current status: implemented and verified.

### M2: Real-Time Sessions

Run in this exact order:

1. `test12`: 1 expected swing
2. `test11`: 3 expected swings
3. `test7`: 11 expected swings

Purpose:

- validate re-arming after a completed swing
- validate fresh address locks at fresh locations
- validate time-based de-duplication
- catch long real-time-session false positives before slow-motion work begins
- validate impact as target-slot departure plus ball-inventory drop and ordered club sequence, not local disappearance alone

Gate for each clip:

- exact expected count
- zero false positives
- impact timing inside the rough label tolerance

Stop rule:

- If `test12` fails, do not run `test11`.
- If `test11` fails, do not run `test7`.
- If `test7` fails, do not move to M3.
- On the first failure, generate/inspect trace plus contact sheet and identify the specific mismatch between algorithm belief and visible reality before changing thresholds or logic.

Current status: implemented and verified on `test12`, `test11`, and `test7`.

M2 notes:

- `test7` originally exposed a wrong/stale target lock and two false positives.
- Address locking now requires the stable target to still exist in the current frame when the lock is created.
- Impact evidence now records target-slot departure, low strike-area ball-inventory drop, and ordered near -> away -> near club sequence.
- The 9s ball-positioning candidate still showed real target departure and ball-count drop, but failed `no_swing_sequence`, which is the intended distinction between a golf swing and nudging a ball with the club.

### M3: Slow-Motion Timeline And Adaptive Burst

Run in this exact order:

1. `test5`: 4 expected swings at `8x`
2. `test14`: 3 expected swings at `8x`
3. `test10`: 4 expected swings at `8x`
4. `test13`: 6 expected swings at `8x`

Purpose:

- validate `source_time_scale` handling
- validate real-time state durations on slow-motion exports
- validate post-sweep disappearance persistence under occlusion
- validate state-driven high-rate burst behavior

Gate:

- exact expected count for each clip
- zero false positives

### M4: Longest Slow-Motion Session And Throughput

Run:

1. `test4`: 18 expected swings at `8x`

Purpose:

- validate long-session scale
- validate no runaway candidate accumulation
- validate throughput at chosen burst rate

Gate:

- exactly 18 detections
- zero false positives
- evaluator performance remains bounded enough for the selected sampling profile

### M5: App Wiring

Build:

- switch Capture live detection to `SwingDetectorV2`
- pass V2 live detections into Trim after recording stops
- run imported/library Trim post-pass through `SwingDetectorV2AssetDetector`
- replay Debug frames through `SwingDetectorV2`
- remove old contact/impact/hybrid detector mode wiring from the app UI

Gate:

- Capture badge updates from V2 snapshots
- captured recordings open Trim with V2 ranges
- imported clip path runs V2 without diverging from the shared detector core
- Replay Debug has one detector path and one timing selector

Current status: implemented in app wiring. The old detector source remains present but is no longer referenced by Capture, Trim, or Replay Debug.

## Deferred

- Classical luma/template patch fallback.
- Soft-import profile for clips that start mid-swing with no visible address.
- Learned scorer weights from labelled evidence.
- Hard-negative fixture expansion: ball repositioning, club-over-ball setup, waggles, spare balls, nearby-bay audio, walk-ins.
- Lag-aware live sampling. Current live capture keeps recording safe by allowing
  AVFoundation to discard late video-data frames if detector processing falls
  behind. That prevents a long post-stop backlog, but it can discard detector
  evidence blindly. Revisit with phone telemetry: preserve burst sampling during
  swing/impact states, and temporarily reduce idle/cooldown sampling below the
  normal low rate until `analysisLagMS` recovers.
- Removing or rewriting the legacy detector.

## Verification Discipline

Use this sequence:

```text
test2 -> test12 -> test11 -> test7 -> test5 -> test14 -> test10 -> test13 -> test4
```

Do not score the whole suite and tune to the average. A failure on the current milestone means the detector is disagreeing with reality at one layer. Fix that layer before advancing.
