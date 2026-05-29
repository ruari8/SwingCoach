# Experimental On-Device Swing Detector

## Decision

The product goal is an on-device swing detector that can find real golf swings in recorded or imported iPhone video.

The detector should be treated as a fused system, not one monolithic model. The current preferred direction is:

```text
audio impact candidates
  + Apple Vision pose/motion
  + optional lightweight golf-anchor model
  -> real swing timestamps
```

The first trained model, if needed, should not be an end-to-end "swing detector". The preferred trainable component is a lightweight golf-anchor model that helps the detector localize the club and strike area:

- clubhead at address
- shaft or shaft endpoints
- useful foreground golf-ball candidates
- confidence for each anchor

The model should not predict `addressed_ball`, `impact`, `swing_start`, or `swing_end` in the first version. Those are derived runtime concepts. The app should infer them from body motion, audio, clubhead/shaft geometry, local ball candidates, and temporal consistency.

The app-level swing detector remains a pipeline:

```text
Audio transient detector
  -> candidate impact timestamps

Apple Vision pose
  -> primary golfer, hands, body motion, swing phase

Lightweight golf-anchor model
  -> clubhead, shaft geometry, foreground ball candidates

Temporal state machine
  -> address, takeaway, downswing, impact, follow-through, end

Strike-spot verification
  -> did the exact locked strike patch change after impact?

Output
  -> start time, impact time, end time, confidence, reason
```

Audio is now an explicit experiment because impact is often a short, sharp transient. If audio reliably locates impact, the visual system can focus on validating that the primary golfer was actually swinging around that time.

## Why Not Train A Whole Swing Detector First

An end-to-end swing detector would take short video clips and directly output "real swing", "practice swing", start, impact, and end. That is attractive but risky for the first experiment:

- it needs many labeled clips, not just labeled frames
- temporal video models are heavier than single-frame detectors
- on-device performance is harder to guarantee
- failures are less interpretable
- it may learn motion patterns but still fail to confirm contact

The current detector already has useful pose and motion logic. Its weak point is semantic anchoring around the golf club and addressed ball. The trained model should fill that missing piece.

## Current Detector Limitation

Current impact/contact logic is mostly pixel-based. It looks for compact bright patches and local before/after changes. That is too weak for range footage where the frame can contain:

- multiple balls around the club
- alignment balls
- bucket balls
- range balls in the background
- white socks/shoes
- mat seams and clubhead highlights
- a partially occluded addressed ball

The important question is not "where is a white golf ball?". It is:

```text
Which exact patch is the primary golfer's clubhead addressing?
```

That requires clubhead-derived strike-spot localization.

## Audio Impact Hypothesis

Golf impact may be detectable from audio without training a model. The expected signal is a short high-frequency transient: a fast onset, brief decay, and much more high-frequency energy than ordinary body motion.

For imported videos, no microphone permission is needed because the audio track is already part of the video asset. For live recording, microphone capture would need to be enabled and permissioned in the iOS capture session.

Audio should not be trusted alone. It can false-positive on:

- another golfer striking a ball nearby
- club/mat noise during a practice swing
- dropped clubs or range-bay noise
- speech, wind, or clipped audio
- slow-motion export quirks that stretch or alter audio timing

The intended use is as an impact candidate generator:

```text
audio spike found
  -> check primary golfer pose/motion around that time
  -> if golfer is in downswing/follow-through, accept or raise confidence
  -> otherwise reject as nearby bay/background noise
```

For slow-motion clips where the visible swing window is roughly 14 seconds on playback, an initial clip window can be estimated as:

```text
start = impact - 9s
end = impact + 4s
```

Those offsets should be learned or tuned from labels rather than hard-coded as final behavior.

### Current Audio Fixture Result

Diagnostic script:

```bash
./backend/venv/bin/python tools/analyze_audio_impacts.py \
  --video .videos/IMG_2592.mov \
  --labels .videos/IMG_2592.labels.json \
  --output .videos/audio_eval/audio_impact_report.json
```

Initial result on the labeled long slow-motion range video:

- the video has usable audio aligned to the full slow-motion playback timeline
- every one of the 18 labeled swing windows contains an audio transient candidate
- the median transient offset is about 9.7 seconds after the labeled window start
- 16 of 18 windows have the strongest in-window transient at least 7 seconds after the labeled start, matching the rough "impact happens late in the slow-motion clip" expectation
- audio alone is not selective enough: the top-ranked global transients include many spikes outside the labeled swing windows

Conclusion:

```text
Audio is promising as an impact locator inside pose/video candidate windows.
Audio is not reliable enough as a standalone swing detector in range footage.
```

Next detector experiment:

```text
pose/motion proposes a likely swing window
  -> audio picks the likely impact transient inside that window
  -> start/end offsets are derived around impact
  -> optional visual/contact logic rejects practice swings or nearby-bay audio
```

## Desired First Model

The first model should be small enough to run on iPhone through Core ML, preferably at sparse frame rates rather than every video frame.

Target behavior:

- run on address/setup frames or cropped regions around the golfer/hands/mat
- output clubhead and strike-spot anchors
- provide confidence, including low-confidence failures
- be usable by the state machine rather than replacing it

Likely label formats, in order of preference:

1. Keypoints:
   - `clubhead_center`
   - `strike_spot`
   - `shaft_top`
   - `shaft_bottom`
   - optional `addressed_ball_center`
2. Bounding boxes:
   - `clubhead`
   - `addressed_ball`
   - optional `golf_club`
3. Segmentation masks:
   - shaft/clubhead/ball masks if keypoints or boxes prove insufficient

Keypoints are the preferred starting point because the detector needs geometry, not perfect object masks.

## Dataset Strategy

Use real SwingCoach capture footage first.

The user's current app library is a good source because it contains the videos the product must handle. A starting set of roughly 100 videos can produce a useful first experiment if frames are extracted automatically.

Example extraction target:

```text
100 videos x 15-30 frames = 1,500-3,000 frames
```

Useful extracted frame types:

- address/setup
- takeaway
- downswing/near-impact
- impact/just-after-impact
- early follow-through
- hard negatives: practice motion, spare balls, coach in frame, walking/setup

Split train/validation/test by source video or session, not by adjacent frames. Otherwise the test set will contain near-duplicates of training frames and produce misleading results.

Recommended split:

```text
train: 70%
validation: 15%
test: 15%
```

The first experiment should likely be scoped as:

```text
DTL, driver-heavy, iPhone range/capture footage
```

Face-on videos and iron-heavy range clips should be held out or tracked separately until the DTL pipeline is working.

