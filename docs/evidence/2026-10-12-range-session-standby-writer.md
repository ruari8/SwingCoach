# October 12 range session: standby writer on the phone

**Status: the `consecutive-v2` standby writer is confirmed working on the phone and cut drops per file switch by about two thirds, but jitter is not fixed. Each rollover still drops 1–5 camera frames, and roughly 10 unexplained 8–20-frame bursts occur away from any writer event.**

This is the device acceptance run requested by the [October 4 handoff analysis](./2026-10-04-handoff-stall.md). It changes no app code.

## Inputs

- 44 Library exports and `metadata 2.json` in `~/Downloads/12:10_range_session` (Auto, DTL, 240 fps, 8× slow motion, 2.9 s source per clip).
- Phone diagnostics copied from the iPhone 17 on October 18. Process run `CCDD8E26` (16:45–17:30 UTC, build `2026.10.4`, iOS 26.6.2) has 44 `swing-saved` events, and all 44 exports join by `swingID`. All `writer-start` events report `recordingPolicy=consecutive-v2`.

Local evidence, including the analysis scripts and a contact sheet of the gap frames: `.verification-artifacts/issue-28/2026-10-12-range/`.

## Saved-video cadence

`analyze_auto_cadence.py --pattern 'swingcoach_*'` reads every decoded presentation timestamp. Smooth frames alternate 26.7/40 ms; one playback frame equals one 240 fps source frame (4.2 ms real time).

| Measurement | September 10 | September 14 | October 12 |
| --- | ---: | ---: | ---: |
| Exported clips | 27 | 19 | 44 |
| Clips with gaps above 75 ms | 12 | 2 | 4 |
| Gaps above 75 ms | 626 | 3 | 4 |
| Longest gap | 240 ms | 400 ms | 373 ms |
| Further clips with only single-frame 67 ms blips | n/a | 0 | 5 |

Every non-smooth interval, joined to the logs:

| Clip | Playback gap | Source frames lost | Cause in logs | Visible phase |
| --- | --- | ---: | --- | --- |
| `swingcoach_019` | 10.987 s, 373 ms | ~10 | Isolated burst, 10 `outOfBuffers`; nearest writer event 1.5 s away | Downswing |
| `swingcoach_017` | 5.112 s, 173 ms (and 72 ms at 4.640 s) | ~5 | Rollover, +50 ms after seal | Address |
| `swingcoach_011` | 0.160 s, 133 ms (and 67 ms) | ~4 | Rollover, +48 ms | Address |
| `swingcoach_039` | 9.382 s, 133 ms (and 67 ms) | ~4 | Rollover, +46 ms | Address |
| `swingcoach_002` | 20.142 s, 2 × 67 ms | 2 | Rollover, +46 ms | Finish |
| `swingcoach_004`, `010`, `043` | one 67 ms each | 1 | Rollover, +45 to +54 ms | Late follow-through |

The other 35 clips have no interval above 40 ms.

## Phone diagnostics

`check_auto_handoffs.py` fails: 84 rollovers, 433 failing summaries. No thermal or pressure change occurred: every second was `Nominal`, thermal state 0.

| Camera summaries | Seconds | `outOfBuffers` drops | Seconds with drops |
| --- | ---: | ---: | ---: |
| Within 1.2 s of a rollover seal (84) | 207 | 228 | 86 |
| Within 1.2 s of an export seal (44) | 93 | 93 | 37 |
| Within 1.2 s of a writer start only | 23 | 62 | 11 |
| Elsewhere | 1,929 | 146 | 11 |

On September 14 there were about 7.8 drops per seal; now there are about 2.5.

What the October 4 change fixed:

- 130 of 130 eligible rollovers used `writerSource=standby`. The 13 inline starts are Auto session starts or recoveries after an interruption. `writer-standby-failed` never fired.
- Writer `maxPendingFrames` never exceeded 1. The recording queue is no longer blocked, and the app never holds a backlog of camera buffers.
- Finalization runs off the queue: median 50 ms, maximum 67 ms.

What remains:

1. **Rollover drops (7 of 8 clips with gaps).** Pauses land 45–65 ms after the seal, the same moment the old writer's `writer-end` arrives (+53 to +70 ms). The app queue is idle, so the camera buffers are being held inside AVFoundation or VideoToolbox. The likely cause: for about 50 ms, two H.264 encoders hold pixel buffers at once, the old one flushing and writing its movie header and the new one filling its pipeline. That exhausts the camera's fixed pool. This is inferred from timing; there is no direct measurement of encoder buffer retention. Export seals drop frames the same way, but they fall after the saved clip ends, so they rarely reach a saved video.
2. **Isolated bursts.** Ten bursts of 8–20 drops (38–88 ms) happened at 59, 121, 474, 568, 885, 1012, 1326, 1734, 1892 and 2604 s, at least 1.4 s from any seal or writer start, with no focus, exposure, thermal or pending-frame change. Only the 1734 s burst reached a saved clip (019), but it hit the downswing. The logs cannot attribute these bursts. They contain no detector inference timing, and with `expectsMediaDataInRealTime` an internal encoder stall would not show up in app-side pending frames.
3. **Startup and interruptions.** Each Auto start drops 8–12 frames in its first second. Three interruptions stopped the camera for 4.5–13.8 s, and the writers then failed with `Operation Interrupted` and recovered inline. The app was probably backgrounded or the screen locked. Neither affected a saved clip.

## Next steps

- Remove encoder handoffs. Keep one long-lived encoder and cut files from its output, either with `AVAssetWriter` segment output (fragmented MP4 through `AVAssetWriterDelegate`) or with a single `VTCompressionSession` feeding passthrough writers. That eliminates rollover and export-seal handoffs together. A cheaper partial mitigation is to defer rollover while a swing candidate is active, or to lengthen chunks. The `quiet-rollover-v1` policy (October 19) does both. It defers rollover while the detector is not idle and allows chunks of up to 60 s. It targets the 7 rollover clips and does not address the isolated bursts.
- To confirm the buffer-retention cause before rebuilding, briefly copy appended pixel buffers into an app-owned pool around rollovers. If the post-seal drops disappear, retention is confirmed.
- To attribute the isolated bursts, log per-second maximum analysis inference time and detector stage, and keep the camera-drop summary next to it. The `detector` and `detector-state` events (October 19) add this, and the Library export now carries the log.
