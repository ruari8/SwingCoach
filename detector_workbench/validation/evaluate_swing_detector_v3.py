#!/usr/bin/env python3
"""
Fail-fast fixture harness for SwingDetectorV3.

Runs the V3 Swift evaluator on V3 fixtures, scores accepted swings against
`detector_test_v3_labels.json` (count, matched, missed, false positives,
impact-time error), summarises the per-candidate evidence traces, and (with
--contact-sheets) renders annotated YOLO contact sheets around each labelled
impact and each false positive for visual debugging.

The detector and labels both live on the SOURCE timeline; the v3 detector is
told each clip's `source_time_scale` so detection times come back in source
seconds. Impact-time error is reported in REAL seconds (source / scale).

Examples:
  python3 detector_workbench/validation/evaluate_swing_detector_v3.py --build --only test2
  python3 detector_workbench/validation/evaluate_swing_detector_v3.py --only test2 --contact-sheets
  python3 detector_workbench/validation/evaluate_swing_detector_v3.py --labels held_out.json --fixtures-root .held-out
  python3 detector_workbench/validation/evaluate_swing_detector_v3.py            # all active fixtures

Manifests may define contiguous mixed-speed segments and per-impact time scales.
Each segment gets fresh detector state; merged detections and traces use absolute
source-video timestamps.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LABELS = REPO / "detector_workbench/validation/labels/detector_test_v3_labels.json"
FIXTURES = REPO / ".detectorTestV3"
MODEL = REPO / "SwingCoach/MLModels/SwingObjectsYOLO11n.mlpackage"
V3_BIN = REPO / ".videos/bin/evaluate_swing_detector_v3"
SHEET_BIN = REPO / ".videos/bin/generate_model_detection_contact_sheet"
OUT_ROOT = FIXTURES / "perf_v3"

V3_SOURCES = [
    "SwingCoach/Models/OnDeviceSwingDetector.swift",
    "SwingCoach/Models/LiveSwingDetector.swift",
    "SwingCoach/Models/LiveSwingDetecting.swift",
    "SwingCoach/Models/GolfObjectDetector.swift",
    "SwingCoach/Models/SwingDetectorV2/SwingEvidence.swift",
    "SwingCoach/Models/SwingDetectorV2/SwingCandidateTrace.swift",
    "SwingCoach/Models/SwingDetectorV3",  # expands to *.swift below
    "detector_workbench/validation/evaluate_swing_detector_v3.swift",
]
SHEET_SOURCES = [
    "SwingCoach/Models/GolfObjectDetector.swift",
    "detector_workbench/modeling/generate_model_detection_contact_sheet.swift",
]
FRAMEWORKS = [
    "AVFoundation", "CoreML", "Vision", "CoreGraphics", "CoreVideo", "ImageIO", "AppKit",
]


def expand_sources(entries: list[str]) -> list[str]:
    out: list[str] = []
    for entry in entries:
        path = REPO / entry
        if path.is_dir():
            out.extend(sorted(str(p.relative_to(REPO)) for p in path.glob("*.swift")))
        else:
            out.append(entry)
    return out


def swiftc(sources: list[str], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    cmd = ["xcrun", "swiftc", "-parse-as-library", "-O"]
    for fw in FRAMEWORKS:
        cmd += ["-framework", fw]
    cmd += expand_sources(sources)
    cmd += ["-o", str(output)]
    print(f"compiling {output.name} ...", flush=True)
    subprocess.run(cmd, cwd=REPO, check=True)


def build() -> None:
    swiftc(V3_SOURCES, V3_BIN)
    swiftc(SHEET_SOURCES, SHEET_BIN)


def load_labels(path: Path) -> dict:
    data = json.loads(path.read_text())
    return {v["id"]: v for v in data["videos"]}


def video_duration(video: Path) -> float:
    output = subprocess.check_output(
        [
            "ffprobe", "-v", "error", "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1", str(video),
        ],
        text=True,
    )
    return float(output.strip())


def configured_segments(meta: dict, duration: float) -> list[dict]:
    """Return explicit mixed-speed segments or one legacy whole-video segment."""
    if meta.get("segments"):
        segments = meta["segments"]
    else:
        segments = [{
            "id": "full",
            "start": 0,
            "end": duration,
            "source_time_scale": meta.get("source_time_scale", 1.0),
        }]
    previous_end = 0.0
    for segment in segments:
        start = float(segment["start"])
        end = float(segment["end"])
        if abs(start - previous_end) > 0.05 or end <= start:
            raise ValueError(f"{meta['id']} segments must be contiguous and ordered")
        previous_end = end
    if abs(previous_end - duration) > 0.05:
        raise ValueError(f"{meta['id']} segments must cover the complete source timeline")
    return segments


def run_segment(video: Path, scale: float, low_fps: float, burst_fps: float,
                compute: str, start: float, end: float) -> dict:
    cmd = [
        str(V3_BIN), str(video), str(MODEL),
        str(low_fps), str(scale), "400000", str(burst_fps), compute,
        str(start), str(end),
    ]
    proc = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"v3 evaluator failed for {video.name}: {proc.stderr.strip()}")
    return json.loads(proc.stdout)


def run_detector(video: Path, segments: list[dict], low_fps: float,
                 burst_fps: float, compute: str) -> dict:
    """Run independently configured timeline segments and merge absolute outputs."""
    results = []
    for index, segment in enumerate(segments):
        segment_id = segment.get("id", f"segment-{index + 1}")
        scale = float(segment["source_time_scale"])
        result = run_segment(
            video, scale, low_fps, burst_fps, compute,
            float(segment["start"]), float(segment["end"]),
        )
        source_offset = float(result.get("segmentStart", segment["start"]))
        for detection in result.get("detections", []):
            detection["sourceTimeScale"] = scale
            detection["segmentId"] = segment_id
        for trace in result.get("traces", []):
            trace["segmentId"] = segment_id
            if trace.get("impactSourceTime") is not None:
                trace["impactSourceTime"] += source_offset
            if trace.get("addressLock") is not None:
                trace["addressLock"]["lockedAtSource"] += source_offset
        for key in ("sampling", "observations"):
            for row in result.get(key, []):
                row["segmentId"] = segment_id
                row["sourceTime"] += source_offset
        for decision in result.get("decisions", []):
            decision["segmentId"] = segment_id
            decision["impactSourceTime"] += source_offset
            if decision.get("declaredSourceTime") is not None:
                decision["declaredSourceTime"] += source_offset
        results.append((segment_id, scale, result))

    processed = sum(result.get("processedFrames", 0) for _, _, result in results)
    processing_ms = sum(
        result.get("averageProcessingTimeMS", 0) * result.get("processedFrames", 0)
        for _, _, result in results
    )
    return {
        "video": str(video),
        "model": results[0][2].get("model"),
        "computeUnits": results[0][2].get("computeUnits"),
        "configuration": "mixed timeline segments" if len(results) > 1
        else results[0][2].get("configuration"),
        "lowSampleFPS": low_fps,
        "burstSampleFPS": burst_fps,
        "duration": sum(result.get("duration", 0) for _, _, result in results),
        "representedRealSeconds": sum(
            result.get("duration", 0) / scale for _, scale, result in results
        ),
        "decodedFrames": sum(result.get("decodedFrames", 0) for _, _, result in results),
        "processedFrames": processed,
        "averageProcessingTimeMS": processing_ms / processed if processed else None,
        "wallClockElapsedSeconds": sum(
            result.get("wallClockElapsedSeconds", 0) for _, _, result in results
        ),
        "detections": sorted(
            [d for _, _, result in results for d in result.get("detections", [])],
            key=lambda detection: detection.get("impactTime") or detection.get("start", 0),
        ),
        "traces": [row for _, _, result in results for row in result.get("traces", [])],
        "sampling": [row for _, _, result in results for row in result.get("sampling", [])],
        "observations": [row for _, _, result in results for row in result.get("observations", [])],
        "decisions": [row for _, _, result in results for row in result.get("decisions", [])],
        "segments": [
            {
                "id": segment_id,
                "sourceTimeScale": scale,
                "start": result.get("segmentStart"),
                "end": result.get("segmentEnd"),
                "duration": result.get("duration"),
                "processedFrames": result.get("processedFrames"),
                "averageProcessingTimeMS": result.get("averageProcessingTimeMS"),
                "wallClockElapsedSeconds": result.get("wallClockElapsedSeconds"),
                "detectionCount": len(result.get("detections", [])),
            }
            for segment_id, scale, result in results
        ],
    }


def label_center(label: dict) -> float:
    return (label["start"] + label["end"]) / 2.0


def score(result: dict, labels: list[dict], default_scale: float) -> dict:
    """Match accepted detections to impact labels on the source timeline."""
    detections = result.get("detections", [])
    det_impacts = [d.get("impactTime") for d in detections]

    matched_labels = []
    impact_errors_real = []
    used = set()
    for idx, label in enumerate(labels):
        scale = float(label.get("source_time_scale", default_scale))
        tol = max(1.0, 1.0 * scale)  # +/- 1 real second, in source seconds
        lo, hi = label["start"] - tol, label["end"] + tol
        best = None
        for di, t in enumerate(det_impacts):
            if di in used or t is None:
                continue
            detection_scale = float(detections[di].get("sourceTimeScale", default_scale))
            if not math.isclose(detection_scale, scale):
                continue
            if lo <= t <= hi:
                err = abs(t - label_center(label))
                if best is None or err < best[1]:
                    best = (di, err)
        if best is not None:
            used.add(best[0])
            matched_labels.append(idx)
            impact_errors_real.append(best[1] / scale)

    false_positives = [i for i in range(len(detections)) if i not in used]
    missed = [i for i in range(len(labels)) if i not in matched_labels]

    return {
        "expected": len(labels),
        "detected": len(detections),
        "matched": len(matched_labels),
        "missed": missed,
        "falsePositives": len(false_positives),
        "meanImpactErrorRealSec": (sum(impact_errors_real) / len(impact_errors_real))
        if impact_errors_real else None,
        "passed": len(missed) == 0 and len(false_positives) == 0,
    }


def trace_summary(result: dict) -> dict:
    traces = result.get("traces", [])
    failures: dict[str, int] = {}
    for t in traces:
        failures[t["primaryFailure"]] = failures.get(t["primaryFailure"], 0) + 1
    return {
        "candidates": len(traces),
        "accepted": sum(1 for t in traces if t.get("accepted")),
        "withAddressLock": sum(1 for t in traces if t.get("addressLock") is not None),
        "primaryFailures": failures,
    }


def aggregate_summary(cases: list[tuple[dict, dict]]) -> dict:
    """Combine correctness, live-rate throughput, and declaration latency."""
    total_frames = sum(int(result.get("processedFrames") or 0) for result, _ in cases)
    processing_ms = sum(
        float(result.get("averageProcessingTimeMS") or 0)
        * int(result.get("processedFrames") or 0)
        for result, _ in cases
    )
    wall_seconds = sum(float(result.get("wallClockElapsedSeconds") or 0) for result, _ in cases)
    real_seconds = sum(float(result.get("representedRealSeconds") or 0) for result, _ in cases)
    delays = sorted(
        (float(detection["declaredAt"]) - float(detection["impactTime"]))
        / float(detection.get("sourceTimeScale", 1.0))
        for result, _ in cases
        for detection in result.get("detections", [])
        if detection.get("declaredAt") is not None and detection.get("impactTime") is not None
    )

    def percentile(values: list[float], fraction: float) -> float | None:
        if not values:
            return None
        return values[max(0, math.ceil(len(values) * fraction) - 1)]

    return {
        "expected": sum(sc["expected"] for _, sc in cases),
        "detected": sum(sc["detected"] for _, sc in cases),
        "matched": sum(sc["matched"] for _, sc in cases),
        "missed": sum(len(sc["missed"]) for _, sc in cases),
        "falsePositives": sum(sc["falsePositives"] for _, sc in cases),
        "processedFrames": total_frames,
        "weightedAverageProcessingMS": processing_ms / total_frames if total_frames else None,
        "representedRealSeconds": real_seconds,
        "wallClockSeconds": wall_seconds,
        "replaySpeedMultiple": real_seconds / wall_seconds if wall_seconds else None,
        "decisionDelayRealSeconds": {
            "minimum": delays[0] if delays else None,
            "median": percentile(delays, 0.5),
            "p95": percentile(delays, 0.95),
            "maximum": delays[-1] if delays else None,
        },
    }


def render_contact_sheets(video: Path, default_scale: float, labels: list[dict],
                          result: dict, out_dir: Path) -> None:
    if not SHEET_BIN.exists():
        print("  (contact-sheet binary missing; run with --build)", flush=True)
        return
    out_dir.mkdir(parents=True, exist_ok=True)
    half = 5

    def sheet(center: float, name: str, scale: float) -> None:
        step = 0.25 * scale  # 0.25 real-second steps, in source seconds
        times = [round(center + (k - half) * step, 3) for k in range(2 * half + 1)]
        times = [t for t in times if t >= 0]
        csv = ",".join(str(t) for t in times)
        out = out_dir / f"{name}.jpg"
        detections_json = out_dir / f"{name}.json"
        cmd = [str(SHEET_BIN), str(video), str(MODEL), csv, str(out), str(detections_json), "4", "360"]
        proc = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
        if proc.returncode != 0:
            raise RuntimeError(f"contact sheet failed for {video.name}: {proc.stderr.strip()}")

    for idx, label in enumerate(labels):
        scale = float(label.get("source_time_scale", default_scale))
        sheet(label_center(label), f"impact_{idx + 1}_t{int(label_center(label))}", scale)
    for di, det in enumerate(result.get("detections", [])):
        t = det.get("impactTime")
        if t is not None:
            sheet(t, f"detection_{di + 1}_t{int(t)}",
                  float(det.get("sourceTimeScale", default_scale)))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", nargs="*", help="fixture ids, e.g. test2 test11")
    parser.add_argument("--build", action="store_true", help="compile binaries first")
    parser.add_argument("--contact-sheets", action="store_true")
    parser.add_argument("--low-fps", type=float, default=8.0)
    parser.add_argument("--burst-fps", type=float, default=16.0)
    parser.add_argument("--compute", default="cpuAndNeuralEngine")
    parser.add_argument("--labels", type=Path, default=LABELS,
                        help="label manifest; defaults to the reviewed regression set")
    parser.add_argument("--fixtures-root", type=Path, default=FIXTURES,
                        help="directory containing manifest filenames")
    parser.add_argument("--out-root", type=Path, default=OUT_ROOT,
                        help="result directory")
    args = parser.parse_args()

    if args.build:
        build()
    if not V3_BIN.exists():
        print("v3 evaluator binary missing; run with --build", file=sys.stderr)
        return 2

    labels_by_id = load_labels(args.labels)
    selected = args.only if args.only else list(labels_by_id.keys())

    args.out_root.mkdir(parents=True, exist_ok=True)
    summary = {"params": {"lowFPS": args.low_fps, "burstFPS": args.burst_fps,
                          "compute": args.compute, "labels": str(args.labels),
                          "fixturesRoot": str(args.fixtures_root)}, "cases": {}}
    aggregate_cases: list[tuple[dict, dict]] = []
    any_fail = False

    for vid in selected:
        meta = labels_by_id.get(vid)
        if meta is None:
            print(f"[{vid}] not in labels; skipping")
            continue
        video = args.fixtures_root / meta["filename"]
        if not video.exists():
            print(f"[{vid}] video missing at {video}; skipping")
            continue
        scale = float(meta.get("source_time_scale", 1.0))
        impacts = meta.get("impact_time_labels", [])
        segments = configured_segments(meta, video_duration(video))

        result = run_detector(video, segments, args.low_fps, args.burst_fps, args.compute)
        sc = score(result, impacts, scale)
        tr = trace_summary(result)
        aggregate_cases.append((result, sc))

        case_dir = args.out_root / vid
        case_dir.mkdir(parents=True, exist_ok=True)
        (case_dir / "result.json").write_text(json.dumps(result, indent=2))
        if args.contact_sheets:
            render_contact_sheets(video, scale, impacts, result, case_dir / "sheets")

        summary["cases"][vid] = {"score": sc, "traces": tr,
                                 "segments": result.get("segments", []),
                                 "wallClockSec": result.get("wallClockElapsedSeconds"),
                                 "avgMS": result.get("averageProcessingTimeMS")}

        status = "PASS" if sc["passed"] else "FAIL"
        if not sc["passed"]:
            any_fail = True
        err = sc["meanImpactErrorRealSec"]
        err_str = f"{err:.3f}s" if err is not None else "n/a"
        print(f"[{vid}] {status}  expected={sc['expected']} detected={sc['detected']} "
              f"matched={sc['matched']} missed={len(sc['missed'])} fp={sc['falsePositives']} "
              f"impactErr={err_str}  candidates={tr['candidates']} "
              f"failures={tr['primaryFailures']}")

    summary["aggregate"] = aggregate_summary(aggregate_cases)
    aggregate = summary["aggregate"]
    (args.out_root / "summary.json").write_text(json.dumps(summary, indent=2))
    if aggregate["processedFrames"]:
        print(
            f"\nTOTAL matched={aggregate['matched']}/{aggregate['expected']} "
            f"missed={aggregate['missed']} fp={aggregate['falsePositives']} "
            f"speed={aggregate['replaySpeedMultiple']:.2f}x "
            f"frame={aggregate['weightedAverageProcessingMS']:.1f}ms"
        )
    else:
        print("\nTOTAL no fixtures processed")
    print(f"\nsummary -> {args.out_root / 'summary.json'}")
    return 1 if any_fail else 0


if __name__ == "__main__":
    raise SystemExit(main())
