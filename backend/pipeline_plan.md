# SwingCoach Implementation Plan

> **Created:** January 2026
> **Status:** Planning Phase
> **Reference:** See `pipeline_theory.md` for SOTA model details

---

## 1. Current State Summary

### What's Built (Production-Ready)

| Component | Implementation | Files |
|-----------|----------------|-------|
| Frame Extraction | ffmpeg-based sampling | `frame_extractor.py` |
| 2D Pose Detection | MediaPipe 33 keypoints | `pose_detector.py` |
| Swing Events | 4 phases (address→top→impact→finish) | `event_detector.py` |
| Equipment Tracking | SAM3 text-prompted segmentation | `equipment_tracker.py` |
| Club Plane | PCA-based 2D shaft angle | `club_analyzer.py` |
| 2D Metrics | Head sway, hip slide, spine angle, X-factor, tempo | `metrics.py` |
| Coaching | GPT-4o-mini + rule-based fallback | `coach.py` |
| Visualization | Skeleton, reference lines, club overlay, swing path | `visualizer.py` |
| Video Export | ffmpeg with audio preservation | `video_exporter.py` |
| API | FastAPI endpoints + R2 storage | `main.py`, `r2_client.py` |

**Total:** ~5,900 lines of Python across 14 files

### Architecture Diagram (Current)
```
┌─────────────────────────────────────────────────────────────────┐
│                        CURRENT PIPELINE                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Video → Frame Extraction → MediaPipe 2D Pose                   │
│                                  │                              │
│                                  ▼                              │
│                          Event Detection                        │
│                          (4 swing phases)                       │
│                                  │                              │
│         ┌────────────────────────┼────────────────────────┐     │
│         ▼                        ▼                        ▼     │
│   SAM3 Equipment            2D Metrics              Coaching    │
│   (optional)             (head, hip, spine)      (GPT-4o-mini)  │
│         │                        │                        │     │
│         └────────────────────────┼────────────────────────┘     │
│                                  ▼                              │
│                     Visualization + Video Export                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Target State (SOTA Pipeline)

### Pipeline Phases from Theory

| Phase | Purpose | SOTA Models |
|-------|---------|-------------|
| I | Detection & Segmentation | RF-DETR → SAM 3 |
| II | 3D Lifting | SAM 3D Body + PromptHMR-Vid |
| III | Rigid Body Tracking | PnP + Inverse Kinematics |
| IV | Geometric Checklist | 3D Vector Mathematics |
| V | Synthesis & Coaching | Gemini 3 Pro / GPT-5.2 |

### Architecture Diagram (Target)
```
┌─────────────────────────────────────────────────────────────────┐
│                        TARGET PIPELINE                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Video → Frame Extraction → RF-DETR Detection                   │
│                                  │                              │
│                                  ▼                              │
│                    SAM 3 Segmentation (golfer + club)           │
│                                  │                              │
│                                  ▼                              │
│              ┌───────────────────┴───────────────────┐          │
│              ▼                                       ▼          │
│     SAM 3D Body (MHR)                    PromptHMR-Vid          │
│     (single-frame 3D)                    (temporal smooth)      │
│              │                                       │          │
│              └───────────────────┬───────────────────┘          │
│                                  ▼                              │
│                     3D Joint Coordinates (x,y,z)                │
│                                  │                              │
│         ┌────────────────────────┼────────────────────────┐     │
│         ▼                        ▼                        ▼     │
│   Rigid Body Tracking       3D Metrics            Event Detect  │
│   (PnP + IK for club)    (true angles/velocities) (improved)    │
│         │                        │                        │     │
│         └────────────────────────┼────────────────────────┘     │
│                                  ▼                              │
│                    Geometric Checklist (3D planes)              │
│                                  │                              │
│                                  ▼                              │
│               Frontier LLM (video + metrics → coaching)         │
│                                  │                              │
│                                  ▼                              │
│                     Visualization + Video Export                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Gap Analysis

### Critical Gaps (Blocking)

| Gap | Impact | Dependency |
|-----|--------|------------|
| **No 3D body reconstruction** | Can't calculate true depth, velocities, 3D angles | Blocks Phase III, IV |
| **No temporal consistency** | Frame-to-frame jitter in tracking | Blocks accurate velocity calc |
| **No RF-DETR for detection** | Less accurate club detection, can't fine-tune | Limits Phase I accuracy |

### High-Priority Gaps

| Gap | Impact | Current Workaround |
|-----|--------|-------------------|
| No clubhead velocity | Can't report club speed | Not calculated |
| No attack angle | Missing key metric | Not calculated |
| No 3D swing plane | 2D approximation only | PCA on shaft mask |
| Limited keypoints | 33 vs potential 208 | MediaPipe sufficient for now |

