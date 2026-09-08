# Detector Validation Tools

These scripts validate the app's model-backed live detector against local fixture videos and exported SwingCoach clips.

## Performance profiling

Use `python3 scripts/profile_detector.py --video /absolute/path/to/clip.mp4 --output .verification-artifacts/profile/run-1` from the repository root for an isolated optimized V3 build with repeated timing runs and input/source/model hashes. Add `--compare /path/to/baseline/report.json` to require identical settings, detections, and frame counts. The evaluator now emits model setup, synchronous sample-read wait, and detector processing durations. See [Foundation performance](../../docs/FOUNDATION_PERFORMANCE.md) for interpretation, the tensor equivalence probe, and device limits.

## V3 Swing Detector

Issue #29's walking false positive and three smooth September 6 Auto exports
have a hash-checked video gate. It runs both contact and practice modes, requires
zero detections for the walk, and compares the controls' timestamps, clip bounds,
and confidence with the pre-fix baseline:

```bash
python3 detector_workbench/validation/verify_walking_false_positive.py \
  --fixtures-root '/Users/ruari/Downloads/6:9_range_session' \
  --output .verification-artifacts/walking-regression/run-1
```

Use a new output directory for each run. Missing or changed videos fail before
building. The [report](reports/2026-09-07-walking-false-positive.md) explains the
8× timing assumption, visual trigger, and verification limits. The four small
observation fixtures also run in the fast production-module checks below,
without access to the private videos or model inference.

Fast production-module regression checks cover club ownership under unrelated
high-confidence detections, shaft support when a head is missing, mirrored and
translated framing, practice swings, and temporary versus sustained occlusion:

```bash
backend/venv/bin/python -B detector_workbench/validation/test_swing_detector_v3_evidence.py --build
```

These checks use synthetic observations without model inference. They do not
replace the labelled full-video replay gate below.

The fast checks also replay 53 recorded observations through the production
contact and practice paths together. They assert one incremental export event
per swing, two events for successive swings, unchanged contact timing and
confidence, ball-free practice capture, and practice fallback after contact
expires. The [duplicate-capture report](reports/2026-09-04-duplicate-auto-capture.md)
records the failing result before the fix and the full recording comparison.
`processObservation` is the same decision entry point that live model inference
calls; trace output includes wrist height and luma motion for repeatable replay.

`SwingDetectorV3` is the app-wired detector for Capture, Trim/import, and Replay Debug. It removes the fixed image-height boundary, tracks ball identities, freezes the target during a swing episode, uses target-specific contact evidence, and separates full strokes from ball nudges through pose motion when visible.

The 2026-09-03 evidence reconstruction replaced confidence-only club selection
with golfer/shaft association and made club-covered target frames an explicit
unknown state. The combined regression then passed **73/73 reviewed hits with
zero misses and zero extras**: the approved 19-hit new-session set plus the
original 54-hit suite. Read the [root-cause analysis, implementation, and proof](reports/2026-09-03-v3-evidence-reconstruction.md).

The final 2026-09-02 live-order replay matched **54/54 reviewed impacts with zero misses and zero extras**. Estimated-impact-to-declaration delay was 0.250–0.333 real seconds. The Mac processed 2,735.7 real seconds of represented movement in 1,020.1 seconds, with a 31.2 ms weighted mean per analyzed frame. See [the V3 implementation record](../../docs/SWING_DETECTOR_V3.md) for architecture, evidence, and limits.

```bash
python3 detector_workbench/validation/evaluate_swing_detector_v3.py --build
```

The evaluator can keep a machine-proposed or held-out set separate from the
reviewed regression manifest:

```bash
python3 detector_workbench/validation/evaluate_swing_detector_v3.py \
  --labels detector_workbench/validation/labels/proposed/example_labels.json \
  --fixtures-root .detectorTestV3/example \
  --out-root .detectorTestV3/example/results
```

The evaluator defaults to contact-only detection. Pass `--practice-swings` to
include full practice swings, and use a manifest that labels those swings too.
The JSON records `allowsPracticeSwings`. Replay Debug uses the Capture preference.

