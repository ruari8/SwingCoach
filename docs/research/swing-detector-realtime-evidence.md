# Evidence for reconstructing the real-time swing detector

Reviewed 2026-08-31. This note supports design discussion; it does not change the detector or establish new accuracy or latency results. Local context comes from [the V2 source audit](../SWING_DETECTOR_LOGIC.md). External claims below use Apple documentation, the GolfDB paper, and its authors' implementation. Recommendations are identified separately from source findings.

The central distinction is between recognizing swing motion and establishing that the intended ball was struck. A robust design should preserve that distinction even when one is easy to recognize and the other is temporarily unobservable.

## 1. Capture delivers observations with timestamps, not a perfect clockwork sequence

Apple's TN2445 explains that slow processing or retained capture buffers can cause dropped frames. `alwaysDiscardsLateVideoFrames` bounds the output queue to one frame, preventing a growing backlog, but cannot make chronically slow analysis keep up. The dropped-frame callback retains timing and reason metadata even though its image data is gone. A capture discontinuity can lose an unknown number of frames and produce a timestamp jump. Apple recommends measuring drops and adjusting the supported capture rate when necessary. [Apple: Handling Frame Drops with AVCaptureVideoDataOutput](https://developer.apple.com/library/archive/technotes/tn2445/_index.html).

**Design implication:** use delivered sample timestamps for motion, dwell and confirmation intervals. Preserve observation gaps explicitly. Five missing detections across a capture gap are not five clear views of an empty target patch. Separate recording and analysis budgets; record capture drops, intentional analysis skips and inference completion times separately. These are proposed requirements, not behavior verified on an iPhone in this investigation.

## 2. High capture rate and useful visual evidence are different requirements

