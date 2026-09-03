# V3 evaluation on the six trimmed range recordings

> Historical baseline: the later [evidence reconstruction](2026-09-03-v3-evidence-reconstruction.md)
> fixed both failure classes and passed 73/73 reviewed hits with no extras.

Run on 2026-09-03 after the user approved all 19 ball-hit labels. V3 matched
**17/19 hits, missed two, and produced one false positive**. All three failures
occurred in test16. No detector code, model, thresholds, or labels were tuned.

| Video | Approved hits | Matched | Missed | Extra detections |
|---|---:|---:|---:|---:|
| test16 / IMG_4484 | 3 | 1 | 2 | 1 |
| test17 / IMG_4485 | 3 | 3 | 0 | 0 |
| test18 / IMG_4486 | 1 | 1 | 0 | 0 |
| test19 / IMG_4487 | 7 | 7 | 0 | 0 |
| test20 / IMG_4488 | 2 | 2 | 0 | 0 |
| test21 / IMG_4489 | 3 | 3 | 0 | 0 |
| **Total** | **19** | **17** | **2** | **1** |

V3 emitted 18 detections: 17 matches and one extra. Recall against the approved
labels is 89.5%; precision is 94.4%. All timestamps below are **trimmed MP4
playback positions**, not original MOV times or real-movement seconds.

## Failure review

| Video | Kind | Playback time | What happened |
|---|---|---|---|
| test16 | Miss | 9:33.9 | V3 located the event at 9:34.0 and saw the target ball disappear, but rejected the candidate because club sequence evidence was zero. |
| test16 | Miss | 17:27.5 | V3 located the event at 17:27.5 and saw the target ball disappear, but rejected it for the same zero club sequence evidence. |
| test16 | Extra | 8:07.5 | A rehearsal followed by returning the club to address hid the ball; V3 incorrectly declared a strike at 8:12.0. |

### Both missed hits: club identity breaks the required sequence

The two candidates had departure evidence 1.0, full-stroke pose score 1.0, and
strong club-sweep/arc evidence. Their combined scores were 0.757 and 0.758.
They failed the separate mandatory `swingSequence > 0` gate in
[`SwingDetectorV3.evaluate`](../../../SwingCoach/Models/SwingDetectorV3/SwingDetectorV3.swift).
The decision outcome was `unresolved`, so no clip was accepted.

The observation trace repeatedly reports a clubhead at approximately
`x=0.957, y=0.904`, on a stationary item near the bottom-right of the image.
[`bestClubPoint`](../../../SwingCoach/Models/SwingDetectorV3/SwingObservationV3.swift)
chooses the highest-confidence clubhead anywhere in the frame and only falls
back to a shaft when no clubhead is available. At impact it therefore chooses
this stationary object even when the actual shaft is detected near the ball.

[`ClubTrackerV3`](../../../SwingCoach/Models/SwingDetectorV3/ClubTrackerV3.swift)
requires its selected point to follow a near-away-near sequence relative to
the target. The selected points never return near the ball within these
candidate windows. Recomputing that sequence from the saved observations gives
exactly zero for both misses, agreeing with the detector traces.

This identifies a club-association weakness. It is not a timing-format failure
or a failure to see the target ball depart. A possible correction is to follow
the golfer's moving club consistently instead of selecting the strongest
clubhead box independently on each frame. That change has not been tested.

### Extra detection: the occlusion safeguards permit covered-ball evidence

Source frames show a rehearsal, lowering the club, and returning to address.
The ball is visible before the club returns and then hidden by it. There is no
full strike at the reported 8:07.5 event. The detector carries enough wrist and
club movement from the preceding rehearsal into its candidate window to score
the motion as a stroke: pose-motion score 0.852 and combined score 0.841.

Two rules allow the covered ball to count as departed:

- `SwingDecisionEngineV3.maybeResolveImpact` resolves after 0.55 real seconds
  even without the required number of uncovered absent samples.
