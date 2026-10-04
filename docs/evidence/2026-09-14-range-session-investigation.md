# September 14 range session investigation

The exported videos show much less interrupted cadence than September 10, but the recording fix is not complete. Three presentation gaps remain in two of today's 19 clips. The flagged practice swing also reproduces as a false contact in the current Mac detector replay with practice capture disabled.

This investigation changes no app code or recording settings. It uses the current working tree at `28a040c`, including the existing consecutive-writer change. Source and model hashes are retained with the local evidence. The installed phone binary's source identity has not been independently verified.

## Saved-video cadence

All timestamps refer to the exported video's slow-motion playback timeline. Every decoded presentation timestamp was measured with the same script and 75 ms threshold used for the [September 10 investigation](./2026-09-10-auto-cadence-investigation.md).

| Measurement | September 10 | September 14 |
| --- | ---: | ---: |
| Exported clips | 27 | 19 |
| Total playback duration | 626.398 s | 440.810 s |
| Clips with gaps above 75 ms | 12 | 2 |
| Gaps above 75 ms | 626 | 3 |
| Longest gap | 240 ms | 400 ms |

The gap rate per playback second falls by 99.3%. These are different range sessions, so this is an observed improvement, not a controlled estimate of the fix's effect. The longest remaining individual gap is worse than the September 10 maximum.

| September 14 clip | Playback gap | Interval | Visible phase |
| --- | --- | ---: | --- |
| `swingcoach_005_dtl_20260914_095236.mp4` | 3.235–3.635 s | 400 ms | Address, before takeaway |
| Same clip | 3.635–3.742 s | 106.667 ms | Same interruption cluster |
| `swingcoach_009_dtl_20260914_093723.mp4` | 13.527–13.767 s | 240 ms | Near the top of the backswing |

The other 17 clips, including `fp_swingcoach_016_dtl_20260914_092755.mp4`, have no intervals above 40 ms. The 26.667/40 ms alternation matches the smooth exports from the earlier session. Lowering the inspection threshold to 50 ms would still find only these three gaps. No clip reported a decoder error or a non-increasing timestamp.

On September 27, at the user's request, clips 005 and 009 were renamed with a `jitter_` prefix in the Downloads folder. Their SHA-256 hashes still match the original cadence report. The table above and original export manifest retain the original names; `jitter-renames.json` in the local evidence directory records the mapping. Three gaps affect two videos, not three videos.

The 400 ms and 240 ms intervals represent holds between successive decoded frames. They establish timing gaps in the saved files. This pass does not test every clip in the app player or exclude image duplication at otherwise regular timestamps.

The two isolated interruption clusters are consistent with the residual handoff problem found in the [September 11 phone check](./2026-09-11-auto-cadence-fix.md). Without September 14 camera and writer logs, their upstream cause remains unconfirmed. Today’s export directory contains videos and a Library manifest, not capture diagnostics. Phone readiness was requested before copying logs. The initial local device-discovery command timed out initializing CoreDeviceService, and no phone data was retrieved.

## Flagged false positive

The ball stays at the same place on the mat throughout the full practice swing and finish. The ball crops show it before and after the club passes at about 11 seconds. The flagged file has clean presentation timing, so its classification failure is separate from the two measured stutters.

The current V3 evaluator decodes the original MP4 using AVFoundation and runs the bundled object model and Apple Vision pose with CPU plus Neural Engine. The analysis scheduler uses 8 to 16 samples per real second. The replay assumes an 8× slow-motion factor, consistent with the earlier 240 fps sessions and the visible motion. Today's MP4 and Library manifest do not independently record the original capture-rate setting.

With practice capture disabled, the replay returns one `strikeSupported` detection:

- Estimated impact: 15.846667 playback seconds, during the finish.
- Declaration: 19.380 playback seconds.
- Route: `startupInFlight`, with `startup_inflight_anchor`.
- Evidence score: 0.770756. This is a heuristic score, not a calibrated probability.
- Pose stroke-motion score: 1. The golfer performs a full stroke, so this guard correctly passes.

### The gate that falsely passes

The replay tracks the correct, stationary ball at normalized center approximately `(0.5954, 0.6211)`. Wrong-target selection is not the cause in this run.

The model output loses that ball on four sampled frames: 15.846667, 17.380, 18.380, and 19.380 seconds. It sees the same ball at 16.380 seconds with confidence 0.354, between those misses. The ball is detected again at 20.380 seconds and thereafter. Visual crops show that the ball remains present during the missed observations.

