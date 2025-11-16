<!-- ebc20d91-8cb3-4b72-9c7e-9135e22a95b1 a0ada705-6cb9-4f9e-8b3d-7544e813589a -->
# AI Golf Coach: iOS v0→v2 Roadmap (On‑device First, Hybrid Ready)

## Scope & Direction

Build iOS‑only first to nail capture quality and low‑latency vision. Run 2D pose and swing event detection on‑device for privacy and reliability; add a small cloud to lift 2D skeletons to 3D later. Keep the app useful offline.

## Core Tech Choices

- App: Swift/SwiftUI, iOS 17+, target A14+ devices
- Camera: AVFoundation (`AVCaptureSession`, 120/240 fps where available)
- Vision/ML: Apple Vision 2D pose (`VNDetectHumanBodyPose`) or Core ML MoveNet/BlazePose; smoothing with Kalman/Savitzky–Golay
- Rendering: SwiftUI + overlay layer for annotations; optional Metal for heavy overlays
- Optional backend (v1.5+): FastAPI + PyTorch for 3D lifting and advanced coaching; S3-compatible object store; Postgres

## Incremental Releases

### v0 (Foundations — capture, manual tooling)

- Slo‑mo capture or video import; session management
- Manual camera alignment helper (DTL/FO selection, horizon/ball line guides)
- Manual annotations: head box, shaft/plane line, ball/target line
- Save/export annotated clips and key frames

### v1 (On‑device analyst — 2D pose, events, basic coaching)

- Automatic 2D pose per frame; temporal smoothing
- Swing event detection: address, takeaway, top, downswing, impact, finish
- Metrics (DTL & FO subsets):
  - Head sway (lateral/vertical), pelvis sway, spine/shoulder tilt
  - Shaft lean at impact (proxy via hands-clubline), hand path width
  - Early extension proxy (hip-line forward drift), sway/slide at top
- Overlays: swing plane, shoulder/hip lines, head box auto‑tracking, angles
- Rule engine: thresholded metrics → concise cues + linked drills
- Local library: clips, metrics, notes; iCloud optional

### v1.5 (Hybrid lift — minimal backend)

- Upload compressed skeleton time‑series (+ a few stills) to backend
- 3D pose lifting (temporal model) + refined metrics; return results to device
- A/B improve coaching without app updates; keep app fully functional offline

### v2 (3D sandbox — coaching simulator)

- Full 3D kinematic model and constraints; skeleton retargeting to avatar
- “Sandbox” adjustments: experiment with pelvis/torso/arm parameters → show predicted changes in key metrics
- Personalized goals and drill sequencing based on gaps to sandboxed target

## Video→Feedback Algorithm (v1 focus)

1. Capture/import slo‑mo; normalize orientation, crop, and downsample analysis fps (e.g., 60) while retaining full‑res for overlays.
2. 2D pose per frame; confidence‑aware temporal smoothing.
3. Event detection via kinematic signatures (hand/clubbased peaks, velocity zero‑crossings) constrained to golf swing order.
4. Metric computation:

   - DTL: swing plane deviation, head/pelvis sway, early extension proxy
   - FO: spine/shoulder tilt, shaft lean at impact, lateral sway
   - Normalize by body scale; express angles/distances in camera space with calibration helpers

5. Rule mapping: each metric has ranges → issue label → cue → drill(s)
6. Render overlays synced to events; generate a short session report.

Minimal data shape for hybrid upload:

```json
{
  "fps": 60,
  "vantage": "DTL|FO",
  "joints": ["nose","leftShoulder",...],
  "frames": [
    {"t":0.000,"kps":[[x,y,c], ...]},
    ...
  ],
  "events": {"address":123,"top":987,"impact":1320}
}
```

## DTL vs Face‑On Handling

- User selects vantage at capture; show vantage‑specific guides.
- Use separate metric sets and thresholds per vantage; combine in a unified report when both are available.

## Overlays & Annotations (progression)

- v0: user‑placed head box, plane line, ball/target line
- v1: auto head box tracking, auto shoulder/hip/spine lines from pose, suggested plane line with user nudge
- v2: 3D avatar with projected 2D guides

## Performance & Quality

- Throttle analysis to 30–60 fps; run on a background queue; pre‑allocate buffers
- Gate advanced analysis by device class; provide low‑power mode
- Provide calibration aids (horizon, ball height estimate) to stabilize 2D metrics

## Data, Updates, and Privacy

- Store locally first; optional iCloud sync
- Remote model updates (Core ML) via secure download with version pinning
- Explicit consent for uploads/telemetry; skeleton‑only by default to preserve privacy

## Future Ideas Log (tracked for v2+)

- Full 3D sandbox with forward/inverse kinematics and physics hints
- Club/ball detectors and AoA/face/path estimators from video
- Personalized learning plan; coach personas; LLM summarizer for sessions
- Multi‑camera fusion (DTL+FO simultaneous)
- add tab to trim large videos to grab swings. ie upload 40min range session. put in app, it detects all swings in video, select x amount (5) to keep and send ot video analysis pipeline, then delete the 40min video (cleans up storage).

## Suggested iOS Structure (high‑level)

- `App/` SwiftUI app entry and DI
- `Capture/` camera session, vantage guides, import
- `Analysis/` pose, smoothing, events, metrics
- `Overlays/` drawing layers and UI adapters
- `Coach/` rules, cues, drills content
- `Data/` models, persistence, (optional) sync
- `Backend/` thin client for skeleton upload (v1.5+)

### To-dos

- [ ] Create SwiftUI iOS app targeting iOS 17+, A14+
- [ ] Implement AVFoundation slo-mo capture and import flow
- [ ] Add DTL/FO selection and camera alignment guides
- [ ] Integrate Vision/Core ML 2D pose with temporal smoothing
- [ ] Detect address/top/impact/finish from keypoint sequences
- [ ] Compute head/pelvis sway, tilt, shaft lean, plane deviation
- [ ] Render plane, head box, hip/shoulder lines, angles
- [ ] Map metric ranges to cues and drills content
- [ ] Build local library for clips, metrics, notes, iCloud optional
- [ ] Add calibration tools and device-class performance gates
- [ ] Create minimal FastAPI to accept skeletons and return 3D
- [ ] Train/deploy temporal 2D→3D lifting for golf sequences
- [ ] Implement 3D avatar and parameterized swing sandbox
- [ ] Implement clear consent, privacy, and model update UX