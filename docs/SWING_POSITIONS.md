# Swing positions (P1–P10)

During Auto, the app finds the ten swing positions on the phone from live camera frames, about 0.8 s after impact, and stores them on the swing when it's saved. Swing Info lists them. When the live run can't finish, the app reads the saved clip instead.

Down-the-line clips only. Face-on clips and imported videos are skipped.

## What runs

| Step | Code |
| --- | --- |
| Live: copy every 8th Auto frame (30 per second of real time) at 480 wide out of the camera's buffers, keep the last 3 s, and run pose on the swing's copies once the detector declares it | `SwingCoach/Models/SwingPositions/LiveSwingPoses.swift`, fed from `CaptureView.swift` |
| Join live results to the saved swing; otherwise queue the saved clip, one at a time, utility priority, after the Auto save and when a swing without current positions is opened | `SwingPositionProcessor.swift` |
| Saved clip: read the swing part, run Vision body pose 30 times per second of real swing time (every 0.033 s), run the model | `SwingPositionAnalyzer.swift` |
| Feature rows and ordered decoding; the stored result types | `SwingPositions.swift` |
| Model | `SwingCoach/MLModels/SwingPositionTCN.mlpackage` |

The model is `tcn_vision_v2` from `../detectSwings/event_model`. It's a small temporal network: Apple Vision 19-joint pose in, a score per frame for each position out. The decoder picks one frame per position, in order.

Only the swing is used: the detector's window, 1.6 s before impact to 0.8 s after (2.4 s, so 72 pose calls). The Extra swing footage before and after is left out; `SavedSwing.swingWindow` records where the swing sits in the clip. Swings saved before this was recorded, and imports, are read whole.

Saved clips play 8× slower than real time for 240 fps capture (4× for 120 fps). The model works in real time, so `SavedSwing.sourceTimeScale` records the factor at save time. Clips without it (imports, swings saved before this change) get no positions.

Stored per swing in `swing_library.json` under `swingPositions`:
- the model name
- for each position: number, time on the clip's own slow-motion timeline, and confidence (the model's score through a sigmoid)

Swing Info fades positions under 50% confidence.

## Accuracy

Measured on the frozen bench in detectSwings: 106 of your range clips, never trained on.

| Position | P1 | P2 | P3 | P4 | P5 | P6 | P7 | P8 | P9 | P10 | All |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Within ±1 frame at 30 fps | 60% | 69% | 84% | 79% | 96% | 97% | 98% | 84% | 56% | 46% | 77% |

Within ±2 frames: 90% overall. One frame at 30 fps is 33 ms of real time, about 8 frames of a 240 fps clip.

P1 comes out 1.4 frames late and P10 1.8 frames early on average. The analyzer removes both offsets. Address and finish are fuzzy to label, so treat those two as rough.

The decoder always returns ten positions. If Vision finds a body in fewer than half the slots, the analyzer stops with "no golfer" and nothing is stored.

## Choices and their evidence

Checked on the frozen bench before building:
- **One pose call per slot.** Training measured joint velocity between consecutive source frames. Measuring it between slots instead scores the same (77% / 90%), so the phone needs about 90 Vision calls for a 3 s swing, not one per frame.
- **Separate pose calls rather than reuse the live detector's pose.** The live detector runs pose at its sample rate: 8 fps by default, 16 fps during bursts around a swing. Fed to the model, 16 fps held between samples scores 75% / 88%, and 8 fps scores 59% / 83%. Keeping the live joints could at most replace about half the pose calls.
- **Frame choice uses timestamps.** The analyzer picks the decoded frame nearest each slot by presentation time. Training picked by frame index, which drifts when frames are dropped. On two range clips the two disagree by at most one slot.

## Live path and fallback

The camera gets each frame back at once: the live path makes its own small copy (480 × 270) and runs pose on that, so it never holds camera buffers. A swing's positions are ready when the copy of its last slot arrives, 0.8 s after impact, because the detector's window ends there. Pose on the swing's 72 copies (about 0.4 s) runs while that last 0.52 s is still being recorded.

