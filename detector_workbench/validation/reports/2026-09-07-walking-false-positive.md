# Walking false positive from September 6

Issue [#29](https://github.com/ruari8/SwingCoach/issues/29) reproduces on the exact
`fp_auto_swing_C066ED04.MP4` export. The baseline accepts a contact swing at
12.653 source seconds, declared at 16.893 seconds, with confidence 0.7744897.
The fix rejects it in both contact-only and practice-enabled modes. Three
smooth controls retain exactly the same detections, bounds, timestamps, and
confidence as the baseline.

## What the clip shows

All timestamps below refer to the exported video's playback timeline.

- At 0–4 seconds the golfer stands upright with the club down beside the mat.
- At 5–11 seconds the golfer turns and starts walking toward the camera.
- Around 12.1–13.2 seconds the golfer's leg passes in front of the selected
  ball. The ball is last detected at 12.147 seconds and first missing at
  12.653 seconds. The target observer knows about club occlusion, but has no
  leg-occlusion signal, so it counts missing detections as clear absence.
- At 14–19 seconds the golfer continues toward the camera. There is no visible
  backswing, strike, or held golf finish. The camera framing remains steady.

The likely trigger is walking with a held club while the leg hides the ball.
The visual occlusion explanation has strong support from the frames and target
trace, but there is no body segmentation output proving visibility. The false
acceptance itself is reproducible, including from the 35 recorded model/pose
observations without inference.

## Why V3 accepted it

The normal path locks target 2 at 7.907 seconds. Its candidate reports full
pre-event ball presence and full post-event absence, sweep 0.8814, arc 0.9437,
and a small positive sequence score of 0.002405. The score is 0.77449.

The pose guard measures the bounding span of wrists in image coordinates,
divided by torso height. Walking changes both image position and apparent size.
That movement earns a pose-motion score of 0.95364 despite the wrists moving
only 0.35324 torso lengths relative to the hips in the candidate window.
The three controls have hip-relative spans of 1.68524, 1.71624, and 1.94675.

The fix retains the image-space check and also checks the existing hip-relative
hand-height signal when at least four samples are readable. It uses the existing
0.75–1.65 score ramp and 0.50 acceptance threshold. It changes neither model
weights nor global confidence, contact, or sampling thresholds.

The first regression run after changing normal contact still failed. On the
next observation after normal rejection, startup recovery accepted the same
walk. Startup now uses the same motion guard and records its pose score and
outcome. Final replay records two rejected candidates:

| Path | Estimated impact | Decision time | Evidence score | Pose-motion score | Outcome |
| --- | ---: | ---: | ---: | ---: | --- |
| Normal | 12.653 | 16.893 | 0.774490 | 0 | nonContactSupported |
| Startup | 13.187 | 17.893 | 0.811847 | 0 | nonContactSupported |

The evidence scores remain high. They are heuristic detector scores, not
calibrated probabilities. The independent motion guard prevents either
candidate from exporting a clip.

## Reproduction and regression

The [manifest](../fixtures/2026-09-06-walking-regression.json) records source
video SHA-256 hashes, baseline revision and detections, and observation fixture
names. No private videos or contact sheets are committed. The saved checkout's
uncommitted replay helper was inspected read-only; none of its changes were
copied or edited. The committed checks extend this worktree's existing test.

Replay uses the production V3 sources, AVFoundation decoding, Apple Vision,
the bundled YOLO model, CPU plus Neural Engine, and the 8-to-16 fps scheduler.
The source-time scale is 8. This follows the visibly uniform slow-motion
exports and Auto's 2.4-real-second clip window becoming 19.2 playback seconds.
The exact capture setting is not embedded in these exports, so this is an
explicit timing inference, not a claim based on nominal file frame rate.
An exploratory 1× run gave zero detections, illustrating why the timing matters.

Run the video gate with locally supplied originals:

```bash
python3 detector_workbench/validation/verify_walking_false_positive.py \
  --fixtures-root '/Users/ruari/Downloads/6:9_range_session' \
  --output .verification-artifacts/walking-regression/run-1
```

It builds once, checks all input hashes, runs both modes, saves full output and
source/model hashes, and fails on any unexpected negative detection or changed
control detection. Missing or altered files fail rather than being skipped.

| Clip | Baseline count | Fixed count | Control impact | Confidence |
| --- | ---: | ---: | ---: | ---: |
| fp_auto_swing_C066ED04 | 1 | 0 | — | — |
| auto_swing_07BCC95D | 1 | 1 | 12.653333 | 0.9545098802 |
| auto_swing_129C3634 | 1 | 1 | 13.213333 | 0.8817342626 |
| auto_swing_1F843DE5 | 1 | 1 | 12.666667 | 0.8333629256 |

Both modes produce these results: **8/8 video checks pass**. All three control
detection objects match the baseline exactly. The negative decodes 575 frames
and analyzes 35; the controls decode 575, 576, and 575 frames and analyze 34
each. These are AVFoundation evaluator counts, not `ffprobe` packet counts.

The model-free regression command is:

```bash
python3 detector_workbench/validation/test_swing_detector_v3_evidence.py --build
```

Before the fix it fails the two negative checks and passes all six control
checks. With both acceptance paths fixed, all 32 checks pass, including the
previous club-ownership, occlusion, and duplicate/practice regressions.

Local evidence is under `.verification-artifacts/issue-29/`: `baseline-run`,
the per-video baseline JSON files, `final-replay/report.json`, and
`evidence-tests.log`. The affected Simulator pass uses
`scripts/verify-capture-controls.sh` and stores its result in `capture-ui`.

The Debug test build succeeded on an owned iPhone 17 Simulator, iOS 26.3.1.
XCTest finished with **4 passed and 1 failed**, so the UI gate is not green.
Review playback/paging/deletion, stats persistence across capture modes,
waiting/error states, and Manual recording/Trim cancellation passed.
`testDisabledDetectionDoesNotClaimToBeRunning` failed before its status
assertions: the settings-to-Capture tap had hit point `{-1, -1}`, then XCTest
could not find the Manual segmented control. That test uses injected detector
snapshots rather than the model replay. The failure remains unresolved.

The user stopped further app launches after reporting macOS crash dialogs
during concurrent verification. This run's tests finished without a logged
app-crash failure, and no retry ran. `cleanup.txt` confirms the owned Simulator
`C655FC48-4EEC-4C9A-8CBE-857F6DAD19F2` is absent and its scratch build removed.

## Limits and follow-up

This is a regression result on one negative and three visually inspected
controls. The historical 73-hit full-video suite was not rerun. The new guard
can reject abbreviated strokes with little vertical wrist travel, and broader
independent negatives and short-stroke coverage remain necessary. With sparse
pose the prior fallback remains, so this does not solve arbitrary body occlusion.

Offline replay starts with fresh state and decodes exported footage. It cannot
recreate the live session's full history or exact delivered-frame schedule.
No physical iPhone was used. Live camera cadence, dropped frames, thermal
behavior, and rolling-buffer save behavior still require a device check.
