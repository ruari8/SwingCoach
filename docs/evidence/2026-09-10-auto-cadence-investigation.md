# September 10 Auto jitter investigation and proposed fix

September 11 update: the consecutive-writer implementation is now in the working tree. The sections below preserve the evidence and original proposal; the implementation verification is recorded separately in the September 11 fix artifacts. Phone installation alone does not establish that hardware jitter is eliminated.

The strongest explanation for this session's saved-video jitter is the rolling buffer encoding the same camera frames into two overlapping chunks. Remove that sustained duplicate recording, and assemble clips from consecutive chunks using the existing composition code. This is a proposed fix supported by recorded evidence, not a verified hardware fix.

## Evidence from the actual session

The user recorded exclusively in Auto and observed jitter in saved videos. No live-preview observation is available or needed. The exported folder contains 27 videos and one batch manifest, `metadata 2.json`. All 27 permanent swing IDs join to retained `swing-saved` phone events, including the three videos renamed with a `jit_` prefix.

Decoded presentation timestamps show 626 intervals above 75 ms across 12 videos. The other 15 videos have maximum intervals of 40 ms. No decode errors or non-increasing timestamps were reported. The three marked videos have 53, 67, and 83 pauses, with maximum intervals of 240, 213, and 237 ms respectively.

Camera logs report 1920×1080 capture at 240 fps. Saved clips have an 8× slow-motion factor. Every affected clip overlaps camera reports of `dropped_outOfBuffers`. All retained September 10 camera summaries report nominal thermal state and nominal camera pressure.

