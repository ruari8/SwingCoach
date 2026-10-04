# October 4 handoff stall analysis

**Status: cause identified, fix implemented, not yet device-tested.**

The September 14 range-session logs were copied from the iPhone 17 on October 4. Process run `737260DD` (08:24–09:02 UTC) has 19 `swing-saved` events, matching the 19 exported clips. It ran the build with temporary `DEBUG-handoff-*` timings, so the measurements requested in the [September 11 notes](./2026-09-11-auto-cadence-fix.md) exist without another session.

## Handoff timings

| Step on the recording queue | Samples | Median | Max |
| --- | ---: | ---: | ---: |
| New writer configuration | 78 | 5.4 ms | 20.3 ms |
| New writer `startWriting` + `startSession` | 78 | 17.5 ms | 60.8 ms |
| Old writer `endSession` + `markAsFinished` | 67 | 32.3 ms | 39.9 ms |
| Old writer `finishWriting` call | 67 | 0.3 ms | 1.5 ms |

At 240 fps a frame arrives every 4.2 ms, so a typical rollover blocks the queue for about 12 frame periods, and up to about 30.

## Drops cluster at handoffs

| Camera summaries | Seconds | `outOfBuffers` drops | Seconds with drops |
| --- | ---: | ---: | ---: |
| Within 1.2 s of a `writer-sealed` event | 150 | 524 | 70 |
| Elsewhere (also excluding writer starts) | 1,064 | 15 | 4 |

Both jittery clips map onto a rollover. Clip 005 (`E0BD3530`) has its gap at session time 60.053–60.116 s, 50 ms after a rollover seal at 60.003 s. Clip 009 (`C575A8F0`) has its gap at 129.604–129.634 s, 45 ms after a rollover seal at 129.559 s. Session-relative times restart with each Auto session, so these matches use the nearest seal; they are consistent with, but do not individually prove, the same session.

This supports the first two hypotheses: synchronous writer setup and synchronous finalization block the queue. The third hypothesis, that encoders retain buffers, is not needed to explain the measured drops.

## Change

`AutoRollingVideoBuffer` (`recordingPolicy=consecutive-v2`):

- Opens the next writer on a separate queue right after each chunk starts. A rollover or export seal hands frames to the waiting writer without blocking. If no matching writer is ready, it falls back to opening one inline.
- Runs `endSession`, `markAsFinished` and `finishWriting` on a separate finalization queue. The recording queue does not touch a sealed writer until completion returns to it.
- Removes the temporary `DEBUG-handoff-*` events. `writer-start.writerSource` shows whether each chunk used the waiting writer.

All nine `SwingClipContextTests` pass, including a new test showing that a rollover records into the writer opened ahead of time. These are synthetic 64×64 frames, not physical-camera measurements.

## Acceptance still required

Record an Auto session of at least two minutes at 240 fps, copy the logs, and run `scripts/diagnostics/check_auto_handoffs.py`. Rollovers should show `writerSource=standby` and no clustering of `outOfBuffers` drops. Then decode saved clips that cross a file boundary.

Local evidence: `.verification-artifacts/issue-28/2026-10-04-logs/`.
