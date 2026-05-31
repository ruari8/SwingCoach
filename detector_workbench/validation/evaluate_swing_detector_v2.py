#!/usr/bin/env python3
"""
Fail-fast fixture harness for SwingDetectorV2.

Runs the v2 Swift evaluator on V3 fixtures, scores accepted swings against
`detector_test_v3_labels.json` (count, matched, missed, false positives,
impact-time error), summarises the per-candidate evidence traces, and (with
--contact-sheets) renders annotated YOLO contact sheets around each labelled
impact and each false positive for visual debugging.

The detector and labels both live on the SOURCE timeline; the v2 detector is
told each clip's `source_time_scale` so detection times come back in source
seconds. Impact-time error is reported in REAL seconds (source / scale).

Examples:
  python3 detector_workbench/validation/evaluate_swing_detector_v2.py --build --only test2
  python3 detector_workbench/validation/evaluate_swing_detector_v2.py --only test2 --contact-sheets
  python3 detector_workbench/validation/evaluate_swing_detector_v2.py            # all active fixtures
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LABELS = REPO / "detector_workbench/validation/labels/detector_test_v3_labels.json"
FIXTURES = REPO / ".detectorTestV3"
MODEL = REPO / "SwingCoach/MLModels/SwingObjectsYOLO11n.mlpackage"
V2_BIN = REPO / ".videos/bin/evaluate_swing_detector_v2"
SHEET_BIN = REPO / ".videos/bin/generate_model_detection_contact_sheet"
OUT_ROOT = FIXTURES / "perf_v2"

V2_SOURCES = [
    "SwingCoach/Models/OnDeviceSwingDetector.swift",
    "SwingCoach/Models/LiveSwingDetector.swift",
    "SwingCoach/Models/LiveSwingDetecting.swift",
    "SwingCoach/Models/GolfObjectDetector.swift",
    "SwingCoach/Models/SwingDetectorV2",  # expands to *.swift below
    "detector_workbench/validation/evaluate_swing_detector_v2.swift",
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
    swiftc(V2_SOURCES, V2_BIN)
    swiftc(SHEET_SOURCES, SHEET_BIN)


def load_labels() -> dict:
    data = json.loads(LABELS.read_text())
    return {v["id"]: v for v in data["videos"]}


def run_detector(video: Path, scale: float, low_fps: float, burst_fps: float, compute: str) -> dict:
    cmd = [
        str(V2_BIN), str(video), str(MODEL),
        str(low_fps), str(scale), "400000", str(burst_fps), compute,
    ]
    proc = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"v2 evaluator failed for {video.name}: {proc.stderr.strip()}")
    return json.loads(proc.stdout)


def label_center(label: dict) -> float:
    return (label["start"] + label["end"]) / 2.0


def score(result: dict, labels: list[dict], scale: float) -> dict:
    """Match accepted detections to impact labels on the source timeline."""
    tol = max(1.0, 1.0 * scale)  # +/- 1 real second, expressed in source seconds
    detections = result.get("detections", [])
    det_impacts = [d.get("impactTime") for d in detections]

    matched_labels = []
    impact_errors_real = []
    used = set()
    for idx, label in enumerate(labels):
        lo, hi = label["start"] - tol, label["end"] + tol
        best = None
        for di, t in enumerate(det_impacts):
            if di in used or t is None:
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


def render_contact_sheets(video: Path, scale: float, labels: list[dict],
                          result: dict, out_dir: Path) -> None:
    if not SHEET_BIN.exists():
        print("  (contact-sheet binary missing; run with --build)", flush=True)
        return
    out_dir.mkdir(parents=True, exist_ok=True)
    step = 0.25 * scale  # 0.25 real-second steps, in source seconds
    half = 5

    def sheet(center: float, name: str) -> None:
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
        sheet(label_center(label), f"impact_{idx + 1}_t{int(label_center(label))}")
    for di, det in enumerate(result.get("detections", [])):
        t = det.get("impactTime")
        if t is not None:
            sheet(t, f"detection_{di + 1}_t{int(t)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", nargs="*", help="fixture ids, e.g. test2 test11")
    parser.add_argument("--build", action="store_true", help="compile binaries first")
    parser.add_argument("--contact-sheets", action="store_true")
    parser.add_argument("--low-fps", type=float, default=8.0)
    parser.add_argument("--burst-fps", type=float, default=16.0)
    parser.add_argument("--compute", default="cpuAndNeuralEngine")
    args = parser.parse_args()

    if args.build:
        build()
    if not V2_BIN.exists():
        print("v2 evaluator binary missing; run with --build", file=sys.stderr)
        return 2

    labels_by_id = load_labels()
    selected = args.only if args.only else list(labels_by_id.keys())

    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    summary = {"params": {"lowFPS": args.low_fps, "burstFPS": args.burst_fps,
                          "compute": args.compute}, "cases": {}}
    any_fail = False

    for vid in selected:
        meta = labels_by_id.get(vid)
        if meta is None:
            print(f"[{vid}] not in labels; skipping")
            continue
        video = FIXTURES / meta["filename"]
        if not video.exists():
            print(f"[{vid}] video missing at {video}; skipping")
            continue
        scale = float(meta.get("source_time_scale", 1.0))
        impacts = meta.get("impact_time_labels", [])

        result = run_detector(video, scale, args.low_fps, args.burst_fps, args.compute)
        sc = score(result, impacts, scale)
        tr = trace_summary(result)

        case_dir = OUT_ROOT / vid
        case_dir.mkdir(parents=True, exist_ok=True)
        (case_dir / "result.json").write_text(json.dumps(result, indent=2))
        if args.contact_sheets:
            render_contact_sheets(video, scale, impacts, result, case_dir / "sheets")

        summary["cases"][vid] = {"score": sc, "traces": tr,
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

    (OUT_ROOT / "summary.json").write_text(json.dumps(summary, indent=2))
    print(f"\nsummary -> {OUT_ROOT / 'summary.json'}")
    return 1 if any_fail else 0


if __name__ == "__main__":
    raise SystemExit(main())