## Assisted Labeling

Heavy models can help create proposed labels, but they should not be treated as ground truth without review.

Possible assisted-labeling flow:

```text
extract frames
  -> run heavy model(s) to propose clubhead/shaft/ball candidates
  -> generate overlay images
  -> human corrects ambiguous labels
  -> train small model from corrected labels
```

SAM-style segmentation can help isolate objects after a prompt, but it does not solve the contextual question by itself. The harder part is selecting the clubhead and ball/strike spot belonging to the primary golfer.

### SAM3, SAM3 Image, MLX, And Mac Performance

SAM3 should be treated as a labeling aid for this project, not as the eventual on-device detector.

Important terminology:

- `facebookresearch/sam3` is Meta's official PyTorch implementation. It is CUDA/NVIDIA-first.
- `facebook/sam3` on Hugging Face is the Meta checkpoint/model repository used by different runtimes.
- `mlx-community/sam3-image` is a converted SAM3 image model for Apple's MLX runtime. It is not a new product-level detector; it is the SAM3 image path running through an Apple-native harness and converted weights.
- SAM3.1 is mainly interesting for video tracking efficiency and object multiplexing. It is not the same workflow as independently prompting every extracted frame.

The first full pseudo-label pass used the Meta PyTorch package. Although the wrapper selected `mps`, local inspection showed the model and processor were still CPU-bound:

```text
tracker.device: mps
model parameters: cpu
processor device: cpu
MPS allocated memory: effectively zero
```

The cause is in the official PyTorch SAM3 setup path: it moves the model to CUDA when `device == "cuda"`, but does not move it for `mps`. Forcing the current package to MPS fails in prompt/grounding code around unsupported MPS operations such as `grid_sample`.

A community `device-agnostic` branch of Meta SAM3 can run image inference on MPS by:

- moving the model with `model.to(device)`
- constructing the processor on `mps`
- enabling `PYTORCH_ENABLE_MPS_FALLBACK=1`
- falling back to CPU for unsupported MPS operations

That path works for image inference, but still bounces some work to CPU and is therefore only a partial speedup.

The MLX path was the best local Mac route tested. It downloads converted weights from `mlx-community/sam3-image` and runs through Apple's MLX runtime. It produced the same detection counts as the good PyTorch routes on the hard-frame sample, with much better throughput after the one-time weight download.

20-frame benchmark on previously missed ball frames:

| Route | Runtime | Approx/frame | Detection counts |
| --- | ---: | ---: | --- |
| Meta PyTorch SAM3, CPU | 237.6s | 11.9s | club 18, shaft 19, clubhead 19, ball 19 |
| Community-patched Meta SAM3, MPS | 131.9s | 6.6s | club 18, shaft 19, clubhead 19, ball 19 |
| Hugging Face Transformers SAM3, MPS | 1556.7s | 77.8s | club 17, shaft 20, clubhead 20, ball 19 |
| MLX SAM3 image | 46.0s | 2.3s | club 18, shaft 19, clubhead 19, ball 19 |

The Hugging Face Transformers route technically ran, but `Sam3Model.from_pretrained("facebook/sam3")` reported missing text encoder weights and the run had a large runtime stall. Do not rely on it without further investigation.

Meta's SAM3.1 real-time claims are not directly comparable to this experiment. Meta's reported high frame rates are for optimized video tracking on H100-class NVIDIA hardware, where objects can be multiplexed/tracked across frames. Our current labeling workflow is different:

```text
for each extracted image:
  encode image
  prompt multiple concepts independently
  convert masks to boxes
```

That is useful for dataset creation, but it is not the optimized SAM3.1 video-tracking path.

Current recommendation:

```text
Use MLX SAM3 image for Mac-side pseudo-labeling.
Use SAM3.1 only as a later experiment if we need temporally consistent video-propagated labels.
Do not plan to ship SAM3/SAM3.1 in the iPhone live detector.
```

SAM3D is separate from SAM3 image/video segmentation and still needs its own Apple Silicon investigation. Do not assume the MLX SAM3 image finding applies to SAM3D body/object models.

### Relabeling Hypothesis

The relabeling goal is not to force every frame to contain every class. The target is to label every useful visible object while preserving confidence and uncertainty.

Raw object classes for the first detector dataset:

- `golf_ball_candidate`
- `clubhead`
- `club_shaft`
- `golf_club`

Derived runtime concepts should not be first-model classes:

- `addressed_ball`
- `impact`
- `ball_visible_before_after`

Those should be computed by app logic from object detections, pose/motion, and temporal consistency.

Expected label presence across the 708 extracted frames:

| Object | Expected useful labels | Notes |
| --- | ---: | --- |
| `golf_ball_candidate` | 450-650 frames | Any visible ball candidate, including spare balls. Not necessarily the addressed ball. |
| `clubhead` | 500-650 frames | Can blur or leave frame during backswing/downswing. |
| `club_shaft` / `golf_club` | 500-650 frames | Often visible, but motion blur and framing can break it. |
| all objects together | 350-500 frames | Many frames are valid partial-label examples. |

For `addressed_ball`, the expected reliable count is much lower because it is contextual:

```text
address/setup-ish frames -> derive addressed ball from clubhead proximity
impact/follow-through frames -> addressed ball may be gone
```

Rough target:

```text
200-350 confident derived addressed-ball examples
```

The current `pre_impact`, `impact_candidate`, and `post_impact` extraction phases are weak metadata. Contact sheets showed that these frames are sometimes all before impact. They are useful for object-label diversity, but they must not be treated as impact ground truth.

Preferred relabeling flow:

```text
MLX SAM3 image
  -> threshold about 0.3
  -> prompt variants for club/shaft/clubhead/ball
  -> keep multiple ball candidates
  -> merge duplicate prompt hits with NMS
  -> preserve raw candidate labels and confidence
  -> create overlays for review
  -> derive addressed_ball later from clubhead proximity and temporal consistency
```

Multiple ball prompts can return duplicate detections for the same physical ball. The relabeling code should merge highly overlapping boxes/masks and keep the best-scoring candidate. It should also allow multiple unique `golf_ball_candidate` detections per frame because range footage often contains spare balls, alignment balls, and background balls.

The lightweight on-device model should learn generic golf objects. The swing detector algorithm then derives:

```text
primary golfer from Apple Vision
clubhead and ball candidates from the golf-object model
addressed ball from clubhead/clubface proximity at address
impact from addressed-ball region change plus club/body/audio evidence
start/end from pose, club motion, and temporal state
```

### Current MLX Relabel Run

The first MLX SAM3 image relabel run completed over the 708 extracted SwingCoach frames using:

- threshold: `0.3`
- max image side: `960`
- output folder: `detector_model/mlx_sam3_labels`
- classes: `golf_club`, `club_shaft`, `clubhead`, `golf_ball_candidate`
- ball prompts: `golf ball`, `golfball`, `white golf ball`, `small white golf ball`
- duplicate handling: class-level NMS across prompt variants
- overlay review set: 220 frames

Verified output:

| Artifact | Count |
| --- | ---: |
| annotations | 708 |
| YOLO label files | 708 |
| overlays | 220 |
| empty frames | 0 |

Class totals:

| Class | Detections | Frames with class |
| --- | ---: | ---: |
| `golf_club` | 633 | 633 |
| `club_shaft` | 623 | 623 |
| `clubhead` | 623 | 623 |
| `golf_ball_candidate` | 2942 | 620 |

Average timing:

```text
set_image: 0.4823s/frame
prompts:   1.0754s/frame
```

Comparison with the previous CPU SAM3 label pass:

| Metric | CPU SAM3 | MLX SAM3 image |
| --- | ---: | ---: |
| frames | 708 | 708 |
| empty frames | 24 | 0 |
| club detections | 602 | 633 |
| shaft detections | 581 | 623 |
| clubhead detections | 597 | 623 |
| ball detections | 323 single `golf_ball` | 2942 multi-candidate `golf_ball_candidate` |

The ball count is intentionally much higher because this run labels all plausible ball candidates, including spare/alignment/background balls. Addressed-ball selection remains a separate derived step.

### Filtered YOLO Dataset

The raw MLX SAM3 labels are too noisy to train directly because the range background contains many tiny golf balls. A filtered training dataset was built with:

```bash
./backend/venv/bin/python tools/build_detector_training_dataset.py --overwrite
```

Output:

```text
detector_model/yolo_swing_objects_v1
```

This directory is ignored by git. The tracked builder script is `tools/build_detector_training_dataset.py`.

Working layout for this experiment:

| Path | Git status | Purpose |
| --- | --- | --- |
| `detector_model/` | ignored | heavy local workspace for videos, extracted frames, pseudo-labels, trained checkpoints, Core ML exports, and QA images |
| `tools/` | tracked | reusable experiment/preprocessing/evaluation scripts |
| `docs/EXPERIMENT_SWING_DETECTOR.md` | tracked | decisions, results, and current interpretation |

The `tools/` name is generic, but it is already the repo's existing home for detector/build/evaluation utilities. If this work graduates from experiment to product code, move the stable pieces into a more explicit package such as `backend/analysis/detector_training/` or `experiments/swing_detector/`.

The first model dataset deliberately uses three classes:

| Class | Reason |
| --- | --- |
| `club_shaft` | needed for shaft/plane geometry and club context |
| `clubhead` | needed to derive the addressed strike area |
| `golf_ball_candidate` | generic useful ball candidates, not addressed-ball identity |

The full `golf_club` box from SAM3 was excluded from v1 because it is a large nested box around the shaft/head and is less useful for impact timing than the specific anchors.

Ball filtering policy:

- keep only `golf_ball_candidate` boxes with area >= `100` px
- keep only boxes with normalized center-y >= `0.50`
- keep at most `5` balls per frame after scoring by confidence, size, and foreground position
- do not try to choose the addressed ball during dataset creation

Filtered dataset summary:

| Metric | Count |
| --- | ---: |
| frames | 708 |
| train frames | 528 |
| validation frames | 108 |
| test frames | 72 |
| source videos | 59 |
| train source videos | 44 |
| validation source videos | 9 |
| test source videos | 6 |
| frames with labels | 707 |
| frames without labels | 1 |
| kept `club_shaft` labels | 623 |
| kept `clubhead` labels | 623 |
| kept `golf_ball_candidate` labels | 768 |
| dropped tiny ball candidates | 2168 |

Splitting is by source video, not random frame, so adjacent frames from the same swing do not leak across train/val/test.

### First YOLO Training Run

Two nano YOLO detectors were trained on the filtered pseudo-label dataset. These are experiments, not production models, because the labels are still SAM3-derived rather than hand-corrected.

Training environment:

- Mac local training on Apple MPS
- Ultralytics `8.4.54`
- training/evaluation image size `960`
- batch size `4`
- conservative geometry/color augmentation
- output folder: `detector_model/yolo_runs`

The image-size setting is the model input size, not a claim that source videos must be exactly 960 pixels. Training and inference resize/letterbox each input frame to the fixed model input, then output boxes are mapped back to the original frame coordinate system. On-device Core ML packages also expose fixed input dimensions, so the app-side camera pipeline must perform the same resize/letterbox and box remapping.

YOLO11n was trained first because it is the stronger current Ultralytics nano detector:

```text
detector_model/yolo_runs/swing_objects_yolo11n_v1_960/weights/best.pt
```

YOLO11n validation metrics:

| Class | Precision | Recall | mAP50 | mAP50-95 |
| --- | ---: | ---: | ---: | ---: |
| all | 0.975 | 0.886 | 0.941 | 0.770 |
| `club_shaft` | 0.949 | 0.960 | 0.986 | 0.866 |
| `clubhead` | 0.989 | 0.944 | 0.975 | 0.831 |
| `golf_ball_candidate` | 0.988 | 0.754 | 0.863 | 0.614 |

YOLO11n held-out test metrics:

| Class | Precision | Recall | mAP50 | mAP50-95 |
| --- | ---: | ---: | ---: | ---: |
| all | 0.973 | 0.928 | 0.960 | 0.829 |
| `club_shaft` | 1.000 | 0.918 | 0.972 | 0.871 |
| `clubhead` | 0.923 | 0.970 | 0.980 | 0.868 |
| `golf_ball_candidate` | 0.995 | 0.896 | 0.929 | 0.747 |

YOLO11n is the best research checkpoint from this run. Initial Core ML testing was inconclusive because the backend Python `3.14` environment hit `coremltools`/wrapper failures before proving whether the model package itself was valid. A clean Python `3.13` re-check loaded and ran both raw YOLO11n Core ML packages:

| Export | Direct Core ML load/predict? | Input size | Output shape |
| --- | --- | ---: | --- |
| `best.mlpackage` | yes | `640x640` | `(1, 7, 8400)` |
| `best_960_raw.mlpackage` | yes | `960x960` | `(1, 7, 18900)` |

Remaining YOLO11n Core ML work:

