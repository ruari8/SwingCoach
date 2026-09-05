# SwingCoach slop audit

Audited 4 September 2026, starting at `73cd63b`, with working-tree changes present. Other tasks were editing the app during this audit. Source locations may move. This audit adds this report and `slop_evidence.py`; it changes no application behavior.

## Assessment

The dominant problem is incomplete removal after a replacement. Old detectors, screens, and pipeline contracts remain beside their successors. There are also tests that report success without proving their stated behavior.

The first cleanup should remove unused code and misleading interfaces. A broad architectural rewrite would add risk before addressing the clearest problems. Approximately 2,300 lines across four unused detector implementations are credible deletion candidates, after preserving their shared types. This is a source maintenance estimate, not a measured binary-size or performance saving.

I inventoried 107 tracked Swift and Python files, approximately 41,000 lines, then traced selected candidates through app entry points, callers, evaluator source lists, tests, and canonical docs. This is a targeted repository audit, not a claim to have reviewed every line or exhaustively proven runtime reachability. No simulator, camera, model inference, R2, or deployed service was exercised.

## Findings, in cleanup order

### 1. Remove four unused detector implementations, preserving shared types

**High value; high confidence in repository caller evidence.**

No tracked source instantiates these types:

| Candidate | Location | Approximate removable lines |
| --- | --- | ---: |
| `OnDeviceSwingDetector` and its private helpers | [OnDeviceSwingDetector.swift](../../SwingCoach/Models/OnDeviceSwingDetector.swift), from line 36 | 581 |
| `LiveSwingDetector` and its private helpers | [LiveSwingDetector.swift](../../SwingCoach/Models/LiveSwingDetector.swift), from line 52 | 939 |
| `ModelBackedSwingDetector` actor | [ModelBackedSwingDetector.swift](../../SwingCoach/Models/ModelBackedSwingDetector.swift), lines 486 through 1149 | 664 |
| `SwingDetectorV2AssetDetector` | [SwingDetectorV2AssetDetector.swift](../../SwingCoach/Models/SwingDetectorV2AssetDetector.swift) | 119 |

Capture and Replay Debug construct `SwingDetectorV3`; Trim constructs `SwingDetectorV3AssetDetector`. The older source filenames still occur in evaluator build lists because they contain shared declarations. `DetectedSwing` lives above the unused on-device actor. `LiveSwingDetectionStatus` and `LiveSwingDetectionSnapshot` live above the unused live detector.

`ModelBackedSwingDetector.swift` also contains `LiveModelSwingDetector`, which **does** have a caller in `evaluate_live_model_detector.swift`. Keep that experiment and its supporting types unless it is deliberately retired. Likewise, V2 has a working evaluator and cannot be classified as wholly unused.

Extract the shared declarations to a clearly named file, update evaluator source lists, and remove the four unused implementations. Check the app build and V2/V3 evaluator builds after the cut. These files belong to Xcode's synchronized app group; being unused does not exclude their source from target membership.

### 2. Replace tests that can pass while the advertised behavior is absent

**High value; demonstrated with controlled failure probes.**

- [test_temporal_smoothing.py](../../backend/test_temporal_smoothing.py), `test_synthetic_noisy_sequence`, line 194, prints a jitter reduction and returns `True` without asserting an improvement. Replacing `smooth_poses` with an identity function produced **0% improvement and “Synthetic test passed.”** Use a seeded trajectory and check error against the known motion, plus a meaningful jitter bound. Checking jitter alone would also reward flattening the entire swing.
- [test_animation_export.py](../../backend/test_animation_export.py), line 85 and the script entry point, catches failures and returns booleans. The entry point logs them without a failing exit status. Forcing `export_animation` to return `False` produced a logged failure and normal script termination. Fail the command when an expected export fails, and inspect the generated animation before treating it as a regression test. Preserve a manual demo separately if that is the intended purpose.
- [test_pipeline_3d.py](../../backend/test_pipeline_3d.py), line 16, checks the absence of three attribute names. It passes without calling `analyze_video` at all, even when that method is replaced with a function that would fail immediately. Replace this with an output-contract check. The separate `main()` does process video, but primarily logs results; it does not make the attribute test behavioral.

These findings do not justify deleting the test suite. The annotation-track contract test and run-state test both passed during this audit and assert observable results. The visual tests check pixels, and the V3 evidence tests exercise useful adversarial cases. Keep those.

### 3. Finish removing superseded UI and import code

**High value; high confidence in source evidence.**

[AnalyseView.swift](../../SwingCoach/AnalyseView.swift) still defines the roughly 128-line `AnalysisCard` at line 480. It has no caller. The dashboard uses `AnalysisQueueRow` and `RecentAnalysisRow`.

[LibraryView.swift](../../SwingCoach/LibraryView.swift) still has an uncalled `loadAndPlay` function. It is the only path that sets the old full-screen playback and loading state to true. The associated state, cover, loading overlay, and error alert therefore remain after card navigation moved to swing detail. Remove that branch together. **Keep `SwingPlaybackView` and the shared playback controls**, which have other callers.

`VideoFileTransferable` only refers to itself in its transfer representation; the import flow uses `VideoPickerWithProgress`. `ContentView` is the template “Hello, Golf!” screen, referenced only by its own preview. `TrimSession` in `SwingClip.swift` has no caller. These are small, straightforward deletion candidates.

Verify library-card navigation, import-to-trim, and the remaining playback entry points after removing this code. Coordinate Library changes with the concurrent task before applying them.

