# Performance findings

Measured on 2026-09-04, macOS 26.6.2 on Apple silicon, Python 3.14.6, FFmpeg 7.1.1. The baseline revision was `73cd63b` with unrelated iOS work in progress. This pass changed the reset backend pipeline and its verification tools. It did not measure deployed response time or physical-iPhone performance.

## Implemented: remove the full-video PNG round trip

The reset pipeline previously extracted every frame to a PNG file, loaded the entire sequence into Python, wrote another PNG sequence, and encoded it to H.264. Generated overlays are disabled, so no stage needed those images.

`VideoExporter.export_clean_video` now runs the conversion directly through FFmpeg. `ArtifactRenderer` takes video bytes and FPS, then probes the output MP4 to construct the empty per-frame overlay contract. Both compatibility video files remain available. This removes full-video image storage while retaining the existing playback semantics.

Three fresh-process samples per case produced these medians:

| Input and measurement | Before | After | Change |
| --- | ---: | ---: | ---: |
| 22.23-second, 720×1280 reference swing, 667 frames: pipeline time | 5.302 s | 1.739 s | 3.05× faster |
| Same input: Python peak RSS | 1,008.6 MiB | 51.7 MiB | 94.9% lower |
| Same input: child-process peak RSS | 565.5 MiB | 488.6 MiB | 13.6% lower |
| Generated three-second 1280×720 clip: pipeline time | 0.545 s | 0.303 s | 1.80× faster |
| Generated clip: Python peak RSS | 58.5 MiB | 42.4 MiB | 27.5% lower |

These are local measurements, not service-level latency promises. Other tasks were active on the machine during this session, and the samples were not interleaved. An earlier synthetic after-run took 0.593 seconds, showing why subsecond timing needs controlled machine load. The reference video's removed extraction stage alone took about 3.2 seconds. Its Python memory reduction was consistent across samples.

FFmpeg still buffers decoded frames for encoding, and Python still holds compressed input/output bytes and per-frame track records. The 94.9% reduction describes Python peak RSS, not total machine memory.

## Verification evidence

The real reference swing preserved 667 frames, 720×1280 dimensions, 30 FPS, and 22.233333-second duration. Whole-video PSNR against the former output was 35.84 dB. The generated clip measured 42.05 dB. Both exceeded the explicit 30 dB regression floor. Decoded frame 300 from the source, previous output, and new output was visually inspected. The conversion is lossy and avoids the old RGB intermediate, so byte-for-byte or pixel-for-pixel equality is not expected.

The offline runner passed seven artifact test methods, including multiple rotation/FPS cases, plus the run-state lifecycle check. A deliberately missing interpreter produced a nonzero readiness failure and retained its summary. An impossible benchmark speed threshold also failed with its report preserved.

Local ignored evidence from this session:

- `.verification-artifacts/backend-performance/real-before/report.json`
- `.verification-artifacts/backend-performance/real-final/report.json`
- `.verification-artifacts/backend-performance/before/report.json`
- `.verification-artifacts/backend-performance/synthetic-final/report.json`
- `.verification-artifacts/backend-performance/verification/summary.json`
- `.verification-artifacts/backend-performance/expected-readiness-failure/summary.json`
- `.verification-artifacts/backend-performance/expected-budget-failure/report.json`

Each benchmark folder retains the source and generated artifacts needed to inspect that run. These local evidence paths will not exist in a fresh clone. [Verification instructions](VERIFICATION.md) reproduce the generated cases without private data.

## Remaining targets, in priority order

These are code-backed candidates, not measured speedups.

| Target | Evidence | Next proof needed |
| --- | --- | --- |
| Duplicate cloud video uploads | `backend/main.py::_upload_run_artifacts` uploads `base.mp4` and `annotated.mp4` separately even though the reset renderer writes identical bytes. | Record download/upload stage time and bytes in an actual R2 run. Verify both API artifact fields and signed-URL refresh before sharing an object key or using server-side copying. |
| Main-thread library disk work | `SwingLibrary` is `@MainActor`; `addSwing` synchronously copies a local video, and `saveToDisk` encodes and writes the entire library. `AnalysisLibrary` also writes its complete JSON collection. | Seed a large library in an isolated app instance. Measure save/import latency and main-thread stalls in Release before moving writes to an ordered background store. Verify that saves, deletions, and app restarts retain the correct data. |
| Long-video detector import | `SwingDetectorV3AssetDetector.detectSwings` reads every source sample; the detector chooses which samples receive model processing. | Separate decode time from YOLO and Vision time on a physical iPhone. Compare detection events and frame timestamps against the same labeled fixture before changing sampling or decode resolution. |
| Detector benchmark reproducibility | `evaluate_detector_test_v3_performance.py` uses a shared work directory and skips missing fixture videos. It measures the workbench path, not physical-iPhone capture. | Give runs unique output locations, record the actual fixture coverage and evaluator build, and require the intended fixture set before accepting a comparison. |

## Agent verification improvements delivered

The backend now has a single offline check command with readiness checks, retained logs, a summary, timeouts, and nonzero failures. Its fixtures are generated, so a fresh worktree needs NumPy and FFmpeg rather than cloud credentials, model downloads, or an ignored personal video.

The benchmark records source, input hashes, environment, per-stage timings, process memory, output metadata, and decoded pixel similarity. A configurable speed threshold makes performance claims executable on a comparable machine. The existing disposable-simulator workflow remains the route for iOS behavior. It was inspected but not changed or run for this backend-only implementation.

The FFmpeg command uses explicit frame-number timestamps and constant-rate output. See the official [timestamp filter documentation](https://ffmpeg.org/ffmpeg-filters.html#setpts_002c-asetpts) and [frame-rate mode documentation](https://ffmpeg.org/ffmpeg.html#Advanced-options) for the underlying behavior.
