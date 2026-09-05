# Foundation app performance

Work tracked in [issue #14](https://github.com/ruari8/SwingCoach/issues/14), under the Foundation epic. This pass covers local Library work and the detector used by Capture and Trim/import. External coaching, API, and object storage are outside this pass.

## Measured changes — 2026-09-05

Baseline app source: `f1854d5`. Measurements below used optimized production Swift code on this Mac or its Simulator; they are not physical-iPhone frame-rate, battery, thermal, or UI-latency claims.

| Operation | Before median | After median | Verification |
| --- | ---: | ---: | --- |
| Delete 50 of 100 library entries | 19.019 ms | 0.327 ms | Three runs, saved metadata checked |
| Delete 100 of 1,000 entries | 358.285 ms | 2.570 ms | Three runs, saved metadata checked |
| Delete 100 of 5,000 entries | 1,730.620 ms | 15.890 ms | Three runs, saved metadata checked |
| V3 replay, `test2.mp4`, full short clip | 1.796 s | 1.026 s | Three runs per version; 179 decoded / 65 processed frames |
| V3 replay, `test7.mp4`, first 60 seconds | 21.479 s | 13.666 s | Three runs per version; 1,801 decoded / 542 processed frames |

**Library deletion:** the UI previously called single-entry deletion repeatedly, encoding and writing the whole remaining collection after every removal. `removeSwings(withIDs:)` removes the selection and its local copies, then saves once. Single-entry callers use the same API. No-op selections do not save. Photos originals remain untouched by library-only deletion. The separate permanent-delete action still performs its Photos deletion before removing the library entry.

The Simulator probe runs real `SwingLibrary` methods on the main thread with synthetic metadata, including 128-character notes. It checks persistence, survivor identity, local-file deletion, absent/duplicate IDs, empty selection, and local copy bytes. It does not include SwiftUI rendering or real Photos access in its timings. The app UI regression also selects/deletes the three personal fixtures, relaunches, checks that references remain, and checks persisted JSON and local files outside the app.

**Detector output parsing:** resolving `MLMultiArray` strides and storage type for each scalar was expensive. The detector now resolves them once per output tensor. Model, thresholds, sampling, coordinate mapping, and suppression logic remain unchanged. On a synthetic 18,900-prediction tensor, floating-point parsing fell from about 10.2 ms to 0.05–0.06 ms. This measures output parsing only. The complete Mac replay improved by 43% on the short clip and 36% on the session segment. Every compared run returned identical swing timestamps/confidences and decoded/processed frame counts. Baseline session replay varied from 17.816 to 23.204 seconds, so the medians are local measurements, not a fixed speed guarantee.

Tensor checks compare the baseline and current production decoders in one optimized process, including float16, float32, double, and the int32 fallback, each with contiguous and padded strides. They require equal classes, scores, and rectangles. The existing 24 decision-core regressions also pass. Two footage comparisons do not constitute a rerun of the full labelled detector corpus or prove live camera behavior.

## Repeatable commands

Requires macOS, Xcode 26/Swift and Python 3.11+. The library probe defaults to the iOS 26.3 iPhone 17 Simulator; `--runtime` and `--device-type` select other installed targets. The UI checks also need FFmpeg. Each profiling command requires a new output directory; it preserves commands, source snapshots/hashes, and measurements. Required real footage must be supplied explicitly, including from another checkout when ignored fixtures are absent from a worktree. A missing video fails instead of skipping verification. The Simulator probe creates and removes its own app/device and does not touch a phone or existing Simulator.

```bash
python3 scripts/profile_library.py \
  --output .verification-artifacts/foundation/library

python3 scripts/profile_tensor_decode.py --baseline-ref f1854d5 \
  --output .verification-artifacts/foundation/tensor

python3 scripts/profile_detector.py --video /absolute/path/to/test7.mp4 --end 60 \
  --output .verification-artifacts/foundation/detector-before

# Run this after changing detector code, with identical footage/model/settings:
python3 scripts/profile_detector.py --video /absolute/path/to/test7.mp4 --end 60 \
  --output .verification-artifacts/foundation/detector-after \
  --compare .verification-artifacts/foundation/detector-before/report.json

bash scripts/verify-review.sh .verification-artifacts/foundation/ui
python3 detector_workbench/validation/test_swing_detector_v3_evidence.py --build
```

To reproduce library before/after timings, run the probe from the corresponding source revisions: the baseline probe used the former repeated `removeSwing` UI loop; the current probe uses the batch API. Both exact source snapshots are saved with the original evidence. The tensor tool handles baseline extraction directly with `git show`.

The detector runner compiles the current V3 evaluator in its output directory, records video/model/source hashes and settings, and preserves complete per-run JSON. Comparisons fail on settings mismatch, unstable outputs, changed swing results, or changed frame counts. Profiling enables the evaluator's debug trace recording and uses its contact-only configuration; the timings include that work. Do not compare simultaneous benchmark runs or infer phone throughput from Mac timings.

The evaluator reports:

- `modelSetupSeconds`: detector construction and startup/reset.
- `sampleReadSeconds`: time spent waiting in `copyNextSampleBuffer`, including samples the scheduler skips. AVFoundation may decode asynchronously; this is not total decoder CPU time.
- `sampleProcessingSeconds`: time inside calls to the production detector.
- `wallClockElapsedSeconds`: the evaluation loop, excluding model setup.
- `processSeconds` in the profiling report: whole evaluator process, including startup and model setup.

The original full local evidence is in the original checkout under `.verification-artifacts/foundation-performance/`: `library-baseline`, `library-after`, `tensor-decode`, `detector-before-short`, `detector-after-short`, `detector-before-session`, `detector-after-session`, and `app-verification-final`. The final app run passed seven review/model tests plus the deletion UI test, with no failures or skips; its post-test filesystem check passed and its owned Simulator was removed.

## Generated fixtures and remaining work

Generated video fixtures are short deterministic moving patterns with known dimensions, rate, and duration. `verify-review.sh` makes six separate local clip files from one such pattern. They exercise playback, filtering, review gestures, orientation, deletion, and persistence without needing private recordings, Photos originals, or the backend. They cannot validate swing recognition or golf coaching. Use reviewed real golf footage for those questions.

Favouriting still rewrites the collection on the main thread: roughly 3 ms at 1,000 records and 15 ms at 5,000 in this probe. Local copies of 1 and 128 MiB both took under 1 ms on the Mac-hosted Simulator; APFS copy behavior makes that unsuitable evidence of physical-phone storage cost. Background persistence or import-copy changes need device measurements and an explicit ordering/durability design before implementation.

In these two replay samples, model/detector processing dominates synchronous sample-read waiting. This does not rule out decoder CPU, memory pressure, or latency on longer/high-resolution phone imports. The next useful gate is physical-iPhone import and live Capture measurement, with the phone confirmed ready, followed by the full labelled replay corpus before any broader detector accuracy claim. Record UI stalls, analyzed FPS, dropped frames, memory and thermal behavior. The current change does not establish those results.
