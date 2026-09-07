#!/usr/bin/env python3
"""Read decoded video presentation times without changing private source media."""
import argparse
from collections import Counter
import json
import hashlib
from pathlib import Path
import statistics
import subprocess


def summarize(times, threshold):
    gaps = [(a, b) for a, b in zip(times, times[1:]) if b - a > threshold]
    deltas = [b - a for a, b in zip(times, times[1:])]
    return {
        "decoded_frames": len(times),
        "first_pts_seconds": times[0] if times else None,
        "last_pts_seconds": times[-1] if times else None,
        "median_interval_seconds": statistics.median(deltas) if deltas else None,
        "max_interval_seconds": max(deltas) if deltas else None,
        "non_increasing_pts": sum(d <= 0 for d in deltas),
        "interval_histogram_ms": dict(sorted(Counter(round(d * 1000, 1) for d in deltas).items())),
        "gap_count": len(gaps),
        "gaps_seconds": [[a, b] for a, b in gaps],
    }


def analyze(path, threshold):
    result = subprocess.run([
        "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_frames",
        "-show_streams", "-show_entries",
        "frame=best_effort_timestamp_time:stream=codec_name,width,height,r_frame_rate,avg_frame_rate,time_base,duration,nb_frames",
        "-of", "json", str(path)
    ], capture_output=True, text=True, check=True)
    data = json.loads(result.stdout)
    times = [float(f["best_effort_timestamp_time"]) for f in data["frames"]]
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return {"file": path.name, "sha256": digest.hexdigest(), "size_bytes": path.stat().st_size, "stream": data["streams"][0],
            "decode_errors": result.stderr.strip(), **summarize(times, threshold)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--gap-seconds", type=float, default=0.075,
                        help="Report decoded PTS intervals above this duration; default 75ms for 30fps slow-motion exports")
    parser.add_argument("--assert-no-gaps", action="store_true")
    args = parser.parse_args()
    if args.gap_seconds <= 0:
        parser.error("--gap-seconds must be positive")
    paths = sorted(args.directory.glob("jit_*.MP4")) + sorted(args.directory.glob("auto_swing_*.MP4"))
    if not paths:
        parser.error("No jit_*.MP4 or auto_swing_*.MP4 inputs")
    reports = []
    for path in paths:
        report = analyze(path, args.gap_seconds)
        reports.append(report)
        print(f"{path.name}: {report['decoded_frames']} frames, {report['gap_count']} gaps > {args.gap_seconds}s, max {report['max_interval_seconds']:.3f}s", flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({"ffprobe_version": subprocess.check_output(["ffprobe", "-version"], text=True).splitlines()[0], "gap_threshold_seconds": args.gap_seconds, "clips": reports}, indent=2) + "\n")
    if args.assert_no_gaps and any(r["gap_count"] or r["decode_errors"] or r["non_increasing_pts"] for r in reports):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