[Apple's frame-drop documentation](https://developer.apple.com/library/archive/technotes/tn2445/_index.html) defines OutOfBuffers as exhaustion of the source buffer pool, typically from retaining supplied buffers too long. This establishes source-frame loss before final export. It does not identify every buffer owner or exclude additional playback problems.

## Duplicate recording predicts the pauses

`AutoRollingVideoBuffer` starts a 20-second chunk every 17.4 seconds. Its append loop sends the same frame to every unfinished, non-finishing chunk. Each chunk has its own H.264 writer configured for 240 fps and 50 Mbps in this session. For the 2.6-second overlap, two writers therefore receive the same camera frames.

The diagnostics independently confirm overlapping writer source ranges. Reconstructing those ranges from `writer-start` and accepted writer timestamps produces 74 overlap periods in the range-session process run.

| Camera summary category | Reports | Median frames per report | Reports with more than 20 out-of-buffers drops |
| --- | ---: | ---: | ---: |
| Entirely inside a writer overlap | 94 | 135 | 94 |
| Entirely outside a writer overlap | 1,281 | 240 | 6 |
| Crossing an overlap boundary | 182 | 185 | 136 |

Classification expands each camera summary's first-to-last source timestamp range by 100 ms before testing containment. Reports are approximately one second; these medians are counts per report, not exact measured FPS. Single-frame startup summaries are excluded. Writer spans describe accepted source frames, not internal encoder lifetimes, and incomplete terminal logs can shorten the inferred spans.

Using each swing's exact source range and 8× factor to map playback gaps back to capture time, 617 of 626 pauses intersect duplicate-recording intervals. The remaining nine lie within 48.5 ms of those intervals. The method does not assume the first chunk ID names all chunks in a composed clip.

For marked clip 002, camera summaries show roughly 240 frames with no drops before a second writer starts at 18:14:09 local time. During the overlap, one report records 132 delivered frames and 109 out-of-buffers drops. After the older writer completes, delivery returns to 240 frames with no drops. All 53 pauses in this clip intersect the overlap.

This repeated start/degrade/finish/recover pattern makes simultaneous rolling writers the leading cause. Detector work continues through both smooth and affected periods. The evidence is stronger than a general suspicion about detector load, though a controlled device comparison is still needed for causation and final validation.

## Proposed implementation

### Why overlap existed

The original [June 5 Auto implementation](https://github.com/ruari8/SwingCoach/commit/6b9ed28be6afc8ce41be474587d73448b84c6417) used 12-second chunks starting every six seconds. Its exporter required a single chunk to contain both the requested start and end; otherwise it returned `clipUnavailable`. Overlap provided coverage for clips near a file boundary. This rationale follows from the original selection code, rather than a separate design record.

The [July 11 capture fix](https://github.com/ruari8/SwingCoach/commit/ff19c4e992ccdde8fcb2775964b93f30e4ff87a3) changed the schedule to 20-second chunks starting every 17.4 seconds. Its documentation calls the remaining 2.6 seconds a safety overlap and says the reduction avoids near-continuous double encoding. That commit also released consumed sample buffers sooner to fix an earlier cause of camera-buffer starvation. The history inspected here does not establish why precisely 2.6 seconds was chosen.

The [September 8 extra-footage change](https://github.com/ruari8/SwingCoach/commit/7f73f51141d9737471b4a9c1909925f82c642a0e) added multi-file composition while retaining the overlap schedule. The single-file export constraint therefore no longer justifies sustained duplicate recording.

### Record consecutive chunks

Replace overlapping rolling recording with consecutive chunks. Keep 240 fps, the existing detector, and the requested pre/post-swing footage for the first comparison.

1. Give each incoming source frame one recording destination. At rollover, seal the old chunk before appending the boundary frame to the new chunk. Use source timestamps and frame duration to preserve continuous coverage. Changing only `chunkStartInterval` to 20 is insufficient: the current loop can still append the boundary frame to both writers.
2. Reuse `PreparedClip.segments` and `makeAsset()` to join a swing crossing a boundary. Those functions already select source ranges, preserve gaps, and combine multiple files. The overlap is no longer necessary to fit a complete swing into one file.
3. Keep finalization asynchronous and keep the camera callback free of encoder waits. A writer finishing its earlier frames can briefly coexist with the next writer, so measure that handoff separately. The required invariant is that each source frame is submitted to one rolling writer; it does not imply that AVFoundation destroys the previous encoder instantly.
4. Preserve the existing rules for early stop, pending extra footage, retention, camera rotation, and review-session resets. An export that seals a chunk must leave the next camera frame assigned exactly once to a new chunk.
5. Extend diagnostics with writer-seal time, handoff duration, and the number of rolling writers receiving each frame. Retain camera drop and source-timestamp measurements. If drops remain around handoffs, measure camera-buffer lifetime across the queue and encoder before choosing bounded app-owned pixel-buffer copies or a continuous single-encoder design.

Do not begin by copying every 1080p frame or reducing the capture rate. Removing duplicate encoding addresses the measured workload without adding a full-frame copy or reducing captured swing detail. Those alternatives remain available if the single-destination path still exhausts buffers.

## Verification needed before declaring the app fixed

- Add a rollover check that counts writer destinations per unique source timestamp. Assert exactly one destination, including the boundary frame and an export-triggered closure.
- Exercise real encoded clips spanning consecutive chunks. Check decoded frame count, monotonic timestamps, duration, absence of duplication, and absence of newly introduced gaps. Existing `SwingClipContextTests` already provide encoded multi-chunk, early-stop, and dropped-frame fixtures; extend those rather than treating a build as proof.
- Run one focused Capture UI verification pass after implementation is ready, per the repository instructions.
- Compare the existing and revised builds on the same iPhone at 240 fps with detection enabled. Record long enough to cross repeated chunk rollovers and export boundaries. A moving subject is sufficient to measure cadence; another range session is not required. Verify sustained double submission is gone, then compare camera out-of-buffers counts and saved-video presentation gaps, including boundary-spanning clips.
- If drops persist, keep the fix unverified and isolate writer handoff, export concurrency, and detector buffer retention in separate comparisons. Do not accept silently discarding frames or merely moving the gaps elsewhere as success.

## Reproduction and retained artifacts

Private media remain in `/Users/ruari/Downloads/10:9_range_session`. Phone logs and analysis artifacts are retained locally under `.verification-artifacts/issue-28/2026-09-10/`. Raw logs and Photos identifiers are not copied into this document.

From the repository root:

```bash
python3 scripts/diagnostics/analyze_auto_cadence.py '/Users/ruari/Downloads/10:9_range_session' --pattern '*.mp4' --output .verification-artifacts/issue-28/2026-09-10/cadence.json --assert-no-gaps
python3 .verification-artifacts/issue-28/2026-09-10/correlate.py
python3 .verification-artifacts/issue-28/2026-09-10/analyze_writer_overlap.py
```

All three commands were run. The first exits 1 because the files contain timing gaps. The remaining commands produce `correlation.json` and `writer-overlap.json` with the joined records, inferred writer ranges, and counts reported above. Overlapping one-second diagnostic summaries include some frames outside each clip, so their drop counts are not exact per-clip loss totals.

The installed app reports version 1.0/build 1, which does not identify its source commit. The current source contains the overlap mechanism, and actual phone writer events independently establish duplicate recording in the session. No app code, installation, or recording settings were changed during this investigation.
