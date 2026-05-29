#!/usr/bin/env python3
"""Run the realtime-capable detector setup across .detectorTestV3."""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(".detectorTestV3")
WORK_DIR = ROOT / "perf_v3_8fps"
EVALUATOR = Path(".videos/bin/evaluate_live_model_detector")
MODEL = Path("SwingCoach/MLModels/SwingObjectsYOLO11n.mlpackage")
DEFAULT_LABELS = Path("tools/detector_test_v3_labels.json")


@dataclass(frozen=True)
class Window:
    start: float
    end: float


@dataclass(frozen=True)
class Case:
    name: str
    filename: str
    source_scale: float
    expected_count: int
    positive_windows: tuple[Window, ...] = ()
    impact_windows: tuple[Window, ...] = ()


def window_from_payload(item: dict[str, Any]) -> Window:
    return Window(float(item["start"]), float(item["end"]))


def load_cases(labels_path: Path) -> tuple[Case, ...]:
    payload = json.loads(labels_path.read_text())
    cases = []
    for item in payload["videos"]:
        cases.append(
            Case(
                name=str(item["id"]),
                filename=str(item["filename"]),
                source_scale=float(item["source_time_scale"]),
                expected_count=int(item["expected_swing_count"]),
                positive_windows=tuple(
                    window_from_payload(window)
                    for window in item.get("positive_swing_windows", [])
                ),
                impact_windows=tuple(
                    window_from_payload(window)
                    for window in item.get("impact_time_labels", [])
                ),
            )
        )
    return tuple(cases)


def run(command: list[str], *, capture: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=True, text=True, capture_output=capture)


def video_duration_seconds(case: Case) -> float:
    try:
        completed = run(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "default=nokey=1:noprint_wrappers=1",
                str(ROOT / case.filename),
            ],
            capture=True,
        )
        return float(completed.stdout.strip())
    except (subprocess.CalledProcessError, ValueError):
        return float("inf")


def proxy_path(case: Case, sample_fps: float) -> Path:
    source_fps = sample_fps / max(1.0, case.source_scale)
    label = f"{source_fps:g}".replace(".", "p")
    return WORK_DIR / "proxies" / f"{case.name}_{label}fps.mp4"


def ensure_proxy(case: Case, sample_fps: float, force: bool) -> tuple[Path, float]:
    target = proxy_path(case, sample_fps)
    if target.exists() and target.stat().st_size > 0 and not force:
        return target, 0.0

    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(".tmp.mp4")
    tmp.unlink(missing_ok=True)
    source_fps = sample_fps / max(1.0, case.source_scale)
    started = time.perf_counter()
    run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(ROOT / case.filename),
            "-map",
            "0:v:0",
            "-vf",
            f"fps={source_fps:.6f}",
            "-an",
            "-c:v",
            "libx264",
            "-preset",
            "ultrafast",
            "-crf",
            "28",
            "-movflags",
            "+faststart",
            str(tmp),
        ]
    )
    tmp.replace(target)
    return target, time.perf_counter() - started


def overlaps(a: Window, b: Window) -> bool:
    return a.start <= b.end and b.start <= a.end


def latency_values(detections: list[dict[str, Any]], source_scale: float) -> list[float]:
    values = []
    for detection in detections:
        declared_at = detection.get("declaredAt")
        impact_time = detection.get("impactTime")
        if declared_at is None or impact_time is None:
            continue
        values.append((float(declared_at) - float(impact_time)) / max(1.0, source_scale))
    return values


def mean(values: list[float]) -> float | None:
    return round(statistics.fmean(values), 4) if values else None


def score_windows(detections: list[dict[str, Any]], labels: tuple[Window, ...]) -> dict[str, Any]:
    matched: set[int] = set()
    false_positive_indices: list[int] = []
    duplicate_indices: list[int] = []

    for detection_index, detection in enumerate(detections, start=1):
        window = Window(float(detection["start"]), float(detection["end"]))
        matches = [index for index, label in enumerate(labels) if overlaps(window, label)]
        if not matches:
            false_positive_indices.append(detection_index)
        elif all(index in matched for index in matches):
            duplicate_indices.append(detection_index)
        else:
            matched.update(matches)

    return {
        "matched": len(matched),
        "missed": [index + 1 for index in range(len(labels)) if index not in matched],
        "falsePositiveIndices": false_positive_indices,
        "duplicateIndices": duplicate_indices,
    }


def score_impacts(detections: list[dict[str, Any]], impact_windows: tuple[Window, ...]) -> dict[str, Any]:
    matched: set[int] = set()
    false_positive_indices: list[int] = []
    duplicate_indices: list[int] = []

    for detection_index, detection in enumerate(detections, start=1):
        impact = float(detection["impactTime"])
        matches = [
            index
            for index, label in enumerate(impact_windows)
            if label.start <= impact <= label.end
        ]
        if not matches:
            false_positive_indices.append(detection_index)
        elif all(index in matched for index in matches):
            duplicate_indices.append(detection_index)
        else:
            matched.update(matches)

    return {
        "matched": len(matched),
        "missed": [index + 1 for index in range(len(impact_windows)) if index not in matched],
        "falsePositiveIndices": false_positive_indices,
        "duplicateIndices": duplicate_indices,
    }