- `SwingDetectorV3.departureEvidence` first excludes club-covered post-impact
  frames, but uses all post-impact frames if none remain. With no ball detected
  behind the club, that fallback yields departure evidence 1.0.

All eight saved post-event samples have a club box intersecting even the
minimum possible target patch, confirming that the all-covered fallback applies.

The result is a false strike declaration 0.5625 real seconds after the estimated
event. A possible correction is to keep an entirely obscured target unresolved
until there is readable evidence of departure, and to ensure motion and contact
belong to the same stroke. Neither change was made in this baseline run.

## Runtime and timing

The fresh Swift build used the app's V3 implementation, `SwingObjectsYOLO11n`
and Apple Vision pose, CPU plus Neural Engine compute, 8 fps scanning, and
16 fps during a swing. Practice-swing capture was disabled. Every input used
one constant `source_time_scale=8`, without speed segments or boundary resets.
TCN was used only to propose labels before this run, not to drive V3.

| Measurement | Result |
|---|---:|
| Analyzed frames | 9,604 |
| Mean processing per analyzed frame | 27.4 ms |
| Represented real movement | 1,090.5 seconds |
| Mac replay wall time | 350.1 seconds |
| Aggregate replay speed | 3.11 times real time |
| Mean impact error for 17 matched hits | 0.026 real seconds |
| Maximum impact error for matched hits | 0.071 real seconds |
| Declaration delay for matched hits | 0.250 to 0.313 real seconds |

Matching uses the existing tolerance of one real second, or eight playback
seconds for these clips. The actual matched errors above are much smaller.
Performance numbers are local replay measurements and include diagnostic
tracing; they are not physical-iPhone camera, thermal, or frame-drop validation.

## Reproduction and evidence

The [approved labels](../labels/unseen_range_slow_only_labels.json) and their
SHA-256 were frozen before the run. The original proposal and earlier withdrawn
mixed-speed records were left unchanged. This set remains separate from the
original 54-label regression set; that older suite was not rerun here.

The exact command, per-event matches, result hashes, and metrics are in
[the machine-readable result](2026-09-03-slow-only-v3-results.json).
Detector/evaluator source was at local pre-squash commit `7ddd581`; the run verified that source
and model bytes remained unchanged, all six video hashes matched, every fixture
produced output covering its timeline, and the summary agreed with raw events.
The evaluator exited with status 1 because the fixture set contains failures.

Local full traces and diagnostics are under
`.verification-artifacts/unseen-range-slow-only-v3-2026-09-03/`:

- `run-inputs.json`: frozen video, label, source and model hashes and command.
- `results/summary.json` and `results/test*/result.json`: raw evaluation output.
- `audit.json`: verified coverage and event-level matches, misses and extras.
- `test16-club-sequence-audit.json`: selected club points and recomputed zero sequence scores.
- `test16-occlusion-audit.json`: the eight covered post-event samples at the false positive.

Rerun the saved-result audit from the repository root:

```bash
backend/venv/bin/python detector_workbench/validation/audit_v3_fixture_run.py \
  .verification-artifacts/unseen-range-slow-only-v3-2026-09-03
```

Visual evidence:

- [Miss at 9:33.9](../../../.verification-artifacts/unseen-range-slow-only-v3-2026-09-03/test16/contact-review/test16-miss-02.jpg)
- [Miss at 17:27.5](../../../.verification-artifacts/unseen-range-slow-only-v3-2026-09-03/test16/contact-review/test16-miss-03.jpg)
- [Extra at 8:07.5, ball area](../../../.verification-artifacts/unseen-range-slow-only-v3-2026-09-03/test16/contact-review/test16-extra-02.jpg)
- [Extra at 8:07.5, preceding rehearsal](../../../.verification-artifacts/unseen-range-slow-only-v3-2026-09-03/test16/wide-review/test16-extra-02.jpg)
