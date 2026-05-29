#!/usr/bin/env python3
"""Score the Swift/Core ML live model detector on labelled range fixtures."""

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


def run_detector(args: argparse.Namespace, clip_path: Path) -> dict[str, Any]:
    command = [
        str(args.evaluator),
        str(clip_path),
        str(args.model),
        f"{args.sample_fps:.3f}",
        f"{args.time_scale:.3f}",
        str(args.max_frames),
        "",
        str(args.min_strong_motion_frames),
        f"{args.min_mean_club_motion:.6f}",
        f"{args.min_club_path_span:.6f}",
        f"{args.max_club_top_y:.6f}",
    ]
    if args.impact_confirmation_post_roll is not None:
        command.extend([
            f"{args.time_scale:.3f}",
            "",
            "",
            f"{args.impact_confirmation_post_roll:.3f}",
        ])

    completed = subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(completed.stdout)


def raw_to_absolute_detections(
    raw: dict[str, Any],
    clip_start: float,
    detection_stream: str,
) -> list[dict[str, float]]:
    detections: list[dict[str, float]] = []
    for detection in raw.get(detection_stream, []):
        output = {
            "start": round(clip_start + float(detection["start"]), 3),
            "end": round(clip_start + float(detection["end"]), 3),
            "confidence": round(float(detection["confidence"]), 4),
        }
        if "impactTime" in detection:
            output["impact_time"] = round(clip_start + float(detection["impactTime"]), 3)
        if detection.get("declaredAt") is not None:
            output["declared_at"] = round(clip_start + float(detection["declaredAt"]), 3)
        if detection.get("latencyFromEnd") is not None:
            output["latency_from_end"] = round(float(detection["latencyFromEnd"]), 3)
        detections.append(output)
    return detections


