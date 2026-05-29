#!/usr/bin/env python3
"""Run targeted performance experiments for .detectorTestV3/test5."""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import time
from pathlib import Path
from typing import Any


ROOT = Path(".detectorTestV3")
VIDEO = ROOT / "test5.mp4"
WORK_DIR = ROOT / "perf_test5"
EVALUATOR = Path(".videos/bin/evaluate_live_model_detector")
MODEL = Path("SwingCoach/MLModels/SwingObjectsYOLO11n.mlpackage")


def run(command: list[str], *, capture: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        check=True,
        text=True,
        capture_output=capture,
    )


def proxy_path(sample_fps: float, source_scale: float) -> Path:
    source_fps = sample_fps / max(1.0, source_scale)
    label = f"{source_fps:g}".replace(".", "p")
    return WORK_DIR / f"test5_{label}fps_detector_proxy.mp4"


def ensure_proxy(force: bool, sample_fps: float, source_scale: float) -> tuple[Path, float]:
    target = proxy_path(sample_fps, source_scale)
    if target.exists() and target.stat().st_size > 0 and not force:
        return target, 0.0

    source_fps = sample_fps / max(1.0, source_scale)
    if source_fps <= 0:
        raise ValueError("source fps must be positive")

    # Keep 16fps experiments on the existing high-quality proxy if present.
    legacy = WORK_DIR / "test5_2fps_detector_proxy.mp4"
    if abs(source_fps - 2.0) < 0.0001 and legacy.exists() and legacy.stat().st_size > 0 and not force:
        if not target.exists():
            target.symlink_to(legacy.name)
        return target, 0.0

    if target.exists() and target.stat().st_size > 0 and not force:
        return target, 0.0

    WORK_DIR.mkdir(parents=True, exist_ok=True)
    tmp = target.with_suffix(".tmp.mp4")
    tmp.unlink(missing_ok=True)
    # test5 is 8x-stretched slow motion. Detector fps maps to source fps / 8.
    started = time.perf_counter()
    run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(VIDEO),
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


def impact_latencies(detections: list[dict[str, Any]]) -> list[float]:
    values = []
    for detection in detections:
        value = detection.get("latencyFromImpact")
        if value is None and detection.get("declaredAt") is not None:
            value = float(detection["declaredAt"]) - float(detection["impactTime"])
        if value is not None:
            values.append(float(value))
    return values


def latency_summary(values: list[float]) -> dict[str, float | None]:
    if not values:
        return {"mean": None, "max": None}
    return {
        "mean": round(statistics.fmean(values), 4),
        "max": round(max(values), 4),
    }


def scaled_latency_summary(values: list[float], source_scale: float) -> dict[str, dict[str, float | None]]:
    return {
        "sourceTimeline": latency_summary(values),
        "realTime": latency_summary([value / max(1.0, source_scale) for value in values]),
    }


