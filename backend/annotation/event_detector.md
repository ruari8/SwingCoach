# Event Detector Plan

This document captures the current plan for building the swing event detector
that will support automated video annotations.

The event detector is foundational. It answers:

> Where are the meaningful positions in this swing?

The annotation pipeline then uses those positions:

```text
event detector:
  find P1, P2, P3, P4, P5, P6, P7, P8, P9, P10

annotation pipeline:
  at P1, draw plane line, head line, bum line, spine angle
  at P2, check takeaway hand/club relationship
  at P3, check shaft/butt-of-club relation to the ball
  at P6, check delivery shaft/forearm relation
  at P7, check impact posture/contact evidence
```

Events are the timing skeleton. Annotations hang off that skeleton.

## Scope

Start with down-the-line (`DTL`) swings.

Face-on (`FO`) can come later because the useful annotations and detection cues
are different. For example, DTL heavily uses plane, shaft, hand depth, hip depth,
and club path. FO will care more about sway, pressure/shift proxies, handle lean,
ball position, and low point.

## P-System Reference

Local visual reference sheet:

```text
backend/annotation/reference/p_system_dtl_one_sheet.png
```

The image file is intentionally gitignored because it is reference media.

## Target Events

For data labeling, use P1-P10.

For initial product annotations, we may only use a subset:

```text
P1  address
P2  shaft parallel back / takeaway
P3  lead arm parallel back
P4  top
P5  lead arm parallel down
P6  shaft parallel down / delivery / pre-impact
P7  impact
P8  shaft parallel through
P9  trail arm or lead arm parallel through
P10 finish
```

Even if V1 annotations only use `P1`, `P2`, `P3`, `P4`, `P6`, `P7`, and `P8`,
labeling all ten positions gives us a cleaner event map and future-proofs the
dataset.

## Why Events Matter

We do not only care about ten still frames.

We care about:

1. Key checkpoint windows.
2. Motion tracks between checkpoints.

Checkpoint examples:

```text
P1:
  plane line
  head line
  bum line
  spine angle

P2:
  hands versus clubhead
  club rolling inside/outside
  club working through the pocket

P3:
  shaft steep/shallow relative to ball
  butt of club points inside/outside ball

P6:
  delivery shaft
  shaft through trail forearm
  body depth before impact

P7:
  impact posture
  contact evidence
```

Track examples:

```text
P1 -> P8:
  clubhead path
  hand path
  head movement
  hip depth / early extension
  posture changes
```

The event detector tells every annotation where to inspect.

## Dataset Shape

The source data should be full trimmed swing videos, not just ten extracted
frames.

Human-facing dataset:

```text
video clips
+ P1-P10 timestamp labels
+ lightweight metadata
```

Example label file:

```json
{
  "video_id": "yt_abc123_swing_07",
  "path": "clips/yt_abc123_swing_07.mp4",
  "view": "dtl",
  "handedness": "right",
  "club": "iron",
  "speed_type": "normal_speed",
  "encoded_fps": 30.0,
  "capture_fps": null,
  "slowmo_factor": 1.0,
  "events": {
    "p1": { "time": 0.22, "quality": "clear" },
    "p2": { "time": 0.61, "quality": "clear" },
    "p3": { "time": 0.87, "quality": "clear" },
    "p4": { "time": 1.16, "quality": "clear" },
    "p5": { "time": 1.31, "quality": "ok" },
    "p6": { "time": 1.43, "quality": "blurred" },
    "p7": { "time": 1.51, "quality": "nearest_frame" },
    "p8": { "time": 1.62, "quality": "ok" },
    "p9": { "time": 1.82, "quality": "clear" },
    "p10": { "time": 2.34, "quality": "clear" }
  }
}
```

The labels are timestamps. We do not manually label pose, YOLO boxes, or visual
embeddings.

## Labels Versus Features

Labels are the answers we teach the model.

```text
P6 happens at 1.43s.
P7 happens at 1.51s.
```

Features are the inputs the model uses to learn those answers.

Possible features:

```text
raw pixels:
  the actual video frames

pose:
  automatically detected head, shoulders, hips, elbows, wrists, knees, ankles

YOLO object tracks:
  automatically detected ball, clubhead, shaft boxes

visual embeddings:
  compact learned representation of what each frame looks like
```

Pose, YOLO, and embeddings are optional model inputs. They are not extra human
labels.

The simplest conceptual training setup is:

```text
input = video pixels
label = P1-P10 timestamps
```

The practical model may use additional automatically extracted signals because
500 videos may not be enough for a pure pixel model to learn golf structure from
scratch.

## Why Not Train On Only Ten Frames?

We could extract the ten labeled frames and train:

```text
input = still image
label = P number
```

This is not ideal as the primary detector because production input is a full
video, not the ten frames already selected.

Also, some positions are ambiguous without motion context:

```text
P3 lead arm parallel back
P5 lead arm parallel down
```

These can look similar as still images. The difference is direction:

```text
P3: hands/club are moving up and back
P5: hands/club are moving down toward impact
```

