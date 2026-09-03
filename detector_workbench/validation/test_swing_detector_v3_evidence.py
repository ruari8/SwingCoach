#!/usr/bin/env python3
"""Build and run fast production-module regression checks without model inference."""
import argparse
import subprocess


def main():
    from evaluate_swing_detector_v3 import REPO, V3_SOURCES, swiftc

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", action="store_true")
    args = parser.parse_args()
    binary = REPO / ".videos/bin/test_swing_detector_v3_evidence"
    if args.build or not binary.exists():
        sources = V3_SOURCES[:-1] + ["detector_workbench/validation/test_swing_detector_v3_evidence.swift"]
        swiftc(sources, binary)
    return subprocess.run([str(binary)], cwd=REPO).returncode


if __name__ == "__main__":
    raise SystemExit(main())
