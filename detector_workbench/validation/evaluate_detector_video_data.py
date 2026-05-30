#!/usr/bin/env python3
"""Run the live model detector across exported single-swing videos.

The exported `detector_model/video_data` directory is treated as a library of
one-swing clips. This harness infers the playback time scale from clip duration,
runs the same Swift/Core ML evaluator used by the V3 detector tests, and writes
repeatable per-video reports plus an aggregate pass/fail summary.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_VIDEO_DIR = Path("detector_model/video_data")
DEFAULT_METADATA = DEFAULT_VIDEO_DIR / "metadata.json"
DEFAULT_FRAME_MANIFEST = Path("detector_model/frame_dataset/dataset_manifest.json")
DEFAULT_LABELS = Path("detector_workbench/validation/labels/detector_video_data_labels.json")
DEFAULT_EVALUATOR = Path(".videos/bin/evaluate_live_model_detector")
DEFAULT_MODEL = Path("SwingCoach/MLModels/SwingObjectsYOLO11n.mlpackage")
DEFAULT_OUTPUT_DIR = Path(".videos/detector_video_data_eval")


@dataclass(frozen=True)
class RoughImpact:
    time_seconds: float
    frame_index: int


@dataclass(frozen=True)
class Case:
    filename: str
    video_path: Path
    duration: float
    source_time_scale: float
    rough_impact: RoughImpact | None
    expected_count: int


def run(command: list[str], *, capture: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=True, text=True, capture_output=capture)


def media_duration_seconds(path: Path) -> float:
    completed = run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=nokey=1:noprint_wrappers=1",
            str(path),
        ],
        capture=True,
    )
    return float(completed.stdout.strip())


def infer_source_time_scale(
    duration: float,
    *,
    realtime_max_duration: float,
    four_x_max_duration: float,
) -> float:
    """Infer original capture slow-motion scale from exported clip duration."""

    if duration <= realtime_max_duration:
        return 1.0
    if duration <= four_x_max_duration:
        return 4.0
    return 8.0


def load_rough_impacts(frame_manifest_path: Path) -> dict[str, RoughImpact]:
    if not frame_manifest_path.exists():
        return {}

    payload = json.loads(frame_manifest_path.read_text())
    impacts: dict[str, RoughImpact] = {}
    for frame in payload.get("frames", []):
        if frame.get("phase") != "impact_candidate":
            continue
        filename = str(frame["source_filename"])
        impacts[filename] = RoughImpact(
            time_seconds=float(frame["time_seconds"]),
            frame_index=int(frame["frame_index"]),
        )
    return impacts


def load_case_labels(labels_path: Path) -> tuple[int, dict[str, dict[str, Any]]]:
    if not labels_path.exists():
        return 1, {}

    payload = json.loads(labels_path.read_text())
    default_expected_count = int(payload.get("default_expected_swing_count", 1))
    labels = {
        str(item["filename"]): item
        for item in payload.get("videos", [])
        if "filename" in item
    }
    return default_expected_count, labels


def load_cases(args: argparse.Namespace) -> tuple[Case, ...]:
    rough_impacts = load_rough_impacts(args.frame_manifest)
    default_expected_count, labels_by_filename = load_case_labels(args.labels)
    metadata_by_filename: dict[str, dict[str, Any]] = {}
    if args.metadata.exists():
        metadata = json.loads(args.metadata.read_text())
        metadata_by_filename = {
            str(item["filename"]): item
            for item in metadata.get("swings", [])
            if "filename" in item
        }

    video_paths = sorted(args.video_dir.glob("*.mp4"))
    if args.only:
        wanted = set(args.only)
        video_paths = [path for path in video_paths if path.name in wanted or path.stem in wanted]
    if args.limit:
        video_paths = video_paths[: args.limit]

    cases: list[Case] = []
    for video_path in video_paths:
        metadata = metadata_by_filename.get(video_path.name, {})
        labels = labels_by_filename.get(video_path.name, {})
        duration = float(metadata.get("duration") or media_duration_seconds(video_path))
        source_time_scale = float(
            labels.get("source_time_scale")
            or infer_source_time_scale(
                duration,
                realtime_max_duration=args.realtime_max_duration,
                four_x_max_duration=args.four_x_max_duration,
            )
        )
        cases.append(
            Case(
                filename=video_path.name,
                video_path=video_path,
                duration=duration,
                source_time_scale=source_time_scale,
                rough_impact=rough_impacts.get(video_path.name),
                expected_count=int(labels.get("expected_swing_count", default_expected_count)),
            )
        )
    return tuple(cases)


def report_path(output_dir: Path, case: Case) -> Path:
    return output_dir / "reports" / f"{case.video_path.stem}.json"


def summary_detection_payload(
    detections: list[dict[str, Any]],
    source_time_scale: float,
) -> list[dict[str, Any]]:
    output = []
    for index, detection in enumerate(detections, start=1):
        declared_at = detection.get("declaredAt")
        impact_time = float(detection["impactTime"])
        output.append(
            {
                "index": index,
                "sourceStart": round(float(detection["start"]), 3),
                "sourceImpact": round(impact_time, 3),
                "sourceEnd": round(float(detection["end"]), 3),
                "realStart": round(float(detection["start"]) / max(1.0, source_time_scale), 3),
                "realImpact": round(impact_time / max(1.0, source_time_scale), 3),
                "realEnd": round(float(detection["end"]) / max(1.0, source_time_scale), 3),
                "confidence": round(float(detection["confidence"]), 4),
                "declaredDelayReal": round(
                    (float(declared_at) - impact_time) / max(1.0, source_time_scale),
                    4,
                )
                if declared_at is not None
                else None,
            }
        )
    return output


def rough_impact_score(
    detections: list[dict[str, Any]],
    rough_impact: RoughImpact | None,
    *,
    duration: float,
    tolerance: float,
) -> dict[str, Any] | None:
    if rough_impact is None:
        return None

    window_start = max(0.0, rough_impact.time_seconds - tolerance)
    window_end = min(duration, rough_impact.time_seconds + tolerance)
    matched_indices = [
        index
        for index, detection in enumerate(detections, start=1)
        if window_start <= float(detection["impactTime"]) <= window_end
    ]
    return {
        "roughImpactSource": "detector_model/frame_dataset impact_candidate frame",
        "roughImpactTime": round(rough_impact.time_seconds, 3),
        "roughImpactFrame": rough_impact.frame_index,
        "toleranceSeconds": tolerance,
        "window": {"start": round(window_start, 3), "end": round(window_end, 3)},
        "matched": bool(matched_indices),
        "matchedDetectionIndices": matched_indices,
    }


def summarize_case(
    case: Case,
    data: dict[str, Any],
    elapsed: float,
    args: argparse.Namespace,
) -> dict[str, Any]:
    hybrid = data.get("hybridImpactDetections") or []
    impact = data.get("impactCenteredDetections") or []
    count_passed = len(hybrid) == case.expected_count
    rough_score = rough_impact_score(
        hybrid,
        case.rough_impact,
        duration=case.duration,
        tolerance=args.rough_impact_tolerance,
    )
    rough_alignment_passed = rough_score is None or bool(rough_score["matched"])
    passed = count_passed and (
        rough_alignment_passed or not args.require_rough_impact_alignment
    )

    return {
        "video": case.filename,
        "expectedCount": case.expected_count,
        "sourceTimeScale": case.source_time_scale,
        "durationSeconds": round(case.duration, 4),
        "detectorDurationSeconds": round(float(data["detectorDuration"]), 4),
        "targetSampleFPS": data.get("targetSampleFPS"),
        "targetSourceSampleFPS": data.get("targetSourceSampleFPS"),
        "computeUnits": data.get("computeUnits"),
        "elapsedSeconds": round(elapsed, 4),
        "decodedFrames": data.get("decodedFrames"),
        "processedFrames": data.get("processedFrames"),
        "averageModelPipelineMSPerSample": round(float(data.get("averageProcessingTimeMS") or 0), 4),
        "averagePoseMSPerSample": round(float(data.get("averagePoseProcessingTimeMS") or 0), 4),
        "impactCandidateCount": len(impact),
        "hybridDetectionCount": len(hybrid),
        "missed": case.expected_count > 0 and len(hybrid) < case.expected_count,
        "extraDetectionCount": max(0, len(hybrid) - case.expected_count),
        "countPassed": count_passed,
        "roughImpactScore": rough_score,
        "passed": passed,
        "hybridDetections": summary_detection_payload(hybrid, case.source_time_scale),
    }


def evaluate_case(case: Case, args: argparse.Namespace) -> dict[str, Any]:
    output_path = report_path(args.output_dir, case)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if args.reuse_reports and output_path.exists() and not args.force:
        data = json.loads(output_path.read_text())
        summary = summarize_case(case, data, float(data.get("wallClockElapsedSeconds") or 0), args)
        summary["report"] = str(output_path)
        return summary

    safe_source_end = max(0.0, case.duration - 0.10)
    command = [
        str(args.evaluator),
        str(case.video_path),
        str(args.model),
        f"{args.sample_fps:.3f}",
        f"{case.source_time_scale:.3f}",
        str(args.max_frames),
        "",
        str(args.min_strong_motion_frames),
        f"{args.min_mean_club_motion:.6f}",
        f"{args.min_club_path_span:.6f}",
        f"{args.max_club_top_y:.6f}",
        f"{args.timeline_scale:.3f}",
        "0",
        f"{safe_source_end:.3f}",
        f"{args.impact_confirmation_post_roll:.3f}",
        args.compute,
        f"{args.declaration_poll_interval:.3f}",
    ]
    started = time.perf_counter()
    completed = run(command, capture=True)
    elapsed = time.perf_counter() - started
    output_path.write_text(completed.stdout)
    data = json.loads(completed.stdout)
    summary = summarize_case(case, data, elapsed, args)
    summary["report"] = str(output_path)
    return summary


def aggregate_report(summaries: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    rough_scored = [item for item in summaries if item.get("roughImpactScore") is not None]
    return {
        "parameters": {
            "videoDir": str(args.video_dir),
            "metadata": str(args.metadata),
            "frameManifest": str(args.frame_manifest),
            "labels": str(args.labels),
            "evaluator": str(args.evaluator),
            "model": str(args.model),
            "sampleFPS": args.sample_fps,
            "timelineScale": args.timeline_scale,
            "compute": args.compute,
            "impactConfirmationPostRoll": args.impact_confirmation_post_roll,
            "declarationPollInterval": args.declaration_poll_interval,
            "realtimeMaxDuration": args.realtime_max_duration,
            "fourXMaxDuration": args.four_x_max_duration,
            "roughImpactToleranceSeconds": args.rough_impact_tolerance,
            "requireRoughImpactAlignment": args.require_rough_impact_alignment,
        },
        "caseCount": len(summaries),
        "passedCount": sum(1 for item in summaries if item["passed"]),
        "failedCount": sum(1 for item in summaries if not item["passed"]),
        "missedCount": sum(1 for item in summaries if item["missed"]),
        "extraDetectionCount": sum(int(item["extraDetectionCount"]) for item in summaries),
        "exactlyOneDetectionCount": sum(1 for item in summaries if item["hybridDetectionCount"] == 1),
        "roughImpactScoredCount": len(rough_scored),
        "roughImpactAlignedCount": sum(
            1
            for item in rough_scored
            if item["roughImpactScore"] and item["roughImpactScore"]["matched"]
        ),
        "videos": summaries,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video-dir", type=Path, default=DEFAULT_VIDEO_DIR)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument("--frame-manifest", type=Path, default=DEFAULT_FRAME_MANIFEST)
    parser.add_argument("--labels", type=Path, default=DEFAULT_LABELS)
    parser.add_argument("--evaluator", type=Path, default=DEFAULT_EVALUATOR)
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--sample-fps", type=float, default=8.0)
    parser.add_argument("--timeline-scale", type=float, default=8.0)
    parser.add_argument("--compute", default="cpuAndNeuralEngine")
    parser.add_argument("--impact-confirmation-post-roll", type=float, default=0.20)
    parser.add_argument("--declaration-poll-interval", type=float, default=0.20)
    parser.add_argument("--max-frames", type=int, default=100_000)
    parser.add_argument("--min-strong-motion-frames", type=int, default=2)
    parser.add_argument("--min-mean-club-motion", type=float, default=0.05)
    parser.add_argument("--min-club-path-span", type=float, default=0.32)
    parser.add_argument("--max-club-top-y", type=float, default=0.58)
    parser.add_argument("--realtime-max-duration", type=float, default=3.75)
    parser.add_argument("--four-x-max-duration", type=float, default=10.5)
    parser.add_argument("--rough-impact-tolerance", type=float, default=1.0)
    parser.add_argument("--require-rough-impact-alignment", action="store_true")
    parser.add_argument("--reuse-reports", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--only", action="append", default=[])
    args = parser.parse_args()

    cases = load_cases(args)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    summaries: list[dict[str, Any]] = []
    for index, case in enumerate(cases, start=1):
        print(
            f"[start] {index}/{len(cases)} {case.filename} "
            f"duration={case.duration:.3f}s scale={case.source_time_scale:g}",
            flush=True,
        )
        summary = evaluate_case(case, args)
        summaries.append(summary)
        print(
            "[done] {video} detections={hybridDetectionCount} "
            "passed={passed} elapsed={elapsedSeconds}s".format(**summary),
            flush=True,
        )

    report = aggregate_report(summaries, args)
    output_path = args.output_dir / "results" / "detector_video_data_report.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
