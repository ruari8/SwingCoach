# V3 evidence reconstruction

The user requested root-cause fixes for test16 without fixture-specific tuning
or regressions in the other recordings. The starting baseline was 17/19 on the
six new recordings: two misses and one extra in test16. Its approved labels
and all video/model bytes remain unchanged.

## What the failures meant

The misses did not lack visible swing evidence. V3 assigned full pose-stroke
motion and target-departure scores to both, but its club sequence was zero.
The point used for that sequence was whichever detected clubhead had the
highest class confidence anywhere in the frame. A stationary item near the
bottom-right repeatedly beat the actual moving club. Even a readable shaft
could not help because the old fallback used it only when no head was detected.

The extra was a rehearsal followed by returning to address, not a ball strike.
Most other practice swings kept the target ball visible and never entered the
departure path. Here, the club covered the ball after the rehearsal. The
earlier movement still occupied the motion window, the timer resolved the
candidate without clear absence samples, and scoring treated all covered
samples as if they showed an empty target. These were contradictory meanings
of "absent" in different parts of the pipeline.

## Changes

`SwingObservationV3.heldClub` now associates club observations with the golfer.
It selects a shaft with an endpoint near the wrists, takes the opposite endpoint
as its distal end, and associates a detected head near that end. A visible shaft
can supply the point when the head is not detected. Proximity is relative to
torso and shaft dimensions. There are no excluded screen regions or fixture
identifiers. With pose but no usable shaft it uses the existing golfer-relative
reach limit; without pose the confidence fallback remains.

`ClubTrackerV3` uses that same associated club for motion points and sweep
evidence. It no longer combines an arbitrary head's path with unrelated boxes
near the ball. This is spatial association on each analyzed frame, not a newly
trained model or a persistent club-ID tracker.

`TargetRegionObservationV3` now represents three distinct states: present,
club-covered, or clear absence. A visible ball remains present even if a club
box also intersects its patch. Only clear absence adds departure samples.
The existing five-sample requirement remains. The existing 0.55-second deadline
now discards an unresolved candidate instead of granting contact. The normal
and startup scoring paths both exclude covered frames without falling back to
them when all frames are covered.

No swing score threshold, sampling rate, model weight, matching tolerance,
video timing, or label was changed. Other than the new club-association geometry,
the existing numerical budgets remain unchanged.

## Debugging sequence

The fast command compiles and exercises production Swift modules without model
inference:

```bash
backend/venv/bin/python -B detector_workbench/validation/test_swing_detector_v3_evidence.py --build
```

The initial run failed nine checks. Fixing only club association removed eight
failures; the sustained-occlusion case still failed. Fixing visibility semantics
and the timeout removed the final failure. All 17 checks then passed, including
clean strokes, high-confidence distractors, a missing head with a visible shaft,
mirrored/translated observations, visible-ball practice, temporary occlusion,
clear departure, and a real departure preceded by brief impact occlusion.

The first full-video test16 replay passed 3/3 with zero extras. At the two former
misses, sequence evidence changed from 0 to 0.821 and 0.627. Their estimated impact
times remained 574.0 and 1047.5 playback seconds. Their target-departure scores
remained 1.0; no requirement was waived to accept them.

In the final test16 trace, the rehearsal exits the swinging state by 481.5
playback seconds. After reacquiring address, it stays addressed through the
old false-positive time at 487.5 seconds. Correct club association therefore
also prevents the old rehearsal from carrying into a fresh impact candidate
in this replay. Separately, the sustained-occlusion regression deliberately
supplies strong swing evidence and verifies that the contact stage still
cannot resolve a covered ball. The final result does not rely on only one of
those protections.

## Verification result

| Check | Result |
|---|---:|
| test16 first replay | 3/3, zero misses or extras |
| Six new videos | 19/19, zero misses or extras |
| Original suite | 54/54, zero misses or extras |
| Combined full-video gate | **73/73, zero misses or extras** |
| Fast evidence checks | 17/17 |
| iOS Simulator Debug build | Passed |

test16 passed twice: once alone, then inside the combined run. Outside test16,
all 70 accepted impact timestamps were exactly unchanged from the preceding V3
results. test15 still rejected two non-contact candidates, including the known
ball-nudge hard negative.

The combined manifest included the approved 19-hit set and the original 54-hit
set, with video hashes, source hashes, the detector patch, and the compiled
binary hash recorded before execution. Each video uses the unchanged 8/16 fps
live analysis configuration and its declared source-time scale.

The independent audit verified the approved source manifests, all input video
hashes, detector/model source hashes, compiled binary, runtime settings, complete
timeline coverage, raw detections, event matching, and aggregate summary. The
[machine-readable record](2026-09-03-v3-evidence-reconstruction.json) preserves
the scores, hashes, test16 before/after comparison, and unchanged-event check.

This replay is a correctness result. test7 recorded an anomalous 3,310.6-second
wall time and 577.3 ms per analyzed frame while the other 15 videos measured
25.5 to 33.0 ms per analyzed frame. Host activity occurred during the run, so
aggregate replay speed and processing time are not used as performance evidence.

Local evidence is under
`.verification-artifacts/v3-evidence-reconstruction-2026-09-03/`:

- `evidence-before.log` and `evidence-club-fix-only.log`: independent failing checks.
- `test16-first/`: first complete test16 result.
- `full-regression/run-inputs.json`, `labels.json`, and `detector-changes.patch`: frozen run inputs.
- `full-regression/results/`: combined replay output.
- `full-regression/audit.json`: independently recomputed event and coverage check.
- `ios-build.log`: successful app build; unrelated existing warnings remain.

These changes do not establish robustness to every obstruction or every camera
setup. The visibility model currently distinguishes club coverage, not arbitrary
people or equipment blocking the ball. Pose loss still permits the existing
confidence fallback. After this fix the 73 hits are a regression set, not a new
held-out validation set. Physical-iPhone cadence and thermal behavior are not
tested by Mac replay or a Simulator build.