- validate post-processing/NMS against the PyTorch predictions
- test the package from Swift/Core ML, not only Python `coremltools`
- decide whether raw model output plus Swift-side NMS is acceptable
- re-test embedded-NMS export only if app-side NMS becomes a problem

YOLOv8n was trained as a compatibility baseline:

```text
detector_model/yolo_runs/swing_objects_yolov8n_v1_960/weights/best.pt
```

YOLOv8n validation metrics:

| Class | Precision | Recall | mAP50 | mAP50-95 |
| --- | ---: | ---: | ---: | ---: |
| all | 0.961 | 0.901 | 0.955 | 0.731 |
| `club_shaft` | 1.000 | 0.938 | 0.985 | 0.842 |
| `clubhead` | 0.884 | 0.926 | 0.945 | 0.740 |
| `golf_ball_candidate` | 1.000 | 0.838 | 0.935 | 0.610 |

YOLOv8n held-out test metrics:

| Class | Precision | Recall | mAP50 | mAP50-95 |
| --- | ---: | ---: | ---: | ---: |
| all | 0.945 | 0.924 | 0.970 | 0.766 |
| `club_shaft` | 1.000 | 0.921 | 0.995 | 0.855 |
| `clubhead` | 0.836 | 0.930 | 0.949 | 0.785 |
| `golf_ball_candidate` | 1.000 | 0.922 | 0.965 | 0.657 |

YOLOv8n Core ML findings:

| Export | Runs locally? | Test mAP50 | Test mAP50-95 | Ball recall | Approx local inference |
| --- | --- | ---: | ---: | ---: | ---: |
| `640` raw Core ML | yes | 0.869 | 0.567 | 0.692 | 62.6ms/image |
| `960` raw Core ML | yes | 0.953 | 0.743 | 0.870 | 38.2ms/image |

The 960 Core ML package is the compatibility baseline:

```text
detector_model/yolo_runs/swing_objects_yolov8n_v1_960/weights/best.mlpackage
```

It does not include embedded NMS. The app or runtime wrapper must perform post-processing/NMS outside the model.

Current interpretation:

- YOLO11n gives the best detector quality in PyTorch and remains the research target.
- YOLOv8n remains the compatibility fallback because its Core ML path is older and easier to reason about.
- Both raw Core ML packages still need app-side decoding/NMS before either can be called app-ready.
- The metrics are optimistic because the train/val/test labels are pseudo-labels created by SAM3, not hand labels.
- Visual QA on real frames and a held-out iron swing clip was good enough to justify a detector-pipeline experiment.
- The detector model still does not solve addressed-ball identity by itself. Addressed-ball identity is derived later from clubhead proximity, pose context, temporal consistency, and local before/after patch changes.

### YOLO-backed Detector Pipeline Experiment

Script:

```text
tools/evaluate_yolo_object_swing_detector.py
```

Purpose:

Evaluate whether the trained golf-object model can act as the visual confirmation layer for swing detection on the long range-session video, without using the label timestamps during detection.

Algorithm used in the current offline experiment:

1. Sample the slow-motion source video sequentially at `2 fps`, simulating a live-style pass over the already-stretched playback timeline.
2. Run the YOLO11n golf-object model on each sampled frame.
3. Build a motion signal from:
   - frame-to-frame visual difference
   - detected club/clubhead movement
   - club presence confidence
4. Propose swing windows from sustained object/motion activity.
5. Merge nearby short motion chunks before applying the minimum-duration rule. This matters because one true swing can fragment into several short motion bursts when the clubhead detector briefly drops out.
6. Within each candidate window, cluster lower-foreground `golf_ball_candidate` boxes into possible strike-area anchors.
7. Confirm a candidate only if a plausible ball anchor is present before the motion and disappears after the motion.
8. Estimate impact from the first sustained disappearance of the selected ball anchor, then report a trimmed swing window around that impact estimate instead of returning the whole motion-proposal span.

Important implementation notes:

- Addressed-ball identity is still not a model class. The model outputs generic `golf_ball_candidate` boxes.
- The detector derives addressed-ball evidence by selecting the candidate with the strongest before/after disappearance signal in the lower strike area.
- Clubhead-address proximity is recorded in the evidence payload, but it is not a hard acceptance gate yet. It is used preferentially for impact timing when an anchor is clearly next to the clubhead.
- The full-video evaluator supports a feature cache so threshold/logic changes can be rescored without re-running YOLO over the full video.

Current full range-session result:

| Run | Matched labelled swings | Missed labelled swings | Extra detections |
| --- | ---: | ---: | ---: |
| Initial YOLO object pass | 18/18 | 0 | 10 |
| Tuned YOLO object pass | 18/18 | 0 | 0 |

The final tuned report is:

```text
.videos/yolo_object_detector_full_tuned_final/results/yolo_object_detector_full_report.json
```

Readable summary:

```text
.videos/yolo_object_detector_full_tuned_final/results/detection_summary.md
```

The feature cache used for fast rescoring is:

```text
.videos/yolo_object_detector_full_tuned/features_full_yolo11n_2fps.json
```

The same code path also passed the trimmed fixture regression:

| Fixture set | Matched positives | Positive false positives | Negative false positives |
| --- | ---: | ---: | ---: |
| 18 labelled swing clips + 8 negative clips | 18/18 | 0 | 0 |

Report:

```text
.videos/yolo_object_detector_eval_tuned_final/results/yolo_object_detector_report.json
```

Interpretation:

- The object model is useful enough to build around.
- Ball disappearance is currently the strongest visual confirmation signal.
- The app now bundles the YOLO11n Core ML package and uses a Swift port of this detector for live capture-time Trim preselection and imported-video Trim preselection.
- The shipped app path is model-first for trim ranges. The older Vision-only detector is not used as a production fallback. The experimental `Hybrid` capture path uses sparse Apple Vision pose as a gate on top of model impact candidates.
- During capture, the app samples camera frames at the configured real-time rate (`16 fps` by default), runs the object model while recording is active, and stores detected swing ranges. When recording stops, Trim opens with those already-collected ranges and does not run the old fallback detector.
- Replay Debug now uses the same Core ML live detector as capture. Visible playback speed is only playback pacing; the separate source timing selector (`normal`, `120`, `240`) controls whether source timestamps are divided before feeding the detector, then mapped back to the source timeline for display and Trim review. This keeps saved slow-motion exports from being confused with normal-speed camera input.
- The Python `2 fps` source-timeline result is an upper-information baseline for the model logic. In an `8x` real-time replay, the equivalent real-time rate is about `16` YOLO samples per second, so the app exposes `2`, `4`, `8`, and `16 fps` real-time settings for throughput/recall experiments.
- The live acceptance gate now requires ball disappearance plus sustained object motion, average club motion, broad club path span, and high-club evidence. A second post-trim guard verifies that the returned clip itself still contains those motion/club-travel signals, which removes the stale setup/ball-management detection from the continuous Core ML pass.
- Imported/library videos still run a model-backed detector as a local post-pass when Trim opens. The post-pass now uses the selected Experiments detector mode/sample-rate/confirmation-wait settings, so the default Library Trim path uses the same `Hybrid` strategy as live capture and Replay Debug instead of silently falling back to strict contact.
- Audio confirmation remains future work for live capture. The current app path can use model detections, visual/club motion, lower-strike-area ball disappearance, and sparse Apple Vision pose in the experimental `Hybrid` mode.

