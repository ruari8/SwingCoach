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

## 10. Innovation Ideas - 3D Animated Swing Replay

> **Status:** Active exploration (January 2026)
> **Goal:** Create NBA 2K-style 3D animated swing replays viewable from any angle

### Vision

Instead of traditional 2D video overlays, create **full 3D reconstructions** of the golf swing that users can rotate, zoom, and view from any angle - like instant replays in sports video games. Think markerless motion capture for consumer golf coaching.

### What Makes This Revolutionary

**Current competitors (Sportsbox, DeepSwing, etc.):**
- Static 3D pose visualization (single frame)
- Clunky 3D that doesn't animate smoothly
- 2D video with overlays (everyone does this)

**Our approach:**
- Animated 3D model of entire swing (2-3 seconds of motion)
- Smooth temporal consistency (no jitter)
- Includes both golfer AND club in full 3D scene
- Exportable/shareable (GLTF/GLB format)
- Viewable in web browsers (three.js), mobile 3D viewers, or VR

### Technical Foundation (Already Built)

✅ **SAM 3D Body Integration** - body_3d.py produces full 3D mesh per frame
- MHR70 skeleton with 70 keypoints (x,y,z coordinates)
- ~10,000 mesh vertices per frame for body surface
- Batch processing: `detect_batch()` handles sequential frames

✅ **Static 3D Export** - visualization_3d.py creates GLB files
- Semi-transparent body mesh
- Skeletal overlay with joints and bones
- Currently exports single-frame only

✅ **2D Club Detection** - equipment_tracker.py with SAM 3
- Detects club, shaft, clubhead in 2D
- Provides masks and centroids

✅ **Frame Extraction** - frame_extractor.py processes video
- Already handles 240fps high-speed video

### What Needs to Be Built

#### Stage 1: Temporal Smoothing (1-2 weeks)

**Problem:** Per-frame 3D reconstruction causes jitter between frames

**Solution Options:**
1. **Kalman Filter** (Recommended for MVP)
   - Apply to each keypoint's (x,y,z) trajectory across frames
   - Predicts next position based on velocity + measurement
   - Lightweight, real-time capable
   - Implementation: `temporal_smoother.py` using `filterpy` library

2. **Moving Average Filter** (Simpler fallback)
   - Window of 3-5 frames, smooth each keypoint
   - Fast but less sophisticated
   - Good for prototyping

3. **PromptHMR-Vid** (Future upgrade)
   - Research model with temporal transformers
   - May not have public weights yet
   - Keep as Phase 2 enhancement

**Deliverable:** Smooth 3D pose trajectories across all swing frames

**Files to create:**
- `backend/analysis/temporal_smoother.py` (~200 lines)
- Test script: `backend/test_temporal_smoothing.py`

**Dependencies:**
```
filterpy>=1.4.5  # Kalman filter library
```

---

#### Stage 2: Animation Export Pipeline (2-3 weeks)

**Problem:** Current visualization_3d.py exports static GLB (single frame). Need animated GLTF with keyframe tracks.

**Solution:** Build GLTF animation writer

**GLTF Animation Concepts:**
- **Nodes:** Each MHR joint becomes a GLTF node with transform
- **Keyframes:** Store position/rotation for each joint at each timestamp
- **Animation tracks:** Time-series data for each joint's motion
- **Skinning:** Mesh deforms with skeleton (optional for MVP)

**Implementation Approach:**

**Option A: pygltflib** (Recommended)
```python
# Pseudo-code structure
from pygltflib import GLTF2, Node, Animation, AnimationChannel

# For each frame timestamp:
#   For each MHR keypoint:
#     Create keyframe with (x,y,z) position
#     Create keyframe with rotation (quaternion)

# Bundle all keyframes into animation tracks
# Export single animated.gltf file
```

**Option B: Manual GLTF JSON** (More control)
- Write GLTF JSON structure directly
- Reference spec: https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html
- More work but full control

**Deliverable:** Single animated `.gltf` or `.glb` file that plays back swing

**Files to create:**
- `backend/analysis/animation_exporter.py` (~400-500 lines)
  - `AnimationExporter` class
  - `export_swing_animation(poses: List[Pose3DResult], output_path: str)`
  - Handles MHR → GLTF node mapping
  - Writes keyframe tracks

**Dependencies:**
```
pygltflib>=1.16.0  # GLTF file format library
```

**Test Output:**
```bash
python test_animation_export.py
# Generates: swing_3d_animated.glb
# View in: https://gltf-viewer.donmccurdy.com/
```

---

#### Stage 3: 3D Club Reconstruction (2-3 weeks)

