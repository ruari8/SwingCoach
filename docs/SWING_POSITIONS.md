# Swing positions (P1–P10)

After an Auto swing is saved, the app finds the ten swing positions on the phone and stores them on the swing. Swing Info lists them.

Down-the-line clips only. Face-on clips and imported videos are skipped.

## What runs

| Step | Code |
| --- | --- |
| Queue: one clip at a time, utility priority, after the Auto save and when a swing without current positions is opened | `SwingCoach/Models/SwingPositions/SwingPositionProcessor.swift` |
| Read the saved clip, run Vision body pose once per 30 fps real-time slot, run the model | `SwingPositionAnalyzer.swift` |
| Feature rows and ordered decoding; the stored result types | `SwingPositions.swift` |
| Model | `SwingCoach/MLModels/SwingPositionTCN.mlpackage` |

The model is `tcn_vision_v2` from `../detectSwings/event_model`. It's a small temporal network: Apple Vision 19-joint pose in, a score per frame for each position out. The decoder picks one frame per position, in order.

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
- **Re-read the clip rather than reuse the live detector's pose.** The live detector runs pose at its sample rate: 8 fps by default, 16 fps during bursts around a swing. Fed to the model, 16 fps held between samples scores 75% / 88%, and 8 fps scores 59% / 83%. Keeping the live joints could at most replace about half the post-capture pose calls.
- **Frame choice uses timestamps.** The analyzer picks the decoded frame nearest each slot by presentation time. Training picked by frame index, which drifts when frames are dropped. On two range clips the two disagree by at most one slot.

## Timing

On an M-series Mac, a 2.9 s driver swing at 240 fps reads 693 frames, makes 87 pose calls and takes about 1.1 s; the model takes about 1 ms. iPhone timing is not measured yet. Each run writes a `swing-positions` event (decoded frames, pose calls, body slots, seconds) to the capture diagnostics log, so an exported session shows phone timings.

Processing runs while the camera may still be capturing. Check Auto cadence in the diagnostics on the first phone session with this build.

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
