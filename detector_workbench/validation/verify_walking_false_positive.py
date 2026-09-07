#!/usr/bin/env python3
"""Replay issue #29's exact negative and three smooth controls in both modes."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

from evaluate_swing_detector_v3 import REPO, MODEL, V3_SOURCES, expand_sources, swiftc

MANIFEST = Path(__file__).with_name("fixtures") / "2026-09-06-walking-regression.json"


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    for case in manifest["cases"]:
        video = args.fixtures_root / case["filename"]
        if not video.is_file() or sha256(video) != case["sha256"]:
            parser.error(f"Missing or changed fixture: {video}")

    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    binary = output / "evaluate_v3"
    report = {
        "route": "Mac AVFoundation/Core ML; no physical iPhone",
        "manifestSHA256": sha256(MANIFEST),
        "sourceHashes": {p: sha256(REPO / p) for p in expand_sources(V3_SOURCES)},
        "modelHashes": {str(p.relative_to(MODEL)): sha256(p)
                        for p in sorted(MODEL.rglob("*")) if p.is_file()},
        "cases": [],
    }
    swiftc(V3_SOURCES, binary)
    for case in manifest["cases"]:
        for practice in [False, True]:
            command = [str(binary), str((args.fixtures_root / case["filename"]).resolve()),
                       str(MODEL), "8", str(manifest["source_time_scale"]),
                       "400000", "16", "cpuAndNeuralEngine"]
            if practice:
                command.append("--practice-swings")
            result = subprocess.run(command, cwd=REPO, capture_output=True, text=True)
            stem = Path(case["filename"]).stem + ("-practice" if practice else "-contact")
            (output / f"{stem}.stderr.log").write_text(result.stderr)
            result.check_returncode()
            (output / f"{stem}.json").write_text(result.stdout)
            data = json.loads(result.stdout)
            detections = data["detections"]
            # Exact control comparison includes timestamps, clip bounds and confidence.
            # The negative must become empty, not merely score lower.
            passed = len(detections) == case["expected_count"]
            if case["expected_count"]:
                passed = passed and detections == case["baseline_detections"]
            passed = passed and data["processedFrames"] > 0
            row = {"filename": case["filename"], "videoSHA256": case["sha256"],
                   "practice": practice, "passed": passed, "command": command,
                   "detections": detections, "decisions": data["decisions"],
                   "decodedFrames": data["decodedFrames"], "processedFrames": data["processedFrames"]}
            report["cases"].append(row)
            print(f"{'PASS' if passed else 'FAIL'} {stem}: {len(detections)} detections", flush=True)
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    return 0 if all(case["passed"] for case in report["cases"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
