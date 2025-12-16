# SwingCoach — Project Refresher & Implementation Guide

**Last updated:** December 16, 2025  
**Status:** v0 Foundation (~40% complete)

---

## 🎯 Core Premise: Replicate a Golf Coach's Job

A real golf coach does four things:

1. **👁️ OBSERVE** — Watch the swing from DTL (down-the-line) or Face-On
2. **🧮 COMPUTE** — Mentally analyze body positions, club path, ball flight
3. **💬 DIAGNOSE** — Identify the issue based on visual/metric inputs
4. **🎓 PRESCRIBE** — Recommend a specific drill or correction

### The App's Job = Automate This Pipeline

```
📹 Record Swing (DTL/FO)
    ↓
🔍 Extract Data (pose keypoints, club path, ball flight)
    ↓
📊 Calculate Metrics (head sway, hip slide, shaft lean, plane deviation, etc.)
    ↓
🧠 Recommendation Algorithm (metrics → diagnosis → drill)
    ↓
✏️ Annotate & Visualize (draw lines, compare to pro, show issue)
    ↓
📤 Deliver Feedback (video + overlays + drill recommendation)
```

---

## 📋 Feature Checklist (Organized by Coach Job Function)

### 1️⃣ OBSERVE — Capture the Swing

| Feature | Status | Priority | Notes |
|---------|--------|----------|-------|
| ✅ Record standard video (30 fps) | Done | — | CaptureView.swift implemented |
| ✅ Import video from Photos | Done | — | LibraryView.swift implemented |
| ⬜ **Record slo-mo (120/240 fps)** | Not started | **HIGH** | Code pattern in gettingStarted.md Step 5 |
| ⬜ **DTL vs Face-On vantage selector** | Not started | **HIGH** | UI toggle + metadata storage |
| ⬜ Camera alignment guides | Not started | Medium | Horizon line, ball position helper |
| ⬜ Save to persistent library | Not started | **HIGH** | Currently temp files only |
| ⬜ Multi-camera sync (DTL + FO) | Not started | Low (v2) | Requires hardware setup |

**Next Step:** Implement slo-mo capture.

---

### 2️⃣ COMPUTE — Extract & Calculate Metrics

| Feature | Status | Priority | Notes |
|---------|--------|----------|-------|
| ⬜ **Access frames for analysis** | Not started | **HIGH** | Extract frames from video |
| ⬜ **2D pose detection (Vision)** | Not started | **HIGH** | Body pose detection |
| ⬜ Temporal smoothing (Kalman/SG) | Not started | **HIGH** | Reduce jitter in keypoints |
| ⬜ **Swing event detection** | Not started | **HIGH** | Detect address/top/impact/finish |
| ⬜ **DTL metrics** | Not started | **HIGH** | Head sway, pelvis sway, early extension, plane deviation |
| ⬜ **Face-On metrics** | Not started | **HIGH** | Spine/shoulder tilt, shaft lean at impact, lateral sway |
| ⬜ Club path tracking | Not started | Medium | Requires club detection model |
| ⬜ Ball flight analysis | Not started | Low (v2) | Requires ball tracking + physics |

**Key Metrics to Calculate (v1):**

**DTL View:**
- Head sway (lateral + vertical movement)
- Pelvis sway/slide
- Early extension (hip line forward drift)
- Swing plane deviation
- Hand path width

**Face-On View:**
- Spine angle at address/top/impact
- Shoulder tilt
- Shaft lean at impact
- Lateral sway magnitude

**Next Step:** Wire up frame access and run Vision pose on throttled frames.

---

### 3️⃣ DIAGNOSE & PRESCRIBE — Recommendation Algorithm

| Feature | Status | Priority | Approach |
|---------|--------|----------|----------|
| ⬜ **Rule-based recommendations** | Not started | **HIGH** | Map metric ranges → cues + drills |
| ⬜ Drill content database | Not started | **HIGH** | JSON/SQLite with drill metadata + videos |
| ⬜ LLM-enhanced coaching | Not started | Medium (v1.5) | GPT API call for natural language feedback |
| ⬜ Trained drill classifier | Not started | Low (v2) | Supervised model: swing features → drill ID |

#### Recommendation Algorithm Options (Ranked by Feasibility)

**Phase 1 (v1): Rule-Based Mapping** ✅ *Start here*

Example: IF head_sway_dtl > 4_inches THEN recommend "Headcover drill" and "Wall contact drill"

Pros: Deterministic, explainable, no training data needed  
Cons: Rigid, requires manual threshold tuning

**Phase 2 (v1.5): LLM API Enhancement**
- Send structured metrics + rule output to GPT-4
- Get natural language explanation + personalized tips
- Cache common patterns to reduce API costs