The detector should therefore understand the sequence over time.

## Temporal Model

A temporal model is a model that reads a sequence rather than one still frame.

Image classifier:

```text
one frame -> class
```

Temporal event detector:

```text
frame 1, frame 2, frame 3, ...
-> P-event probabilities over time
-> event windows
```

Useful temporal model families:

```text
LSTM / GRU
TCN, Temporal Convolutional Network
Transformer
3D CNN / video transformer
```

The exact model can be chosen after the dataset and labeling workflow exist.

## Recommended Training Target

Use event heatmaps / probability curves over time.

Instead of training the model to output only:

```text
P6 = 1.43s
```

train it to output:

```text
for every sampled frame:
  probability this frame is P1
  probability this frame is P2
  ...
  probability this frame is P10
```

Around the human label, create a soft target window.

Example:

```text
time: 1.34  1.38  1.42  1.46  1.50
P6:  0.10  0.45  0.90  1.00  0.55
```

At inference time:

```text
P6 anchor = peak of P6 probability curve
P6 window = surrounding high-probability region
P6 confidence = peak probability plus quality checks
```

This gives us timestamps, windows, and confidence.

## FPS And Slow Motion

Do not think only in terms of file FPS.

Important concepts:

```text
encoded_fps:
  what the MP4 file plays at, often 30fps

capture_fps:
  what the camera originally captured, often 120fps or 240fps for slow-mo

slowmo_factor:
  how much the captured motion has been slowed down for playback

unique frames across the swing:
  the practical signal density available to the model and labeler
```

Example normal-speed 30fps clip:

```text
actual swing duration: 1.2s
encoded duration: 1.2s
frames across swing: about 36
```

Example 240fps capture exported as 30fps slow-mo:

```text
actual swing duration: 1.2s
encoded duration: 9.6s
frames across swing: about 288
```

Both may report `30fps`, but the slow-mo clip contains many more unique frames
across the swing.

High-frame-source slow-mo is especially valuable for:

```text
P5
P6
P7
P8
```

These happen quickly and are often blurred in real-time clips.

Label in the displayed video timeline first:

```text
P6 occurs at encoded_time = 6.13s
```

If source timing is known, also store:

```text
source_time = encoded_time / slowmo_factor
```

For drawing annotations on the video, encoded frame/time is enough. For later
tempo or time-based swing metrics, source timing matters.

## Dataset Size Targets

Suggested milestones:

```text
100 labelled swings:
  lock label definitions
  build labeling UI
  validate prelabeling

300-500 labelled DTL swings:
  first useful event detector

1,000-1,500 labelled DTL swings:
  serious product-grade DTL detector

3,000+ labelled swings:
  stronger robustness across camera angles, clubs, players, lighting, and
  YouTube/range differences
```

Initial target:

```text
500 labelled DTL swings
```

Try to include at least:

```text
100 true slow-mo swings
```

Ideal first 500 mix:

```text
150-250 true slow-mo DTL swings
250-350 normal-speed DTL swings
```

Acceptable first 500 mix:

```text
100 true slow-mo DTL swings
400 normal-speed DTL swings
```

The dataset does not need a perfect ratio. Normal-speed YouTube clips are useful
because they resemble abundant real-world input. True slow-mo range clips are
valuable because they make fast downswing events easier to label and learn.

## True Slow-Mo Versus Fake Slow-Mo

True slow-mo:

```text
captured at high FPS
exported at lower playback FPS
many unique frames
```

Fake slow-mo:

```text
captured at normal FPS
slowed by repeating or interpolating frames
fewer useful unique frames
```

The dataset pipeline should eventually classify clips as:

```text
normal_speed
true_slowmo
unknown_slowmo
fake_slowmo_or_duplicate_heavy
```

This can be estimated from frame-to-frame differences and duplicate frame rates.

## Dataset Acquisition

Use `detectSwings` to extract trimmed swings from longer source videos.

Potential flow:

```text
YouTube/source video
-> detectSwings
-> 70+ trimmed swings where available
-> metadata extraction
-> optional quality filtering
-> labeling tool
-> dataset manifest
```

Keep metadata per extracted clip:

```text
source_url
source_video_id
clip_index
clip_path
view
handedness
club
encoded_fps
resolution
speed_type
duplicate_frame_score
quality notes
```

## Labeling Tool Requirements

The labeling tool should make correction fast.

Minimum useful features:

```text
load one swing clip
scrub frame-by-frame
hotkeys for P1-P10
show current frame number and timestamp
save labels to JSON
jump between labels
mark event quality: clear, ok, blurred, nearest_frame, occluded, unknown
mark clip quality: usable, questionable, reject
```

Useful next features:

```text
prelabel with heuristics
overlay pose/YOLO detections if available
side-by-side P-system reference sheet
contact sheet export
fast review mode for correcting prelabels
```

## Prelabeler

The first prelabeler can be heuristic. It does not need to be the final model.

Purpose:

```text
reduce human labeling time
create initial labels
reveal where definitions are ambiguous
```

