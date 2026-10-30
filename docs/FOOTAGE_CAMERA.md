# Footage camera

DEBUG builds can replace the back camera with recorded video. The footage enters where camera frames enter (`CameraSession.handleVideoFrame`), so detection, the rolling recorder, Auto save, swing positions and the capture diagnostics log all run as they would at the range. This lets Auto be tested from a desk, on the Simulator or on a phone.

Code: `SwingCoach/Models/FootageCamera.swift`, wired in `CaptureView.swift`.

## Launch options

| Option | Meaning |
| --- | --- |
| `-footage-camera <path>` | A video file, a folder of `.mov`/`.mp4` files played in name order, or comma-separated files. Relative paths resolve against the app's Documents folder. |
| `-footage-camera-time-scale <n>` | How many times slower than real time the footage plays. Default 1. Use 8 for 240 fps footage exported at 30 fps (the labelled range videos and saved Auto clips). |
| `-footage-camera-buffers <n>` | Frame pool size. Default 15. |
| `-footage-camera-every-frame YES\|NO` | Deliver every frame, waiting for the app instead of dropping. Default YES on the Simulator, NO on a phone. See [Two pacing modes](#two-pacing-modes). |
| `-footage-camera-impacts <t,t,…>` | Labelled impacts, in real seconds from the start of the footage. Auto saves these instead of the detector's swings. The detector still runs, and each swing it accepts is logged as `detector-swing`. Use this on the Simulator, where Vision pose can't run. |

Saved clips go to the app's library but never to Photos while the footage camera is on, whatever the Save to Photos setting says. Add `-footage-camera-photos YES` to send them to Photos for a test that needs it.

When the footage ends, any clip still waiting for footage after its swing is saved with what was recorded, as stopping Auto does. Each frame carries its own file's rotation, so a kept session recorded across a phone rotation replays upright.

The Capture tab shows the footage instead of the camera preview, with a yellow status line: file, position, frames delivered, and either frames dropped (real time) or playback speed (every frame). When the footage finishes, **Replay** on the status line plays it again from the start in the same Auto session, labelled impacts included. The frame-rate menu follows the footage's real frame rate and can't be changed.

## Two pacing modes

**Every frame** (Simulator default) gives the app a perfect stream: nothing is dropped or skipped. Each frame waits for a free buffer and for the detector to finish the previous frame, and is stamped with its own moment on the footage timeline. When the machine can't keep up, the footage plays slower than real time instead; the status line shows the speed. The detector then samples at its full 8 or 16 fps of footage time, as on a phone that keeps up. Wall-clock timings, such as impact to saved clip, mean nothing in this mode.

**Real time** (phone default) behaves like the camera, drops included, as described below. On a phone, drops are real findings. On the Simulator they mostly measure the Simulator: it has no Neural Engine, so YOLO and body pose run on the CPU and a detector check takes 160–230 ms, against about 36 ms on an iPhone 17. It can't keep up in real time. `scripts/verify.sh footage` uses real time so the run lasts as long as the footage.

## How real time behaves like the camera

- **Real clock.** Frames are delivered at their real-time moment and stamped on the host clock, as camera frames are. Footage plays only while the Capture tab is open, and resumes where it stopped.
- **Fixed buffer pool.** Each frame is copied into a pool of 15 buffers. If the app still holds all of them, the frame is dropped and logged as `dropped_outOfBuffers`, the same reason the camera reports. The September jitter came from exactly this starvation. The camera's real pool size isn't documented. 15 is an assumption; change it with `-footage-camera-buffers`.
- **Late frames.** If decoding falls more than two frames behind the clock, frames are skipped to catch up and logged as `dropped_footageLate`. At least 30 frames a second are still delivered, late if necessary, so a feeder that can't keep up lowers the frame rate instead of stopping the stream. This is the feeder failing to keep up, not the app, so read it separately from `outOfBuffers`.

## What it doesn't cover

- **Camera hardware:** exposure, focus, stabilization, rotation and sound.
- **Extra load:** decoding the footage and copying each frame use CPU and memory bandwidth that a real camera doesn't. On a phone this makes the test slightly harsher than the range.
- **Heat:** a phone on a desk and charger stays cooler than one in the sun.
- **Simulator:** Vision body pose fails ("Unable to setup request") because the Simulator's copy of iOS leaves out the pose model's weights file. The detector then rejects every swing because it sees no golfer, and swing positions end in "could not be found". Without a Neural Engine its detector is also several times slower than a phone's, so its timings and drop counts say nothing about a phone.

## Keeping range footage to replay

Library > gear > Experiments > **Keep Auto recordings** (DEBUG builds). Auto's rolling recordings normally last 45 s. With this on, each finished recording moves to `Documents/KeptRecordings/<start time>-<id>/`, with a new folder each time Auto starts or resumes after review. Files are named by their start on the session timeline, so name order is recording order.

- **Size:** about 22 GB an hour at 240 fps (50 Mbit/s). The folder is excluded from iCloud backup.
- **Diagnostics:** each kept file logs `recording-kept`. A failed move logs `keep-recordings-failed` with the file's tmp path and leaves the file there rather than deleting it.
- **Replay:** copy a folder off the phone, or leave it on the phone, and play it with `-footage-camera KeptRecordings/<folder>` (time scale 1).

Copy kept recordings off the phone:

```bash
xcrun devicectl device copy from --device CD21BEF7-8C46-5763-8024-1312A7C79D5F \
  --domain-type appDataContainer --domain-identifier Pear.ai.SwingCoach \
  --source Documents/KeptRecordings --destination .verification-artifacts/kept-recordings
```

## Checks

`scripts/verify.sh footage` runs the check on a disposable Simulator. It runs only on request, never in `all`, because it needs the private videos. `FOOTAGE_VIDEO=<video-id> scripts/verify.sh footage` picks another video.

1. It reads the labels for the video from `detector_workbench/validation/labels/detector_test_v3_labels.json`. The default is test15: 71 s of 240 fps range footage with 3 swings.
2. It copies the private video from `.detectorTestV3/` (this checkout or the main one) into the app. Without it the run reports `BLOCKED`.
3. It runs `SwingCoachUITests/FootageCameraUITests` with the labelled impacts and Keep Auto recordings on, plus `FootageCameraTests`.

Afterwards it checks the diagnostics log: every labelled impact was fed and saved, `footage-end` was logged, and the log has camera, detector, writer and export events. When the last swing falls within its clip's 0.8 s tail of the end, a clip must also be saved after `footage-end`, through the end-of-footage flush; test15 ends too late to need it. The test then leaves Capture, which stops Auto and keeps the recordings still in the rolling window. The runner checks that the kept recordings have no failed moves and one `recording-kept` event per file, and that together they cover at least 90% of the footage played. It then writes `footage-metrics.json`:

- frames delivered and dropped
- the detector's impact candidates against the labels
- time from impact to saved clip
- swing-position results

Simulator run of the script, test15 (Oct 27, 2026):
- **Saves:** 3/3 labelled swings saved, 1.7–1.9 s after each impact. That includes the clip's 0.8 s after impact.
- **Detector:** reached an impact candidate within 1 s of all 3 labels (8 candidates in total), but accepted none, because Vision found no golfer.
- **Frames:** 66% delivered (11,278). The rest were 4,610 skipped by a feeder running behind and 1,234 pool drops. This is the Simulator running YOLO on its CPU, not phone behaviour.
- **Swing positions:** failed on all 3 with "no golfer", as expected in the Simulator.

## On a phone

This needs the phone ready for Xcode (see the [testing ladder](../.agents/skills/verify-swingcoach/references/testing-ladder.md#physical-iphone-recipe)).

1. Install the Debug build as the ladder describes.
2. Copy the footage into the app's Documents:

   ```bash
   xcrun devicectl device copy to --device CD21BEF7-8C46-5763-8024-1312A7C79D5F \
     --domain-type appDataContainer --domain-identifier Pear.ai.SwingCoach \
     --source .detectorTestV3/test15.mp4 --destination Documents/test15.mp4
   ```

3. Launch with the real detector. Leave out `-footage-camera-impacts`, because Vision pose runs on the phone:

   ```bash
   xcrun devicectl device process launch --device 00008150-001838EE36F8401C --terminate-existing \
     Pear.ai.SwingCoach -footage-camera test15.mp4 -footage-camera-time-scale 8
   ```

4. Let the footage finish, then copy `CaptureDiagnostics` off the phone. On a phone, the frame drops, detector timing and `swing-positions` timings are real measurements.