**Problem:** 3D scene only has body. Need to add golf club in 3D space.

**Solution:** Rigid body fitting using Perspective-n-Point (PnP)

**Technical Approach:**

1. **Get 3D wrist positions** (already available from SAM 3D Body)
   - Left wrist: `pose.keypoints_3d["left_wrist"]`
   - Right wrist: `pose.keypoints_3d["right_wrist"]`

2. **Get 2D club mask** (already available from SAM 3)
   - Run `equipment_tracker.detect_shaft()` → shaft mask
   - Extract centerline of shaft (skeletonize or PCA)
   - Sample 5-10 points along shaft centerline in 2D

3. **Model club geometry**
   - Club = cylinder (shaft) + small sphere (clubhead)
   - Driver dimensions: Shaft length ~45 inches, diameter ~0.5 inches
   - Grip anchored at wrist position(s)

4. **Solve for 3D club pose using OpenCV solvePnP**
   ```python
   import cv2

   # Define 3D club model points (cylinder along axis)
   club_3d_points = np.array([
       [0, 0, 0],        # Grip (at wrist)
       [0, 0, 0.25],     # Shaft point 1
       [0, 0, 0.50],     # Shaft point 2
       [0, 0, 0.75],     # Shaft point 3
       [0, 0, 1.14],     # Clubhead (45 inches = 1.14m)
   ])

   # 2D observations from club mask centerline
   club_2d_points = extract_shaft_centerline(club_mask)

   # Solve PnP with wrist anchor constraint
   success, rvec, tvec = cv2.solvePnP(
       club_3d_points,
       club_2d_points,
       camera_matrix,
       dist_coeffs
   )
   ```

5. **Generate club geometry for visualization**
   ```python
   # Create cylinder mesh for shaft
   shaft_mesh = trimesh.creation.cylinder(
       radius=0.0127,  # 0.5 inches
       height=1.14,    # 45 inches
       transform=compute_transform(rvec, tvec)
   )

   # Create sphere for clubhead
   clubhead_mesh = trimesh.creation.icosphere(
       radius=0.025,   # ~1 inch radius
       subdivisions=2
   )
   ```

6. **Add to scene before export**
   - Combine body mesh + skeleton + club geometry
   - Export as single animated GLTF

**Challenges & Solutions:**

**Challenge:** 2D club mask is noisy/incomplete during fast motion
**Solution:**
- Temporal smoothing on club pose (same Kalman filter)
- Anchor to wrist position (constrains search space)
- Use previous frame's pose as prior

**Challenge:** Need camera intrinsics (focal length, principal point)
**Solution:**
- SAM 3D Body already estimates these (stored in `Pose3DResult`)
- Use estimated camera parameters from body detector

**Deliverable:** Combined 3D scene with animated body + club

**Files to create:**
- `backend/analysis/club_3d.py` (~300-400 lines)
  - `Club3DReconstructor` class
  - `fit_club_pose(wrist_3d, club_mask_2d, camera_params) → Club3DPose`
  - `generate_club_geometry(pose) → trimesh.Trimesh`
  - Integration with temporal smoother

**Dependencies:**
```
opencv-python>=4.8.0  # For solvePnP
scikit-image>=0.22.0  # For skeletonize (shaft centerline)
```

---

#### Stage 4: Integration & Polish (1 week)

**Deliverable:** End-to-end pipeline that generates 3D animated replays

**Pipeline Flow:**
```
Video (240fps)
  → frame_extractor.py (sample frames)
  → body_3d.detect_batch() (3D poses per frame)
  → temporal_smoother.py (smooth trajectories)
  → equipment_tracker.py (2D club masks per frame)
  → club_3d.py (fit 3D club poses)
  → animation_exporter.py (export animated GLTF)
  → swing_replay_3d.glb (final output)
```

**New API Endpoint:**
```python
@app.post("/analyze-3d-animated")
async def analyze_3d_animated(video_file: UploadFile):
    """Generate 3D animated replay of golf swing."""
    # Extract frames
    frames = frame_extractor.extract(video_file)

    # 3D body detection (batch)
    body_poses = body_3d_detector.detect_batch(frames)

    # Temporal smoothing
    smoothed_poses = temporal_smoother.smooth(body_poses)

    # Club detection & 3D fitting
    club_masks = equipment_tracker.detect_shaft_batch(frames)
    club_poses = club_3d_reconstructor.fit_batch(
        smoothed_poses,
        club_masks
    )

    # Export animated GLTF
    output_path = animation_exporter.export(
        body_poses=smoothed_poses,
        club_poses=club_poses,
        timestamps=frame_timestamps
    )

    return {
        "glb_url": upload_to_r2(output_path),
        "duration": len(frames) / fps,
        "frame_count": len(frames)
    }
```