Possible cues:

```text
P1:
  stable address, ball visible, clubhead near ball

P2:
  early takeaway, shaft/club roughly parallel back

P3:
  lead arm roughly parallel back, hands rising

P4:
  top of backswing, hands/club reverse direction

P5:
  lead arm roughly parallel down after top

P6:
  shaft roughly parallel down before impact, delivery window

P7:
  clubhead near ball, ball departure/disappearance, optional audio spike

P8:
  shaft roughly parallel through after impact

P9:
  arms through and extended

P10:
  finish / motion settles
```

Existing SwingCoach pieces may help:

```text
existing live/offline swing detector for address and impact windows
YOLO boxes for ball, clubhead, shaft
pose detector for body landmarks
```

## Model Plan

### V0: Heuristic Prelabeler

Inputs:

```text
video
optional pose tracks
optional YOLO object tracks
```

Output:

```text
rough P1-P10 timestamps
confidence per event
```

Use this to speed up manual labeling.

### V1: Feature-Based Temporal Model

Inputs:

```text
automatically extracted per-frame features
```

Example features:

```text
hand center x/y
hand velocity
head x/y
shoulder/hip landmarks
clubhead x/y
clubhead velocity
ball x/y and visibility
shaft box position
normalized time in clip
```

Model:

```text
TCN, BiLSTM, or small Transformer
```

Output:

```text
P1-P10 probability curves over time
```

Pros:

```text
data efficient
interpretable
can work before we have a huge dataset
```

Cons:

```text
depends on pose/YOLO quality
may fail when detectors fail
```

### V2: Video-Based Temporal Model

Inputs:

```text
sampled video frames / pixels
```

Model:

```text
pretrained frame encoder, such as MobileNet/EfficientNet/ResNet
+ TCN/BiLSTM/Transformer temporal head
```

Output:

```text
P1-P10 probability curves over time
```

Pros:

```text
can learn visual cues beyond pose/YOLO
less dependent on separate detectors
```

Cons:

```text
needs more labeled data
less interpretable
more expensive to train/infer
```

### V3: Hybrid Temporal Model

Inputs:

```text
video/frame visual features
+ pose features
+ YOLO object features
```

Output:

```text
P1-P10 probability curves over time
```

This may become the strongest product detector, but it does not have to be the
first implementation.

## Recommended Build Order

1. Build a DTL event label format.
2. Build a labeling/review tool.
3. Collect an initial 100 DTL swings.
4. Manually label P1-P10.
5. Build a heuristic prelabeler.
6. Use prelabeler to accelerate labeling toward 500 swings.
7. Train V1 feature-based temporal model or V2 video-based temporal model.
8. Evaluate on held-out source videos.
9. Use the model to prelabel more data.
10. Iterate toward 1,000+ swings.

## Train/Test Split Rule

Split by source, not by derived clip or downsampled version.

If a 240fps swing is downsampled to 120fps, 60fps, and 30fps, all versions must
stay in the same split.

Bad split:

```text
same original swing appears in train and test via different downsampled copies
```

Good split:

```text
all versions of original swing stay together
```

This prevents leakage and fake accuracy.

## Evaluation

Evaluate event timing error in frames and milliseconds.

Metrics:

```text
mean absolute time error per P event
median absolute time error per P event
percentage within tolerance window
event confidence calibration
failure rate / withheld event rate
```

Suggested tolerances:

```text
P1/P4/P10:
  easier, larger visual plateaus

P6/P7:
  harder, faster, more blur
  evaluate with event windows, not only single-frame exactness
```

Report separately by:

```text
normal speed
true slow-mo
fake/unknown slow-mo
club type
view quality
source type: range, YouTube, lesson, broadcast
```

## Production Output Contract

The product event detector should return windows, not just single frames.

Example:

```json
{
  "events": {
    "p6": {
      "name": "delivery",
      "anchor_frame": 184,
      "timestamp": 6.13,
      "window": {
        "start_frame": 176,
        "end_frame": 191
      },
      "confidence": 0.74,
      "quality": {
        "motion_blur": "medium",
        "occlusion": "low"
      },
      "evidence": {
        "after_top": true,
        "before_impact": true,
        "shaft_parallel_down": true
      }
    }
  }
}
```

Annotations should be allowed to reject an event if the event quality is too low
for that specific annotation.

Example:

```text
P6 event detected, but shaft too blurred for shaft-through-forearm annotation.
Still useful for hip depth or hand position annotation.
```

## Open Questions

Important questions to settle during the first 100-swing labeling pass:

```text
Should P2 be first shaft-parallel-back or clubhead toe-up?
Should P3 be lead-arm-parallel-back or hand-height checkpoint?
Should P6 be shaft-parallel-down exactly or broader delivery window?
Should P9 be trail-arm-parallel-through or lead-arm-parallel-through?
How do we label partial swings?
How do we label swings where the event is between frames?
How do we label occluded or motion-blurred P6/P7?
```

The first 100 labelled swings are mostly about making these definitions boring
and repeatable.