### 4. Delete or explicitly retain orphaned backend experiments

**Medium value; high confidence within tracked source, external scripts unverified.**

These modules have no imports or callers in the tracked Python or Swift source:

- [body3d_runner.py](../../backend/analysis/body3d_runner.py), 83 lines.
- [club3d_fuser.py](../../backend/analysis/club3d_fuser.py), 222 lines.
- [event_window_selector.py](../../backend/analysis/event_window_selector.py), 66 lines.

That is 371 lines of disconnected pipeline code. The reset pipeline no longer uses their orchestration. Delete them if the historical implementation in git is sufficient, or retain them under an explicit experiment with a real entry point. Do not leave them looking like components of the current pipeline.

This finding is deliberately narrower than “delete all old ML code.” Several dormant modules still have manual experiments and tests. `CoachResponseBuilder.answer_chat` is called by `/chat`; deleting the entire builder would break a current endpoint.

### 5. Remove inert inputs from the reset renderer

**Medium value; confirmed by AST inspection and callers.**

[ArtifactRenderer.render](../../backend/analysis/artifact_renderer.py), line 56, accepts six parameters it never reads: `poses2d`, `club2d_frames`, `poses3d`, `club3d_frames`, `swing_phases`, and `export_baked_overlays`. The pipeline supplies empty values to satisfy this obsolete signature. Even passing `export_baked_overlays=True` cannot enable overlays.

[pipeline_3d.py](../../backend/analysis/pipeline_3d.py) also accepts `max_dense_frames`, but only records it as metadata. The test CLI still claims `--max-dense` caps frames for faster runs. Remove the inert parameter and option rather than implying they work.

The pipeline writes four empty pose/club NPZ files. No tracked consumer reads those filenames. They are documented artifacts, so removing them requires updating the backend docs and checking for any local consumers. Keep the current public video and track response fields while compatibility requires them. Empty overlay output itself is an explicit product decision, not a defect identified by this audit.

### 6. Remove the pretend lifecycle from `ClubTrackerV3`

**Small, clear simplification; high confidence.**

[ClubTrackerV3.swift](../../SwingCoach/Models/SwingDetectorV3/ClubTrackerV3.swift), lines 29 through 34, defines a state-free class with an empty `reset()` and an `update(frame:lock:)` that does nothing. `SwingDetectorV3` owns it, resets it, and calls its update method before computing evidence from the supplied frame window.

Expose the evidence calculation as a static function or equivalent value operation, then delete the object ownership and lifecycle calls. This removes a misleading dependency on previous updates. The same pattern exists in V2, but changing the retained baseline is a separate choice. Preserve the evidence calculation and verify its existing behavior tests; the calculation itself is useful.

### 7. Remove abandoned convenience methods and choose one expiry rule

**Small cleanup; high confidence in caller evidence.**

[AnalysisLibrary.swift](../../SwingCoach/Models/AnalysisLibrary.swift), line 178, has an unused `updateAnnotatedVideoURL` wrapper around `updateAnnotatedVideoURLs`. Its `needsArtifactRefresh` method is also unused, while `AnnotatedAnalysisVideo.prepareArtifacts` separately hardcodes the same 45-minute rule in [AnalysisResultView.swift](../../SwingCoach/AnalysisResultView.swift), line 698.

Delete the unused wrapper. Put the expiry rule where the actual caller can use it, or remove the unused alternative. Leaving two implementations suggests a shared policy that does not exist.

Other low-risk candidates include the uncalled one-line `VideoTrimmer.getDuration`, `VideoTrimmer.clipsDirectory`, `SwingLibrary.updateSwing`, and `SwingLibrary.getVideoURL`. Check callers again immediately before deleting because other tasks are active.

## What I would preserve

- V2 and legacy model evaluators with real entry points, reviewed labels, and evidence reports. Comparing experiments is a legitimate use, even if the product uses V3.
- The explicit annotation reset and its public compatibility contract. Canonical docs say the reset is intentional.
- The `/analyze` compatibility endpoint. The iOS client actually falls back to it after a 404 or 405 from `/analysis-runs`.
- Saved-data decoding and old overlay playback until compatibility requirements are resolved. A current empty backend response does not prove older saved analyses are absent.
- Small SwiftUI view helpers and framework adapters that improve readability or satisfy a protocol. A short body alone is not evidence of waste.
- Capture/media complexity that handles actual permissions, slow-motion timelines, asynchronous exports, and camera lifecycle. File size alone is not a reason to rewrite it.

## Reproduce the evidence

From the repository root:

```bash
python3 docs/audits/slop_evidence.py
backend/venv/bin/python docs/audits/slop_evidence.py --probe-tests
backend/venv/bin/python backend/test_analysis_runs.py
backend/venv/bin/python backend/test_annotation_tracks.py
```

All four commands completed successfully during the audit. The probe command succeeds when it reproduces the documented weaknesses; it is **not** a product acceptance test. Replacements exist only in that Python process. No production methods were edited.

The source scan includes declarations and comments and cannot establish safe deletion by itself. Findings above add caller and behavior inspection. The script intentionally stays small and specific to this audit.

## Recommended first change

Remove the unused UI and helpers, then extract the shared detector declarations and remove the four unused implementations. Keep these separate from performance work. Repair the misleading tests in a second change, and simplify the reset backend contract in a third. Update the canonical feature docs alongside any removal that changes documented behavior or commands.
