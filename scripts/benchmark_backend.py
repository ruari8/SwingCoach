#!/usr/bin/env python3
"""Measure the real local pipeline in fresh processes, without R2 or model weights."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import resource
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def command(args: list[str], **kwargs) -> str:
    result = subprocess.run(args, capture_output=True, text=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f"Command failed: {args}\n{result.stderr}")
    return result.stdout


def probe(path: Path) -> dict:
    data = json.loads(command([
        "ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
        "-show_entries", "stream=codec_name,pix_fmt,width,height,nb_read_frames,r_frame_rate,duration",
        "-of", "json", str(path),
    ]))
    return data["streams"][0]


def compare_pixels(previous: Path, current: Path) -> dict:
    result = subprocess.run([
        "ffmpeg", "-nostdin", "-i", str(previous), "-i", str(current),
        "-filter_complex", "[0:v]setpts=PTS-STARTPTS[a];[1:v]setpts=PTS-STARTPTS[b];[a][b]psnr",
        "-an", "-f", "null", "-",
    ], capture_output=True, text=True)
    match = re.search(r"PSNR .*average:([\d.inf]+)", result.stderr)
    if result.returncode or match is None:
        raise RuntimeError(f"Video comparison failed: {result.stderr}")
    psnr = float(match[1])
    if psnr < 30:
        raise RuntimeError(f"Output pixels changed: PSNR {psnr:.2f} dB is below the 30 dB regression threshold")
    return {"psnr_db": psnr if psnr != float("inf") else "infinite", "minimum_psnr_db": 30}


def worker(video: Path, output: Path, fps: float | None) -> None:
    sys.path.insert(0, str(ROOT / "backend"))
    from analysis.pipeline_3d import SwingCoachPipeline3D

    started = time.perf_counter()
    result = SwingCoachPipeline3D(output_root=str(output)).analyze_video(
        video.read_bytes(), requested_fps=fps,
    )
    elapsed = time.perf_counter() - started
    # macOS reports bytes; Linux reports KiB. These are separate high-water marks,
    # not a simultaneous sum of the process tree's memory.
    divisor = 1024 * 1024 if sys.platform == "darwin" else 1024
    print(json.dumps({
        "wall_seconds": elapsed,
        "python_peak_rss_mib": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / divisor,
        "child_peak_rss_mib": resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss / divisor,
        "stages": result.quality["timings"],
        "run_dir": result.run_dir,
    }))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video", type=Path, help="Local input; defaults to a generated 3-second 720p clip")
    parser.add_argument("--output", type=Path, required=True, help="New evidence directory, never overwritten")
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--fps", type=float, help="Exercise the pipeline's playback FPS override")
    parser.add_argument("--compare", type=Path, help="Prior report.json using the same input and settings")
    parser.add_argument("--min-speedup", type=float, help="Fail below this speedup; requires --compare and a comparable machine")
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.worker:
        worker(args.video, args.output, args.fps)
        return
    if args.runs < 1:
        parser.error("--runs must be at least 1")
    if args.min_speedup is not None and (not args.compare or args.min_speedup <= 0):
        parser.error("--min-speedup must be positive and requires --compare")
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    if args.video:
        video = args.video.resolve()
    else:
        video = args.output / "input.mp4"
        command([
            "ffmpeg", "-v", "error", "-f", "lavfi", "-i",
            "testsrc2=size=1280x720:rate=30:duration=3", "-c:v", "libx264",
            "-preset", "fast", "-pix_fmt", "yuv420p", str(video),
        ])
    identity = {
        "sha256": hashlib.sha256(video.read_bytes()).hexdigest(),
        "requested_fps": args.fps,
    }
    previous = json.loads(args.compare.read_text()) if args.compare else None
    if previous and any(previous["input"][key] != value for key, value in identity.items()):
        parser.error("Comparison requires identical input bytes and FPS override")
    report = {
        "input": {"path": str(video), **identity, "stream": probe(video)},
        "environment": {
            "python": sys.version, "platform": platform.platform(),
            "ffmpeg": command(["ffmpeg", "-version"]).splitlines()[0],
            "git_revision": command(["git", "rev-parse", "HEAD"], cwd=ROOT).strip(),
            "git_status": command(["git", "status", "--short"], cwd=ROOT),
        },
        "samples": [],
    }
    # Keep the actual code diff next to the measurements, including new Python files.
    (args.output / "source.diff").write_text(command(["git", "diff", "--", "backend", "scripts"], cwd=ROOT))
    source_dir = args.output / "source"
    for source in [*sorted((ROOT / "backend" / "analysis").glob("*.py")), Path(__file__).resolve()]:
        destination = source_dir / source.relative_to(ROOT)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(source.read_bytes())
    for index in range(args.runs):
        cmd = [sys.executable, str(Path(__file__).resolve()), "--worker", "--video", str(video),
               "--output", str(args.output / f"sample-{index + 1}")]
        if args.fps is not None:
            cmd += ["--fps", str(args.fps)]
        sample = json.loads(command(cmd))
        run_dir = Path(sample["run_dir"])
        stream = probe(run_dir / "base.mp4")
        tracks = json.loads((run_dir / "annotation_tracks.json").read_text())
        metadata = json.loads((run_dir / "annotation_metadata.json").read_text())
        count = int(stream["nb_read_frames"])
        assert count > 0 and count == len(tracks["frames"]) == metadata["frame_count"]
        assert (stream["width"], stream["height"]) == (tracks["frame_width"], tracks["frame_height"])
        assert (run_dir / "base.mp4").read_bytes() == (run_dir / "annotated.mp4").read_bytes()
        assert metadata["layers"] == [] and all(frame["layers"] == {} for frame in tracks["frames"])
        sample["output_stream"] = stream
        sample["output_bytes"] = (run_dir / "base.mp4").stat().st_size
        report["samples"].append(sample)
        print(f"Run {index + 1}: {sample['wall_seconds']:.3f}s; Python peak {sample['python_peak_rss_mib']:.1f} MiB", flush=True)
    report["medians"] = {
        key: statistics.median(sample[key] for sample in report["samples"])
        for key in ("wall_seconds", "python_peak_rss_mib", "child_peak_rss_mib")
    }
    if previous:
        assert previous["samples"][0]["output_stream"] == report["samples"][0]["output_stream"], "Output video contract changed"
        report["comparison"] = {
            "baseline": str(args.compare.resolve()),
            "speedup": previous["medians"]["wall_seconds"] / report["medians"]["wall_seconds"],
            "python_peak_rss_reduction_percent": 100 * (1 - report["medians"]["python_peak_rss_mib"] / previous["medians"]["python_peak_rss_mib"]),
            "pixels": compare_pixels(
                Path(previous["samples"][0]["run_dir"]) / "base.mp4",
                Path(report["samples"][0]["run_dir"]) / "base.mp4",
            ),
        }
    (args.output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"medians": report["medians"], "comparison": report.get("comparison")}, indent=2))
    if args.min_speedup is not None and report["comparison"]["speedup"] < args.min_speedup:
        raise SystemExit(f"FAIL: speedup below {args.min_speedup}; evidence: {args.output / 'report.json'}")
    print(f"PASS: {args.output / 'report.json'}")


if __name__ == "__main__":
    main()
