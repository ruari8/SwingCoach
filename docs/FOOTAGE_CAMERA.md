# Footage camera

DEBUG builds can replace the back camera with recorded video. The footage enters where camera frames enter (`CameraSession.handleVideoFrame`), so detection, the rolling recorder, Auto save, swing positions and the capture diagnostics log all run as they would at the range. This lets Auto be tested from a desk, on the Simulator or on a phone.

Code: `SwingCoach/Models/FootageCamera.swift`, wired in `CaptureView.swift`.

## Launch options

| Option | Meaning |
| --- | --- |
| `-footage-camera <path>` | A video file, a folder of `.mov`/`.mp4` files played in name order, or comma-separated files. Relative paths resolve against the app's Documents folder. |
| `-footage-camera-time-scale <n>` | How many times slower than real time the footage plays. Default 1. Use 8 for 240 fps footage exported at 30 fps (the labelled range videos and saved Auto clips). |
| `-footage-camera-buffers <n>` | Frame pool size. Default 15. |
| `-footage-camera-impacts <t,t,…>` | Labelled impacts, in real seconds from the start of the footage. Auto saves these instead of the detector's swings. The detector still runs, and each swing it accepts is logged as `detector-swing`. Use this on the Simulator, where Vision pose can't run. |

The Capture tab shows the footage instead of the camera preview, with a yellow status line: file, position, frames delivered, and frames dropped. The frame-rate menu follows the footage's real frame rate and can't be changed.

## How it behaves like the camera

- **Real clock.** Frames are delivered at their real-time moment and stamped on the host clock, as camera frames are. Footage plays only while the Capture tab is open, and resumes where it stopped.
- **Fixed buffer pool.** Each frame is copied into a pool of 15 buffers. If the app still holds all of them, the frame is dropped and logged as `dropped_outOfBuffers`, the same reason the camera reports. The September jitter came from exactly this starvation. The camera's real pool size isn't documented. 15 is an assumption; change it with `-footage-camera-buffers`.
- **Late frames.** If decoding falls more than two frames behind the clock, frames are skipped to catch up and logged as `dropped_footageLate`. At least 30 frames a second are still delivered, late if necessary, so a feeder that can't keep up lowers the frame rate instead of stopping the stream. This is the feeder failing to keep up, not the app, so read it separately from `outOfBuffers`.

## What it doesn't cover

- **Camera hardware:** exposure, focus, stabilization, rotation and sound.
- **Extra load:** decoding the footage and copying each frame use CPU and memory bandwidth that a real camera doesn't. On a phone this makes the test slightly harsher than the range.
- **Heat:** a phone on a desk and charger stays cooler than one in the sun.
- **Simulator:** Vision body pose fails ("Unable to setup request"), so the detector rejects every swing because it sees no golfer, and swing positions end in "could not be found". The Simulator also encodes the rolling recording in software, so its drop counts say nothing about a phone.

## Keeping range footage to replay

Library > gear > Experiments > **Keep Auto recordings** (DEBUG builds). Auto's rolling recordings normally last 45 s. With this on, each finished recording moves to `Documents/KeptRecordings/<start time>/`, with a new folder each time Auto starts or resumes after review. Files are named by their start on the session timeline, so name order is recording order.

- **Size:** about 22 GB an hour at 240 fps (50 Mbit/s). The folder is excluded from iCloud backup.
- **Diagnostics:** each kept file logs `recording-kept`; failures log `keep-recordings-failed`.
- **Replay:** copy a folder off the phone, or leave it on the phone, and play it with `-footage-camera KeptRecordings/<folder>` (time scale 1).

Copy kept recordings off the phone:

```bash
xcrun devicectl device copy from --device CD21BEF7-8C46-5763-8024-1312A7C79D5F \
  --domain-type appDataContainer --domain-identifier Pear.ai.SwingCoach \
  --source Documents/KeptRecordings --destination .verification-artifacts/kept-recordings
```

## Checks

`scripts/verify-footage-camera.sh [artifact-dir] [video-id]` runs the check on a disposable Simulator:

1. It reads the labels for `video-id` from `detector_workbench/validation/labels/detector_test_v3_labels.json`. The default is test15: 71 s of 240 fps range footage with 3 swings.
2. It copies the private video from `.detectorTestV3/` into the app.
3. It runs `SwingCoachUITests/FootageCameraUITests` with the labelled impacts.

The script asserts that every labelled swing is saved and that the diagnostics log has footage, camera, detector, writer and export events. It then writes `metrics.json`:

- frames delivered and dropped
- the detector's impact candidates against the labels
- time from impact to saved clip
- swing-position results

First Simulator run, test15 (Oct 27, 2026):
- **Saves:** 3/3 labelled swings saved.
- **Detector:** reached an impact candidate at all 3 labels, but rejected each one because Vision found no golfer.
- **Frames:** about 70% delivered. Most of the drops were the feeder falling behind while the Simulator encoded 240 fps in software.

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
