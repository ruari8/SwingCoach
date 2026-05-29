#!/usr/bin/env python3
"""Compare live swing detector strategies on the local .detectorTestV2 clips."""

from __future__ import annotations

import argparse
import array
import json
import math
import statistics
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Window:
    start: float
    end: float


@dataclass(frozen=True)
class Case:
    filename: str
    labels: tuple[Window, ...]
    source_time_scale: float = 1.0
    source_start: float | None = None
    source_end: float | None = None


CASES = (
    Case(
        "1cde87c1-420b-4a92-8d4d-adde03917ae9.MP4",
        (Window(1.8, 4.3),),
    ),
    Case(
        "ScreenRecording_04-01-2026 16-13-45_1.MP4",
        (Window(8.0, 15.8),),
    ),
    Case(
        "ScreenRecording_05-13-2026 06-46-28_1.MP4",
        (Window(2.7, 7.7), Window(8.5, 11.9)),
    ),
    Case(
        "eb5a91a1830f4dc894afbe2ffafa3a45.MOV",
        (Window(1.0, 4.8),),
    ),
    Case(
        "IMG_2622.mov",
        (
            Window(20.5, 28.5),
            Window(34.0, 42.0),
            Window(64.0, 75.0),
            Window(83.0, 94.0),
        ),
        source_end=120.0,
    ),
)


def overlaps(a: Window, b: Window) -> bool:
    return a.start <= b.end and b.start <= a.end


def score(detections: list[dict], labels: tuple[Window, ...]) -> dict:
    matched = set()
    false_positives = 0
    duplicate_detections = 0
    latencies = []
    label_end_latencies = []

    for detection in detections:
        window = Window(float(detection["start"]), float(detection["end"]))
        matched_indices = [index for index, label in enumerate(labels) if overlaps(window, label)]
        if matched_indices:
            if not any(index not in matched for index in matched_indices):
                duplicate_detections += 1
            matched.update(matched_indices)
        else:
            false_positives += 1
        latency = detection.get("latencyFromEnd")
        if latency is not None:
            latencies.append(float(latency))
        label_latency = detection.get("latencyFromMatchedLabelEnd")
        if label_latency is not None:
            label_end_latencies.append(float(label_latency))

    return {
        "matched": len(matched),
        "labels": len(labels),
        "falsePositives": false_positives,
        "duplicateDetections": duplicate_detections,
        "count": len(detections),
        "meanLatencyFromEnd": round(sum(latencies) / len(latencies), 3) if latencies else None,
        "meanLatencyFromMatchedLabelEnd": round(sum(label_end_latencies) / len(label_end_latencies), 3)
        if label_end_latencies
        else None,
    }


def annotate_label_latency(detections: list[dict], labels: tuple[Window, ...]) -> list[dict]:
    annotated = []
    for detection in detections:
        output = dict(detection)
        window = Window(float(output["start"]), float(output["end"]))
        matched_indices = [index for index, label in enumerate(labels) if overlaps(window, label)]
        output["matchedLabelIndices"] = [index + 1 for index in matched_indices]
        declared_at = output.get("declaredAt")
        if matched_indices and declared_at is not None:
            label_end = max(labels[index].end for index in matched_indices)
            offset = float(declared_at) - label_end
            output["declaredOffsetFromMatchedLabelEnd"] = offset
            output["latencyFromMatchedLabelEnd"] = max(0.0, offset)
        annotated.append(output)
    return annotated


def run_live_model_evaluator(
    case: Case,
    root: Path,
    evaluator: Path,
    model: Path,
    sample_fps: float,
    impact_confirmation_post_roll: float | None,
) -> dict:
    command = [
        str(evaluator),
        str(root / case.filename),
        str(model),
        f"{sample_fps:.3f}",
        str(case.source_time_scale),
        "18000",
        "",
        "2",
        "0.05",
        "0.32",
        "0.58",
        "8",
    ]
    if case.source_start is not None or case.source_end is not None or impact_confirmation_post_roll is not None:
        command.append(str(case.source_start or 0.0))
        command.append("" if case.source_end is None else str(case.source_end))
    if impact_confirmation_post_roll is not None:
        command.append(f"{impact_confirmation_post_roll:.3f}")

    completed = subprocess.run(command, text=True, capture_output=True, check=True)
    return json.loads(completed.stdout)