## Current six-recording preparation: slow motion only

The user chose to remove normal-speed sections rather than support mixed speed
for these recordings. The prepared MP4s are in
`.detectorTestV3/unseen-2026-08-31/slow-only/test16.mp4` through `test21.mp4`.
All six use one constant `source_time_scale=8`; do not configure mixed segments
or reset the detector at speed boundaries for these copies. IMG_4489 retains
its ending because it was already slow motion.

The Downloads originals and their MOV fixture copies remain unchanged. Cuts
use keyframes slightly inside the confirmed slow sections. Video and audio
were copied without re-encoding. The [preparation manifest](fixtures/2026-08-31-slow-only.json)
records the original time offsets, output hashes, durations, and verification.

Fresh labels were generated on 2026-09-03: **22 TCN P7 proposals, reduced to
19 proposed ball hits after agent visual review**. The other three proposals
were practice swings. Counts and trimmed playback timestamps are in the
[review list](reports/2026-09-03-slow-only-p7-review.md); the
[original proposal](labels/proposed/unseen_range_slow_only_labels.json) remains
unchanged. The user approved all 19 ball-hit labels; the
[approved manifest](labels/unseen_range_slow_only_labels.json) records that review.

The first V3 run on these correctly formatted copies matched **17/19**, with
two misses and one false positive, all in test16. The other five videos passed.
No detector code, model, or thresholds changed. See the
[results and failure analysis](reports/2026-09-03-slow-only-v3-results.md).

```bash
backend/venv/bin/python detector_workbench/validation/evaluate_swing_detector_v3.py \
  --build \
  --labels detector_workbench/validation/labels/unseen_range_slow_only_labels.json \
  --fixtures-root .detectorTestV3/unseen-2026-08-31/slow-only \
  --out-root .verification-artifacts/unseen-range-slow-only-v3-rerun/results
```

`audit_v3_fixture_run.py RUN_ROOT` checks a run against `run-inputs.json`, which
records the input-video, approved-label, source, and model hashes before execution.
It requires every frozen fixture to have output, checks timeline coverage and
runtime settings, rescores raw detections, and exports event-level matches,
misses, and extras. It applies to constant-speed fixtures with separated impact
labels. The recorded run and audit are in
`.verification-artifacts/unseen-range-slow-only-v3-2026-09-03/`.

To regenerate raw proposals on the trimmed timeline, use the command below.
Keep raw output separate from the contact-reviewed manifest. Do not use the withdrawn 31/33
labels or compare against original full-video counts, because the discarded
normal-speed sections also contained swings.

```bash
backend/venv/bin/python detector_workbench/validation/propose_p7_labels.py \
  --fixture-root .detectorTestV3/unseen-2026-08-31/slow-only \
  --source-time-scale 8 \
  --artifacts-dir .verification-artifacts/unseen-range-slow-only-tcn \
  --labels-out .verification-artifacts/unseen-range-slow-only-tcn/raw-tcn-proposals.json
```

The recorded run reused packet-verified per-frame pose/club observations and
reran TCN inference with `--skip-extraction`. The review list records the
cache checks and command. Running without that flag extracts features again.

## Independent P7 label proposals

`propose_p7_labels.py` reproduces the TCN labelling path first used for
`test15`. It extracts Apple Vision pose and `club_seg_v2_960` features from
every encoded frame, runs the existing `tcn_vision_club_v1` checkpoint over
overlapping four-real-second windows, preserves every local P7 peak, and
renders video-only review sheets around selected peaks. It never reads
SwingDetectorV3 output.

Run it with the SwingCoach backend environment because the tool needs PyTorch,
SciPy, Ultralytics, OpenCV, and Pillow:

```bash
backend/venv/bin/python detector_workbench/validation/propose_p7_labels.py \
  --fixture-root .detectorTestV3/example \
  --source-time-scale 8 \
  --artifacts-dir .verification-artifacts/example-tcn \
  --labels-out detector_workbench/validation/labels/proposed/example_labels.json
```

