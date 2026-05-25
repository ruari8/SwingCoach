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
- addressed ball or strike spot
- confidence for each anchor

The app-level swing detector remains a pipeline:

```text
Audio transient detector
  -> candidate impact timestamps

Apple Vision pose
  -> primary golfer, hands, body motion, swing phase

Lightweight golf-anchor model
  -> clubhead, shaft geometry, strike spot/addressed ball

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
