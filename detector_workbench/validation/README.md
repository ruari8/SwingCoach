# Detector Validation Tools

These scripts validate the app's model-backed live detector against local fixture videos and exported SwingCoach clips.

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