The live run fails, and the saved clip is read as before, when:
- the swing starts within 1.6 s of Auto starting, before the oldest copy
- a copy is missing from the window (slots must be every 0.033 s)
- the window hasn't filled 3 s after the swing was declared, e.g. Auto stopped or paused for review
- Vision finds a body in fewer than half the slots

Each failure logs `swing-positions-failed` with `path` `live-copy`.

## Timing

With the live path, positions are ready 0.78–0.81 s after impact on an iPhone 17 (every live run on Oct 30, 2026: test13, test14 and test15 through the footage camera). The rest of this section times the saved-clip path, which is the fallback.

On an M-series Mac, a 2.9 s driver swing at 240 fps reads 693 frames, makes 87 pose calls and takes about 1.1 s; the model takes about 1 ms.

On an iPhone 17 (Oct 30, 2026, test15 through the footage camera, Photos off), positions are ready about 2.8 s after impact:

| Step | Seconds |
| --- | --- |
| Record the 0.8 s after impact (the detector declares the swing 0.28 s after impact) | 0.80 |
| Seal the recording and export the clip | 0.2 |
| Thumbnail and library save | 0.3–0.9 |
| Decode about 576 frames of the saved clip | 0.7–1.3 |
| Pose on 72 of them (about 7 ms each) | 0.5 |
| Position model | 0.003 |

Decoding, not pose, is the largest step. The export sometimes stalls for 5–14 s; that happened with Photos on and off, so the likely cause is the phone's own background video work (for example Photos processing earlier test clips) competing for the video encoder. The cause is unconfirmed.

Each run writes a `swing-positions` event to the capture diagnostics log, with `path` `live-copy` or `library`: decode and pose seconds, pose calls, body slots, the chosen slots and the clip times. A `swing-declared` event records how long after impact the detector declared the swing, so later steps can be measured from impact.

### Speed experiments

Debug launch options:

| Option | Effect |
| --- | --- |
| `-positions-live off\|copy\|pose` | `copy` is the default. `off` uses only the saved-clip path. `pose` runs pose on every copy straight away instead of after a swing is declared. |
| `-positions-live-width <px>` | Width of the live copies. Default 480; 0 keeps full size. |
| `-positions-live-after <s>` | Ends the live window this many seconds after impact instead of 0.8. |

The runs below also tried options removed afterwards because they gained little: task priority (`utility`, `userInitiated`, `high`), loading the models when Auto starts, starting the saved-clip run at export or on the rolling recording, and running the saved-clip path beside the live one to compare.

Results on the iPhone 17 (Oct 30, 2026; three swings per run; phone thermal state "serious" for most runs):

| Configuration | Ready after impact |
| --- | --- |
| Current (saved clip, `utility`) | 2.8–3.5 s |
| `userInitiated` | 2.7–2.8 s |
| `early clip` + `userInitiated` + prewarm | 2.6–2.8 s |
| `early source` + `userInitiated` + prewarm | 2.5–2.7 s |
| `live pose` or `live copy`, widths 480, 960 and full size | 0.78–0.81 s |
| `live`, window ends 0.7 s after impact | 0.68–0.71 s |

Live positions are ready as soon as the window's last frame arrives. Compared on the same swings with `-positions-live-compare`, live and saved-clip positions differ by 3 frames on average (240 fps). Both pick from a grid of one frame every 8, and the two grids start at slightly different frames, so a gap under 8 frames is grid offset, not error. The saved-clip path also moves by one slot (8 frames) between runs of the same footage. Width 480, 960 and full size gave the same positions. Ending the window 0.6 or 0.5 s after impact moved P10 early by 7–22 frames; 0.7 s moved it by 15 frames once in six swings.

Guard metrics stayed level with live pose on: footage frames dropped late 14–32 per 17,100 (control runs 12–29), recorded-frame gaps 5–10 per run, and detector inference 34–37 ms (control 37 ms). `copy` mode ran pose about 72 times per swing; `pose` mode ran it 30 times a second for the whole session. One `copy` run showed 6 out-of-buffer drops; the others showed none. These runs use the footage camera, which decodes video on the phone; a real camera session at the range still has to confirm cadence and heat.