def positive_cases(args: argparse.Namespace, windows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    fixtures_dir = args.output_dir / "fixtures"
    selected_windows = windows[: args.limit] if args.limit else windows
    cases: list[dict[str, Any]] = []

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

        raw = run_detector(args, clip_path)
        detections = raw_to_absolute_detections(raw, clip_start, args.detection_stream)
        for detection in detections:
            detection["overlaps_label"] = overlaps(
                detection["start"],
                detection["end"],
                label_start,
                label_end,
            )
            if detection["overlaps_label"] and "declared_at" in detection:
                offset = round(float(detection["declared_at"]) - label_end, 3)
                detection["declared_offset_from_label_end"] = offset
                detection["latency_from_label_end"] = round(max(0.0, offset), 3)
                detection["latency_from_label_end_realtime"] = round(
                    detection["latency_from_label_end"] / max(1.0, args.time_scale),
                    3,
                )

        matched_label_latencies = [
            detection["latency_from_label_end"]
            for detection in detections
            if detection.get("overlaps_label") and "latency_from_label_end" in detection
        ]
        matched_label_realtime_latencies = [
            detection["latency_from_label_end_realtime"]
            for detection in detections
            if detection.get("overlaps_label") and "latency_from_label_end_realtime" in detection
        ]

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
                "matched": any(detection["overlaps_label"] for detection in detections),
                "false_positive_count": sum(1 for detection in detections if not detection["overlaps_label"]),
                "mean_latency_from_label_end": round(sum(matched_label_latencies) / len(matched_label_latencies), 3)
                if matched_label_latencies
                else None,
                "mean_latency_from_label_end_realtime": round(
                    sum(matched_label_realtime_latencies) / len(matched_label_realtime_latencies),
                    3,
                )
                if matched_label_realtime_latencies
                else None,
                "detections": detections,
                "processed_frames": raw.get("processedFrames"),
                "average_processing_time_ms": raw.get("averageProcessingTimeMS"),
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
    negatives = negative_windows(
        windows=windows,
        video_duration=video_duration,
        clip_duration=args.negative_duration,
        margin=args.negative_margin,
        limit=args.negative_limit,
    )
    cases: list[dict[str, Any]] = []

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

        raw = run_detector(args, clip_path)
        detections = raw_to_absolute_detections(raw, clip_start, args.detection_stream)
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
                "processed_frames": raw.get("processedFrames"),
                "average_processing_time_ms": raw.get("averageProcessingTimeMS"),
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

    positives = positive_cases(args, windows)
    negatives = negative_cases(args, windows, video_duration) if args.negative_limit != 0 and video_duration > 0 else []
    positive_label_latencies = [
        case["mean_latency_from_label_end"]
        for case in positives
        if case["mean_latency_from_label_end"] is not None
    ]
    positive_label_realtime_latencies = [
        case["mean_latency_from_label_end_realtime"]
        for case in positives
        if case["mean_latency_from_label_end_realtime"] is not None
    ]
    report = {
        "video": str(args.video),
        "labels": str(args.labels),
        "evaluator": str(args.evaluator),
        "model": str(args.model),
        "parameters": {
            "sample_fps": args.sample_fps,
            "time_scale": args.time_scale,
            "max_frames": args.max_frames,
            "pre_roll": args.pre_roll,
            "post_roll": args.post_roll,
            "negative_duration": args.negative_duration,
            "negative_margin": args.negative_margin,
            "min_strong_motion_frames": args.min_strong_motion_frames,
            "min_mean_club_motion": args.min_mean_club_motion,
            "min_club_path_span": args.min_club_path_span,
            "max_club_top_y": args.max_club_top_y,
            "detection_stream": args.detection_stream,
            "impact_confirmation_post_roll": args.impact_confirmation_post_roll,
        },
        "positive_case_count": len(positives),
        "matched_count": sum(1 for case in positives if case["matched"]),
        "missed_count": sum(1 for case in positives if not case["matched"]),
        "false_positive_count": sum(case["false_positive_count"] for case in positives),
        "mean_latency_from_label_end": round(sum(positive_label_latencies) / len(positive_label_latencies), 3)
        if positive_label_latencies
        else None,
        "mean_latency_from_label_end_realtime": round(
            sum(positive_label_realtime_latencies) / len(positive_label_realtime_latencies),
            3,
        )
        if positive_label_realtime_latencies
        else None,
        "negative_case_count": len(negatives),
        "negative_false_positive_count": sum(case["false_positive_count"] for case in negatives),
        "cases": positives,
        "negative_cases": negatives,
    }

    output_path = args.output_dir / "results" / "live_model_detector_fixture_report.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2) + "\n")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video", type=Path, default=Path(".videos/IMG_2592.mov"))
    parser.add_argument("--labels", type=Path, default=Path(".videos/IMG_2592.labels.json"))
    parser.add_argument("--evaluator", type=Path, default=Path(".videos/bin/evaluate_live_model_detector"))
    parser.add_argument("--model", type=Path, default=Path("SwingCoach/MLModels/SwingObjectsYOLO11n.mlpackage"))
    parser.add_argument("--output-dir", type=Path, default=Path(".videos/live_model_detector_fixture_eval"))
    parser.add_argument("--sample-fps", type=float, default=16.0)
    parser.add_argument("--time-scale", type=float, default=8.0)
    parser.add_argument("--max-frames", type=int, default=300)
    parser.add_argument("--min-strong-motion-frames", type=int, default=2)
    parser.add_argument("--min-mean-club-motion", type=float, default=0.05)
    parser.add_argument("--min-club-path-span", type=float, default=0.32)
    parser.add_argument("--max-club-top-y", type=float, default=0.58)
    parser.add_argument("--impact-confirmation-post-roll", type=float, default=0.20)
    parser.add_argument(
        "--detection-stream",
        choices=("detections", "impactCenteredDetections", "hybridImpactDetections"),
        default="detections",
    )
    parser.add_argument("--pre-roll", type=float, default=10.0)
    parser.add_argument("--post-roll", type=float, default=10.0)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--width", type=int, default=960)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--negative-limit", type=int, default=8)
    parser.add_argument("--negative-duration", type=float, default=40.0)
    parser.add_argument("--negative-margin", type=float, default=20.0)
    parser.add_argument("--force-clips", action="store_true")
    parser.add_argument("--verbose-ffmpeg", action="store_true")
    args = parser.parse_args()

    print(json.dumps(evaluate(args), indent=2))


if __name__ == "__main__":
    main()