Pros: Natural language, adaptive, easy to iterate  
Cons: Requires internet, costs per request, latency

**Phase 3 (v2): Trained Recommendation Model**
- Collect labeled dataset: (swing_metrics, vantage, skill_level) → drill_id
- Train multi-class classifier or ranking model
- Similar to YouTube recommendations: collaborative filtering on (user, drill, improvement_signal)

Pros: Personalized, learns from outcomes  
Cons: Requires large labeled dataset, cold start problem

**Next Step:** Build rule engine (v1) first — create a simple JSON structure mapping metric ranges to drills.

---

### 4️⃣ ANNOTATE & VISUALIZE — Show the Issue

| Feature | Status | Priority | Notes |
|---------|--------|----------|-------|
| ⬜ **Manual annotations** | Not started | **HIGH** | Head box, plane line, ball/target line (v0) |
| ⬜ **Auto pose overlay** | Not started | **HIGH** | Draw skeleton from Vision keypoints |
| ⬜ Swing plane line | Not started | **HIGH** | From shoulder-hand-ball geometry |
| ⬜ Hip/shoulder rotation lines | Not started | Medium | Perpendicular to spine |
| ⬜ Head tracking box | Not started | Medium | Auto-track head position through swing |
| ⬜ Angle measurements | Not started | Medium | Spine angle, shaft lean, etc. |
| ⬜ Pro swing comparison | Not started | Low (v1.5) | Side-by-side or overlay reference swing |
| ⬜ 3D avatar rendering | Not started | Low (v2) | Requires 3D lifting backend |

**Annotation Strategy:**
- v0: Manual placement (user draws guides)
- v1: Auto-generated from pose (skeleton, planes, angles)
- v1.5: Compare to pro database
- v2: 3D avatar projection

**Next Step:** Implement manual annotation tools (SwiftUI Path/Canvas overlays).

---

## 🏗️ Frontend → Backend: Implementation Architecture

### What Needs Done in Frontend BEFORE Backend?

The frontend must be "backend-ready" — capture quality input and package it for processing.

### Phase 1: Frontend Foundation (Do This First)

**Goal:** Capture quality input video + minimal preprocessing

1. **Slo-mo capture** (120 fps minimum)
   - Gives enough frames for smooth pose detection
   - Standard 30/60 fps misses critical swing moments
   
2. **DTL/FO vantage selection**
   - Must know camera angle to apply correct metrics/thresholds
   - Store as metadata with video

3. **Persistent library**
   - Save recordings with metadata (timestamp, vantage, duration)
   - Need a "library" before you can select swings to analyze

4. **Video trimming/preprocessing UI** (CRITICAL)
   - User records 2-minute range session → trim to individual 3-5 second swings
   - Reduces upload size (3 sec @ 120fps ≈ 10-20MB vs 2 min @ 120fps ≈ 400MB+)
   - Can detect/auto-segment swings on-device (motion detection when hands move)

5. **Optional: Manual annotations**
   - Ball position, target line (helps backend calibrate camera space)
   - Not blocking, but useful

**4K vs 1080p:** High FPS matters more than resolution. Most devices can't do 4K @ 120fps. **Stick with 1080p @ 120fps.** Ball tracking is v2 anyway.

**Ball Tracer Approach:** Need 3-4 keyframes:
- Frame 1: Ball at address
- Frame 2: Ball leaves frame (top of arc)
- Frame 3: Ball re-enters frame (descent)
- Frame 4: Ball lands/stops

With those 4 points + timestamps, interpolate the arc. Frontend work: manual annotation v0, auto-detection v2.

### Phase 2: Backend Setup (After Frontend is Solid)

**Goal:** Process video → return analysis

**When to move to backend?**
When you have:
- ✅ Reliable slo-mo capture
- ✅ Trimmed swing clips saved
- ✅ Vantage metadata attached
- ✅ A few test swings to work with

**What backend does:**
1. Receive video upload (trimmed 3-5 sec clip + metadata)
2. Extract frames (server-side, more CPU available)
3. Run pose detection (can use bigger/better models than on-device)
4. Compute metrics (more complex calculations)
5. Generate recommendations (LLM calls, rule engine)
6. Return structured JSON: `{events, keypoints, metrics, cues, drills, annotated_frames}`

### Repository Structure: Monorepo Approach

**Recommendation: Monorepo** (same repo, different folders)

**Why monorepo?**
- Easier to version together (API changes affect both)
- Shared documentation lives in one place
- Simpler deployment/testing