Heat and load, longer footage (Oct 30, 2026; width 480; runs back to back from a cool phone, plugged in; Instruments Power Profiler attached to the app):

| Run | Footage | Ready after impact | App CPU energy impact | Thermal state |
| --- | --- | --- | --- | --- |
| off (saved clip) | test14, 3.4 min, 3 swings | 2.4–3.3 s | 4.2 | nominal |
| `live copy` | test14 | 0.78–0.80 s | 4.0 | nominal |
| `live pose` | test14 | 0.78–0.80 s | 8.4 | nominal, fair after 50 s |
| `live copy` | test13, 5.8 min, 6 swings | 0.78–0.81 s | 4.1 | started serious (after `pose`), fair after 4.3 min |
| off (saved clip) | test13 | 2.5–3.2 s | 4.3 | fair |

`copy` costs the same as running without live pose; `pose` doubles the app's CPU energy impact and was the only run that raised the thermal state. All five runs had 0 out-of-buffer drops, detector inference 34–37 ms, and 48–131 late footage frames. Late frames fall in the first second and about 1.5 s after each swing, likely when the footage decoder competes with clip export. Instruments reports no GPU impact for the app and doesn't show Neural Engine use.

## Simulator

Vision body pose fails in the iOS 26.3 Simulator ("Unable to setup request in VNDetectHumanBodyPoseRequest"), so Simulator runs always end in "Swing positions could not be found". Check results with the Mac harness or a phone.

## Checking a model change

The harness compiles the app's own analyzer files on macOS:

```bash
W=detector_workbench/validation/swing_positions
xcrun coremlcompiler compile SwingCoach/MLModels/SwingPositionTCN.mlpackage /tmp/sp/
swiftc -O -parse-as-library -o /tmp/sp/harness \
  SwingCoach/Models/SwingPositions/SwingPositions.swift \
  SwingCoach/Models/SwingPositions/SwingPositionAnalyzer.swift $W/harness.swift
/tmp/sp/harness /tmp/sp/SwingPositionTCN.mlmodelc 8 /tmp/sp clip1.mp4 clip2.mp4
```

`parity.py` reruns the training pipeline on the same clips and prints the slot differences:

```bash
swiftc -O -parse-as-library -o /tmp/sp/vpe ../detectSwings/event_model/vision_pose_extract.swift
../detectSwings/.venv/bin/python $W/parity.py ../detectSwings /tmp/sp/vpe /tmp/sp 8 clip1.mp4 clip2.mp4
```

Expect differences of 0 or ±1 slot from frame choice. Larger differences mean the features or the model export changed.

To export a new run:

```bash
cd ../detectSwings
POSE_BACKEND=vision .venv/bin/python event_model/export_coreml.py --run <run> --out ../SwingCoach/SwingCoach/MLModels/SwingPositionTCN.mlpackage
```

Then update `SwingPositions.currentModel` so stored results recompute, along with the P1/P10 offsets and the accuracy table here. A run with club channels (`tcn_vision_club_v1`) also needs the club segmentation model running on the same frames; the feature builder currently writes zeros there.

## Possible improvements

- **P5–P7 accuracy.** These can land 1–5 frames (240 fps) away from the true position. One idea: after the model picks a 30 fps slot, search the 240 fps frames around it (for example ±4 frames) for the exact moment, using a signal such as club-shaft angle or hand position. Not designed yet. Measure first: check P5–P7 against hand labels on range clips before building it.
- **Speed.** Positions now wait only for the 0.8 s recorded after impact. Ending the window sooner moves P10 early; see [Speed experiments](#speed-experiments).
- **Live path at the range.** The footage-camera runs above hold up on a desk. A real-camera session still has to confirm heat and pool drops; one copy-mode run dropped 6 frames for lack of buffers at a swing.

