# Detector Validation Tools

These scripts validate the app's model-backed live detector against local fixture videos and exported SwingCoach clips.

## V2 Swing Detector

`SwingDetectorV2` is the clean-restart detector path. It is validated through a separate fail-fast harness so it can be iterated beside the legacy detector before any app wiring changes.

The canonical milestone order is documented in [Swing Detector V2 Implementation Plan](../../docs/SWING_DETECTOR_V2_IMPLEMENTATION_PLAN.md). Advance one fixture at a time and stop on the first mismatch.

Compile and run the v2 evaluator:

```bash
python3 detector_workbench/validation/evaluate_swing_detector_v2.py --build --only test2
```

Run with visual contact sheets:

```bash
python3 detector_workbench/validation/evaluate_swing_detector_v2.py --only test2 --contact-sheets
```

Current v2 behavior:

- source timestamps are passed through to Swift; the detector converts them to real swing-time using each fixture's `source_time_scale`
- model-load failures are fatal, not reported as zero detections
- contact-sheet rendering failures are fatal when `--contact-sheets` is requested
- every run writes JSON results, candidate traces, and processed-frame sampling traces under `.detectorTestV3/perf_v2/`
- M1 currently targets the locked-address-patch flow: address lock, patch watcher, graded club evidence, state transitions, and evidence scoring

The initial green fixture is `test2`. Wider fixture coverage is intentionally not assumed until the next milestones add more cases and tune against failures.

## Legacy Live Model Detector

Compile the Swift evaluator from the repository root:

```bash
mkdir -p .videos/bin
xcrun swiftc -parse-as-library \
  -framework AVFoundation -framework CoreML -framework Vision \
  -framework CoreGraphics -framework CoreVideo -framework ImageIO \
  SwingCoach/Models/OnDeviceSwingDetector.swift \
  SwingCoach/Models/LiveSwingDetector.swift \
  SwingCoach/Models/GolfObjectDetector.swift \
  SwingCoach/Models/ModelBackedSwingDetector.swift \
  detector_workbench/validation/evaluate_live_model_detector.swift \
  -o .videos/bin/evaluate_live_model_detector
```

Run current fixture validation:

```bash
python3 detector_workbench/validation/evaluate_detector_test_v3_performance.py
```

Run exported-clip validation:

```bash
python3 detector_workbench/validation/evaluate_detector_video_data.py --force
```

Validation labels live in `detector_workbench/validation/labels/`. Heavy fixture videos, compiled binaries, generated proxies, and reports remain ignored.