**Structure:**
```
SwingCoach/                    (root)
├── ios/                       (SwiftUI app)
│   ├── SwingCoach/
│   ├── SwingCoach.xcodeproj/
│   └── ...
├── backend/                   (Python FastAPI)
│   ├── api/
│   │   ├── main.py           (FastAPI routes)
│   │   ├── models.py         (Pydantic schemas)
│   │   └── analysis.py       (pose/metrics logic)
│   ├── ml/
│   │   ├── pose_detector.py
│   │   ├── event_detector.py
│   │   └── metrics.py
│   ├── requirements.txt
│   └── Dockerfile
├── shared/                    (Optional: shared types/contracts)
│   └── api_spec.yaml         (OpenAPI spec)
├── docs/
│   ├── ai.plan.md
│   ├── gettingStarted.md
│   └── refresher.md
└── README.md
```

**Why Python for backend?**
- PyTorch, OpenCV, NumPy = best ecosystem for video/ML
- FastAPI = modern, fast, easy to deploy
- Can run heavier pose models (MediaPipe, MMPose, ViTPose)
- Easy to integrate OpenAI API for LLM coaching

### Frontend-to-Backend Data Flow

```
iOS App                           Backend API
--------                          -----------
1. Record swing (120fps)
2. Trim to 3-5 sec clip
3. Compress video (H.264)
4. POST /api/analyze
   {
     video: <binary>,
     vantage: "DTL",
     fps: 120,
     user_id: "..."
   }
                                  5. Receive upload
                                  6. Extract frames (ffmpeg)
                                  7. Run pose on each frame
                                  8. Detect events (address/top/impact)
                                  9. Calculate metrics
                                  10. Map metrics → drills (rules or LLM)
                                  11. Generate annotated frames (optional)
                                  
12. Receive JSON response:        12. Return JSON:
    {                                 {
      swing_id,                         swing_id,
      events,                           events: {...},
      metrics,                          metrics: {...},
      recommendations,                  recommendations: [...],
      annotated_video_url               annotated_video_url
    }                                 }

13. Display results in app
14. Show overlays on video
15. Present drill recommendations
```

### Frontend Readiness Checklist (Before Backend)

- [ ] Slo-mo capture working (120 fps)
- [ ] Video trimming UI (select start/end of swing)
- [ ] Persistent library with metadata
- [ ] Can export clip as H.264 .mp4
- [ ] Have 5-10 test swings saved
- [ ] Manual ball position annotation (optional but useful)

**Once these are done, you're ready to build the backend.**

### Implementation Timeline Strategy

**Weeks 1-2:** Complete frontend foundation
- Slo-mo, vantage selection, trimming, library

**Week 3:** Build minimal backend
- Single endpoint: POST /analyze
- Runs pose detection only
- Returns raw keypoints JSON

**Week 4:** Iterate on metrics
- Add event detection
- Calculate 2-3 basic metrics (head sway, shaft lean)
- Return metrics in response

**Week 5+:** Recommendation engine
- Rule-based first
- Add LLM layer if needed

---

## 🚀 Immediate Next Steps (Prioritized)

### Week 1-2: Complete v0 Foundation

