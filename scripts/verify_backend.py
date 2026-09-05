#!/usr/bin/env python3
"""Run the offline backend checks and retain readiness, logs, and exit status."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--python", help="Python with backend/requirements-verification.txt installed")
    parser.add_argument("--output", type=Path, help="New evidence directory; defaults to a unique ignored directory")
    args = parser.parse_args()
    local_python = ROOT / "backend" / "venv" / "bin" / "python"
    python = args.python or (str(local_python) if local_python.exists() else sys.executable)
    output = args.output or ROOT / ".verification-artifacts" / "backend" / uuid.uuid4().hex[:12]
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    checks = [
        ("python", [python, "-c", "import sys,numpy; print(sys.executable); print(sys.version); print('numpy='+numpy.__version__)"]),
        ("ffmpeg", ["ffmpeg", "-version"]),
        ("ffprobe", ["ffprobe", "-version"]),
        ("git-revision", ["git", "rev-parse", "HEAD"]),
        ("git-status", ["git", "status", "--short"]),
        ("artifact-contract", [python, "-m", "unittest", "-v", "test_annotation_tracks"]),
        ("run-lifecycle", [python, "test_analysis_runs.py"]),
    ]
    report = {"root": str(ROOT), "python": python, "checks": [], "passed": False}
    try:
        for name, command in checks:
            started = time.perf_counter()
            with (output / f"{name}.log").open("w") as log:
                log.write(json.dumps(command) + "\n")
                log.flush()
                result = subprocess.run(command, cwd=ROOT / "backend", stdout=log, stderr=subprocess.STDOUT, timeout=120)
            report["checks"].append({"name": name, "exit_code": result.returncode, "seconds": time.perf_counter() - started})
            if result.returncode:
                raise RuntimeError(f"{name} failed; see {output / (name + '.log')}")
            print(f"PASS: {name}", flush=True)
        report["passed"] = True
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        report["error"] = str(error)
        print(f"FAIL: {error}", file=sys.stderr)
        print("Setup: python3 -m venv backend/venv && backend/venv/bin/python -m pip install -r backend/requirements-verification.txt", file=sys.stderr)
        print("FFmpeg and ffprobe must be on PATH; the rotation fixtures require FFmpeg 6 or later.", file=sys.stderr)
    finally:
        (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Evidence: {output}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
