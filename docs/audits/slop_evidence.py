#!/usr/bin/env python3
"""Inspect cleanup source references from the September 2026 slop audit.

Historical: the former --probe-tests fault-injection probes targeted backend
tests that were later renamed or deleted with the SAM3/3D modules. Recover them
from tag pre-legacy-cleanup-2026-10 if needed.
"""

import argparse
import ast
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[2]


def source_checks():
    paths = subprocess.check_output(
        ["git", "ls-files", "*.swift", "*.py"], cwd=ROOT, text=True
    ).splitlines()
    sources = {path: (ROOT / path).read_text() for path in paths
               if (ROOT / path).is_file() and not path.startswith("docs/audits/")}
    print(f"Tracked source inventory: {len(sources)} files, "
          f"{sum(len(text.splitlines()) for text in sources.values())} lines")

    symbols = [
        "OnDeviceSwingDetector", "LiveSwingDetector", "ModelBackedSwingDetector",
        "SwingDetectorV2AssetDetector", "AnalysisCard", "loadAndPlay",
        "VideoFileTransferable", "TrimSession", "updateAnnotatedVideoURL",
        "needsArtifactRefresh", "getDuration", "Body3DRunner", "Club3DFuser",
        "compute_dense_window", "choose_sparse_sample_rate",
    ]
    print("\nText references, including declarations, comments, and source lists.")
    print("These are review evidence, not an automatic safe-deletion decision.")
    for symbol in symbols:
        pattern = re.compile(r"\b" + symbol + r"\b")
        hits = [f"{path}:{number}" for path, text in sources.items()
                for number, line in enumerate(text.splitlines(), 1)
                if pattern.search(line)]
        print(f"{symbol}: {', '.join(hits)}")

    renderer = ast.parse(sources["backend/analysis/artifact_renderer.py"])
    render = next(node for node in ast.walk(renderer)
                  if isinstance(node, ast.FunctionDef) and node.name == "render")
    used = {node.id for statement in render.body for node in ast.walk(statement)
            if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load)}
    unused = [arg.arg for arg in render.args.args if arg.arg not in used]
    print("\nArtifactRenderer.render unused parameters:", ", ".join(unused))

    print("\nTop-level backend test functions and assert counts:")
    for path, text in sources.items():
        if not path.startswith("backend/test_") or not path.endswith(".py"):
            continue
        for node in ast.parse(text).body:
            if isinstance(node, ast.FunctionDef) and node.name.startswith("test_"):
                count = sum(isinstance(child, ast.Assert) for child in ast.walk(node))
                print(f"{path}:{node.lineno} {node.name}: {count} asserts")


if __name__ == "__main__":
    argparse.ArgumentParser(description=__doc__).parse_args()
    source_checks()