Current app detector structures:

| Mode | Purpose | Acceptance rule | Start/end rule | Main failure mode |
| --- | --- | --- | --- | --- |
| `contact` | High-precision production-style trim preselection | model motion + club evidence + addressed-ball disappearance/contact guards | estimate impact from ball disappearance, then use configured pre/post impact trim | misses real swings when the ball is yellow, occluded, too small, one of several balls, or not consistently detected |
| `impact` | Strict addressed-ball impact experiment | sustained addressed-ball departure + club contact at the same anchor + local strike motion | fixed window around confirmed departure/contact time: `impact - impactPreRoll` to `impact + impactPostRoll`; very close neighboring events are merged | lower recall when the ball is occluded, too small, inconsistently detected, or hidden by app UI/video overlays |
| audio + model | Debug Replay mode + strategy harness | audio transient must fall inside/near an impact-mode visual window | keep the matched model impact window in Debug Replay; strategy harness also scores a short fixed window around audio impact | misses screen recordings or clips with weak/no useful impact audio; can false-positive on nearby bays |
| Apple Vision pose gate | Debug Replay mode + strategy harness | impact-mode visual window must also contain plausible primary-golfer hand motion/address-to-finish change | keep the impact-mode fixed window | reduces static/setup false positives, but can miss swings when Vision sees a mostly static or partial body |
| hybrid pose/cadence | Experimental live capture mode, Replay Debug mode, and strategy harness | pose-gated impact windows, nearby weaker pose duplicate suppression, plus a narrow low-pose/cadence fallback after a previously accepted swing | keep the impact-mode fixed window | tuned on the current V2 clips; needs more real range sessions before it can be trusted as production behavior |

The current `contact` detector is sequential, not a set of long post-processing jobs running in parallel. Each sampled frame appends one feature row, then rescans the retained feature buffer to see whether any new completed window can be declared. The feature row contains:

- YOLO/Core ML object detections: `club_shaft`, `clubhead`, `golf_ball_candidate`
- visual motion from luma difference: the average absolute difference between the current and previous downsampled Y-plane frame (`80x120`, normalized to `0-1`)
- club motion: normalized movement of the best detected club/clubhead point between sampled frames
- smoothed motion: weighted visual motion + club motion + a club-confidence bonus

The distinction between candidate and swing is intentional:

```text
candidate = sustained smoothed motion AND club evidence
swing     = candidate AND ball/contact validation AND club path/motion guards
```

In `contact` mode, a motion run starts when smoothed motion passes the threshold and the frame has enough club evidence. The candidate gets a small pre/post pad. It only becomes a detected swing if validation finds a lower-strike-area ball anchor before the motion, that same anchor mostly disappears after the motion, the clip has enough peak motion, enough strong-motion samples, enough average club motion, enough club path span, and the club travels high enough in frame. When impact can be estimated, the returned trim is centered on that impact estimate instead of the full candidate span.

Live Capture can now be switched between `contact`, `impact`, and `hybrid` from Library > Experiments. New installs and devices still carrying the old default `contact` setting migrate once to `hybrid`; the user can still switch back afterward for comparison. Replay Debug now has one footage timing selector (`30/1x`, `120/4x`, `240/8x`) instead of separate playback-speed and source-speed controls, and its overlay shows visible replay source time as `elapsed/total` seconds instead of a percent-only progress label. Replay Debug also back-pressures visible playback when the detector reader falls more than a few source seconds behind, because otherwise `240/8x` video can visually advance far ahead of the model loop and make detections appear long after the swing was watched. The hybrid impact confirmation wait is configurable from Experiments and Replay Debug Advanced controls (`0.20s`, `0.28s`, `0.35s`, or `0.55s`) so phone testing can compare faster declaration against safer/slower waits without another build. In `hybrid`, capture runs the same YOLO sampling path and also samples Apple Vision pose sparsely on the capture frame queue. The live badge recomputes the shared hybrid selector on each sampled frame so the golfer can see hybrid detection count, latest impact time, impact-to-declaration delay, returned-window-end delay, and pose sample count while recording. It also shows `target/effective fps`, model last/average milliseconds, pose last/average milliseconds, and camera-to-analysis lag. When recording stops, the same selector is applied to the retained impact candidates before Trim opens, and the final detector timing snapshot is shown under the Trim timeline. `pose` and `audio` remain Replay Debug modes.

This explains the confusing debug UX from the failing clips:

```text
candidate found
  -> model saw club/motion
  -> contact validator could not prove addressed-ball disappearance
  -> no detected swing emitted
```

It also explains the delay that appeared in the app: the detector cannot confirm a contact swing until enough post-impact samples exist to decide that the ball disappeared. The strict contact path should still declare close to the end of the swing, but if the candidate stretches too long or the post-impact evidence is weak, declaration can lag. The hybrid impact path now has an explicit confirmation wait, `impactConfirmationPostRoll`, which defaults to `0.20s` of detector time instead of the older implicit `0.55s`. That is roughly three 16fps detector samples after estimated impact; shorter waits are intentionally not the default because the local motion peak has too little post-impact context. The evaluator records `impactTime`, `declaredAt`, `latencyFromEnd`, and `latencyFromMatchedLabelEnd`; Debug Replay detected-swing chips show impact and returned-window lag; captured Trim auto-detected thumbnails show `imp +Xs / end +Ys` for declaration delay from estimated impact and returned clip end.

Generalization check with `.detectorTestV2`:

The `.detectorTestV2` folder now contains five local videos. The strategy harness uses rough visual labels embedded in `tools/evaluate_detector_test_v2.py`, including the first 120 seconds of `IMG_2622.mov` where four visible swing windows were marked. These labels are rough scoring anchors, not final ground truth.

Command:

```text
python3 tools/evaluate_detector_test_v2.py > .detectorTestV2/strategy_report.json
```