### Lower-Priority Gaps

| Gap | Impact | Current Workaround |
|-----|--------|-------------------|
| Not using GPT-5.2/Gemini 3 | Less sophisticated reasoning | GPT-4o-mini works |
| No RAG corpus | Generic advice | Rule-based drills |
| Only 4 swing events | Missing P1-P10 phases | Sufficient for core analysis |

---

## 4. Implementation Phases

### Phase A: Enhanced 2D Pipeline (Incremental Improvements)
**Goal:** Maximize value from current 2D approach before major 3D work

#### A.1 — Clubhead Velocity Estimation (2D Approximation)
- Track SAM3 clubhead centroid across frames
- Calculate pixel velocity: `Δpixels / Δtime`
- Apply scale factor from shoulder width calibration
- **Output:** Approximate club speed (mph) with confidence interval
- **Files:** New `velocity_estimator.py`, update `metrics.py`

#### A.2 — Improved Event Detection
- Expand from 4 to 10 swing phases (P1-P10)
- Add: takeaway, early backswing, late backswing, transition, early downswing, late downswing
- Use velocity curves + pose positions for phase boundaries
- **Files:** Update `event_detector.py`

#### A.3 — Sapiens Integration (Dense 2D Keypoints)
- Replace MediaPipe (33 keypoints) with Meta Sapiens (208 keypoints)
- Provides denser body coverage for better metric accuracy
- More robust to occlusion
- **Files:** New `sapiens_detector.py`, update `pose_detector.py` as fallback

#### A.4 — RF-DETR for Club Detection
- Fine-tune RF-DETR on golf club dataset
- Replace SAM3 text prompts with trained detector
- Better accuracy for fast-moving clubhead
- **Files:** New `club_detector.py`, training scripts in `training/`

---

### Phase B: 3D Reconstruction (Core Upgrade)
**Goal:** Add depth estimation for true 3D analysis

#### B.1 — SAM 3D Body Integration
- Integrate Meta SAM 3D Body model
- Output: MHR (Momentum Human Rig) mesh per frame
- Provides (x, y, z) for all body joints
- **Files:** New `body_3d.py`
- **Dependencies:** PyTorch, model weights (~2GB)

#### B.2 — PromptHMR-Vid for Temporal Consistency
- Add PromptHMR-Vid for smooth multi-frame reconstruction
- Eliminates per-frame jitter
- Critical for accurate velocity calculations
- **Files:** New `temporal_smoother.py`
- **Dependencies:** Requires SAM 3D Body output

#### B.3 — 3D Metrics Upgrade
- Convert all 2D metrics to 3D equivalents
- True spine angle (not projection)
- True hip/shoulder rotation (degrees, not linear distance)
- 3D X-factor calculation
- **Files:** New `metrics_3d.py` or major update to `metrics.py`

---

### Phase C: Advanced Club Tracking
**Goal:** Professional-grade club metrics

#### C.1 — Rigid Body Model for Club
- Model club as rigid body attached to wrist joints
- Use 3D wrist coordinates from Phase B
- Apply inverse kinematics for shaft position
- **Files:** New `club_kinematics.py`

#### C.2 — True Clubhead Speed
- Calculate from 3D trajectory: `Δ(x,y,z) / Δtime`
- Scale using known club length
- Report in mph with high accuracy
- **Files:** Update `velocity_estimator.py`

#### C.3 — Attack Angle & Club Path
- 3D vector of clubhead through impact zone
- Attack angle: vertical component of path vector
- Club path: horizontal component (in-to-out, out-to-in)
- **Files:** New `impact_analyzer.py`

#### C.4 — 3D Swing Plane
- Define plane from ball position through shoulder line
- Calculate club's deviation from plane throughout swing
- Report as "on plane", "over the top", "under plane"
- **Files:** Update `club_analyzer.py`

---

### Phase D: Coaching Upgrade
**Goal:** More sophisticated analysis and feedback

#### D.1 — Frontier LLM Integration
- Upgrade to GPT-5.2 or Gemini 3 Pro
- Enable native video input (if supported)
- More nuanced swing analysis
- **Files:** Update `coach.py`

#### D.2 — Golf Instruction RAG
- Build corpus of golf instruction content
- Implement retrieval-augmented generation
- Provide drill recommendations backed by sources
- **Files:** New `rag_coach.py`, `corpus/` directory

#### D.3 — Comparative Analysis
- Compare user swing to professional templates
- Identify specific deviations
- "Your shoulder turn is 15° less than pro average"
- **Files:** New `comparator.py`, `templates/` directory