def audio_peaks(path: Path, sr: int = 8000, win_ms: int = 20, top: int = 32) -> list[tuple[float, float]]:
    command = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        str(path),
        "-vn",
        "-ac",
        "1",
        "-ar",
        str(sr),
        "-f",
        "s16le",
        "-",
    ]
    completed = subprocess.run(command, capture_output=True)
    if completed.returncode != 0 or not completed.stdout:
        return []

    samples = array.array("h")
    samples.frombytes(completed.stdout)
    sample_count = max(1, int(sr * win_ms / 1000))
    rms = []
    for start in range(0, len(samples) - sample_count + 1, sample_count):
        total = 0.0
        for value in samples[start : start + sample_count]:
            normalized = value / 32768.0
            total += normalized * normalized
        rms.append(math.sqrt(total / sample_count))

    half_window = int(0.5 / (win_ms / 1000))
    scores = []
    for index, value in enumerate(rms):
        lower = max(0, index - half_window)
        upper = min(len(rms), index + half_window + 1)
        baseline = statistics.median(rms[lower:upper]) if upper > lower else 0.0
        scores.append(value / (baseline + 1e-5))

    peaks = []
    for index, value in enumerate(scores):
        if 0 < index < len(scores) - 1 and value >= scores[index - 1] and value >= scores[index + 1] and value > 2.5:
            peaks.append((index * win_ms / 1000, value))

    peaks.sort(key=lambda item: item[1], reverse=True)
    kept: list[tuple[float, float]] = []
    for peak in peaks:
        if all(abs(peak[0] - existing[0]) > 0.35 for existing in kept):
            kept.append(peak)
        if len(kept) >= top:
            break
    return sorted(kept)


def audio_model_detections(case: Case, root: Path, evaluator_output: dict) -> list[dict]:
    peaks = audio_peaks(root / case.filename)
    if case.source_end is not None:
        peaks = [peak for peak in peaks if peak[0] <= case.source_end]

    model_windows = [
        Window(float(item["start"]), float(item["end"]))
        for item in evaluator_output.get("impactCenteredDetections", [])
    ]
    detections = []
    for time, score_value in peaks:
        if not any(window.start - 0.4 <= time <= window.end + 0.4 for window in model_windows):
            continue
        start = max(0.0, time - 1.25)
        end = time + 0.75
        detections.append(
            {
                "start": start,
                "end": end,
                "impactTime": time,
                "confidence": min(0.95, 0.45 + score_value / 20.0),
                "declaredAt": time + 0.08,
                "latencyFromEnd": max(0.0, time + 0.08 - end),
            }
        )

    merged = []
    for detection in detections:
        window = Window(detection["start"], detection["end"])
        if any(overlaps(window, Window(existing["start"], existing["end"])) for existing in merged):
            continue
        merged.append(detection)
    return merged


def passes_pose_gate(detection: dict) -> bool:
    pose = detection.get("poseDiagnostics")
    if not pose:
        return False

    if pose["validSampleCount"] < 3 or pose["coverage"] < 0.40:
        return False
    if pose["bodyDrift"] > 0.18:
        return False

    has_sustained_hand_motion = pose["handTravel"] >= 0.22 and pose["peakHandSpeed"] >= 0.70
    has_address_to_finish_change = pose["addressToFinishDistance"] >= 0.38 and pose["peakHandSpeed"] >= 0.50
    has_large_swing_shape = pose["handTravel"] >= 0.65 and pose["addressToFinishDistance"] >= 0.45
    return has_sustained_hand_motion or has_address_to_finish_change or has_large_swing_shape


def pose_gated_impact_detections(evaluator_output: dict) -> list[dict]:
    return [
        detection
        for detection in evaluator_output.get("impactCenteredDetections", [])
        if passes_pose_gate(detection)
    ]


def pose_quality(detection: dict) -> float:
    pose = detection.get("poseDiagnostics") or {}
    return (
        float(pose.get("handTravel", 0.0))
        + float(pose.get("addressToFinishDistance", 0.0))
        + float(pose.get("peakHandSpeed", 0.0)) * 0.10
    )


def passes_low_pose_cadence_fallback(detection: dict, last_core_impact: float | None) -> bool:
    if last_core_impact is None:
        return False
    if float(detection.get("impactTime", 0.0)) - last_core_impact < 14.0:
        return False

    pose = detection.get("poseDiagnostics") or {}
    diagnostics = detection.get("diagnostics") or {}
    return (
        float(pose.get("coverage", 0.0)) >= 0.80
        and int(pose.get("validSampleCount", 0)) >= 8
        and float(pose.get("handTravel", 99.0)) <= 0.08
        and float(pose.get("peakHandSpeed", 99.0)) <= 0.15
        and float(pose.get("bodyDrift", 99.0)) <= 0.03
        and float(diagnostics.get("peakMotion", 0.0)) >= 1.0
        and int(diagnostics.get("strongMotionFrameCount", 0)) >= 3
        and float(diagnostics.get("meanClubMotion", 0.0)) >= 0.045
        and float(diagnostics.get("clubFrameRatio", 0.0)) >= 0.90
    )


