# Golf Swing Video Analysis Research

## Overview

Analysing a golf swing from video presents a fascinating computer vision and physics challenge. A typical swing captured at 240fps produces 240-480 frames for a 1-2 second swing, which when exported at 30fps creates roughly 300 frames of slow-motion footage. The goal is to extract meaningful biomechanical and physics data from these frames to provide actionable feedback.

This document explores the technical approaches, trade-offs, and implementation strategies for building a golf swing analysis system.

---

## The Three Primary Objects of Interest

### 1. The Club
The club is arguably the most important object to track. Its motion directly determines ball flight through impact physics. Key properties:
- **Clubhead position** throughout the swing
- **Clubhead orientation** (face angle, lie angle)
- **Shaft flex/bow** at various points
- **Velocity vector** at impact

Tracking challenges: The clubhead moves extremely fast (100+ mph at impact), causing motion blur. The shaft is thin and can blend with backgrounds.

### 2. The Body
Human pose provides context for swing mechanics. Key joints of interest:
- **Spine angle** and tilt
- **Hip rotation** and slide
- **Shoulder rotation** relative to hips
- **Lead arm position** and extension
- **Wrist hinge** angles
- **Head position** (stability)
- **Weight shift** (foot pressure, though harder to infer from video alone)

### 3. The Ball
The ball is stationary pre-impact, making it useful as a reference point. Post-impact:
- **Launch angle** (vertical)
- **Launch direction** (horizontal relative to target)
- **Initial velocity** (if we can track the blur)
- **Spin axis** (very difficult from video alone)

Ball flight tracking is largely impractical with a single camera - the ball becomes a small blur almost immediately.

---

## Frame Extraction: Determining Valuable Frames

Not all 300 frames are equally useful. A golf swing has distinct phases, and certain frames provide disproportionate analytical value.

### Key Positions (In Order)

| Frame Name | Description | Why It Matters |
|------------|-------------|----------------|
| **Address** | Setup position, ball in frame | Baseline for all measurements, reference distances |
| **Takeaway** | Club parallel to ground, going back | Initial swing path direction |
| **Lead Arm Parallel** | Left arm (for RH) parallel to ground | Wrist hinge check, early swing plane |
| **Top of Backswing** | Maximum rotation, club at apex | Full shoulder turn, arm position, club position |
| **Transition** | First move down | Sequencing, hip vs shoulder timing |
| **Lead Arm Parallel (Down)** | Arms parallel on downswing | Lag retention, swing plane |
| **Pre-Impact** | ~0.05s before impact | Shaft lean, hand position entering impact |
| **Impact** | Club-ball contact | The moment of truth |
| **Post-Impact/Extension** | Full arm extension | Release pattern, club path through the ball |
| **Follow-Through** | Mid-way to finish | Balance, swing completion |
| **Finish** | End position | Balance check, full rotation |

### Automatic Frame Detection Strategies

**Option A: Motion-Based Detection**
- Calculate frame-to-frame motion magnitude
- Backswing: Motion increases then plateaus at top
- Downswing: Rapid acceleration
- Impact: Can be detected by ball position change
- Peak motion = around impact zone

```
Frame Motion Profile (conceptual):
          /\      
         /  \     
        /    \    
       /      \   Impact Peak
______/        \_____
   Backswing  Follow-through
```

**Option B: Pose-Based Detection**
- Run pose estimation on sampled frames
- Detect key positions by joint angles:
  - Top of backswing: Maximum shoulder-hip differential
  - Impact: Hands near ball position
  - Lead arm parallel: 90° elbow angle check

**Option C: Object Detection-Based**
- Track clubhead position through frames
- Highest point = top of backswing
- Clubhead at ball position = impact
- Requires clubhead detection model

**Option D: Hybrid Approach (Recommended)**
1. Use motion analysis to find approximate regions of interest
2. Run pose estimation on a sparse subset (every 10th frame)
3. Use pose data to narrow down key positions
4. Run detailed analysis only on identified key frames

This minimises compute while maximising accuracy.

---

## Information Extraction Methods

### Method 1: 2D Pose Estimation

**What it is:** Detecting 2D skeletal keypoints (joints) in each frame.

**Available Models:**
- **MediaPipe Pose** - Fast, runs on-device, 33 landmarks
- **OpenPose** - More accurate, heavier compute
- **MoveNet** - Google's fast pose model
- **ViTPose** - State-of-the-art transformer-based

**What you can extract:**
- Joint angles (hip hinge, knee flex, spine angle from side view)
- Rotation estimates (shoulder vs hip lines in DTL view)
- Relative positions (hands relative to body)
- Timing and sequencing of body parts