The output manifest remains `needs_user_review`. TCN P7 scores are motion-event
proposals, not proof of ball contact. AirDropped Photos renders can contain
normal-speed caps around a slowed middle while reporting a constant 30 fps
timeline. Inspect the rendered review sheets and record the timing assumption;
do not apply 8× blindly to a proposal in a normal-speed cap.

The generator uses one supplied time scale for the entire input. It does not
detect speed boundaries or verify ball contact. Its provenance notes must not
claim that either check has happened. Mixed-speed input requires a separately
verified timing map before time-sensitive results can be trusted.

For mixed-speed fixtures, put contiguous `segments` in the label manifest and
set `source_time_scale` on every impact. The evaluator runs each segment with
the correct clock, maps detections and traces back to the original source
timeline, and combines the score:

```json
{
  "segments": [
    {"id": "normal-start", "start": 0, "end": 60, "source_time_scale": 1},
    {"id": "slow-middle", "start": 60, "end": 1320, "source_time_scale": 8},
    {"id": "normal-end", "start": 1320, "end": 1368.633, "source_time_scale": 1}
  ],
  "impact_time_labels": [
    {"start": 31.3, "end": 31.3, "source_time_scale": 1},
    {"start": 261.867, "end": 261.867, "source_time_scale": 8}
  ]
}
```

Choose cuts in settled, swing-free gaps. Each segment starts with fresh
detector state, so a cut through camera handling or golfer motion can trigger
the startup-in-flight path and contaminate false-positive counts.

The 2026-09-02 unseen range-session scores and labels were withdrawn after
user review found a count discrepancy and follow-up inspection confirmed
practice swings labelled as impacts. The invalid manifests and obsolete score
report were removed from the active tree before merge. Read [the correction
and input audit](reports/2026-09-03-unseen-input-audit.md) for the recovered
timing lesson and the commits that preserve the discarded experiment.

## Video timing and labels

"240 fps" describes the capture rate of our iPhone range recordings. The supplied slow-motion export usually already plays at 30 fps with its duration stretched. Do not stretch it again during conversion or interpret its duration as real movement time.

For a uniformly retimed export:

| Capture rate | Export playback rate | `source_time_scale` | One minute of real movement |
| --- | --- | --- | --- |
| 240 fps | 30 fps | 8 | 8 minutes of source video |
| 120 fps | 30 fps | 4 | 4 minutes of source video |
| 30 fps | 30 fps | 1 | 1 minute of source video |

Keep labels in **source video seconds**, matching the player's timecodes. Convert with `real_seconds = source_seconds / source_time_scale`; convert back with `source_seconds = real_seconds * source_time_scale`. For example, a P7 label at 80 seconds in an 8× export occurred at 10 seconds of real movement.

Read the exported file's frame rate and timestamps, and establish its capture/retiming history separately. A 30 fps file alone does not reveal whether it is slow motion. Raw high-frame-rate files and exports with mixed playback speeds need their own timing mapping; the constant factor above applies only to uniformly retimed footage.

Machine-proposed event labels must remain separate from the reviewed baseline labels until a person checks them. They are predictions to review, not independent ground truth for detector accuracy.

## Historical V2 Swing Detector

The [2026-08-31 reconstruction proposal](../../docs/SWING_DETECTOR_RECONSTRUCTION.md) explains what the boundary experiments revealed and led to V3. The results below preserve the V2 baseline and isolated boundary experiments.

Latest experiment, 2026-08-30: a **65% line** completed all ten active recordings with **51/51 original swings plus 2/3 test15 swings**, for **53/54 matched, one missed, and no extra detections**. Only the ordinary line and the two corresponding ball-count comparisons changed from 0.68 to 0.65. Startup's separate 0.58 candidate filter and every other rule, model, and label stayed unchanged. The executable was built from isolated source copies; app source remains at the 68% baseline.

