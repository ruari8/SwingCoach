# Correction: new range recordings, labels, and timing

The 2026-09-02 report was withdrawn and removed before the branch history was
squashed. It incorrectly described practice swings
as confirmed ball impacts and then used the ball remaining in place to argue
that the detector had failed. The previous accuracy scores and the resulting
detector-change recommendations are not reliable. No detector was run or
changed during this correction.

The later [audio follow-up](#audio-follow-up-after-the-users-boundary-check)
below replaces the earlier uncertainty about where the audible transitions
occur. It supports the user's timing estimates for IMG_4484 through IMG_4487.

## Correct source files, incorrect label claims

On 2026-09-03 the six newest MOVs in Downloads were still `IMG_4484.mov`
through `IMG_4489.mov`. SHA-256 comparison confirmed that all six fixture copies
are byte-for-byte identical to those sources. There was no conversion, trimming,
or retiming of the files themselves.

| Downloads file | Fixture | Playback duration | Encoded frames | User count | Previous labels |
|---|---|---:|---:|---:|---:|
| IMG_4484.mov | test16.mov | 1368.633s | 41059 | 5 | 5 |
| IMG_4485.mov | test17.mov | 1184.733s | 35542 | 3 | 5 |
| IMG_4486.mov | test18.mov | 930.767s | 27923 | 2 | 2 |
| IMG_4487.mov | test19.mov | 3580.000s | 107400 | 8 | 10 |
| IMG_4488.mov | test20.mov | 675.567s | 20267 | 3 | 5 |
| IMG_4489.mov | test21.mov | 1423.000s | 42690 | 4 | 6 |

The supplied per-video counts sum to 25. The same user message also said 22;
this audit preserves that discrepancy rather than choosing a new ground truth.
It does not publish a replacement detector score or a fully corrected manifest.

SHA-256 values, each shared by the Downloads source and fixture:

```text
IMG_4484 / test16  62cc065e62fd02930c0fc54ebe88b7ffaf7f603511e726877f623659d26ed148
IMG_4485 / test17  f654367cefca6462b8150459a20872b25e5e025b9eb286586ee6039a482a8d18
IMG_4486 / test18  501ffbec8dc7ccdba6032a3caadf12363528122e2008097f85986a04838be76f
IMG_4487 / test19  0d8af97034a990a16ffe83e7baaba3b59d70121f19c2da0b9706b5ffae5c6134
IMG_4488 / test20  7a1519a8374f2e924901dca03ad2a5789a0ff6269abddb3d981ccaeb87aad16b
IMG_4489 / test21  90b6888974685780e41ea22d3cbab964c5da33f8dbc825d6709673b9171f08fd
```

## What the previous run actually did

1. The TCN proposer applied an 8x time scale across each entire MOV. It did not
   have a mixed-speed map. This compressed normal-speed motion too far and made
   proposals in those sections unreliable.
2. It produced 22 thresholded P7 motion proposals. The agent incorrectly treated
   all of them as verified ball impacts.
3. The agent manually added nine events after reviewing normal-speed boundary
   and low-score images, then froze a 31-label manifest.
4. The V3 evaluator used manually configured 1x/8x/1x segments with fresh detector
   state at each cut. It decoded the segments and sampled frames for inference,
   then mapped outputs to original playback timestamps.
5. Post-detector review added two more labels, giving 33. The agent also changed
   test19's first cut from 60s to 75s after observing a startup false detection.
   That outcome-informed cut adjustment did not establish Apple's true boundary.

The claim that TCN found 33 verified ball impacts was therefore false. TCN
estimated swing motion; the agent made the incorrect contact classifications.

## Confirmed practice swings wrongly labelled as impacts

The existing review frames show the ball remaining on the mat or tee before,
during, and after these swings. These seven events are not evidence that the
detector failed to notice a ball departure:

| Source file | Previous label, playback seconds | Review artifact |
|---|---:|---|
| IMG_4485 | 15.8 | `fine-review/test17-opening-a.jpg` |
| IMG_4485 | 28.3 | `fine-review/test17-opening-b.jpg` |
| IMG_4487 | 14.1 | `fine-review/test19-opening.jpg` |
| IMG_4488 | 556.8 | `v3-diagnostics/test20/miss-3-t556.8.jpg` |
| IMG_4488 | 597.867 | `v3-diagnostics/test20/miss-4-t597.9.jpg` |
| IMG_4489 | 18.2 | `fine-review/test21-opening-a.jpg` |
| IMG_4489 | 566.667 | `v3-diagnostics/test21/miss-4-t566.7.jpg` |

Artifact paths above are relative to
`.verification-artifacts/unseen-range-2026-08-31/`.
These findings establish that the old label set is wrong. They do not yet
reconcile every event in IMG_4487 with the user's count, so no corrected total
is asserted here.

## What is established about Apple timing

Apple Photos lets the user choose the start and end of the slow-motion section.
There is no fixed percentage established by this audit or specified by the
cited instructions. See [Apple's slow-motion editing instructions](https://support.apple.com/en-gb/104968).

For a 240 fps capture rendered into a 30 fps file, one real second can occupy
eight playback seconds in the fully slowed section and one playback second
in a normal-speed section. Playback frame rate alone cannot identify those
regions. Their percentages also depend on whether the denominator is original
recording time or exported playback time.

All six files report 30/1 nominal and average video frame rates. Their video
sample-duration tables contain one constant interval, and their video edit
lists contain one rate-1 edit. The single timed metadata packet in each file
contains a UUID, not a speed map. No explicit slow-motion start/end values
were found in these inspected fields. Visual sequences establish that fast
and slowed motion both occur, but exact transitions were not measured.

The previous evaluator used the following assumptions. Percentages are of the
exported playback duration. **These are the agent's partition choices, not
measured Apple real-time percentages.**

| Source | Assumed normal opening | Assumed slow middle | Assumed normal ending |
|---|---|---|---|
| IMG_4484 | 0-60s, 4.38% | 60-1320s, 92.06% | 1320-1368.633s, 3.55% |
| IMG_4485 | 0-60s, 5.06% | 60-1140s, 91.16% | 1140-1184.733s, 3.78% |
| IMG_4486 | 0-30s, 3.22% | 30-900s, 93.47% | 900-930.767s, 3.31% |
| IMG_4487 | 0-75s, 2.09% | 75-3500s, 95.67% | 3500-3580s, 2.23% |
| IMG_4488 | 0-20s, 2.96% | 20-640s, 91.77% | 640-675.567s, 5.26% |
| IMG_4489 | 0-60s, 4.22% | 60-1380s, 92.76% | 1380-1423s, 3.02% |

At this stage, actual opening/ending percentages and any transition ramps had
not been measured. Cuts in swing-free gaps do not prove the clock or state
resets were harmless. The subsequent audio measurements below supersede that
lack of timing evidence, but are not frame-accurate video transition labels.

## Audio follow-up after the user's boundary check

The user identified the pitch change as a better timing signal and reported
approximately 35s, 30-31s, 24s, and 91s at both ends of IMG_4484 through IMG_4487.
The agent then decoded the first and last 150 playback seconds of the AAC audio
track in all six original Downloads MOVs. No retiming was applied.

The analysis measured the loss and return of high-frequency audio energy. In
IMG_4484 through IMG_4488, these changes are about 54-70 dB, far larger than
the nearby variations. The estimates below use the midpoint between the local
normal and slowed spectral levels. Treat them as approximate audio transition
times, with roughly half-second precision for choosing a video transition,
not frame-accurate video cuts.

| Original | Audio slows at | Audio returns at | Ending length | Opening / ending share of exported duration |
|---|---:|---:|---:|---:|
| IMG_4484 | 35.3s | 22:13.5 | 35.2s | 2.58% / 2.57% |
| IMG_4485 | 30.6s | 19:14.3 | 30.5s | 2.58% / 2.57% |
| IMG_4486 | 24.1s | 15:06.7 | 24.1s | 2.59% / 2.59% |
| IMG_4487 | 1:31.5 | 58:08.6 | 1:31.4 | 2.56% / 2.55% |
| IMG_4488 | 17.6s | 10:58.0 | 17.5s | 2.61% / 2.60% |
| IMG_4489 | 31.2s | No return; user confirmed edited slow ending | None | 2.19% / 0% |

The first five therefore have approximately matching openings and endings,
each about 2.6% of the exported video. They do not support the earlier manually
chosen segments. Small differences remain; this is not proof of an exact
universal Apple percentage.

IMG_4489 differs. Its opening transition is clear, but the audio remains in
the slowed spectral band through the end. A fresh, uncached decode of playback
seconds 1412-1422 confirmed the same result. The user subsequently confirmed
that IMG_4489 was edited and does not return to normal speed, and accepted the
other measured timing results. It must not have a normal-speed final segment.

The mathematical 15% normal / 70% eight-times-slowed / 15% normal split on the
original recording would produce 2.542% / 94.915% / 2.542% on the exported
timeline. The first five measurements are close to that pattern, with small
transition offsets. This is a consistency hypothesis, not a recovered Photos
setting or a verified rule for other recordings. IMG_4489 must be treated
separately.

The reproducible local analysis is:

```bash
backend/venv/bin/python .verification-artifacts/unseen-range-2026-08-31/audio-speed-audit/measure.py
```

It writes `measurements.json` and `audio-transitions.png` beside the script.
This follow-up did not rerun or change the detector, amend impact labels, or
publish a replacement score.

## Consequences for the previous runs

The approximate 2.5% opening and ending shares refer to exported playback
duration, not the original capture duration. All six supplied files play at
30 fps; the 240 fps figure describes capture, not the denominator for these
measured percentages. Keep per-file timing because Photos edits can change it.

The TCN used an 8x factor everywhere. That correctly normalized fully slowed
motion but compressed normal-speed motion to eight times real speed. Its
normal-speed proposals and coverage therefore need a new pass with the correct
timeline. Motion proposals still need separate ball-contact review.

The V3 evaluator used the wrong segment boundaries and reset at each cut.
Comparing every timestamp in the withdrawn 33-label manifest with the accepted
audio boundaries found no label whose assigned local time scale changes.
However, surrounding intervals used the wrong clock, and detector state was
reset artificially. This finding does not validate the old run or permit a
replacement score without replay. IMG_4489's final segment was also wrongly
assigned normal speed.

The user subsequently chose trimming instead of mixed-speed evaluation. The
preparation below supersedes the earlier proposal to handle playback-speed
transitions. Ball-contact review remains necessary; trimming alone does not
repair the seven practice-swing label errors.

## Adopted preparation: remove the normal-speed sections

On 2026-09-03 the user requested slow-motion-only copies. Six MP4s now live in
`.detectorTestV3/unseen-2026-08-31/slow-only/`. Each uses one constant 8x time
factor. There is no adaptive speed processing for this prepared set.

Cuts lie at video keyframes just inside the confirmed slow-motion boundaries,
with a small margin to remove transition frames. HEVC video and AAC audio were
stream-copied without re-encoding or changing playback speed. The originals
remain unchanged. IMG_4489 keeps its existing slow-motion ending.

| Original | Prepared fixture | Original playback start | Requested original end |
|---|---|---:|---:|
| IMG_4484.mov | test16.mp4 | 36.400s | 1332.800s |
| IMG_4485.mov | test17.mp4 | 31.733s | 1153.600s |
| IMG_4486.mov | test18.mp4 | 25.200s | 905.333s |
| IMG_4487.mov | test19.mp4 | 92.400s | 3487.867s |
| IMG_4488.mov | test20.mp4 | 18.667s | 657.067s |
| IMG_4489.mov | test21.mp4 | 31.733s | Original end, 1423.000s |

Packet reordering extends some requested ends by less than 0.25 seconds,
still inside the slow-motion safety margin. The output video starts at zero,
stays at 30 fps, and retains its orientation. Decoded frames sampled at the
start, middle, and end of every output exactly match their original frames.
Audio at both output edges remains in the slow-motion spectral band.

The [preparation manifest](../fixtures/2026-08-31-slow-only.json) records exact
offsets, output durations, file hashes, and verification. Local scripts and
evidence are `prepare_slow_only.py`, `verify_slow_only.py`,
`slow-only-plan.json`, and `slow-only-verification.json` under
`.verification-artifacts/unseen-range-2026-08-31/`.

No labels or detector results were generated for the new copies in this step.
They need fresh ball-contact labels on their zero-based trimmed timelines.
Original full-video swing counts no longer describe the retained footage.

## Status and evidence

The frozen and audited label JSON files and their hashes remain unchanged for
historical inspection. Their README and the original report now explicitly
withdraw them. The label generator's hardcoded claims of timing and visual
validation were removed; it now states which assumptions it actually applies.

Identity checks, ffprobe output, QuickTime timing-table inspection, and timed
metadata packets are saved locally in
`.verification-artifacts/unseen-range-2026-08-31/input-audit/`.

Before publishing a new score, reconcile actual ball strikes against the source
video, record practice swings separately, and establish a verified timing map or
use a uniformly timed export. Do not tune the detector to accept the seven
practice swings listed above.
