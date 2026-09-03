#!/usr/bin/env python3
"""Audit a frozen V3 fixture run and export event-level matches and failures.

The run directory contains run-inputs.json (file hashes recorded before the
run) and results/ (the V3 evaluator output). Run from the repository root.
This check targets whole-video, constant-speed fixtures with separated labels.
It does not change labels or detector settings.
"""

import argparse
import hashlib
import json
from pathlib import Path

from evaluate_swing_detector_v3 import aggregate_summary, score


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def audit(run_root):
    frozen = json.loads((run_root / "run-inputs.json").read_text())
    label_path = Path(frozen["labels"])
    require(digest(label_path) == frozen["labels_sha256"], "Label file changed")
    manifest = json.loads(label_path.read_text())
    require(manifest["review_status"] == "user_approved_ball_hit_labels",
            "Labels lack user approval")
    for name, expected in frozen["source_and_model_sha256"].items():
        require(digest(Path(name)) == expected, f"Source/model changed: {name}")

    labels = {video["id"]: video for video in manifest["videos"]}
    inputs = {video["id"]: video for video in frozen["inputs"]}
    summary = json.loads((run_root / "results/summary.json").read_text())
    require(set(labels) == set(inputs) == set(summary["cases"]),
            "Run did not cover exactly the frozen fixture set")
    require(Path(summary["params"]["labels"]).resolve() == label_path.resolve(),
            "Evaluator used a different label file")

    events = []
    aggregate_cases = []
    coverage = []
    for video_id, meta in labels.items():
        source = inputs[video_id]
        require(digest(Path(source["path"])) == source["sha256"] == meta["input_sha256"],
                f"Video bytes changed: {video_id}")
        scale = float(meta["source_time_scale"])
        require(not meta.get("segments"), "This audit expects constant-speed fixtures")
        result_path = run_root / "results" / video_id / "result.json"
        result = json.loads(result_path.read_text())
        require(Path(result["video"]).resolve() == Path(source["path"]).resolve(),
                f"Wrong evaluated video: {video_id}")
        settings = frozen["settings"]
        require(result["lowSampleFPS"] == settings["low_fps"]
                and result["burstSampleFPS"] == settings["burst_fps"]
                and result["computeUnits"] == settings["compute"],
                f"Unexpected runtime settings: {video_id}")
        require(len(result["segments"]) == 1
                and result["segments"][0]["sourceTimeScale"] == scale,
                f"Unexpected timing segments: {video_id}")
        observations = result["observations"]
        sampling = result["sampling"]
        # Detailed object observations retain only the newest 4,000 frames.
        # Sampling traces cover every processed frame, including long fixtures.
        require(observations and sampling and len(sampling) == result["processedFrames"]
                and len(observations) <= len(sampling),
                f"Missing frame traces: {video_id}")
        require(0 <= sampling[0]["sourceTime"] < scale
                and 0 <= result["duration"] - sampling[-1]["sourceTime"] < scale
                and observations[-1]["sourceTime"] == sampling[-1]["sourceTime"],
                f"Incomplete timeline coverage: {video_id}")

        impacts = meta["impact_time_labels"]
        centers = [(label["start"] + label["end"]) / 2 for label in impacts]
        tolerance = max(1.0, scale)
        require(all(b["start"] - a["end"] > 2 * tolerance
                    for a, b in zip(impacts, impacts[1:])),
                "Independent event audit requires non-overlapping match windows")
        used = set()
        for index, center in enumerate(centers):
            candidates = [(abs(det["impactTime"] - center), n, det)
                          for n, det in enumerate(result["detections"])
                          if det.get("impactTime") is not None
                          and impacts[index]["start"] - tolerance <= det["impactTime"]
                          <= impacts[index]["end"] + tolerance]
            best = min(candidates, default=None, key=lambda row: (row[0], row[1]))
            row = {"video_id": video_id, "label_id": impacts[index]["id"],
                   "label_playback_seconds": center,
                   "label_interval": [impacts[index]["start"], impacts[index]["end"]],
                   "outcome": "matched" if best else "missed"}
            if best:
                error, n, det = best
                require(n not in used, "Detection matched more than one label")
                used.add(n)
                row.update({"detection_index": n,
                            "detected_playback_seconds": det["impactTime"],
                            "impact_error_real_seconds": error / scale,
                            "declared_playback_seconds": det.get("declaredAt")})
            events.append(row)
        for n, det in enumerate(result["detections"]):
            if n not in used:
                events.append({"video_id": video_id, "outcome": "false_positive",
                               "detection_index": n,
                               "detected_playback_seconds": det.get("impactTime"),
                               "declared_playback_seconds": det.get("declaredAt")})

        rescored = score(result, impacts, scale)
        require(rescored == summary["cases"][video_id]["score"],
                f"Summary differs from raw detections: {video_id}")
        require(len(used) == rescored["matched"], "Independent matching disagrees")
        aggregate_cases.append((result, rescored))
        coverage.append({"video_id": video_id, "result_sha256": digest(result_path),
                         "decoded_frames": result["decodedFrames"],
                         "analyzed_frames": result["processedFrames"],
                         "retained_object_observation_frames": len(observations),
                         "last_analyzed_playback_seconds": sampling[-1]["sourceTime"],
                         "duration_playback_seconds": result["duration"]})
    aggregate = aggregate_summary(aggregate_cases)
    require(aggregate == summary["aggregate"], "Aggregate differs from raw results")
    return {"verification": "passed", "labels_sha256": frozen["labels_sha256"],
            "match_tolerance_real_seconds": 1, "aggregate": aggregate,
            "coverage": coverage, "events": events}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_root", type=Path)
    args = parser.parse_args()
    result = audit(args.run_root)
    output = args.run_root / "audit.json"
    output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result["aggregate"], indent=2))
    print(f"Verified source/video/label hashes, full coverage and scoring: {output}")