1. **Implement slo-mo capture** (120 fps minimum)
   - Configure camera for high FPS
   - Test on device (simulator won't show high fps)

2. **Add vantage selection UI**
   - Toggle: DTL ↔ Face-On
   - Store vantage in video metadata

3. **Persist recordings to library**
   - Save to Documents directory with metadata
   - Build simple library grid view

4. **Add manual annotation layer**
   - Overlay drawing tools on VideoPlayer
   - Draw head box, plane line, target line

**Acceptance:** User can record slo-mo DTL/FO swings, save them, and manually annotate key reference lines.

---

### Week 3-4: Start v1 Analysis

5. **Wire up frame access** — Extract frames from video for analysis
6. **Integrate Vision pose detection** — Run body pose detection on frames
7. **Implement swing event detection** — Identify address, top, impact, finish
8. **Compute first metrics** — Start with head sway (DTL)

**Acceptance:** App detects body pose in real-time and identifies basic swing events.

---

## 🏗️ Architecture Overview

### Current Stack
- **App:** Swift/SwiftUI, iOS 17+, A14+ devices
- **Camera:** AVFoundation (`AVCaptureSession`, `AVCaptureMovieFileOutput`)
- **Video:** AVKit (`AVPlayer`, `VideoPlayer`)
- **Import:** PhotosUI (`PhotosPicker`)

### Planned Additions (v1)
- **Vision:** `VNDetectHumanBodyPose` for 2D keypoints
- **Analysis:** Kalman filter, event detection, metric computation
- **Overlays:** SwiftUI Canvas / Path for annotations
- **Storage:** Local JSON for swing library + metadata

### Future (v1.5+)
- **Backend:** FastAPI + PyTorch for 3D lifting
- **Sync:** Optional iCloud for cross-device library
- **Models:** Core ML for offline inference updates

---

## 📊 Progress Tracker

| Phase | Completion | Target Date |
|-------|------------|-------------|
| **v0 Foundation** | 40% | Jan 2026 |
| → Capture & Import | ✅ 100% | Done |
| → Slo-mo & Vantage | ⬜ 0% | Dec 2025 |
| → Persistence & Library | ⬜ 0% | Jan 2026 |
| → Manual Annotations | ⬜ 0% | Jan 2026 |
| **v1 On-device Analyst** | 0% | Mar 2026 |
| → Pose Detection | ⬜ 0% | Jan 2026 |
| → Event Detection | ⬜ 0% | Feb 2026 |
| → Metrics & Rules | ⬜ 0% | Feb 2026 |
| → Auto Overlays | ⬜ 0% | Mar 2026 |
| **v1.5 Hybrid Lift** | 0% | TBD |
| **v2 3D Sandbox** | 0% | TBD |

---

## 🧠 Design Decisions to Make

### 1. Recommendation Algorithm (Near-term)
**Decision needed:** Start with rules or jump to LLM?  
**Recommendation:** Rules first (deterministic, testable, offline), add LLM layer in v1.5.

### 2. Ball Flight Analysis
**Decision needed:** Include in v1 scope or defer?  
**Recommendation:** Defer to v2 — requires ball tracking model and physics engine (complex).

### 3. Pro Swing Database
**Decision needed:** Build reference library now or later?  
**Recommendation:** Defer to v1.5 — focus on user's own swing first. Can add pro comparison as a "premium" feature.

### 4. Storage Strategy
**Decision needed:** Local-first or cloud-dependent?  
**Recommendation:** Local-first (privacy + offline), optional iCloud sync in v1.5.

### 5. Drill Content
**Decision needed:** Text-only or video drills?  
**Recommendation:** Start with text + static images (v1), add video library in v1.5.

---

## 📁 Files to Reference

| File | Purpose |
|------|---------|
| `ai.plan.md` | Full v0→v2 roadmap with technical specs |
| `gettingStarted.md` | Step-by-step implementation guide with code samples |
| `SwingCoach/CaptureView.swift` | Camera session and recording logic |
| `SwingCoach/LibraryView.swift` | Video import and playback |
| `SwingCoach/AppRootView.swift` | Tab navigation structure |

---

## 🎯 Success Criteria (v1 MVP)

The app is "minimally viable" when:

1. ✅ User can record a slo-mo swing (DTL or FO)
2. ✅ App detects body pose automatically
3. ✅ App identifies swing events (address → top → impact → finish)
4. ✅ App calculates 3-5 key metrics (head sway, shaft lean, plane deviation)
5. ✅ App recommends a drill based on metrics
6. ✅ User sees annotated video with overlays showing the issue
7. ✅ User can save and review past swings in a library

**Target:** Achieve this by March 2026 (3 months of focused work).

---

## 💡 Key Insights from Planning

### What Makes This Hard?
1. **Computer vision accuracy** — 2D pose is noisy; golf swings are fast
2. **Domain knowledge** — Need golf instruction expertise to map metrics → drills
3. **UX complexity** — Balancing auto-analysis with manual control
4. **Device constraints** — On-device ML is limited; need smart throttling

### What Makes This Achievable?
1. **Apple Vision is production-ready** — 2D pose works well for sports
2. **Rule-based coaching is proven** — Many golf apps use thresholds successfully
3. **SwiftUI + AVFoundation are mature** — Camera/video stack is stable
4. **You have a clear roadmap** — Incremental v0→v1→v2 path defined

### Critical Path
1. Get frames → 2. Detect pose → 3. Detect events → 4. Compute metrics → 5. Map to drills

Everything else (overlays, 3D, LLM) enhances this core loop but isn't blocking.

---

## 📞 Questions for Alignment

Before diving deeper, confirm:

1. **Is the rules-first approach for recommendations acceptable?** (vs LLM or trained model)
2. **Should ball flight analysis be in scope for v1?** (increases complexity significantly)
3. **Is the 3-month timeline (v1 by March 2026) realistic for your availability?**
4. **Do you have access to golf instruction content?** (For building drill database)
5. **Any device/testing constraints?** (Need real device for slo-mo and pose detection)

---

**Ready to build.** Start with slo-mo capture → frame access → pose detection. The rest follows from there.