**Limitations:**
- No depth information
- DTL view obscures some joints (far-side arm, far-side leg)
- Cannot determine true 3D rotations

**Best for:** Quick feedback, basic swing analysis, mobile/edge processing

### Method 2: Object Detection for Club and Ball

**Purpose:** Track the golf club and ball through frames.

**Approaches:**

*Pre-trained models:*
- General object detectors (YOLO, Faster R-CNN) won't work out of the box
- Would need fine-tuning on golf-specific dataset

*Custom training:*
- Collect/annotate 1000+ frames with clubhead bounding boxes
- Train YOLO or similar for fast inference
- Separate model for ball detection (simpler - circular, white, stationary initially)

*Alternative - Template matching:*
- Works well for the stationary ball
- Less effective for fast-moving clubhead

*Clubhead-specific challenges:*
- Motion blur at high speeds
- Various club types (driver vs iron) look different
- Changing orientation throughout swing

### Method 3: Optical Flow for Motion Tracking

**What it is:** Estimating pixel motion between consecutive frames.

**Tools:**
- OpenCV `calcOpticalFlowFarneback()` - Dense flow
- OpenCV `calcOpticalFlowPyrLK()` - Sparse feature tracking
- RAFT - Deep learning-based, very accurate

**What you can extract:**
- Velocity fields across the frame
- Clubhead speed (if you can identify clubhead region)
- Body segment motion patterns
- Impact timing (sudden change in ball region)

**Use case:** Combine with object detection. Once you find the club in one frame, use optical flow to track it to adjacent frames. This is more efficient than running detection on every frame.

### Method 4: Semantic Segmentation

**What it is:** Classifying each pixel (person, club, ball, background).

**Benefits:**
- Precise boundaries for club shaft/head
- Can isolate body parts for detailed analysis
- Better than bounding boxes for thin objects (club shaft)

**Models:**
- DeepLabV3+
- Segment Anything Model (SAM) - very flexible

**Use case:** Extract exact club position and orientation by fitting lines to the segmented shaft pixels.

### Method 5: 3D Pose Estimation (Single Camera)

**What it is:** Lifting 2D poses to 3D using learned priors.

**Models:**
- **VideoPose3D** - Temporal model, uses video context
- **MotionBERT** - State-of-the-art transformer approach
- **GVHMR** - Recent work on video-based human mesh recovery

**What you get:**
- 3D skeleton positions in camera-relative coordinates
- True joint angles in 3D
- Body rotation estimates