`TargetRegionObserverV3.observe` calls a patch `clearAbsent` when there is neither a retained ball detection nor an overlapping club box. It does not independently prove that the patch is empty. A missed model detection therefore becomes false departure evidence here.

Startup recovery then accepts intermittent absence:

1. Its initial candidate filter requires at least two earlier ball sightings and at least 50% absence among readable post-event samples.
2. `departureEvidence` excludes the candidate instant and computes a 75% post-event absence ratio: three missed ball observations out of four post-event samples. The intervening positive observation does not veto recovery.
3. That ratio maps to disappearance persistence `0.472222`, above the required `0.35`.
4. Club sweep `0.922748` and arc `0.907711` qualify as a strong startup swing. This lowers the aggregate threshold from `0.74` to `0.69`. The measured `0.770756` also exceeds the ordinary threshold.
5. Sequence `0.574574`, human presence, club presence, and full-stroke motion pass. The detector emits contact even though the physical ball did not depart.

This startup route does not use the normal state machine's five-absence-sample confirmation. The normal path resets an impact candidate when the ball reappears. Startup recovery has a separate, weaker ratio-based test.

There is also a threshold mismatch worth carrying into a fix investigation. The patch observer advertises a 0.15 confidence threshold, but `GolfObjectDetector` discards predictions below 0.25 before the observer receives them. This replay records retained boxes only. It does not prove the missing frames had raw ball scores between those thresholds.

### Controlled checks and the live-session limit

The retained 38 model and pose observations reproduce the failure without rerunning inference. The local observation runner calls the production `processObservation` path.

| Check | Captures | Result |
| --- | ---: | --- |
| Original observations, practice off | 1 | Negative expectation fails, exit 1 |
| Restore only the four missing stationary-ball boxes | 0 | Negative expectation passes |
| Shift the same observations five real seconds beyond startup | 0 | The contact acceptance depends on startup recovery |
| Original observations, practice on | 1 | Practice fallback captures the stroke; no contact trace |

The restoration check isolates missing ball evidence as necessary for this reproduced contact acceptance. It is an observation counterfactual, not a proposed product fix.

Starting from an exported clip changes detector history. The original phone session had earlier footage, different analyzed frames, and potentially different state. The replay therefore proves a current false-contact defect with practice capture off, but it does not establish which path saved the clip on the phone or whether practice capture was enabled at 09:27. Shifting timestamps alone also does not reconstruct the full live history.

The cadence logs join saved videos to camera and writer events by permanent swing ID. They do not retain the full per-frame detector observations or a historical practice-preference value for each saved swing. Even after those logs are retrieved, an exact original detector-gate attribution may remain unavailable.

## Reproduction artifacts

Private media remain in `/Users/ruari/Downloads/14:9_range_session`. Local results are in `.verification-artifacts/issue-28/2026-09-14/`:

- `cadence.json`: all 19 file hashes, decoded interval histograms, and gaps.
- `fp-contact-off.json`: full model replay, observations, decision, and evidence trace.
- `ReplayObservations.swift` and `replay-observations`: production-core counterfactual runner.
- `counterfactual-*.txt`: the four controlled results.
- `fp-contact.jpg`, `fp-ball.jpg`, and `swingcoach_005.jpg` / `swingcoach_009.jpg`: visual inspection sheets.
- `source-identity.json`: source revision and source/model hashes.

Run the cadence check from the repository root:

```bash
python3 scripts/diagnostics/analyze_auto_cadence.py \
  '/Users/ruari/Downloads/14:9_range_session' --pattern '*.mp4' \
  --output .verification-artifacts/issue-28/2026-09-14/cadence.json --assert-no-gaps
```

This command ran and exited 1 for the three measured gaps. The exact-video replay command also ran successfully after allowing access to macOS decoding services:

```bash
.verification-artifacts/issue-28/2026-09-14/evaluate_v3 \
  '/Users/ruari/Downloads/14:9_range_session/fp_swingcoach_016_dtl_20260914_092755.mp4' \
  SwingCoach/MLModels/SwingObjectsYOLO11n.mlpackage 8 8 200000 16 cpuAndNeuralEngine
```

The model-free failure check runs in under a second:

```bash
.verification-artifacts/issue-28/2026-09-14/replay-observations \
  .verification-artifacts/issue-28/2026-09-14/fp-contact-off.json baseline
```

It prints `mode=baseline detections=1` and exits 1 because this clip should not be classified as contact. Replace `baseline` with `restore-ball`, `outside-startup`, or `practice` to inspect the controlled alternatives. Both local executables were compiled from the evaluator's existing production-source list; the observation runner replaces only its executable entry point.