The harness accepts `--sample-fps` for detector-rate sweeps and `--impact-confirmation-post-roll` for declaration-latency sweeps.

Aggregate result:

| Strategy | Matched rough swings | False positives | Duplicate windows | Detection count | Interpretation |
| --- | ---: | ---: | ---: | ---: | --- |
| strict `contact` | 1/9 | 0 | 0 | 1 | precise but far too brittle |
| `impact` | 9/9 | 12 | 4 | 25 | high recall, still too noisy for production without more gates |
| pose-gated `impact` | 8/9 | 1 | 2 | 11 | Vision removes most static/setup false positives, but misses one rough long-session swing |
| audio + model | 5/9 | 1 | 0 | 6 | promising on real recordings with useful audio, poor on screen recordings |
| hybrid pose/cadence | 9/9 | 0 | 0 | 9 | best current V2 strategy; uses sparse pose gating plus one low-pose/cadence escape hatch |

Per-case result:

| Video | Rough swings | `contact` | `impact` | pose-gated `impact` | audio + model | hybrid pose/cadence |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `1cde87c1-420b-4a92-8d4d-adde03917ae9.MP4` | 1 | 0/1, 0 FP | 1/1, 0 FP | 1/1, 0 FP | 1/1, 0 FP | 1/1, 0 FP |
| `ScreenRecording_04-01-2026 16-13-45_1.MP4` | 1 | 0/1, 0 FP | 1/1, 1 FP | 1/1, 0 FP | 0/1, 0 FP | 1/1, 0 FP |
| `ScreenRecording_05-13-2026 06-46-28_1.MP4` | 2 | 0/2, 0 FP | 2/2, 1 FP | 2/2, 1 FP | 0/2, 0 FP | 2/2, 0 FP |
| `eb5a91a1830f4dc894afbe2ffafa3a45.MOV` | 1 | 0/1, 0 FP | 1/1, 0 FP | 1/1, 0 FP | 1/1, 0 FP | 1/1, 0 FP |
| `IMG_2622.mov` first 120s | 4 | 1/4, 0 FP | 4/4, 10 FP | 3/4, 0 FP | 3/4, 1 FP | 4/4, 0 FP |

Observed local Mac CPU Core ML time is about `54-55 ms` per sampled model frame in this run. The evaluator also sampled Apple Vision pose at roughly half the model cadence (`900` pose attempts over the first `120s` of `IMG_2622.mov`, with `804` valid pose frames). The wall-clock run became several minutes, so Vision should be treated as a sparse confirmation/gating experiment, not something to run naively at every model frame during live capture. The app uses Core ML `.all` compute units on device, so Mac CPU fallback timing is a correctness/debug signal, not the final phone throughput claim.

Sample-rate sweep:

| Sample rate | V2 hybrid result | V2 false positives | V2 duplicates | 18-swing fixture result | Fixture negative false positives | Decision |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `2 fps` | 5/9 | 1 | 1 | not rerun | not rerun | too sparse |
| `4 fps` | 8/9 | 1 | 1 | not rerun | not rerun | too noisy |
| `8 fps` | 8/9 | 0 | 0 | 16/18 | 1/8 | misses swings |
| `12 fps` | 8/9 | 1 | 1 | 18/18 | 1/8 | not clean enough |
| `16 fps` | 9/9 | 0 | 0 | 18/18 | 0/8 | current default |

The lower-rate failures are useful: the original 18-swing fixture alone would make `12 fps` look acceptable on positives, but V2 and the negative-gap clips show that coarser sampling changes which model/pose peaks win. For now, `16 fps` remains the live default even though it is heavier.

Confirmation-latency sweep:

| Confirmation wait | V2 hybrid result | V2 false positives | V2 duplicates | V2 label-end latency | 18-swing fixture result | Fixture negative false positives | Decision |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `0.55s` | 9/9 | 0 | 0 | not recorded | 18/18 | 0/8 | previous implicit wait, accurate but slower |
| `0.35s` | 9/9 | 0 | 0 | not recorded | 18/18 | 0/8 | accurate, but no longer fastest validated setting |
| `0.28s` | 9/9 | 0 | 0 | not recorded | 18/18 | 0/8 | accurate |
| `0.20s` | 9/9 | 0 | 0 | 0.0s | 18/18 | 0/8 | current default; roughly three 16fps samples after impact |

Real-device throughput check:

The capture badge, and then the captured-video Trim screen, now report enough timing to test whether `16 fps` is actually real time on phone:

```text
16/15.8fps · model 22/24ms · pose 8/9ms · lag 35ms
```

The first number is configured/effective detector sample FPS. `model` and `pose` are last/average per-sampled-frame costs. `lag` is wall-clock delay between the camera frame timestamp and completed analysis. Healthy live capture should keep effective FPS close to the configured rate and keep lag from steadily growing. If lag climbs above a few hundred milliseconds during a normal range recording, the detector is falling behind even if the offline evaluator still scores well.

Current interpretation:

- The YOLO model is useful for club/motion evidence, but the strict addressed-ball/contact validator is the brittle part.
- For the current V3 short-clip iteration, `test2` is the active positive acceptance case. The model detects the addressed white ball until about `2.27s`; the addressed-ball anchor disappears at about `2.33s`; and a shaft box intersects that address region at about `2.27s`. The impact-centered/hybrid stream now emits one impact at `2.333s`, inside the rough `[2.0, 3.0]` label bucket, with declaration at `2.533s`.
- The local evaluator now writes `impactDebugReports` so missed swings can be sorted by rejection reason instead of inferred visually. On `test2`, the addressed-ball anchor reports `confirmed`; the persistent spare-ball/pile anchor reports `ball_departure_not_confirmed`, which is the expected split.
- The second labelled `test5` window exposed an over-tight club-contact gate: ball departure was clean around source `763.5s`, but the nearest club box was about `0.102` normalized frame units from the addressed-ball anchor while the old tight gate required `0.055`. The detector now keeps the tight gate for normal cases, but accepts up to `0.12` only when pre/post ball evidence is very clean. On the four local `test5` labelled-window proxies, this produces one impact in each window: about `204s`, `764s`, `1244.5s`, and `1723s`.
- The full `test5` long-session proxy exposed a separate long-run bug: when later swings reused roughly the same addressed-ball image area, the impact detector only returned the first confirmed disappearance for that anchor and could suppress later real impacts. Impact refresh now evaluates recent anchors and emits every confirmed disappearance per anchor before de-duplicating nearby repeats. With `16fps`, `240/8x` source timing, `0.20s` confirmation, and CPU/Neural Engine compute, the full proxy now returns five impact windows at about `204s`, `674.5s`, `764s`, `1244.5s`, and `1723s`; the hybrid pose/cadence selector keeps four at about `204s`, `764s`, `1244.5s`, and `1723s`.
- The original app-path `test5` replay exposed the real `8fps` impact-mode failure: direct club/ball proximity missed true swings 2/3/4 when sampled at the wrong instant, while address occlusion (`1109-1126s`) and a dispenser/non-address ball (`1475-1492s`) passed because they looked like clean ball disappearance plus nearby club. Impact attribution now requires either direct club/ball contact with strike-like local motion, or a very clean ball departure with a strong swing-shaped motion window when exact contact is missed. On the app-style full `test5` run at `8fps`, `240/8x`, `0.20s`, and CPU/Neural Engine compute, impact and hybrid both return exactly four windows at about `204s`, `764.03s`, `1245.10s`, and `1723.13s`, with no extra detections.
- `test1` and `test3` are useful object-model coverage cases rather than detector-logic acceptance cases for now. MLX SAM3 can identify yellow ball candidates in those clips, while the deployed YOLO model often misses them, so they should come back after yellow/colored-ball training data is curated. `test6` should remain quarantined as a low-quality screen-recording/UI-contamination edge case.
- Fixed-window impact detection is worth exposing in Debug Replay because it answers the user's proposed method directly: find likely impact, then use pre/post timing. It finds the V2 swings, but it needs stronger false-positive gates before it can be the production trim path.
- Apple Vision pose helps as a gate. On V2 it cuts impact false positives from `12` to `1`, but it is not a standalone answer because it misses one rough long-session swing and still leaves duplicate windows in several clips.
- The hybrid pose/cadence strategy is the best current V2 strategy and is now the live-capture default. It keeps pose-gated impact detections, removes nearby weaker pose duplicates, and accepts one low-pose model-impact candidate only when it appears after a long enough gap from the previous accepted swing and has very quiet body/hand pose but enough model motion/club evidence. The pose gate now accepts clear address-to-finish displacement at a slightly lower peak hand speed (`0.50` body-heights/s) because the 12th long-session swing had strong displacement but a smoothed Vision speed of only about `0.54`. On the current V2 set this scores `9/9`, `0` false positives, and `0` duplicate windows. At the default confirmation wait, every V2 hybrid detection declares `0.20s` after estimated impact and before the rough labelled swing window ends (`0.0s` label-end latency).
- The same hybrid stream was rescored on the original 18-swing fixture after that gate adjustment: `18/18` positives matched, `0` positive false positives, and `0/8` negative-gap false positives. Mean source-timeline label-end latency is `0.061s`; after dividing the slow-motion source by `8x`, mean real-time label-end latency is `0.008s`, with the worst positive case at `0.138s` real time. Report: `.videos/live_model_detector_fixture_eval_hybrid/results/live_model_detector_fixture_report.json`.
- Audio is the best next confirmation signal for real camera recordings because impact transients are often sharper than visual ball evidence. It cannot be trusted alone, and it does not help screen recordings with weak or altered audio. Capture now adds a microphone input when available so new recordings can carry audio; live audio-fused capture trimming is still not the production path.
- Apple Vision pose should remain a gate, not a replacement detector: require a primary golfer and plausible address-to-finish body/hand motion around model/audio candidates, then reject setup/waggle windows.
- The original labelled long-session fixture remains a regression test, not proof that the detector generalizes to screen recordings, indoor bays, multiple-ball drills, yellow balls, or grass-ball visibility.

Rejected fusion scratch result:

Before adding another app mode, the current V2 report was rescored with two fused rules:

| Prototype rule | Matched rough swings | False positives | Duplicate windows | Detection count | Decision |
| --- | ---: | ---: | ---: | ---: | --- |
| pose gate OR nearby audio impact | 8/9 | 2 | 3 | 13 | worse than pose alone |
| pose gate OR relaxed model-only escape hatch | 9/9 | 6 | 3 | 18 | restores recall but brings back too much noise |

The useful next fusion work is narrower: make audio a true live capture stream and test this hybrid decision layer on more real camera recordings with known audio rather than screen recordings.

Swift/Core ML live evaluator:

```text
xcrun swiftc -parse-as-library \
  -framework AVFoundation -framework CoreML -framework Vision \
  -framework CoreGraphics -framework CoreVideo -framework ImageIO \
  SwingCoach/Models/OnDeviceSwingDetector.swift \
  SwingCoach/Models/LiveSwingDetector.swift \
  SwingCoach/Models/GolfObjectDetector.swift \
  SwingCoach/Models/ModelBackedSwingDetector.swift \
  tools/evaluate_live_model_detector.swift \
  -o .videos/bin/evaluate_live_model_detector

.videos/bin/evaluate_live_model_detector \
  .videos/IMG_2592.mov \
  SwingCoach/MLModels/SwingObjectsYOLO11n.mlpackage \
  16 8 10000 \
  .videos/IMG_2592.labels.json
```

Fixture-level Core ML live scoring:

```text
./backend/venv/bin/python tools/evaluate_live_model_detector_fixtures.py \
  --output-dir .videos/live_model_detector_fixture_eval_hybrid \
  --detection-stream hybridImpactDetections
```

Current `16fps / 8x` hybrid fixture result:

| Fixture set | Matched positives | Positive false positives | Negative false positives | Mean label-end latency |
| --- | ---: | ---: | ---: | ---: |
| 18 labelled swing clips + 8 negative clips | 18/18 | 0 | 0 | 0.008s real time |

Report:

```text
.videos/live_model_detector_fixture_eval_hybrid/results/live_model_detector_fixture_report.json
```

Continuous long-session Core ML live result:

| Source | Matched positives | Missed positives | False positives | Processed frames | Avg CPU-only model time |
| --- | ---: | ---: | ---: | ---: | ---: |
| `.videos/IMG_2592.mov` at `16fps / 8x` | 18/18 | 0 | 0 | 9040 | 60.2 ms |

Report:

```text
.videos/live_model_detector_full_16fps_8x_post_trim_guard.json
```

The setup/ball-management window `1391.507s-1409.013s` was the last false positive in the earlier continuous pass. It passed initial live proposal logic but did not retain enough motion/club-travel evidence inside the final returned clip, so the post-trim guard rejects it. On this Mac's CPU-only Core ML fallback, the fixture and full-session runs are correctness checks, not phone performance claims, because the app path uses Core ML `.all` compute units on device.

## Public Datasets And Models

Public golf datasets are useful, but they are not all useful in the same way. The key evaluation questions are:

- Does it label clubhead, shaft, addressed ball, or only generic swing events?
- Is it down-the-line or face-on?
- Does it resemble iPhone range footage?
- Does the license allow the intended use?
- Can labels be converted into keypoints/boxes for our model?
- Can any pretrained model be exported to Core ML or used only as a server/labeling aid?

There is an important distinction between model families:

- Fixed-class detectors such as standard YOLO, RF-DETR, and DEIM only detect the classes they were trained on. COCO-trained models can detect `person` and maybe `sports ball`, but not `clubhead`, `shaft`, `driver head`, or `addressed ball`.
- Open-vocabulary/promptable models such as SAM-style grounding pipelines, GroundingDINO, OWL-ViT/OWLv2, Florence-style grounding, and YOLO-World can accept text prompts such as `golf club`, `club head`, or `club shaft`, but they are usually heavier and better suited to offline labeling or server-side experiments than live iPhone inference.

The experiment should therefore separate:

```text
promptable models
  -> assisted labeling/debugging

fixed-class mobile detectors
  -> eventual on-device inference, after using public golf weights or fine-tuning
```

### YOLO / RF-DETR / DEIM Bake-off

Before training a custom detector, run a bake-off on real SwingCoach frames:

- YOLO variants, including public golf-specific weights if available
- RF-DETR Nano/Small/Large where licensing is Apache-2.0
- DEIM/DETR-family models where licensing is Apache-2.0
- promptable models only as offline labeling/debug references

The score is not generic COCO mAP. The score is whether model output helps lock a strike spot:

- does it find the primary golfer?
- does it find golf ball candidates?
- does it find the golf club or clubhead?
- does it pick the addressed ball rather than spare/background balls?
- does it confuse shoes, socks, mat seams, or range balls?
- is it stable across adjacent frames?

Licensing notes for experiments:

- AGPL models are acceptable for local personal experiments, but shipping them in a closed-source App Store app is a deliberate product/legal decision unless a commercial license is used.
- Apache-2.0 models are generally product-friendly if notices are preserved.
- PML or custom model licenses need specific review before product use.

### ClubheadDB

ClubheadDB is currently the most relevant public dataset for the first anchor-model experiment.

Usefulness:

- focused on golf clubhead tracking
- down-the-line frames
- over 10,000 annotated frames
- YOLO-format clubhead bounding boxes
- directly targets one of our missing anchors

Limitations:

- labels clubhead, not addressed ball or strike spot
- web-sourced video may not match SwingCoach iPhone capture
- does not solve multi-ball selection by itself
- published license is CC-BY-NC-4.0, so it is suitable for research/experiments but not automatically safe for commercial product training without legal review or permission

Preferred use:

```text
Use for research/pretraining/bootstrap experiments.
Fine-tune and evaluate on our own iPhone footage.
Do not rely on it as production training data until licensing is cleared.
```

### GolfDB / SwingNet

GolfDB is useful for swing sequencing, not strike-spot anchoring.

Usefulness:

- labels swing events such as address, top, impact, and finish
- supports temporal swing-phase/event detection research
- includes baseline SwingNet code/model ideas

Limitations:

- not a clubhead/addressed-ball/strike-spot dataset
- does not directly solve the current false-positive problem
- repository code is licensed CC-BY-NC-4.0, so commercial use needs care

Preferred use:

```text
Reference for swing-event timing and temporal modeling.
Not the first source for the golf-anchor model.
```

### Roboflow Universe Golf Datasets/Models

Roboflow Universe contains public golf-related object datasets and trained models, including datasets with classes such as golf ball, golf club-head, and golf club-handle.

Usefulness:

- can provide quick baselines for object detection
- may include trained models for experimentation
- some datasets are already in exportable detector formats

Limitations:

- dataset quality and labels vary by author
- "golf ball" means any ball, not the addressed ball
- licenses vary per dataset and must be checked on each project page
- if no license is listed, assume rights are reserved
- public Roboflow models may not be suitable for Core ML deployment or commercial use

Preferred use:

```text
Use only after checking the specific project license and sample quality.
Treat as baselines or labeling aids, not as the core dataset.
```

## Public Dataset Preference

Ranking for this experiment:

1. Our own SwingCoach/iPhone footage
   - best domain match
   - cleanest ownership
   - can label the exact target: clubhead-derived strike spot
2. ClubheadDB
   - best public match for clubhead localization
   - useful for research/pretraining
   - license blocks assumed commercial use
3. Roboflow golf club/ball datasets
   - useful for baselines and labeling aids
   - quality/license must be checked per dataset
   - generic ball detection is not enough
4. GolfDB/SwingNet
   - useful for swing timing research
   - not directly useful for strike-spot anchoring

## First Experiment Proposal

1. Run an audio transient investigation on the existing labeled long video.
2. Fuse promising audio candidates with the current pose detector and score again.
3. Run a public-model bake-off on representative frames for YOLO/RF-DETR/DEIM/open-vocabulary references.
4. Export/copy SwingCoach library videos to a local ignored folder.
5. Automatically extract candidate frames and contact sheets.
6. Label a small first set manually or with assisted labeling only if the public-model/audio experiments show a remaining gap:
   - `clubhead_center`
   - `strike_spot`
   - `shaft_top`
   - `shaft_bottom`
7. Train or fine-tune a small keypoint or detector model only if needed.
8. Export to Core ML early.
9. Benchmark on iPhone before expanding the dataset.
10. Integrate only if the model is small, fast, and materially improves strike-spot locking or practice-swing rejection.

## Open Questions

- Should the first model be DTL-only?
- Should driver and iron models be separate at first?
- Is `strike_spot` easier and more stable to label than `addressed_ball_center`?
- Do we need shaft endpoints, or is clubhead + strike spot enough?
- What latency/model-size budget is acceptable on the target iPhone generation?
- Does audio impact detection catch most real swings in slow-motion range footage?
- How often do nearby golfer impacts create audio false positives?
- Does the app need live microphone capture, or is imported-video audio enough for the first useful workflow?

## Sources Checked

- ClubheadDB PyPI page: https://pypi.org/project/clubhead-db/
- GolfDB GitHub repository: https://github.com/wmcnally/golfdb
- GolfDB dataset overview: https://deepwiki.com/wmcnally/golfdb/2.1-golfdb-dataset
- Roboflow Universe overview: https://docs.roboflow.com/universe
- Roboflow Universe dataset search/docs: https://docs.roboflow.com/roboflow/roboflow-ko/universe/universe
- Roboflow club dataset search: https://universe.roboflow.com/search?q=class%3Aclub
