# Slop cleanup verification

Cleanup for [issue #15](https://github.com/ruari8/SwingCoach/issues/15), verified on 5 September 2026. Application changes are in `16104b9`, based on main `f1854d5`. Later changes in this PR document the results and repair historical links.

The cleanup removes unused detector implementations, screens, import code, helpers, and disconnected backend modules. It moves shared detector declarations into `SwingDetectionTypes.swift`, removes the empty V3 club-tracker lifecycle, and preserves the calculation. The reset backend drops ignored internal inputs and empty NPZ placeholders. Its supported video, track, coaching, and progress responses remain intact.

## Verification results

| Check | Result |
| --- | --- |
| Debug app and test build | Passed |
| Release simulator build | Passed |
| `scripts/verify-review.sh` | 7 passed, 0 failed, 0 skipped |
| Normal launch through Capture, Library, reference detail, paging | 1 passed, 0 failed, 0 skipped |
| `test_swing_detector_v3_evidence.py --build` | 24 checks passed |
| V2, V3 and legacy live-model evaluators | All three compiled |
| Synthetic reset pipeline | Frame count, dimensions, frame rate, decoded pixels, timeline, empty annotations/metrics, progress passed |
| Annotation track contract and run-state checks | Passed |
| Seeded smoothing | Ground-truth error, jitter and motion preservation passed |
| Animation export | Decoded actual GLTF buffer timing and joint coordinates passed |
| Fault probes | Identity smoother, frozen movement, unexpected reset metrics and failed export all rejected |
| Diff and documentation review | No functional findings; two stale documentation references corrected |

The seven review tests cover analysis identity during concurrent requests, stale retry callbacks, display geometry, starred ordering, vantage filtering, reference collection boundaries, and drawing after rotation. Screenshots were inspected alongside the assertions. Both simulator runs confirmed deletion of their owned disposable simulator after completion.

The fault-probe command first runs healthy output checks. It then injects faults only in its Python processes and requires the repaired tests to fail. The animation failure probe also checks the real script's nonzero exit status.

## Reproduce

Use the backend virtual environment with its base and temporal-smoothing requirements installed, plus FFmpeg and Xcode. Verification here reused the existing local backend environment. SAM inference is unnecessary for these synthetic checks.

```bash
backend/venv/bin/python backend/test_pipeline_3d.py
backend/venv/bin/python backend/test_annotation_tracks.py
backend/venv/bin/python backend/test_analysis_runs.py
backend/venv/bin/python backend/test_temporal_smoothing.py
backend/venv/bin/python backend/test_animation_export.py
backend/venv/bin/python docs/audits/slop_evidence.py --probe-tests
python3 detector_workbench/validation/test_swing_detector_v3_evidence.py --build
bash scripts/verify-review.sh
bash .agents/skills/verify-swingcoach/scripts/verify-library-paging.sh
```

The last helper requires the three ignored local reference MP4s described in `SwingCoach/ReferenceSwings/README.md`. The review regression helper generates its own synthetic media. Compiler commands for the retained evaluators are in `detector_workbench/validation`.

## Review

Standards review found no blocking violations or new code smells. It identified a broken historical source link, which was corrected.

Spec review found no functional mismatches. It identified the same historical link and stale instructions for the original fault probe, both corrected. The reviewers inspected `git diff f1854d5...16104b9` independently and did not modify code.

## Limits and local evidence

This change does not claim physical-camera, microphone, live detector performance, Photos import/export, R2 upload, or deployed-service verification. Those hardware and integration paths were not exercised. No detector thresholds or active capture algorithms changed. Manual heavy-model experiments remain available but were not run.

Ignored logs, screenshots, result bundles, instance checks, and cleanup reports are preserved under `.verification-artifacts/slop-cleanup/review` and `.verification-artifacts/slop-cleanup/normal-launch`. The Release build log is `.verification-artifacts/slop-cleanup/release-build.log`. No private footage or generated build products are committed.