| Boundary | Original suite | test15 | Extras across all ten |
| --- | --- | --- | --- |
| 68% baseline | 51/51 | 0/3 | 0 |
| Removed | 38/51 | 2/3 | 2 |
| 60% | 40/51 | 2/3 | 1 |
| 65% | 51/51 | 2/3 | 0 |

At 65%, every original recording has exactly the same detections, candidate traces, sampling rows, and decoded/processed frame counts as the 68% baseline. Relative to 60%, test7 recovers six swings, test11 recovers two and loses its extra, test12 recovers one, and test13 recovers two. Test15 still misses the second swing at **05:30.400 playback time** after switching to the spare at **05:24.500**. Its candidate traces and accepted detections exactly match the 60% run; the previously inspected false clubhead detection over clothing still explains the switch.

The full comparison, remaining miss diagnosis, source snapshots, and input/full-decoding verification are local at `.verification-artifacts/65-percent-line-full-suite/report.md`. This experiment was not adopted. It restores the original suite but does not validate the boundary across camera positions: the struck ball in inspected test15 frames sits as little as six pixels below the new line at 1920-pixel image height. All ten recordings have now informed threshold selection; future generalization checks need held-out footage and deliberate framing variations. Adaptive placement and changes to target retention or departure evidence remain untested.

At 60%, test10 recovers to 4/4 and test14 to 3/3 because their harmful replacement detections at y=52.4% and y=58.1% are excluded again. Test4's extra at 52:49.310 also disappears; its inventory evidence and rejection score match baseline. Test7 remains 5/11, test11 1/3 with an extra at 01:27.995, test12 0/1, and test13 4/6. Those four recordings have identical sampling, candidate traces, and detections to the no-line run. Their harmful targets between y=60.9% and y=64.7% still qualify. Test2 and test5 remain 1/1 and 4/4. Test15 remains 2/3 with the same incorrect switch to the spare after a false clubhead detection on clothing.

All 12 miss timestamps from the earlier 60% run, its extra timestamp, per-failure explanations, three-way comparisons, source snapshots, and input checks are local at `.verification-artifacts/60-percent-line-full-suite/report.md`. The 60% experiment was not adopted.

Local experiment completed, 2026-08-30: removing the 68% position filter from ordinary address selection, retargeting, and ball counts improved test15 from **0/3 to 2/3**, with no extra detections. Startup recovery's separate 58% candidate filter, all other detector rules, model weights, and reviewed labels were unchanged. All 17,122 frames were decoded. The original nine fixtures were initially skipped because the requested test15 gate did not pass. The baseline product code was restored after saving the experimental source, patch, binary, results, and frame probes in `.verification-artifacts/no-68-percent-line/`.

The remaining miss was the second swing at **05:30.400 playback time**. The detector initially held the correct ball, then switched to a spare at 05:24.500 when a false clubhead box over clothing on the mat gave the spare a stronger association score. The 1.35-real-second retarget delay prevented a correction before impact, 0.7375 real seconds later. Probes show the struck ball disappearing while the selected spare remains visible. No impact candidate was resolved near that label. See the local `report.md`, `second-swing-diagnosis.json`, and `second-swing-probe.jpg` in that experiment directory.

The user then requested the full original suite despite the failed test15 gate. The same saved experimental binary completed all nine recordings with **38/51 matched, 13 missed, and two extra detections**. The original baseline was 51/51 with zero extras. No further detector changes were made, and test15 was not rerun during this follow-up.

| Recording | Baseline matched | Line removed: matched | Extra detections |
| --- | --- | --- | --- |
| test2 | 1/1 | 1/1 | 0 |
| test4 | 18/18 | 18/18 | 1 |
| test5 | 4/4 | 4/4 | 0 |
| test7 | 11/11 | 5/11 | 0 |
| test10 | 4/4 | 3/4 | 0 |
| test11 | 3/3 | 1/3 | 1 |
| test12 | 1/1 | 0/1 | 0 |
| test13 | 6/6 | 4/6 | 0 |
| test14 | 3/3 | 2/3 | 0 |