Apple describes high-rate capture through a supported `activeFormat`, its `videoSupportedFrameRateRanges`, and configured minimum/maximum frame durations. It also distinguishes high-rate capture from slower playback of those captured frames. Its archived hardware tables are historical; they should not be used to promise capabilities on a current device. [Apple: Camera formats and high-frame-rate capture](https://developer.apple.com/library/archive/documentation/DeviceInformation/Reference/iOSDeviceCompatibility/Cameras/Cameras.html).

Exposure is separately configurable. Apple's custom-exposure API warns that changing exposure duration may change the active video frame durations and that unsupported duration/ISO values cause an exception. Therefore, exposure and cadence cannot simply be configured independently and assumed correct. [Apple: setExposureModeCustom](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setexposuremodecustom(duration:iso:completionhandler:)).

**Design implication:** measure actual cadence and image usability under the intended lighting, lens, resolution and recording configuration. Higher fps does not itself establish that a small ball or moving clubhead is recognizable. This note supplies no minimum usable fps, shutter setting, device throughput or contact-duration claim.

For existing SwingCoach slow-motion fixtures, preserve the documented distinction between source playback time and real swing time. A uniformly eightfold-slow export has eight playback seconds per real second. Do not stretch it again merely because its original capture rate was 240 fps. Variable-speed assets would need their own time mapping rather than this uniform assumption.

## 3. Pose provides useful geometry, with missing and uncertain joints

Apple's image-based 2D body-pose request returns an observation for each detected body and recognized joints with normalized coordinates and individual confidence. Zero-confidence joints are invalid. Apple advises sufficient subject size and visibility of key body regions, and warns about loose clothing and dense crowds. The documented coordinate origin is bottom-left. [Apple: Detecting Human Body Poses in Images](https://developer.apple.com/documentation/Vision/detecting-human-body-poses-in-images).

**Design implication:** wrists, torso and visible feet can support golfer-relative geometry, but joint absence must remain unknown rather than become a physical position. This API description does not promise that the first body result is the same person in every frame. Explicit golfer association and continuity are application responsibilities. A 2D joint near a ball is supporting evidence, not proof that they occupy the same depth or belong together. The proposal should handle short pose outages without transferring ownership to a neighbor.

## 4. GolfDB studies event timing within a swing

GolfDB defines swing sequencing in trimmed videos containing one swing; it treats localization in untrimmed footage as a separate task. Its eight events cover address, backswing checkpoints, top, downswing, impact, follow-through and finish. The dataset excludes pitches, chips and putts, although some samples include practice movements before the labeled swing. Critically, the authors report that the exact contact instant was rarely captured in native-30fps real-time footage; annotators selected the nearest frame. The metric measures event timing within a tolerance. [McNally et al., GolfDB, sections 3–4](https://arxiv.org/pdf/1903.06528).

**Design implication:** a plausible impact frame can help localize an already-supported shot. Success on this benchmark does not establish continuous-capture rejection of practice swings, marker balls or obscured no-contact motions. Nor does it establish that pitches and chips will behave like full swings. Those require a separate product scope and evaluation.

## 5. Temporal prediction needs an explicit causality contract

The authors' `EventDetector` uses a bidirectional LSTM by default. Its forward pass processes a supplied sequence and initializes hidden state for that call. With bidirectionality enabled, an output can depend on later frames within that supplied sequence. [GolfDB model.py, pinned revision](https://github.com/wmcnally/golfdb/blob/a63b4ce8c0900d09abbe92519223efe16810f5f4/model.py).

The evaluation helper chooses the maximum-probability frame for each event across the supplied sequence, then compares it with the label. That helper is not a continuous event emitter with a no-swing decision, duplicate handling or an online confirmation deadline. [GolfDB util.py, pinned revision](https://github.com/wmcnally/golfdb/blob/a63b4ce8c0900d09abbe92519223efe16810f5f4/util.py).

**Design implication:** reusing an offline event model requires measuring how much future context it consumes. Either use a causal model or permit a bounded confirmation delay with a retained pre-impact buffer. A trailing-window wrapper can be causal at emission time while using later frames relative to the estimated impact; those two times must be reported separately. This is not a claim that SwingCoach's separate P1–P10 model has SwingNet's architecture.

### The actual test15 P7 proposals have separate future-context dependencies

The local proposal script loads the `tcn_vision_club_v1` checkpoint. Its TCN implementation in the sibling `detectSwings/event_model/model.py` workspace uses kernel-three temporal convolutions with symmetric padding and dilations 1–32, followed by `GroupNorm(8, hidden)` on `[B,C,T]` tensors. The convolution path sees later positions; normalization adds another dependency. PyTorch computes group statistics from the input even in evaluation mode. Its implementation reduces across grouped channels and all remaining dimensions, so here statistics include the entire temporal window. [PyTorch GroupNorm](https://docs.pytorch.org/docs/stable/generated/torch.nn.GroupNorm.html), [normalization implementation](https://github.com/pytorch/pytorch/blob/main/aten/src/ATen/native/group_norm.cpp).

The feature builder in `detectSwings/event_model/dataset.py` scales coordinates using the supplied window's median torso length. Its gap interpolation uses club detections on both sides of a gap. The local proposal wrapper under `.verification-artifacts/test15-event-labels/` builds features separately for overlapping four-real-second windows, combines their scores, then extracts P7 peaks from the combined sequence.

**Consequence:** changing convolution padding alone would not produce zero-lookahead per-frame predictions. Normalization, feature scaling, interpolation and output aggregation also need a causal or explicitly delayed contract. The model comment's 127-frame convolutional receptive field is not a complete bound on input dependence once window-wide normalization is included. This source inspection does not measure the accuracy or latency of a causal replacement; no inference was rerun.

## 6. Observability should shape the product contract

The following is first-principles reasoning, not a measured model result: if an occluder hides both the contact region and any distinguishing aftermath, a real shot and a practice swing can produce indistinguishable available observations. No deterministic decision rule can recover information absent from its inputs. More thresholds cannot remove that ambiguity.

A practical reconstruction should therefore represent:

- **Swing motion observed:** a coherent movement by the intended golfer, regardless of contact.
- **Contact supported:** target-specific before/after evidence supports a strike.
- **No contact supported:** the same visible target remains stationary after the movement.
- **Unresolved:** the view, identity or sampled evidence is insufficient.

These are proposed evidence states, not calibrated confidence levels. A marker ball disappearing behind a leg must not become departure evidence. A strong swing pattern must not overwrite unresolved ball evidence. An optional audio signal could supply additional information, but attribution among neighboring bays would need its own validation; this investigation establishes no audio accuracy.

The state transitions can be deterministic for a fixed ordered observation stream while the observations remain uncertain. Repeatability of rules, repeatability of model execution and correctness about the physical world are separate properties. No cross-device bit-for-bit inference guarantee was established here.

## What remains to prove

Before calling a reconstruction robust, evaluate held-out sessions with changed framing, multiple nearby balls, practice swings, temporary covering, neighboring golfers and missed frames. Report contact recall, false captures per recording duration, unresolved cases, and impact-to-confirmation latency. Benchmark live capture on the intended phone while recording, including sustained operation and difficult lighting. Local replay can validate decision logic; it cannot alone establish camera throughput, thermal behavior or live sampling equivalence.
