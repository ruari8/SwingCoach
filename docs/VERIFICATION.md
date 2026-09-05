# Run offline checks and performance comparisons

## Set up the backend check

Run these commands from the repository root if a backend Python environment is not already available:

```bash
python3 -m venv backend/venv
backend/venv/bin/python -m pip install -r backend/requirements-verification.txt
```

Install FFmpeg 6 or later with `ffprobe` and the `libx264` encoder on PATH. The test fixtures use FFmpeg's `-display_rotation` option. The offline pipeline check needs NumPy, but does not need the API server dependencies, R2 credentials, model weights, or downloaded videos.

Run:

```bash
python3 scripts/verify_backend.py
```

The runner chooses `backend/venv/bin/python` when present, otherwise its own Python. Use `--python /absolute/path/to/python` to choose another interpreter. The result must end with successful artifact and lifecycle checks and return exit status zero.

Each run creates a unique `.verification-artifacts/backend/<id>/` directory containing readiness logs, Git revision and working changes, test logs, and `summary.json`. A missing tool, failing assertion, or a command exceeding 120 seconds makes verification fail. An explicit `--output` must name a new directory.

The artifact tests run the actual pipeline and FFmpeg. They check:

- All frames, output duration, H.264/yuv420p, silent playback, and progressive MP4 layout.
- 90, 180, and 270 degree rotation, including decoded pixel orientation.
- Slower, faster, and fractional FPS overrides, variable input timestamps, and missing input frame counts.
- Empty overlays, exact per-frame track timestamps, identical compatibility videos, and successful pipeline progress.
- Decoded pixel similarity against both the source and the previous PNG conversion, with a 30 dB PSNR regression floor.
- Invalid video and FPS failures, and a guard against reintroducing full-video PNG extraction.

The run-state check covers event order and terminal success. These commands do not prove HTTP, SSE transport, R2 upload, or iOS playback integration.

## Measure a change

Capture a baseline before editing:

```bash
backend/venv/bin/python scripts/benchmark_backend.py \
  --output .verification-artifacts/performance/before
```

This generates a three-second 1280×720 input and runs the actual pipeline three times in fresh Python processes. After editing, reuse those exact input bytes:

```bash
backend/venv/bin/python scripts/benchmark_backend.py \
  --video .verification-artifacts/performance/before/input.mp4 \
  --output .verification-artifacts/performance/after \
  --compare .verification-artifacts/performance/before/report.json
```

For a representative video, pass `--video /absolute/path/to/video.mp4` in both calls. Use `--fps` to exercise a playback-rate override and `--runs` to change the sample count. Keep CPU load, interpreter, FFmpeg version, and machine comparable. Avoid running builds or other benchmarks during measurement.

The report records input hash, environment, each sample, median pipeline time, stage timings, Python peak RSS, and child-process peak RSS. The two memory numbers are separate high-water marks, not simultaneous total memory. Timings exclude process startup, output verification, and cloud transfers. The benchmark also retains the analysis source snapshot, Git diff, and generated run artifacts. Treat fixture-derived media as local evidence and keep it ignored.

Comparison requires the same input hash and FPS override. It checks the output stream contract and a whole-video decoded PSNR floor of 30 dB against the baseline. This catches substantial image changes but does not replace visual review. A successful comparison reports speed even when a change is slower. Add `--min-speedup 1.1` to require at least a 10% improvement on a comparable machine. A failed speed threshold retains `report.json` and exits nonzero.

## Use a separate worktree

Run the scripts from the worktree containing the change. Each script resolves source paths from its own location. Point `--python` at an existing environment to avoid reinstalling dependencies, or create a worktree-local environment with the setup above. Invoke the benchmark with the desired Python executable directly.

Use different evidence directories for concurrent tasks. Generated fixtures need no copying from the original checkout. Real videos can be supplied by absolute path. Neither backend script starts a server, changes a branch, or touches a simulator.

## Verify iOS behavior

Use the existing [verify-swingcoach skill](../.agents/skills/verify-swingcoach/SKILL.md) and its feature map. The library paging helper owns a disposable simulator, scratch checkout, and DerivedData directory. Its ignored reference videos must exist in the invoking checkout. The backend fixtures above do not replace those videos.

Use a physical iPhone for camera rate, detector throughput, thermal behavior, and Photos interoperability. Simulator assertions prove the driven UI behavior but do not establish device performance. Record the device, OS, build configuration, input, and before/after measurements with any performance claim.