**Limitations:**
- Scale ambiguity (can't determine absolute distances without reference)
- Golf-specific poses may be out of training distribution
- Fast motion may confuse temporal models

**Mitigation:** Use known reference (ball diameter = 42.67mm, or club length) to establish scale.

---

## 3D Reconstruction Approaches

### Single Camera Limitations

From a single DTL view, we fundamentally cannot observe:
- Exact distance of objects from camera
- True face angle of club (we see edge-on)
- How far left/right (toward/away from camera) objects move
- True swing plane angle (we see projection)

### Depth Estimation from Single Image

**Monocular depth models:**
- MiDaS
- DPT (Dense Prediction Transformer)
- Depth Anything v2

These produce *relative* depth maps. Accuracy is limited but can help:
- Distinguish near vs far objects
- Improve pose estimation with depth cues
- Rough 3D scene understanding

**Accuracy concern:** These models are trained on general scenes. Golf-specific accuracy may be poor, especially for small fast objects.

### Multi-Camera Setup (DTL + Face-On)

This is where things get interesting. Two orthogonal views allow true 3D reconstruction.

**Geometry:**
```
        Face-On Camera
              |
              |
              v
              
       [  Golfer  ] <---- DTL Camera
              |
              |
              Ball
```

**Calibration requirements:**
1. Camera intrinsics (focal length, principal point, distortion)
2. Extrinsic relationship between cameras (rotation, translation)
3. Synchronisation (both cameras must capture same moment)

**Calibration methods:**
- Checkerboard pattern visible to both cameras
- Known points in the scene (ball position, tee markers)
- Structure from Motion if cameras capture same scene points

**3D Reconstruction via Triangulation:**

Given a point detected in both camera views:
1. Compute ray from Camera A through detected 2D point
2. Compute ray from Camera B through detected 2D point
3. Find 3D point where rays (approximately) intersect

With calibrated cameras, this gives true 3D world coordinates.

### Photogrammetry Approach

**True photogrammetry** requires multiple images of a static scene from different viewpoints. Golf swings are dynamic, so traditional photogrammetry doesn't directly apply.

However, we can use photogrammetric principles:
- Stereo reconstruction from two synchronised cameras
- SLAM-like approaches if cameras move around a static setup shot
- Neural Radiance Fields (NeRF) for scene representation (overkill for this use case)

### Practical Multi-Camera Workflow

1. **Sync frames** - Use audio (clap), or visual marker (flash), or hardware sync
2. **Detect key objects** in both views (ball, clubhead, body joints)
3. **Establish correspondences** - Same point identified in both images
4. **Triangulate** to 3D
5. **Build 3D trajectory** of club through swing

**What this unlocks:**
- True swing plane angle
- Actual club path (not projection)
- Face angle at impact
- 3D body rotation metrics

---

## Calculating Metrics

### Geometry-Based Metrics (2D Feasible)

These can be estimated from DTL view alone:

**Spine angle at address:**
- Find hip and shoulder positions from pose
- Calculate angle of line relative to vertical

**Hip slide vs turn:**
- Track hip position horizontally through swing
- Excessive lateral movement indicates slide

**Head movement:**
- Track head position through swing
- Good swings have minimal head movement

**Shaft lean at impact:**
- Measure angle of club shaft relative to vertical
- Positive lean (hands ahead) is generally desirable

**Swing width:**
- Distance from head to clubhead at various positions
- Wider is generally more powerful

### Velocity-Based Metrics

**Clubhead speed (estimated):**
```
If we know:
- Real-world clubhead positions at two frames
- Time between frames (1/fps)

Then:
speed = distance / time
```

Challenge: Getting real-world distance requires scale reference.

**Approximation method:**
- Use ball diameter (42.67mm) as scale reference
- Or golfer height (if known)
- Or club length (driver shaft ~45 inches)

### Angular Velocity Metrics

**X-Factor (shoulder-hip differential):**
- Measure shoulder line angle
- Measure hip line angle
- Difference is X-Factor
- Track through swing to see X-Factor stretch at transition

**Hip rotation speed:**
- Angular change per frame
- Should peak in early downswing

**Shoulder rotation speed:**
- Should lag behind hips (proper sequencing)

### Impact Metrics (Requires Club Tracking)

**Attack angle:**
- Direction of clubhead travel at impact relative to ground
- Negative = hitting down (good for irons)
- Positive = hitting up (good for driver)

**Club path:**
- Direction of clubhead travel relative to target line
- Requires face-on view or 3D reconstruction for accuracy

**Face angle:**
- Orientation of clubface relative to target
- Very difficult from video alone
- Requires 3D reconstruction or face-on view showing face

**Dynamic loft:**
- Loft presented at impact
- Affected by shaft lean and clubface orientation

### Derived Physics Metrics

**Estimated ball speed:**
```
Ball Speed ≈ Clubhead Speed × Smash Factor

Smash factor depends on:
- Center strike
- Club type (driver ~1.5, irons ~1.3-1.4)
```

**Launch angle estimation:**
- If ball trajectory is visible in first few frames
- Can estimate initial launch direction

**Spin estimation:**
- Not feasible from video alone
- Would require very high resolution, high speed camera, or radar

---

## Physics Models

### Basic Impact Physics

The moment of impact follows collision physics:

**Coefficient of Restitution (COR):**
- Regulated by golf rules (max 0.83 for drivers)
- Relates pre/post impact velocities

**Gear effect:**
- Off-center hits cause spin axis tilt
- Ball curves away from miss direction

**Compression:**
- Ball compresses against face
- Launch conditions depend on compression dynamics

### Swing Mechanics Physics

**Double pendulum model:**
- Arms as first pendulum
- Club as second pendulum
- Explains why wrist release happens naturally

**Kinetic chain:**
- Energy transfers from ground → legs → hips → torso → arms → club
- Proper sequencing maximises clubhead speed

**Centripetal force:**
- Club wants to fly outward
- Golfer must resist with grip pressure
- Explains "releasing" the club

### Projectile Motion (Ball Flight)

If we could track ball:
```
x(t) = v₀ × cos(θ) × t
y(t) = v₀ × sin(θ) × t - ½gt²
```

But we'd also need:
- Drag coefficient
- Lift from spin (Magnus effect)
- Wind

**Reality:** Ball flight prediction from video alone is impractical. This is what launch monitors are for.

---

## Implementation Architecture Options

### Option 1: On-Device (iOS)

**Pros:**
- Immediate feedback
- No network dependency
- Privacy - video doesn't leave device

**Cons:**
- Limited compute
- Must use efficient models
- Storage constraints

**Stack:**
- CoreML for inference
- Vision framework for pose
- Metal for custom processing

### Option 2: Cloud Processing

**Pros:**
- Access to powerful GPUs
- Can run sophisticated models
- Easier to update/improve models

**Cons:**
- Upload delay (videos are large)
- Requires connectivity
- Server costs

**Stack:**
- Python backend
- PyTorch/TensorFlow for models
- Video processing with OpenCV/ffmpeg

### Option 3: Hybrid

**Best of both worlds:**
- Quick on-device processing for immediate feedback
- Upload for detailed analysis
- Progressive results (fast first, detailed later)

---

## DTL View: What We Can and Cannot Determine

### Clearly Visible
- Spine angle through swing
- Hip slide (lateral movement)
- Arm extension
- Club plane (from this view)
- Shaft lean at impact
- Head stability
- Knee flex
- Weight shift (to some degree)

### Partially Visible
- Shoulder turn (appears as shoulders narrowing/widening)
- Hip rotation (same - width change)
- Club path (only in/out, not left/right relative to target)

### Not Determinable
- True face angle
- True swing plane (we see projection)
- How far open/closed shoulders are
- Ball-to-target line relationship

---

## Face-On View: Complementary Information

### What FO Adds
- Club path direction (left/right)
- Face angle at impact
- True swing plane
- Hip/shoulder rotation directly visible
- Ball starting direction

### FO Limitations
- Cannot see depth of swing
- Hard to see exact impact position
- Spine angle not visible

---

## Dual Camera Integration Strategy

### Synchronisation Methods

**Hardware sync (ideal):**
- External trigger for both cameras
- Frame-accurate sync
- Requires special hardware

**Audio sync:**
- Both cameras record audio
- Align on impact sound or clap
- Sub-frame accuracy possible

**Visual sync:**
- LED flash visible to both cameras
- Impact moment as sync point (ball movement starts)

### Coordinate System Unification

1. Define world coordinate system (e.g., ball position = origin)
2. Calibrate each camera's pose in world coordinates
3. Transform all detections to world coordinates
4. Merge data into unified 3D representation

### Data Fusion

For each detected object:
1. Get 2D position from DTL camera → 3D ray
2. Get 2D position from FO camera → 3D ray
3. Compute intersection → 3D position
4. Handle occlusions (object visible in only one view)

---

## Recommended MVP Approach

Given the complexity, here's a pragmatic starting point:

### Phase 1: Single Camera (DTL) Analysis
1. Extract frames at key intervals (using motion analysis)
2. Run MediaPipe Pose on key frames
3. Calculate basic metrics:
   - Spine angle at address and impact
   - Hip slide measurement
   - Arm extension at impact
   - Head stability (movement from address)
4. Manual club head marking (user taps clubhead in key frames)
5. Calculate shaft lean at impact

### Phase 2: Automatic Club Detection
1. Train custom YOLO model on golf club dataset
2. Track clubhead through frames
3. Estimate clubhead speed using scale reference
4. Detect attack angle from clubhead trajectory

### Phase 3: 3D Reconstruction (Multi-Camera)
1. Implement camera calibration workflow
2. Build stereo reconstruction pipeline
3. Calculate true 3D metrics

---

## Open Questions / Further Research

1. **Training data availability:** Are there labeled golf swing datasets for club detection?

2. **Motion blur handling:** Can we use deblurring networks to sharpen clubhead in fast frames?

3. **Real-time vs post-processing:** What's the acceptable delay for feedback?

4. **Accuracy validation:** How do our calculated metrics compare to professional launch monitor data?

5. **User guidance:** How do we help users position the camera correctly for reliable analysis?

6. **Lighting conditions:** How robust are our models to outdoor vs indoor, shadows, etc.?

---

## References and Resources

- MediaPipe Pose: https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker
- YOLO for custom object detection: https://docs.ultralytics.com
- OpenCV optical flow: https://docs.opencv.org/master/d4/dee/tutorial_optical_flow.html
- Camera calibration: https://docs.opencv.org/master/dc/dbb/tutorial_py_calibration.html
- MiDaS depth estimation: https://github.com/isl-org/MiDaS
- Stereo triangulation: https://en.wikipedia.org/wiki/Triangulation_(computer_vision)

---

## Appendix: Frame Rate Calculations

| Capture FPS | Swing Duration | Frames in Swing | Export FPS | Playback Duration |
|-------------|----------------|-----------------|------------|-------------------|
| 240         | 1.0s           | 240             | 30         | 8.0s              |
| 240         | 1.5s           | 360             | 30         | 12.0s             |
| 240         | 2.0s           | 480             | 30         | 16.0s             |
| 120         | 1.5s           | 180             | 30         | 6.0s              |

For a 1.5 second swing at 240fps, if we identify ~11 key frames, we process <5% of total frames for the key position analysis.