def hybrid_impact_detections(evaluator_output: dict) -> list[dict]:
    accepted: list[dict] = []
    last_core_impact: float | None = None

    for detection in evaluator_output.get("impactCenteredDetections", []):
        if float(detection.get("impactTime", 0.0)) < 1.15:
            continue

        if passes_pose_gate(detection):
            next_detection = dict(detection)
            next_detection["hybridReason"] = "pose"
            accepted.append(next_detection)
            last_core_impact = float(detection.get("impactTime", 0.0))
        elif passes_low_pose_cadence_fallback(detection, last_core_impact):
            next_detection = dict(detection)
            next_detection["hybridReason"] = "lowPoseCadence"
            accepted.append(next_detection)
            last_core_impact = float(detection.get("impactTime", 0.0))

    keep = [True] * len(accepted)
    for index, detection in enumerate(accepted):
        for next_index in range(index + 1, len(accepted)):
            next_detection = accepted[next_index]
            gap = float(next_detection.get("impactTime", 0.0)) - float(detection.get("impactTime", 0.0))
            if gap > 8.0:
                break
            if (
                detection.get("hybridReason") == "pose"
                and next_detection.get("hybridReason") == "pose"
                and pose_quality(next_detection) - pose_quality(detection) >= 0.45
            ):
                keep[index] = False
                break

    return [detection for detection, should_keep in zip(accepted, keep) if should_keep]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(".detectorTestV2"))
    parser.add_argument("--evaluator", type=Path, default=Path(".videos/bin/evaluate_live_model_detector"))
    parser.add_argument("--model", type=Path, default=Path("SwingCoach/MLModels/SwingObjectsYOLO11n.mlpackage"))
    parser.add_argument("--sample-fps", type=float, default=16.0)
    parser.add_argument("--impact-confirmation-post-roll", type=float, default=0.20)
    args = parser.parse_args()

    aggregate = {
        "strict": {"matched": 0, "labels": 0, "falsePositives": 0, "duplicateDetections": 0, "count": 0},
        "impact": {"matched": 0, "labels": 0, "falsePositives": 0, "duplicateDetections": 0, "count": 0},
        "poseImpact": {"matched": 0, "labels": 0, "falsePositives": 0, "duplicateDetections": 0, "count": 0},
        "audioModel": {"matched": 0, "labels": 0, "falsePositives": 0, "duplicateDetections": 0, "count": 0},
        "hybridImpact": {"matched": 0, "labels": 0, "falsePositives": 0, "duplicateDetections": 0, "count": 0},
    }
    cases = []

    for case in CASES:
        output = run_live_model_evaluator(
            case,
            args.root,
            args.evaluator,
            args.model,
            args.sample_fps,
            args.impact_confirmation_post_roll,
        )
        strict_detections = annotate_label_latency(output.get("detections", []), case.labels)
        impact_detections = annotate_label_latency(output.get("impactCenteredDetections", []), case.labels)
        audio_detections = annotate_label_latency(audio_model_detections(case, args.root, output), case.labels)
        pose_detections = annotate_label_latency(pose_gated_impact_detections(output), case.labels)
        hybrid_detections = annotate_label_latency(
            output.get("hybridImpactDetections") or hybrid_impact_detections(output),
            case.labels,
        )
        strict_score = score(strict_detections, case.labels)
        impact_score = score(impact_detections, case.labels)
        pose_score = score(pose_detections, case.labels)
        audio_score = score(audio_detections, case.labels)
        hybrid_score = score(hybrid_detections, case.labels)

        for key, item in (
            ("strict", strict_score),
            ("impact", impact_score),
            ("poseImpact", pose_score),
            ("audioModel", audio_score),
            ("hybridImpact", hybrid_score),
        ):
            for field in ("matched", "labels", "falsePositives", "duplicateDetections", "count"):
                aggregate[key][field] += item[field]

        cases.append(
            {
                "video": case.filename,
                "labels": [label.__dict__ for label in case.labels],
                "strict": strict_score,
                "impact": impact_score,
                "poseImpact": pose_score,
                "audioModel": audio_score,
                "hybridImpact": hybrid_score,
                "strictDetections": strict_detections,
                "impactDetections": impact_detections,
                "poseImpactDetections": pose_detections,
                "audioModelDetections": audio_detections,
                "hybridImpactDetections": hybrid_detections,
                "processedFrames": output.get("processedFrames"),
                "poseSampledFrames": output.get("poseSampledFrames"),
                "poseValidFrames": output.get("poseValidFrames"),
                "averageProcessingTimeMS": output.get("averageProcessingTimeMS"),
            }
        )

    print(json.dumps({
        "parameters": {
            "sampleFPS": args.sample_fps,
            "impactConfirmationPostRoll": args.impact_confirmation_post_roll,
        },
        "aggregate": aggregate,
        "cases": cases,
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