def summarize(
    data: dict[str, Any],
    external_elapsed: float,
    input_path: Path,
    proxy_build_elapsed: float = 0.0,
) -> dict[str, Any]:
    perf = data.get("performanceSamples") or []
    lag_values = [float(sample["processingLag"]) for sample in perf]
    hybrid = data.get("hybridImpactDetections") or []
    impact = data.get("impactCenteredDetections") or []
    detector_duration = float(data.get("detectorDuration") or 0)
    source_scale = float(data.get("sourceTimeScale") or 1)

    return {
        "input": str(input_path),
        "computeUnits": data.get("computeUnits"),
        "sourceTimeScale": source_scale,
        "targetSampleFPS": data.get("targetSampleFPS"),
        "targetSourceSampleFPS": data.get("targetSourceSampleFPS"),
        "declarationPollInterval": data.get("declarationPollInterval"),
        "durationSeconds": round(float(data.get("duration") or 0), 4),
        "detectorDurationSeconds": round(detector_duration, 4),
        "wallClockElapsedSeconds": round(float(data.get("wallClockElapsedSeconds") or 0), 4),
        "proxyBuildElapsedSeconds": round(proxy_build_elapsed, 4),
        "externalElapsedSeconds": round(external_elapsed, 4),
        "totalElapsedIncludingProxySeconds": round(external_elapsed + proxy_build_elapsed, 4),
        "elapsedVsDetectorDuration": round(external_elapsed / max(0.001, detector_duration), 4),
        "elapsedVsDetectorDurationIncludingProxy": round(
            (external_elapsed + proxy_build_elapsed) / max(0.001, detector_duration),
            4,
        ),
        "decodedFrames": data.get("decodedFrames"),
        "skippedDecodedFrames": data.get("skippedDecodedFrames"),
        "processedFrames": data.get("processedFrames"),
        "poseSampledFrames": data.get("poseSampledFrames"),
        "poseValidFrames": data.get("poseValidFrames"),
        "effectiveDetectorFPS": round(float(data.get("effectiveDetectorFPS") or 0), 4),
        "detectorThroughputFPS": round(float(data.get("detectorThroughputFPS") or 0), 4),
        "averageModelPipelineMSPerSample": round(float(data.get("averageProcessingTimeMS") or 0), 4),
        "lastModelPipelineMS": round(float(data.get("lastProcessingTimeMS") or 0), 4),
        "averagePoseMSPerSample": round(float(data.get("averagePoseProcessingTimeMS") or 0), 4),
        "lastPoseMS": round(float(data.get("lastPoseProcessingTimeMS") or 0), 4),
        "finalProcessingLagSeconds": round(float(data.get("finalProcessingLagSeconds") or 0), 4),
        "maxProcessingLagSeconds": round(max(lag_values), 4) if lag_values else None,
        "lastProcessingLagSeconds": round(lag_values[-1], 4) if lag_values else None,
        "impactDetectionCount": len(impact),
        "hybridDetectionCount": len(hybrid),
        "impactLatencyFromImpactSeconds": scaled_latency_summary(impact_latencies(impact), source_scale),
        "hybridLatencyFromImpactSeconds": scaled_latency_summary(impact_latencies(hybrid), source_scale),
    }


def evaluate(args: argparse.Namespace) -> dict[str, Any]:
    if args.input == "proxy":
        input_path, proxy_build_elapsed = ensure_proxy(args.force_proxy, args.sample_fps, args.source_scale)
    else:
        input_path = VIDEO
        proxy_build_elapsed = 0.0

    WORK_DIR.mkdir(parents=True, exist_ok=True)
    poll = f"poll{args.declaration_poll_interval:g}s"
    report_path = WORK_DIR / f"{args.input}_{args.compute}_{args.sample_fps:g}fps_{poll}.json"
    summary_path = WORK_DIR / f"{args.input}_{args.compute}_{args.sample_fps:g}fps_{poll}.summary.json"

    command = [
        str(EVALUATOR),
        str(input_path),
        str(MODEL),
        f"{args.sample_fps:.3f}",
        f"{args.source_scale:.3f}",
        str(args.max_frames),
        "",
        "2",
        "0.05",
        "0.32",
        "0.58",
        f"{args.timeline_scale:.3f}",
        "0",
        "",
        "0.20",
        args.compute,
        f"{args.declaration_poll_interval:.3f}",
    ]

    started = time.perf_counter()
    completed = run(command, capture=True)
    external_elapsed = time.perf_counter() - started
    report_path.write_text(completed.stdout)
    data = json.loads(completed.stdout)
    summary = summarize(data, external_elapsed, input_path, proxy_build_elapsed)
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    return {"report": str(report_path), "summary": str(summary_path), **summary}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", choices=("original", "proxy"), default="proxy")
    parser.add_argument("--compute", default="cpuOnly")
    parser.add_argument("--sample-fps", type=float, default=16.0)
    parser.add_argument("--declaration-poll-interval", type=float, default=0.0)
    parser.add_argument("--source-scale", type=float, default=8.0)
    parser.add_argument("--timeline-scale", type=float, default=8.0)
    parser.add_argument("--max-frames", type=int, default=100_000)
    parser.add_argument("--force-proxy", action="store_true")
    args = parser.parse_args()

    print(json.dumps(evaluate(args), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
