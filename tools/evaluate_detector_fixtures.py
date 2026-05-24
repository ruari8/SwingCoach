#!/usr/bin/env python3
"""Build trimmed swing-detector fixtures and score OnDeviceSwingDetector output."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path
from typing import Any


def run(command: list[str], verbose: bool = False) -> None:
    stdout = None if verbose else subprocess.DEVNULL
    stderr = None if verbose else subprocess.DEVNULL
    subprocess.run(command, check=True, stdout=stdout, stderr=stderr)


def overlaps(a_start: float, a_end: float, b_start: float, b_end: float) -> bool:
    return a_start <= b_end and b_start <= a_end


def fixture_name(kind: str, index: int, start: float, end: float) -> str:
    return f"{kind}_{index:03d}_{int(start)}_{int(end)}.mp4"


def build_clip(
    source_video: Path,
    output_path: Path,
    clip_start: float,
    clip_duration: float,
    width: int,
    fps: int,
    force: bool,
    verbose: bool,
) -> None:
    if output_path.exists() and not force:
        return

    output_path.parent.mkdir(parents=True, exist_ok=True)
    run(
        [
            "ffmpeg",
            "-y",
            "-ss",
            f"{clip_start:.3f}",
            "-i",
            str(source_video),
            "-t",
            f"{clip_duration:.3f}",
            "-map",
            "0:v:0",
            "-vf",
            f"fps={fps},scale={width}:-2",
            "-an",
            "-c:v",
            "libx264",
            "-preset",
            "ultrafast",
            "-crf",
            "28",
            "-movflags",
            "+faststart",
            str(output_path),
        ],
        verbose=verbose,
    )


def run_detector(
    evaluator: Path,
    clip_path: Path,
    sample_interval: float,
    max_frames: int,
    confidence_threshold: float,
    peak_threshold: float,
    motion_threshold: float,
) -> dict[str, Any]:
    completed = subprocess.run(
        [
            str(evaluator),
            str(clip_path),
            f"{sample_interval:.3f}",
            str(max_frames),
            f"{confidence_threshold:.3f}",
            f"{peak_threshold:.3f}",
            f"{motion_threshold:.3f}",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(completed.stdout)


def positive_cases(args: argparse.Namespace, windows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    fixtures_dir = args.output_dir / "fixtures"
    selected_windows = windows[: args.limit] if args.limit else windows
    cases = []

    for index, label in enumerate(selected_windows, start=1):
        label_start = float(label["start"])
        label_end = float(label["end"])
        clip_start = max(0.0, label_start - args.pre_roll)
        clip_end = label_end + args.post_roll
        clip_duration = clip_end - clip_start
        clip_path = fixtures_dir / fixture_name("positive", index, clip_start, clip_end)

        build_clip(
            source_video=args.video,
            output_path=clip_path,
            clip_start=clip_start,
            clip_duration=clip_duration,
            width=args.width,
            fps=args.fps,
            force=args.force_clips,
            verbose=args.verbose_ffmpeg,
        )

        raw = run_detector(
            args.evaluator,
            clip_path,
            args.sample_interval,
            args.max_frames,
            args.confidence_threshold,
            args.peak_threshold,
            args.motion_threshold,
        )
        detections = []
        matched = False
        false_positive_count = 0
        for detection in raw.get("detections", []):
            absolute = {
                "start": round(clip_start + float(detection["start"]), 3),
                "end": round(clip_start + float(detection["end"]), 3),
                "confidence": round(float(detection["confidence"]), 4),
            }
            absolute["overlaps_label"] = overlaps(
                absolute["start"],
                absolute["end"],
                label_start,
                label_end,
            )
            matched = matched or absolute["overlaps_label"]
            false_positive_count += 0 if absolute["overlaps_label"] else 1
            detections.append(absolute)

        cases.append(
            {
                "index": index,
                "kind": "positive",
                "label": {"start": label_start, "end": label_end},
                "clip": {
                    "path": str(clip_path),
                    "start": clip_start,
                    "end": clip_end,
                    "duration": clip_duration,
                },
                "matched": matched,
                "false_positive_count": false_positive_count,
                "detections": detections,
            }
        )

    return cases


def negative_windows(
    windows: list[dict[str, Any]],
    video_duration: float,
    clip_duration: float,
    margin: float,
    limit: int,
) -> list[dict[str, float]]:
    sorted_windows = sorted(
        ({"start": float(window["start"]), "end": float(window["end"])} for window in windows),
        key=lambda window: window["start"],
    )
    gaps: list[dict[str, float]] = []
    previous_end = 0.0

    for window in sorted_windows:
        gap_start = previous_end + margin
        gap_end = window["start"] - margin
        if gap_end - gap_start >= clip_duration:
            mid = (gap_start + gap_end) / 2
            clip_start = max(gap_start, mid - clip_duration / 2)
            gaps.append({"start": clip_start, "end": clip_start + clip_duration})
        previous_end = max(previous_end, window["end"])

    tail_start = previous_end + margin
    if video_duration - tail_start >= clip_duration:
        mid = (tail_start + video_duration) / 2
        clip_start = max(tail_start, mid - clip_duration / 2)
        gaps.append({"start": clip_start, "end": clip_start + clip_duration})

    return gaps[:limit] if limit else gaps


def negative_cases(args: argparse.Namespace, windows: list[dict[str, Any]], video_duration: float) -> list[dict[str, Any]]:
    fixtures_dir = args.output_dir / "fixtures"
    cases = []
    negatives = negative_windows(
        windows=windows,
        video_duration=video_duration,
        clip_duration=args.negative_duration,
        margin=args.negative_margin,
        limit=args.negative_limit,
    )

    for index, clip in enumerate(negatives, start=1):
        clip_start = float(clip["start"])
        clip_end = float(clip["end"])
        clip_duration = clip_end - clip_start
        clip_path = fixtures_dir / fixture_name("negative", index, clip_start, clip_end)

        build_clip(
            source_video=args.video,
            output_path=clip_path,
            clip_start=clip_start,
            clip_duration=clip_duration,
            width=args.width,
            fps=args.fps,
            force=args.force_clips,
            verbose=args.verbose_ffmpeg,
        )

        raw = run_detector(
            args.evaluator,
            clip_path,
            args.sample_interval,
            args.max_frames,
            args.confidence_threshold,
            args.peak_threshold,
            args.motion_threshold,
        )
        detections = [
            {
                "start": round(clip_start + float(detection["start"]), 3),
                "end": round(clip_start + float(detection["end"]), 3),
                "confidence": round(float(detection["confidence"]), 4),
            }
            for detection in raw.get("detections", [])
        ]

        cases.append(
            {
                "index": index,
                "kind": "negative",
                "label": None,
                "clip": {
                    "path": str(clip_path),
                    "start": clip_start,
                    "end": clip_end,
                    "duration": clip_duration,
                },
                "matched": len(detections) == 0,
                "false_positive_count": len(detections),
                "detections": detections,
            }
        )

    return cases


def evaluate(args: argparse.Namespace) -> dict[str, Any]:
    labels = json.loads(args.labels.read_text())
    windows = labels["positive_swing_windows"]
    timeline = labels.get("timeline_seconds", {})
    video_duration = float(
        labels.get("duration_seconds")
        or labels.get("approx_duration_seconds")
        or timeline.get("duration")
        or timeline.get("duration_approx")
        or 0
    )
    results_dir = args.output_dir / "results"
    results_dir.mkdir(parents=True, exist_ok=True)

    cases = positive_cases(args, windows)
    negatives = negative_cases(args, windows, video_duration) if args.negative_limit != 0 and video_duration > 0 else []

    summary = {
        "video": str(args.video),
        "labels": str(args.labels),
        "evaluator": str(args.evaluator),
        "parameters": {
            "sample_interval": args.sample_interval,
            "max_frames": args.max_frames,
            "confidence_threshold": args.confidence_threshold,
            "peak_threshold": args.peak_threshold,
            "motion_threshold": args.motion_threshold,
            "pre_roll": args.pre_roll,
            "post_roll": args.post_roll,
            "negative_duration": args.negative_duration,
            "negative_margin": args.negative_margin,
        },
        "positive_case_count": len(cases),
        "matched_count": sum(1 for case in cases if case["matched"]),
        "missed_count": sum(1 for case in cases if not case["matched"]),
        "false_positive_count": sum(case["false_positive_count"] for case in cases),
        "negative_case_count": len(negatives),
        "negative_false_positive_count": sum(case["false_positive_count"] for case in negatives),
        "cases": cases,
        "negative_cases": negatives,
    }
    output_path = results_dir / "detector_fixture_report.json"
    output_path.write_text(json.dumps(summary, indent=2))
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video", type=Path, default=Path(".videos/IMG_2592.mov"))
    parser.add_argument("--labels", type=Path, default=Path(".videos/IMG_2592.labels.json"))
    parser.add_argument("--evaluator", type=Path, default=Path(".videos/bin/evaluate_on_device_detector"))
    parser.add_argument("--output-dir", type=Path, default=Path(".videos/detector_eval"))
    parser.add_argument("--pre-roll", type=float, default=10.0)
    parser.add_argument("--post-roll", type=float, default=10.0)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--width", type=int, default=960)
    parser.add_argument("--sample-interval", type=float, default=0.12)
    parser.add_argument("--max-frames", type=int, default=900)
    parser.add_argument("--confidence-threshold", type=float, default=0.50)
    parser.add_argument("--peak-threshold", type=float, default=1.65)
    parser.add_argument("--motion-threshold", type=float, default=0.85)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--negative-limit", type=int, default=8)
    parser.add_argument("--negative-duration", type=float, default=40.0)
    parser.add_argument("--negative-margin", type=float, default=20.0)
    parser.add_argument("--force-clips", action="store_true")
    parser.add_argument("--verbose-ffmpeg", action="store_true")
    args = parser.parse_args()

    summary = evaluate(args)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
