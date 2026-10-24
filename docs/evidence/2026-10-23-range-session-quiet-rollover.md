# October 23 range session: quiet rollover on the phone

**Status: `quiet-rollover-v1` works. 45 of 48 clips are perfectly smooth, against 35 of 44 on October 12. The 3 remaining clips each lose 2–4 source frames, with a longest pause of 107 ms on the 8× playback timeline (373 ms on October 12). One gap is a forced 60-second rollover that landed at the start of a swing; the other two are small isolated drops. None falls in the downswing or impact. The 11 clips recorded at 120 fps are clean and that session had no drops at any file switch.**

Following this session, Auto jitter is treated as resolved for now ([AUTO_CAPTURE_CADENCE.md](../AUTO_CAPTURE_CADENCE.md)).

This is the device run requested by the [October 12 analysis](./2026-10-12-range-session-standby-writer.md). It changes no app code.

## Inputs

- 48 Library exports, `metadata 2.json` and `capture-diagnostics.jsonl` in `~/Downloads/23:10rangeSession`. iPhone18,3, iOS 27.0.1, app build `1`. Every swing has `recordingPolicy=quiet-rollover-v1`.
- One process run, `3F32F909` (16:56–17:47 UTC), with 8 Auto sessions. 37 clips are 240 fps (50 Mbit/s) and 11 are 120 fps (32 Mbit/s, clips 028–038). All 48 exports join to a `swing-saved` event by `swingID`.

Scripts and the gap contact sheet: `.verification-artifacts/issue-28/2026-10-23-range/`.

## Saved-video cadence

`analyze_auto_cadence.py --pattern 'swingcoach_*'` on every decoded frame. Smooth frames alternate 26.7/40 ms.

| Measurement | September 14 | October 12 | October 23 |
| --- | ---: | ---: | ---: |
| Exported clips | 19 | 44 | 48 |
| Clips with any interval above 41 ms | 2 | 9 | 3 |
| Gaps above 75 ms | 3 | 4 | 3 |
| Longest gap | 400 ms | 373 ms | 107 ms |
| Source frames lost across all clips | n/a | ~28 | ~9 |
| Rollovers inside a saved clip | n/a | 7 | 1 (forced) |

Every non-smooth interval, joined to the log:

| Clip | Playback gap | Source frames lost | Cause in log | Swing phase |
| --- | --- | ---: | --- | --- |
| `swingcoach_001` | 8.785 s, 107 ms + 67 ms | ~3 | Forced 60 s rollover, +49 ms after seal, swing window open | Takeaway |
| `swingcoach_015` | 13.693 s, 107 ms | ~2 | Isolated: 2 `outOfBuffers` drops, 1.2 s before the export seal, no writer event, detector max 82 ms | Top of backswing |
| `swingcoach_043` | 3.973 s, 93 ms + 2 × 67 ms | ~4 | Isolated: 4 drops, 2.4 s from any writer event, detector max 162 ms the second before | Address/takeaway |

## Phone diagnostics

No thermal change (state 0 throughout). Pressure was `Nominal` except 2 seconds of `Fair` while the app was being backgrounded at the end. Writer `maxPendingFrames` never exceeded 1. Finalization median 52 ms.

**Quiet rollover did its job.** 28 of the 30 rollovers during play waited for an idle detector and sealed with the swing window closed; the other 2 were forced at 60 s. Export seals all had it open, as expected.

**The forced cap is the hole.** From 2299 s to 2345 s the detector never returned to idle. It cycled between `addressed`, `swinging` and `impactCandidate` through several rehearsal swings, so the window stayed open for 46 s. The chunk had started at 2285 s, so the 60 s cap fired at 2345.3 s, 0.3 s before the real swing was detected. The pause landed 49 ms after the seal, the same handoff signature as October 12. The other forced rollover (1182 s) landed 10 s before a swing and missed the clip.

**Handoff cost is unchanged at 240 fps and zero at 120 fps.**

| Source FPS | Seal | Seals | Drops within 1 s | Per seal |
| ---: | --- | ---: | ---: | ---: |
| 240 | rollover | 22 | 72 | 3.3 |
| 240 | forced rollover | 2 | 6 | 3.0 |
| 240 | export | 37 | 94 | 2.5 |
| 120 | rollover | 6 | 0 | 0 |
| 120 | export | 11 | 0 | 0 |

The 120 fps session ran 558 camera seconds with 5 drops in total. At 240 fps the camera's buffer pool turns over twice as fast, so the ~50 ms where two encoders hold buffers is enough to run it dry; at 120 fps it is not. This fits the encoder buffer-retention explanation from October 12 better than anything else in the log.

**Isolated drops are background noise.** Away from writer events, session starts and interruptions, 1–4 frame drops occur in about 2% of camera seconds, at the same rate in idle and mid-swing seconds. They do not track slow inference. Two of them happened to land in saved clips this time (015, 043).

**Interruptions did not reach clips.** A 4.6 s camera stall at 354 s, two `Operation Interrupted` writer failures about 5 s after an Auto start (1352 s, 1683 s), a 10 s drop cluster after the second one with detector calls up to 365 ms, and the end-of-session suspension (detector calls up to 4 s, then no camera for 592 s) all fall outside saved clips. They look like the app being interrupted or backgrounded.

## Next steps

- Done: `quiet-rollover-v2` raises the forced limit to 120 s. Holding only while the detector is `swinging` would not have helped here, because the detector still read `addressed` when the cap fired. A long open stretch usually ends in a saved swing, whose export seals the chunk anyway, or in the golfer walking off, which allows a quiet rollover. The longest open window this session was 63 s. A 120 s chunk at 240 fps is about 750 MB on disk.
- Removing encoder handoffs (one long-lived encoder, cut files from its output) is still the full fix for the 240 fps seal drops. Export seals drop frames too, but after the clip ends.
- The 120 fps result is a strong data point: if 120 fps is good enough for coaching, it removes the handoff drops entirely today.
- The isolated 1–4 frame drops are small and rare; they are not worth chasing until the handoff drops are gone.