All 13 misses involve retargeting from the addressed ball to an above-line detection. Probes confirm background targets in test7 and test11. The test4 extra at **52:49.310** is the same candidate the baseline rejected; counting above-line balls changes only its inventory-drop score and pushes it over the acceptance threshold. The test11 extra at **01:27.995** follows a new lock on a background ball, which the walking golfer then hides. The 68% rule currently protects against these failures, even though it also excludes valid test15 framing. A replacement needs reliable target retention and departure evidence tied to the selected strike location.

Follow-up evidence, all miss/extra timestamps, per-failure explanations, frame probes, and verified input hashes are local at `.verification-artifacts/no-68-percent-line-original-51/report.md`. The runner checked complete decoding for every recording, including discarded negative-timestamp pre-roll packets where present. App source remains at baseline; none of these experimental variants is adopted. These are local detector results, not iPhone Capture verification.

`SwingDetectorV2` is the clean-restart detector path. It is validated through a separate fail-fast harness so it can be iterated beside the legacy detector before any app wiring changes.

The canonical milestone order is documented in [Swing Detector V2 Implementation Plan](../../docs/SWING_DETECTOR_V2_IMPLEMENTATION_PLAN.md). Advance one fixture at a time and stop on the first mismatch.

Compile and run the v2 evaluator:

```bash
python3 detector_workbench/validation/evaluate_swing_detector_v2.py --build --only test2
```

Run with visual contact sheets:

```bash
python3 detector_workbench/validation/evaluate_swing_detector_v2.py --only test2 --contact-sheets
```

Current v2 behavior:

- source timestamps are passed through to Swift; the detector converts them to real swing-time using each fixture's `source_time_scale`
- model-load failures are fatal, not reported as zero detections
- contact-sheet rendering failures are fatal when `--contact-sheets` is requested
- every run writes JSON results, candidate traces, and processed-frame sampling traces under `.detectorTestV3/perf_v2/`
- M1 currently targets the locked-address-patch flow: address lock, patch watcher, graded club evidence, state transitions, and evidence scoring

The active set now contains ten fixtures with 54 reviewed swing labels. On 2026-08-30, the original nine fixtures passed 51/51 locally. The newly reviewed `test15` then failed 0/3 with the same detector and model, with no false positives. A second complete run reproduced identical detections and traces. The original nine were not rerun during that test15 evaluation.

For the baseline test15 run, the ball sits about 65–66% down the image, above `AddressMonitor.minBallY = 0.68`. All ball detections in the inspected swing windows fail that position gate, so the detector never establishes a regular address lock. V2 already has intermittent-visibility, lock-retention, and club-overlap protections; this baseline failure does not demonstrate that those protections fail. The separate experiment above removes that gate and exposes a retargeting failure. See [the current logic audit](../../docs/SWING_DETECTOR_LOGIC.md) for the exact occlusion behavior and adaptive-selection options. Preserve test15 as a failing regression. Original baseline evidence and a per-miss report are local at `.verification-artifacts/test15-swing-detector/report.md`. These local results do not verify iPhone Capture or saved clips.

## Legacy Live Model Detector

Compile the Swift evaluator from the repository root:

```bash
mkdir -p .videos/bin
xcrun swiftc -parse-as-library \
  -framework AVFoundation -framework CoreML -framework Vision \
  -framework CoreGraphics -framework CoreVideo -framework ImageIO \
  SwingCoach/Models/SwingDetectionTypes.swift \
  SwingCoach/Models/GolfObjectDetector.swift \
  SwingCoach/Models/ModelBackedSwingDetector.swift \
  detector_workbench/validation/evaluate_live_model_detector.swift \
  -o .videos/bin/evaluate_live_model_detector
```

Run current fixture validation:

```bash
python3 detector_workbench/validation/evaluate_detector_test_v3_performance.py
```

Run exported-clip validation:

```bash
python3 detector_workbench/validation/evaluate_detector_video_data.py --force
```

Validation labels live in `detector_workbench/validation/labels/`. Heavy fixture videos, compiled binaries, generated proxies, and reports remain ignored.
