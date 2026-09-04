# SwingDetectorV3

Implemented and app-wired on 2026-09-02. V3 is the detector used by live Capture, Replay Debug, and Trim/import detection. V2 remains in source as the historical comparison baseline.

## Runtime flow

V3 records every delivered camera frame to the rolling video buffer while the analysis scheduler samples the same timestamped stream at 8 fps when scanning and up to 16 fps during a swing episode.

Each analyzed frame runs the existing `SwingObjectsYOLO11n` object model and Apple Vision body pose. No TCN or newly trained model is used. The decision core then:

1. assigns persistent IDs to ball observations with one-to-one temporal association;
2. ranks prepared targets from repeated club association, golfer-relative geometry, ball stability, and shaft-end coupling;
3. requires repeated evidence before changing target identity;
4. freezes the selected target when takeaway starts;
5. watches only that target region for present, covered, absent, or unreadable evidence;
6. requires a club-motion episode and, when pose is readable, full-stroke wrist travel;
7. returns `strikeSupported`, `nonContactSupported`, or `unresolved`;
8. exports a clip only for `strikeSupported`.

There is no absolute image-height boundary and scene-wide ball counts do not influence contact. Spare or downrange balls cannot compensate for what happened at the frozen strike target.

Club-motion evidence associates the club with the golfer before measuring its
path. A shaft endpoint near the wrists identifies the grip; the opposite
endpoint identifies the clubhead region. A detected head near that endpoint
supplies the point, or the shaft endpoint supplies it when the head is blurred.
With pose but no usable shaft, head candidates must be within golfer-relative
reach. If pose is unavailable, the existing confidence-based fallback remains.
Sweep and sequence evidence use the same selected club observations.

Target visibility has three states: ball present, club-covered, and clear
absence. Covered samples are unknown and cannot contribute departure evidence.
Five clear-absence samples confirm a candidate; the 0.55-real-second deadline
expires an unresolved candidate instead of confirming it. Startup and normal
scoring both exclude covered samples, including when every post-event sample
is covered. These states currently account for club occlusion only, not all
possible people or objects crossing the target.

The normal address lock remains authoritative when it arms. If the clubhead
hides the ball for too much of address and no lock forms, a completed full-swing
pose pattern can open a separate contact-recovery path. Recovery requires at
least three consistent ball observations immediately before the pose impact,
golfer-relative strike geometry, persistent clear absence afterward, and
strong club sweep and arc evidence. The confirmed pose pattern supplies the
temporal swing sequence when the object tracker could not build one. Recovery
only runs while the target selector has no lock and the state machine is idle,
so it cannot replace or race an armed normal candidate. If contact recovery
fails, the motion is retained only when optional practice-swing capture is on.

With practice capture enabled, a confirmed pose dip remains pending while the
contact state is `impactCandidate`. The contact decision gets its existing
bounded confirmation window first. An accepted contact covers that dip; a
rejected or expired contact still permits practice fallback. This fixes the
case where practice confirmation arrived one frame before contact confirmation
and both paths emitted a new detection ID for the same stroke. Cooldowns,
contact thresholds, and clip padding are unchanged. Replay Debug now reads the
same practice-capture preference as Capture. See the
[September 4 reproduction and regression](../detector_workbench/validation/reports/2026-09-04-duplicate-auto-capture.md).

## Why the relationships matter

- A single low-confidence clubhead box cannot move the target. Retargeting needs repeated evidence for the same ball ID.
- Golfer-relative target depth replaces the old 68% image line, so test15's higher framing is valid while upper-frame background balls are rejected.
- Shaft-box corners approximate the two shaft ends when several balls share one row. This resolved test4's multi-ball ambiguity.
- Wrist travel in torso units separates a full golf stroke from a ball nudge. The test15 movement at 04:28 produces `nonContactSupported`, not a saved swing.

## Validation result

The final live-order Mac replay used the same 8 to 16 fps analysis schedule as Capture, CPU plus Neural Engine compute, practice-swing capture off, and all ten reviewed fixtures.

| Result | Measurement |
| --- | --- |
| Reviewed impacts | 54 |
| Matched | 54 |
| Missed | 0 |
| Extra detections | 0 |
| Decision delay after estimated impact | 0.250 to 0.333 real seconds |
| Median decision delay | 0.251 real seconds |
| Analyzed-frame processing | 31.2 ms weighted mean |
| Real movement represented | 2,735.7 seconds |
| Mac wall time | 1,020.1 seconds |
| Aggregate replay speed | 2.68 times real time |

Run the complete gate with:

```bash
python3 detector_workbench/validation/evaluate_swing_detector_v3.py --build
```

The ignored local result set is written to `.detectorTestV3/perf_v3/`. Each case includes accepted detections, legacy comparison traces, per-frame object/track observations, and V3 decision traces with target ID, outcome, pose-motion score, impact time, and declaration time. Per-frame observation recording is enabled by the evaluator and disabled in the app so production capture does not retain diagnostic object arrays.

## Limits

On 2026-09-03, the user approved 19 ball-hit labels across six new range recordings after their normal-speed sections were removed. V3's first run on these uniformly slowed copies matched **17/19**, with **two misses and one false positive**, all in test16. test17 through test21 passed. No detector code, model, or thresholds changed for that baseline. See the [recorded baseline and failure analysis](../detector_workbench/validation/reports/2026-09-03-slow-only-v3-results.md).

The two misses had clear ball departure but failed the mandatory club sequence check. A stationary bottom-right object repeatedly selected as the best clubhead prevented the measured path from returning near the ball. The extra detection followed a rehearsal and return to address: the timer and all-occluded-frame fallback allowed the covered ball to count as departed.

The [evidence reconstruction](../detector_workbench/validation/reports/2026-09-03-v3-evidence-reconstruction.md)
fixed both causes without changing swing score thresholds, sampling rates, model
weights, timing configuration, or labels. test16 passed twice. The complete
gate then matched **73/73**, with zero misses and zero extras: all 19 new-session
hits plus the original 54. The other 70 accepted impact timestamps were exactly
unchanged from their preceding V3 results.

All ten original fixtures informed implementation or debugging, so their 54/54 is a regression result rather than held-out generalization evidence. test16 also informed this reconstruction, so the complete 73/73 is now a regression gate rather than held-out proof. A later unseen 30 fps portrait clip exposed a missed full swing when the addressed clubhead hid the ball too often for a quiet address lock. The detector now recovers that shot at 7.60 seconds from the combined full-swing pattern, local ball departure, and club evidence. That clip informed the recovery implementation and is now a local regression fixture, not held-out proof. Deliberate framing changes, people crossing the target, arbitrary occlusion, lighting changes, and practice swings still need broader independent evaluation. The recovery route also depends on a readable full-swing pose pattern, so it does not extend coverage to chips, putts, or abbreviated swings.

The Mac result proves that this configuration can keep up with replayed live-order input on the development Mac. The Simulator build proves integration and navigation only. A physical iPhone run is still required for camera cadence, thermal behavior, frame drops, model latency across supported devices, rolling-buffer export, and real Auto Capture behavior.
