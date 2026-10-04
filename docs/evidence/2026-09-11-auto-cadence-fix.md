# September 11 consecutive-recording candidate — jitter acceptance failed

**Status: not accepted as a complete jitter fix.** Removing overlapping recording passed its mechanism checks, but the physical camera still lost frames at file transitions. The installed build is a candidate under investigation. Synthetic frame-count tests and successful installation are not sufficient acceptance criteria for this performance defect.

Auto now records each source frame into one rolling file. A single `recordingChunk` owns the destination for new frames. At the 20-second boundary, the buffer seals that chunk before appending the boundary frame to the next file. Sealed writers finish asynchronously and remain available for clip assembly. Rotation and export closures use the same ownership rule.

This implements the solution from the [September 10 investigation](./2026-09-10-auto-cadence-investigation.md). The frame rate, detector, extra-footage settings, and saved-library behavior are unchanged. The source no longer contains the 17.4-second schedule or a loop that feeds each incoming frame into multiple recording chunks.

## Verification

- Before the change, the new regression encoded **1,388 frames from 1,230 source frames** into the underlying rolling files. The test failed on duplicate recording even though final composition could hide that duplication.
- After the change, all **nine** selected recording/context and review-session tests passed, with no failures or skips. The new regression checks 41 seconds at 30 fps, 41 seconds at 240 fps, and a 240 fps recording whose writer closes early for an export. It decodes the raw rolling files and requires each source frame exactly once, then checks the assembled clip's frame identity and absence of newly introduced missing-frame intervals. These are synthetic 64×64 inputs, not measurements of a physical camera's performance.
- Tests account for the movie writer's timestamp quantization at 240 fps. They require the correct source frame at every position and intervals no greater than 1.5 source-frame periods, rather than requiring sub-tick precision the track cannot represent.
- All **six distinct Capture UI checks** passed across the initial run and the focused settings rerun. The initial run passed four checks; two settings checks failed because the old driver did not scroll to the diagnostics section after newer settings were added above it. The corrected driver reveals the control before using it, and both affected checks passed on rerun. Passing UI checks were reused.
- The initial UI runner was edited while its XCTest process was running, causing a shell parse error after XCTest completed. Its exit status is not used as proof. The XCTest result bundle was recovered directly and reports four passes and two settings failures. The focused rerun completed normally, and both disposable UI Simulators were deleted.
- The signed Debug build **2026.9.11**, bundle ID `Pear.ai.SwingCoach`, built successfully and installed over the existing app on the connected **iPhone 17**. The existing capture logs were copied before installation. The installation did not uninstall or reset the app.
- After the user unlocked the phone, build 2026.9.11 launched successfully at 14:53:37 local time. A 62-second live-camera observation at 240 fps logged four consecutive writers and three rollovers. Every new writer identified `consecutive-v1`; source ranges did not overlap, and each prior writer sealed before the next started.
- The live observation still logged 38 out-of-buffers drops: 12 during startup and 26 around the three rollovers. The rollover source-timestamp gaps reached roughly 33–42 ms. Removing sustained duplicate recording is verified, but eliminating all jitter is not. No saved swing was exported or visually reviewed in this check.

## Diagnostics for the next session

`writer-start.state.recordingPolicy` identifies this implementation as `consecutive-v1`. `buffer-input.values.recordingChunks` counts the destination receiving new frames, separately from unfinished writers. `writer-sealed` records the closure reason and source end; finalization duration is included on `writer-end` when a seal was recorded.

The phone observation confirms consecutive source ranges but exposes residual encoder-handoff stalls. The next investigation should measure writer creation/finalization and camera-buffer retention during these short transitions, then verify saved-video cadence. The installed change removes sustained overlapping recording; it does not yet establish jitter-free capture.

## Handoff investigation and acceptance

`scripts/diagnostics/check_auto_handoffs.py` checks the latest process run in copied device logs. It requires at least three rollovers and rejects camera, buffer-input, or writer cadence gaps after the explicitly excluded first two seconds. Running it on `phone-rollovers/capture.jsonl` fails with three rollovers and nine failing cadence reports. This is a physical input/encoding check; it does not replace decoding exported files.

The next timing probe distinguishes three hypotheses: synchronous finalization blocks the recording queue; synchronous new-writer setup blocks that queue; or the encoders retain source buffers beyond those synchronous calls. The first two predict a long measured call matching the delegate-to-buffer queue delay. The third predicts drops despite short calls and low queue delay. Build 2026.9.12 adds temporary `DEBUG-handoff-setup` and `DEBUG-handoff-finish` timings for this distinction. It installed and launched, but camera logging stopped after nine seconds, before a rollover; device readiness for a longer run was requested again.

Before accepting the complete repair, require sustained physical 240 fps capture across repeated rollovers, decoded saved clips spanning those boundaries without timing holes, and coverage of an early file closure caused by clip export. Confirm frame counts and source timing remain correct in the existing synthetic tests. Include a real Auto practice-swing recording in final field validation; do not ask the subject to assess the live preview. Startup exclusions and any remaining untested condition must remain explicit.

## Local evidence

Artifacts are retained under `.verification-artifacts/issue-28/2026-09-11-fix/`:

- `red.xcresult` and `red.log`: duplicate-encoding failure on the unchanged implementation.
- `green-final.xcresult` and `unit-summary.json`: nine passing recording/lifecycle tests.
- `capture-ui/` and `capture-settings/`: six UI checks, screenshots, recovered results, and cleanup records.
- `device-build.log`, `DeviceBuild/`, `install.json`, and `launch.log`: signed build, installation, and locked-device launch result.
- `phone-before/`: capture diagnostics preserved before installation.
- `launch-unlocked.json`, `phone-rollovers/`, and `phone-rollover-summary.json`: successful launch and live physical-camera observations after unlocking.
- `source-manifest.json` and `route.txt`: build identity, source hashes, and verification route.

The changes remain in the working tree; no commit or push was performed.
