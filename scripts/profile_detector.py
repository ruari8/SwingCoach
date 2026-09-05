#!/usr/bin/env python3
"""Profile the real V3 Mac evaluator with isolated builds and explicit footage."""
import argparse
import hashlib
import importlib.util
import json
import math
import shutil
import statistics
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--start", type=float, default=0)
    parser.add_argument("--end", type=float)
    parser.add_argument("--source-time-scale", type=float, default=1)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--compute", default="cpuAndNeuralEngine", choices=["cpuOnly", "cpuAndNeuralEngine", "all"])
    parser.add_argument("--compare", type=Path)
    args = parser.parse_args()
    if not args.video.is_file():
        parser.error(f"Required video is missing: {args.video}")
    if args.runs < 1:
        parser.error("--runs must be positive")
    if not math.isfinite(args.start) or args.start < 0:
        parser.error("--start must be a finite nonnegative time")
    if args.end is not None and (not math.isfinite(args.end) or args.end <= args.start):
        parser.error("--end must be finite and later than --start")
    if not math.isfinite(args.source_time_scale) or args.source_time_scale <= 0:
        parser.error("--source-time-scale must be finite and positive")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    def run(command, timeout=600):
        started = time.perf_counter()
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout, cwd=ROOT)
        with (output / "commands.log").open("a") as log:
            log.write(json.dumps(command) + f"\nexit={result.returncode}, seconds={time.perf_counter()-started:.3f}\n" + result.stderr)
        if result.returncode:
            raise RuntimeError(f"Command failed: {command}; see commands.log")
        return result.stdout
    module_path = ROOT / "detector_workbench/validation/evaluate_swing_detector_v3.py"
    spec = importlib.util.spec_from_file_location("v3_recipe", module_path)
    recipe = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(recipe)
    relative_sources = recipe.expand_sources(recipe.V3_SOURCES)
    hashes = {}
    for relative in relative_sources:
        source = ROOT / relative
        destination = output / "source" / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        hashes[relative] = hashlib.sha256(source.read_bytes()).hexdigest()
    model = ROOT / "SwingCoach/MLModels/SwingObjectsYOLO11n.mlpackage"
    model_hashes = {str(p.relative_to(model)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(model.rglob('*')) if p.is_file()}
    with args.video.open('rb') as video_file:
        video_hash = hashlib.file_digest(video_file, 'sha256').hexdigest()
    settings = {"videoSHA256": video_hash, "start": args.start, "end": args.end,
                "sourceTimeScale": args.source_time_scale, "lowFPS": 8, "burstFPS": 16, "compute": args.compute,
                "modelHashes": model_hashes}
    previous = json.loads(args.compare.read_text()) if args.compare else None
    def outputs_stable(samples):
        return bool(samples) and all(
            (s["detections"], s["decodedFrames"], s["processedFrames"]) ==
            (samples[0]["detections"], samples[0]["decodedFrames"], samples[0]["processedFrames"])
            for s in samples)
    if previous and not outputs_stable(previous["samples"]):
        parser.error("Baseline outputs vary between runs; investigate before comparing")
    if previous and previous["settings"] != settings:
        parser.error("Comparison requires the same footage, model, and settings")
    binary = output / "evaluate_v3"
    build = ["xcrun", "swiftc", "-parse-as-library", "-O"]
    for framework in recipe.FRAMEWORKS:
        build += ["-framework", framework]
    build += [str(output / "source" / path) for path in relative_sources] + ["-o", str(binary)]
    run(build)
    report = {"route": "Mac AVFoundation/CoreML evaluator, not physical iPhone", "settings": settings,
              "sourceHashes": hashes, "gitRevision": run(["git", "rev-parse", "HEAD"]).strip(),
              "gitStatus": run(["git", "status", "--short"]), "swift": run(["xcrun", "swiftc", "--version"]),
              "samples": []}
    for index in range(args.runs):
        command = [str(binary), str(args.video.resolve()), str(model), '8', str(args.source_time_scale),
                   '400000', '16', args.compute, str(args.start)]
        if args.end is not None:
            command.append(str(args.end))
        started = time.perf_counter()
        data = json.loads(run(command))
        (output / f"sample-{index + 1}.json").write_text(json.dumps(data, indent=2) + '\n')
        sample = {key: data[key] for key in ["decodedFrames", "processedFrames", "averageProcessingTimeMS",
                  "wallClockElapsedSeconds", "sampleReadSeconds", "sampleProcessingSeconds", "modelSetupSeconds", "detections"]}
        sample["processSeconds"] = time.perf_counter() - started
        report["samples"].append(sample)
        print(f"Run {index+1}: {sample['wallClockElapsedSeconds']:.3f}s, read wait {sample['sampleReadSeconds']:.3f}s, processing {sample['sampleProcessingSeconds']:.3f}s; {len(sample['detections'])} swings", flush=True)
    report["medians"] = {key: statistics.median(s[key] for s in report["samples"]) for key in
                         ["wallClockElapsedSeconds", "sampleReadSeconds", "sampleProcessingSeconds", "modelSetupSeconds", "processSeconds"]}
    report["outputsStable"] = outputs_stable(report["samples"])
    if previous:
        report["comparison"] = {
            "speedup": previous["medians"]["wallClockElapsedSeconds"] / report["medians"]["wallClockElapsedSeconds"],
            "detectionsIdentical": all(s["detections"] == previous["samples"][0]["detections"] for s in report["samples"]),
            "sampleCountsIdentical": all((s["decodedFrames"], s["processedFrames"]) ==
                                          (previous["samples"][0]["decodedFrames"], previous["samples"][0]["processedFrames"]) for s in report["samples"]),
        }
    (output / "report.json").write_text(json.dumps(report, indent=2) + '\n')
    if not report["outputsStable"]:
        raise SystemExit(f"FAIL: detector outputs vary between runs; see {output / 'report.json'}")
    if previous and not (report["comparison"]["detectionsIdentical"] and report["comparison"]["sampleCountsIdentical"]):
        raise SystemExit(f"FAIL: detector outputs changed; see {output / 'report.json'}")
    print(json.dumps(report["medians"], indent=2))
    print(f"PASS: {output / 'report.json'}")


if __name__ == '__main__':
    main()
