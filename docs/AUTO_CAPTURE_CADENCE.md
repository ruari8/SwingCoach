# Auto capture cadence investigation

Issue [#28](https://github.com/ruari8/SwingCoach/issues/28) concerns intermittent jitter in the September 6 range session. All seven marked clips contain presentation-time gaps in the decoded file. The cause upstream of those files remains unproven. This change adds automatic diagnostics; it does not repair existing footage or establish that future capture is fixed.

## Offline evidence

Run from the repository root with Python 3 and ffprobe:

```bash
python3 scripts/diagnostics/analyze_auto_cadence.py \
  '/Users/ruari/Downloads/6:9_range_session' \
  --output .verification-artifacts/issue-28/cadence.json --assert-no-gaps
```

The command exits 1 for this dataset because it detects timing gaps. It reads every decoded frame's presentation timestamp using ffprobe's normal edit-list handling, covering all seven `jit_*.MP4` and all 28 `auto_swing_*.MP4` files. It does not read the false-positive, practice, manual, or screen-recording inputs. No source files change.

The [machine-readable results](./evidence/2026-09-06-auto-cadence.json) contain every interval above 75 ms, full interval histograms, stream metadata, input SHA-256 hashes, ffprobe version, and decode errors. There were no reported decode errors or non-increasing decoded PTS values. The threshold is deliberately conservative for these roughly 30 fps slow-motion playback timelines. Most smooth intervals alternate between 26.667 and 40 ms; neither counts as a pause. Header frame counts and average frame-rate fields are not substitutes for the decoded presentation sequence.

All timestamps below are seconds on the exported clip's playback timeline. The span runs from the start of the first qualifying gap through the end of the last; it does not imply every frame inside it jitters.

| Marked clip suffix | Decoded frames | Gaps >75 ms | Affected span | Longest gap |
| --- | ---: | ---: | --- | ---: |
| `0054AC39` | 404 | 49 | 5.747 to 18.973 | 0.200 s |
| `56AC2880` | 474 | 31 | 0.133 to 8.147 | 0.200 s |
| `97326DD8` | 458 | 33 | 9.853 to 18.973 | 0.200 s |
| `B2BE7819` | 334 | 74 | 0.467 to 19.040 | 0.200 s |
| `C31766CD` | 492 | 25 | 0.067 to 6.453 | 0.200 s |
| `CA91EA1D` | 431 | 47 | 0.093 to 11.253 | 0.200 s |
| `D9F63E0A` | 332 | 73 | 0.093 to 19.000 | 0.200 s |

Twenty of the 28 unmarked controls have no gaps above 75 ms and maximum intervals of 40 ms. Eight controls also have cadence loss:

| Unmarked control suffix | Gaps >75 ms | Affected span | Longest gap |
| --- | ---: | --- | ---: |
| `366DE15B` | 28 | 0.027 to 6.640 | 0.173 s |
| `38B864A0` | 47 | 0.107 to 11.693 | 0.200 s |
| `63B6455B` | 59 | 3.373 to 19.133 | 0.240 s |
| `8FA7A243` | 57 | 0.107 to 13.693 | 0.227 s |
| `A61373F8` | 1 | 18.840 to 18.973 | 0.133 s |
| `AB75963A` | 20 | 14.627 to 19.040 | 0.133 s |
| `B8D06F39` | 19 | 0.000 to 4.507 | 0.200 s |
| `CE3AA7C8` | 54 | 5.053 to 19.040 | 0.200 s |

For a minimal comparison, `jit_auto_swing_0054AC39.MP4` has no new displayed frame between 5.746667 and 5.880000 seconds. `auto_swing_07BCC95D.MP4` has no interval above 40 ms anywhere. This is file-level temporal evidence independent of SwingCoach's player. It does not quantify spatial shake, focus quality, or whether playback adds further stalls.

## Cause and remaining uncertainty

The leading hypothesis is intermittent source-frame loss under capture/encoder load. The marked clips contain long regular sections interspersed with clusters of missing presentation intervals. The current code locks camera frame durations, separates model inference and writing, and retains samples while the writer is not ready. Retained sample buffers and delayed writer work could exhaust camera buffers, but the exported files cannot prove this happened.

Other hypotheses remain distinguishable:

- Camera delivery falls behind or loses buffers. Expect camera PTS gaps and/or `didDrop` reasons, possibly alongside pressure or thermal changes.
- Writer backlog, append failure, or retiming loses frames. Expect regular camera input followed by buffer queue delay, pending-frame growth, append errors, or gaps in accepted writer PTS.
- Export changes cadence. Expect regular camera/writer summaries but gaps in the exported file, correlated through chunk ID and output filename.
- Exposure/focus/stabilization or playback adds visible judder. Timing analysis does not rule out these additional symptoms. Device state is recorded for correlation; a controlled phone experiment is still needed.

No contemporaneous camera/drop/writer/thermal logs or original rolling chunks survive in this evidence set. The exact device build and active settings are not established by the MP4 headers. Capture settings therefore remain unchanged. Audio lifecycle belongs to #22 and detector false positives to #29.

## Automatic diagnostics

Auto capture now writes JSON Lines to the app container at:

```text
Library/Application Support/CaptureDiagnostics/capture.jsonl
Library/Application Support/CaptureDiagnostics/capture.previous.jsonl
```

Collection is always on for Auto and does not depend on `Show model stats`, DEBUG UI, a live console, or a person reading the rear-camera screen. Each file is capped at 8 MiB, for 16 MiB total. The oldest file rotates away. Writes run on a separate utility queue with at most 32 queued events; a blocked disk drops diagnostic events instead of blocking capture. Files survive leaving Capture and app relaunch. Copy them soon after the session, before later sessions overwrite them.

Events contain schema version, process run ID, UTC time, system uptime and a boundary name. They contain no frames, audio, Photos identifiers or location. Each frame boundary aggregates once per wall-clock second while callbacks arrive:

- `camera` records absolute source PTS, received-frame count, gaps greater than 1.5 expected frame periods, non-increasing timestamps, maximum gap, drop counts by `late`/`outOfBuffers`/`discontinuity`/`unknown`, and analysis coalescing. Coalescing is detector workload, not evidence of lost recorded frames.
- Camera state includes requested FPS, actual active min/max frame duration, resolution, exposure, ISO, lens position, focus/exposure adjustment, active stabilization mode, thermal state and pressure level.
- `buffer-input` records source PTS, relative capture time, source FPS, maximum delegate-to-buffer queue delay and active chunk count.
- `writer-start` maps chunk ID to source PTS and relative time, FPS, resolution, bitrate, codec and rotation. `writer` records accepted chunk-relative PTS, maximum pending-frame depth seen at acceptance, current pending depth, readiness and writer status. `writer-end` includes final status/error and remaining cadence summary. Start, retime and append failures have separate events.
- `export-start` maps chunk ID to the requested range and slow-motion factor. `export-written` adds the output filename. `export-end` records save success or failure. `swing-saved` links the permanent `SavedSwing.id` to the chunk, exact source range, slow-motion factor and original filename. Library batch export already includes this ID as `swingID` in `metadata.json`, so renaming exported videos does not break the join.

A gap between summaries remains counted. Timeline resets start a fresh counter and log `camera-reset`/`buffer-reset`; they are not misreported as frame drops. Event timestamps and chunk source PTS allow correlation across the camera, buffer, writer and exported playback timelines. A total callback stall appears as missing periodic events and, if delivery resumes, a large next PTS interval. A crash can lose queued events. These logs do not promise a complete per-frame trace.

## Collect after the next range session

1. Install a build containing this change before the range session. Use Auto normally. Every saved swing, including smooth swings, gets a `swing-saved` record while camera/writer summaries run continuously during Auto. There is no jitter toggle or automatic user-visible jitter label.
2. At home, select the affected swings and at least one smooth comparison in Library, then Export to the Mac. Keep the exported `metadata.json` beside the videos. For 30 swings with problems in 13, 18 and 19, identify those three clips for the investigator; display positions are not permanent IDs.
3. Connect and unlock the development iPhone, then tell the agent that the phone is ready for log retrieval. The agent can use Xcode's `devicectl` to copy the diagnostic directory into the task's evidence folder. The command is below; the user does not need to navigate app-private folders. Device transfer is supported by the installed CLI but has not yet been verified on a physical iPhone for this change. Xcode's Devices and Simulators window can also download the app container.
4. Join each exported video's `metadata.json` entry to the `swing-saved` event using `swingID`, then use the event's chunk ID and source range to select camera/writer evidence. An original `auto_swing_` filename can still match `export-written`, but Library export changes filenames, so prefer the permanent ID. Missing log records must be reported as missing, not matched by guesswork.
5. Analyze the affected videos' presentation gaps and compare the corresponding source-time intervals with the logs. No debug data is embedded in the MP4: video-to-ID mapping is in `metadata.json`, and diagnostic readings are in the separate JSONL logs.

For renamed Library exports, run `python3 scripts/diagnostics/analyze_auto_cadence.py <export-directory> --pattern 'swingcoach_*' --output <evidence-directory>/cadence.json`. The default patterns remain restricted to the original range-session evidence.

Operator command, only after phone readiness is confirmed; substitute the resolved device ID and an owned output path:

```bash
xcrun devicectl device copy from \
  --device '<device-id>' \
  --domain-type appDataContainer --domain-identifier Pear.ai.SwingCoach \
  --source 'Library/Application Support/CaptureDiagnostics' \
  --destination '<evidence-directory>/CaptureDiagnostics' \
  --json-output '<evidence-directory>/copy-result.json'
```

Copy logs soon after the session and before uninstalling the app. They survive relaunch, but rotation can overwrite older sessions. Storage is capped at 16 MiB total, about 17 MB, across all swings and sessions. The instrumentation stores text measurements and IDs; it adds no video copies. The retention period depends on capture activity, so a fixed number of sessions or hours is not guaranteed.

The next controlled device comparison should cover 30/60/120/240 fps, warm versus cool device state, and detector load during a long Auto session. These are deferred hardware checks, not claims established by Simulator.

## Before and after diagnostics

```bash
python3 -m unittest discover -s scripts/diagnostics -p 'test_*.py'
python3 scripts/diagnostics/verify_capture_cadence.py \
  '/Users/ruari/Downloads/6:9_range_session/jit_auto_swing_0054AC39.MP4' \
  --output .verification-artifacts/issue-28/replay
```

Before this change, the affected file supplies no camera/writer boundary evidence and the app has no persistent cadence report. After this change, replaying that file's 404 decoded PTS values through the production Swift counter records all 53 gaps above 50 ms across 14 reports and reads the same gap count back from the JSONL file. This replay uses a 30 fps playback expectation, without guessing the original capture rate. The runtime's 1.5-frame threshold at 30 fps is 50 ms, lower than the investigation's conservative 75 ms threshold, so the counts intentionally differ.

The probe also verifies a gap spanning reports, invalid/duplicate timestamps, queue/backlog metrics and disk rotation. This is an instrumentation before/after comparison. The original clip's pauses remain unchanged. `./scripts/verify-capture-controls.sh` verifies the production Capture UI in a disposable Simulator with synthetic capture and reference playback; it cannot prove real camera cadence, thermal behavior, drop callbacks or pressure reporting.

The corrected Debug app passes a generic iOS Simulator build with two jobs. The final Capture UI pass on an owned iPhone 17 Simulator running iOS 26.3.1 passed all five tests with zero failures or skips and no app crash. It covered Capture state and model-stat persistence, review playback/paging/deletion, and Manual → Trim → Cancel with a second recording. A read of the running app container also confirmed persisted schema-1 `run` and `buffer-reset` diagnostic events. The helper deleted its owned Simulator and scratch build. Evidence is retained locally in `.verification-artifacts/issue-28/capture-controls-final/`; the source revision was `f22f00ab`. This Simulator run used synthetic capture and does not prove real camera drop, pressure or writer-load telemetry.