**Frontend Integration:**
- Use **three.js** for web-based 3D viewer
- Enable orbit controls (rotate, zoom, pan)
- Playback controls (play/pause, scrub timeline)
- Export/share button

---

### Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Temporal smoothness** | <2mm jitter between frames | MPJPE on consecutive frames |
| **Club tracking accuracy** | 95% frames detected | Visual inspection + metrics |
| **Processing time** | <30s for 2-sec swing (240fps) | End-to-end latency |
| **File size** | <10MB for animated GLB | Compressed GLTF |
| **User engagement** | 3x longer session time | Analytics vs 2D-only |
| **Viral coefficient** | 20% share rate | Social media shares |

---

### Phased Rollout Plan

#### Phase 1: Internal Prototype (Weeks 1-3)
- Build temporal smoothing (Kalman filter)
- Create basic animation export (body only, no club)
- Test on 5-10 sample swings
- Validate smoothness and visual quality
- **Deliverable:** Body-only animated GLB

#### Phase 2: Club Integration (Weeks 4-5)
- Implement 3D club reconstruction (solvePnP)
- Add club geometry to scene
- Test club tracking accuracy
- **Deliverable:** Full scene animated GLB (body + club)

#### Phase 3: API & Frontend (Week 6)
- New API endpoint `/analyze-3d-animated`
- Three.js viewer in web app
- Mobile GLB viewer integration
- **Deliverable:** User-facing 3D replay feature

#### Phase 4: Polish & Launch (Week 7)
- Performance optimization (GPU batching)
- UI/UX refinement
- Marketing assets (demo videos)
- Beta user testing
- **Deliverable:** Production launch

---

### Competitive Advantage

**Why competitors can't easily copy this:**

1. **Technical moat:** SAM 3D Body + custom animation pipeline is non-trivial
2. **Temporal smoothing:** Requires domain expertise (Kalman filters, biomechanics)
3. **Club 3D fitting:** PnP with wrist constraints is novel approach
4. **Performance:** Real-time batch processing at scale requires optimization
5. **Time-to-market:** 6-8 week head start while they catch up

**Sportsbox comparison:**
- Their 3D is static/clunky (likely older SMPL models)
- No animated replays
- No club in 3D scene
- We'd be visibly superior in demos

---

### Future Enhancements

Once base system is working:

1. **Multi-angle views** - Show swing from front, side, top simultaneously
2. **Comparison mode** - Overlay user swing with pro template in 3D
3. **VR/AR export** - View swing in VR headset or AR on practice range
4. **Slow-motion scrubbing** - Frame-by-frame 3D analysis
5. **Ghost trails** - Show club path trajectory as 3D ribbon
6. **Ball flight integration** - Add ball trajectory to scene (if trackable)

---

### Technical Risks & Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| **Jitter too severe** | Medium | Multiple smoothing approaches; can fall back to simpler filters |
| **Club tracking fails** | Medium | Temporal priors + wrist anchoring; degrade gracefully |
| **Processing too slow** | Low | GPU acceleration; async processing; precompute for stored swings |
| **GLTF export bugs** | Medium | Test with multiple viewers; follow spec strictly |
| **File sizes too large** | Low | Draco compression; optimize mesh decimation |

---

### Resource Requirements

**Development:**
- 1 senior engineer, 6-8 weeks (backend + 3D pipeline)
- 1 frontend engineer, 2 weeks (three.js integration)

**Compute:**
- GPU instance for 3D reconstruction (NVIDIA T4 or better)
- Batch processing for stored videos
- Real-time for live analysis may require optimization

**Storage:**
- Animated GLB files: ~5-10MB each
- R2/S3 costs: negligible at small scale

---

### Implementation Priority (Option 2: Animation-First)

**This Week:**
1. ✅ Set up temporal smoothing framework (Kalman filter)
2. ✅ Process single test swing through `detect_batch()`
3. ✅ Validate smoothness visually

**Week 2-3:**
4. Build animation exporter with pygltflib
5. Export body-only animated GLB
6. Test in multiple 3D viewers

**Week 4-5:**
7. Implement 3D club reconstruction
8. Integrate club into animated scene
9. End-to-end testing

**Week 6:**
10. API endpoint + frontend viewer
11. Performance optimization

**Week 7:**
12. Polish, beta testing, launch prep

---

*This innovation path prioritizes differentiation and "wow factor" over incremental metric improvements. The 3D animated replay feature creates a competitive moat that justifies premium pricing and drives viral growth.*

---

*This plan will evolve as we learn more during implementation. Update this document as decisions are made.*