def summarize(case: Case, data: dict[str, Any], elapsed: float, proxy_elapsed: float) -> dict[str, Any]:
    scale = float(data["sourceTimeScale"])
    hybrid = data.get("hybridImpactDetections") or []
    impact = data.get("impactCenteredDetections") or []
    detector_duration = float(data["detectorDuration"])
    detections = [
        {
            "index": index,
            "sourceStart": round(float(detection["start"]), 3),
            "sourceImpact": round(float(detection["impactTime"]), 3),
            "sourceEnd": round(float(detection["end"]), 3),
            "realStart": round(float(detection["start"]) / max(1.0, scale), 3),
            "realImpact": round(float(detection["impactTime"]) / max(1.0, scale), 3),
            "realEnd": round(float(detection["end"]) / max(1.0, scale), 3),
            "confidence": round(float(detection["confidence"]), 4),
            "declaredDelayReal": round(
                (float(detection["declaredAt"]) - float(detection["impactTime"])) / max(1.0, scale),
                4,
            ),
        }
        for index, detection in enumerate(hybrid, start=1)
    ]

    window_score = score_windows(hybrid, case.positive_windows) if case.positive_windows else None
    impact_score = score_impacts(hybrid, case.impact_windows) if case.impact_windows else None

    return {
        "video": case.name,
        "expectedCount": case.expected_count,
        "sourceScale": case.source_scale,
        "computeUnits": data.get("computeUnits"),
        "targetSampleFPS": data.get("targetSampleFPS"),
        "targetSourceSampleFPS": data.get("targetSourceSampleFPS"),
        "durationSeconds": round(float(data["duration"]), 4),
        "detectorDurationSeconds": round(detector_duration, 4),
        "proxyElapsedSeconds": round(proxy_elapsed, 4),
        "elapsedSeconds": round(elapsed, 4),
        "totalElapsedSeconds": round(proxy_elapsed + elapsed, 4),
        "elapsedVsDetectorDuration": round(elapsed / max(0.001, detector_duration), 4),
        "totalElapsedVsDetectorDuration": round((proxy_elapsed + elapsed) / max(0.001, detector_duration), 4),
        "decodedFrames": data.get("decodedFrames"),
        "processedFrames": data.get("processedFrames"),
        "effectiveDetectorFPS": round(float(data.get("effectiveDetectorFPS") or 0), 4),
        "detectorThroughputFPS": round(float(data.get("detectorThroughputFPS") or 0), 4),
        "averageModelPipelineMSPerSample": round(float(data.get("averageProcessingTimeMS") or 0), 4),
        "averagePoseMSPerSample": round(float(data.get("averagePoseProcessingTimeMS") or 0), 4),
        "finalProcessingLagSeconds": round(float(data.get("finalProcessingLagSeconds") or 0), 4),
        "maxProcessingLagSeconds": round(
            max((float(sample["processingLag"]) for sample in data.get("performanceSamples", [])), default=0),
            4,
        ),
        "impactCandidateCount": len(impact),
        "hybridDetectionCount": len(hybrid),
        "meanHybridDeclaredDelayReal": mean(latency_values(hybrid, scale)),
        "windowScore": window_score,
        "impactScore": impact_score,
        "hybridDetections": detections,
    }


def evaluate_case(case: Case, args: argparse.Namespace) -> dict[str, Any]:
    input_path, proxy_elapsed = ensure_proxy(case, args.sample_fps, args.force_proxy)
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    report_path = WORK_DIR / f"{case.name}.json"
    if args.reuse_reports and report_path.exists():
        data = json.loads(report_path.read_text())
        summary = summarize(case, data, float(data.get("wallClockElapsedSeconds") or 0), 0.0)
        summary["report"] = str(report_path)
        return summary

    command = [
        str(EVALUATOR),
        str(input_path),
        str(MODEL),
        f"{args.sample_fps:.3f}",
        f"{case.source_scale:.3f}",
        str(args.max_frames),
        "",
        "2",
        "0.05",
        "0.32",
        "0.58",
        f"{args.timeline_scale:.3f}",
        "0",
        "",
        f"{args.impact_confirmation_post_roll:.3f}",
        args.compute,
        f"{args.declaration_poll_interval:.3f}",
    ]
    started = time.perf_counter()
    completed = run(command, capture=True)
    elapsed = time.perf_counter() - started
    report_path.write_text(completed.stdout)
    data = json.loads(completed.stdout)
    summary = summarize(case, data, elapsed, proxy_elapsed)
    summary["report"] = str(report_path)
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample-fps", type=float, default=8.0)
    parser.add_argument("--compute", default="cpuAndNeuralEngine")
    parser.add_argument("--timeline-scale", type=float, default=8.0)
    parser.add_argument("--impact-confirmation-post-roll", type=float, default=0.20)
    parser.add_argument("--declaration-poll-interval", type=float, default=0.20)
    parser.add_argument("--max-frames", type=int, default=100_000)
    parser.add_argument("--force-proxy", action="store_true")
    parser.add_argument("--labels", type=Path, default=DEFAULT_LABELS)
    parser.add_argument("--reuse-reports", action="store_true")
    args = parser.parse_args()

    cases = tuple(sorted(load_cases(args.labels), key=video_duration_seconds))
    results = []
    for case in cases:
        print(f"[start] {case.name}", flush=True)
        summary = evaluate_case(case, args)
        results.append(summary)
        print(
            "[done] {video} detections={hybridDetectionCount} elapsed={elapsedSeconds}s total={totalElapsedSeconds}s".format(
                **summary
            ),
            flush=True,
        )

    aggregate = {
        "parameters": {
            "sampleFPS": args.sample_fps,
            "compute": args.compute,
            "impactConfirmationPostRoll": args.impact_confirmation_post_roll,
            "declarationPollInterval": args.declaration_poll_interval,
        },
        "videos": results,
    }
    output_path = WORK_DIR / "summary.json"
    output_path.write_text(json.dumps(aggregate, indent=2, sort_keys=True) + "\n")
    print(json.dumps(aggregate, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