---

### Phase E: Edge & Performance
**Goal:** On-device capability and speed optimization

#### E.1 — Hybrid Processing Architecture
- On-device: Frame extraction + lightweight detection
- Cloud: 3D reconstruction + heavy inference
- Reduce latency and bandwidth
- **Files:** Update `main.py`, new mobile SDK

#### E.2 — YOLO26 Fallback
- Implement YOLO26 for edge inference
- Fallback when cloud unavailable
- Reduced accuracy but instant feedback
- **Files:** New `edge_detector.py`

#### E.3 — Frame Sampling Optimization
- Intelligent frame selection (not uniform sampling)
- Focus on key swing phases
- Reduce processing time 50%+
- **Files:** Update `frame_extractor.py`

---

## 5. Implementation Priority Matrix

```
                    HIGH IMPACT
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         │   B.1 3D Body │  C.2 Club     │
         │   B.2 Temporal│     Speed     │
         │               │  C.3 Attack   │
         │               │     Angle     │
HIGH     │───────────────┼───────────────│ LOW
EFFORT   │               │               │ EFFORT
         │   D.2 RAG     │  A.1 2D       │
         │   E.1 Hybrid  │     Velocity  │
         │               │  A.2 Events   │
         │               │               │
         └───────────────┼───────────────┘
                         │
                    LOW IMPACT
```

### Recommended Order

1. **A.1** — 2D Clubhead Velocity (quick win, high user value)
2. **A.2** — P1-P10 Events (better UX, moderate effort)
3. **B.1** — SAM 3D Body (unlocks everything else)
4. **B.2** — Temporal Consistency (required for B.1 to be useful)
5. **C.2** — True Club Speed (killer feature)
6. **C.3** — Attack Angle & Path (differentiator)
7. **B.3** — 3D Metrics Upgrade (leverage 3D data)
8. **A.4** — RF-DETR Fine-tuning (accuracy improvement)
9. **D.1** — Frontier LLM (better coaching)
10. **C.4** — 3D Swing Plane (advanced analysis)

---

## 6. Technical Considerations

### Model Weights & Storage
| Model | Size | Storage |
|-------|------|---------|
| MediaPipe Heavy | 26 MB | Local |
| SAM 3 | ~2.4 GB | Cloud/cached |
| SAM 3D Body | ~2 GB | Cloud/cached |
| PromptHMR-Vid | ~1 GB | Cloud/cached |
| RF-DETR (fine-tuned) | ~500 MB | Cloud/cached |
| Sapiens | ~1 GB | Cloud/cached |

**Total new storage:** ~7 GB model weights

### Compute Requirements
| Phase | GPU Required | Inference Time (per frame) |
|-------|--------------|---------------------------|
| Current (MediaPipe) | No | ~30ms |
| SAM 3D Body | Yes (recommended) | ~100ms |
| PromptHMR-Vid | Yes | ~150ms (batch) |
| RF-DETR | Yes (recommended) | ~50ms |

**Recommendation:** GPU instance for cloud processing (NVIDIA T4 minimum)

### API Changes
- New endpoint: `POST /analyze-3d` (full 3D pipeline)
- Extend `AnalysisResult` with 3D metrics
- Add `club_speed_mph`, `attack_angle_degrees`, `club_path_degrees`
- Deprecate 2D-only metrics (or keep as fallback)

---

## 7. Success Metrics

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| Club speed accuracy | N/A | ±3 mph vs Trackman | A/B test with launch monitor |
| Attack angle accuracy | N/A | ±1° vs Trackman | A/B test with launch monitor |
| 3D reconstruction quality | N/A | <5mm joint error | Benchmark dataset |
| Processing time | ~5s | <10s (with 3D) | End-to-end latency |
| User satisfaction | Baseline | +20% | App store ratings |

---

## 8. Open Questions

1. **Training data for RF-DETR:** Where to source golf club images for fine-tuning?
2. **SAM 3D Body licensing:** Confirm commercial use terms
3. **PromptHMR-Vid availability:** Model weights publicly released?
4. **GPU infrastructure:** Self-hosted vs managed (Modal, Replicate, etc.)?
5. **Benchmark baseline:** Can we get Trackman data for validation?

---

## 9. Next Steps

- [ ] Implement A.1 (2D clubhead velocity estimation)
- [ ] Research SAM 3D Body integration requirements
- [ ] Set up GPU-enabled cloud environment
- [ ] Source golf club training images for RF-DETR
- [ ] Create benchmark test suite with known metrics

---

*This plan will evolve as we learn more during implementation. Update this document as decisions are made.*
