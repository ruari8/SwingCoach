#!/usr/bin/env python3
"""Fail when a physical Auto run drops frames after startup or lacks rollover coverage.

This checks camera delivery and writer input, not the exported video's decoder.
Pair it with analyze_auto_cadence.py on saved clips before accepting a jitter fix.
"""
import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--run-id")
    parser.add_argument("--minimum-rollovers", type=int, default=3)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    events = [json.loads(line) for line in args.log.read_text().splitlines() if line.strip()]
    run_id = args.run_id or next(e["runID"] for e in reversed(events) if e["boundary"] == "run")
    events = [e for e in events if e["runID"] == run_id]
    origin = next(e["uptime"] for e in events if e["boundary"] == "run")
    # Exclude the first two seconds explicitly; the first usable saved range
    # must also be inspected separately if accepting startup footage.
    steady = [e for e in events if e["uptime"] - origin >= 2]
    rollovers = [e for e in steady if e["boundary"] == "writer-sealed"
                 and e.get("state", {}).get("reason") == "rollover"]
    failures = []
    if len(rollovers) < args.minimum_rollovers:
        failures.append(f"Only {len(rollovers)} rollovers; need {args.minimum_rollovers}")
    for e in steady:
        cadence = e.get("cadence", {})
        if e["boundary"] in ("camera", "buffer-input", "writer"):
            if cadence.get("gaps", 0) or cadence.get("nonIncreasing", 0):
                failures.append({"boundary": e["boundary"], "elapsed": e["uptime"] - origin,
                                 "gaps": cadence.get("gaps"), "maxGapSeconds": cadence.get("maxGapSeconds")})
        if e["boundary"].endswith("failed"):
            failures.append({"boundary": e["boundary"], "state": e.get("state", {})})
    report = {"runID": run_id, "elapsedSeconds": events[-1]["uptime"] - origin,
              "rollovers": len(rollovers), "startupExcludedSeconds": 2,
              "passed": not failures, "failures": failures}
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"{'PASS' if report['passed'] else 'FAIL'}: {len(rollovers)} rollovers, {len(failures)} failures; {args.output}")
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
