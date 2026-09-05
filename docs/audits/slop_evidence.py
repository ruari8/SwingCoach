#!/usr/bin/env python3
"""Reproduce the September 2026 slop audit evidence without changing app code.

Run with Python for source checks. Add --probe-tests with backend/venv/bin/python
to demonstrate the weak tests using in-memory replacements. No model inference,
network requests, or video exports are performed by these probes.
"""

import argparse
import ast
import logging
from pathlib import Path
import re
import runpy
import subprocess
import sys
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]


def source_checks():
    paths = subprocess.check_output(
        ["git", "ls-files", "*.swift", "*.py"], cwd=ROOT, text=True
    ).splitlines()
    sources = {path: (ROOT / path).read_text() for path in paths}
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


def probe_tests():
    sys.path.insert(0, str(ROOT / "backend"))
    logging.disable(logging.CRITICAL)
    import test_pipeline_3d
    import test_temporal_smoothing
    from analysis.animation_exporter import AnimationExporter

    with patch.object(test_temporal_smoothing.TemporalSmoother, "smooth_poses",
                      lambda self, poses: poses):
        result = test_temporal_smoothing.test_synthetic_noisy_sequence()
        print(f"\nIdentity smoother accepted by synthetic test: {result}")
        assert result is True, "Original audit finding has changed; reassess."

    with patch.object(test_pipeline_3d.SwingCoachPipeline3D, "analyze_video",
                      side_effect=AssertionError("Output must be exercised")) as analyze:
        test_pipeline_3d.test_pipeline_reset_mode_is_annotation_free()
        print(f"Annotation-free test passed; analyze_video calls: {analyze.call_count}")
        assert analyze.call_count == 0, "Original audit finding has changed; reassess."

    # Run the real script entry point. Returning False prevents all export I/O.
    with patch.object(AnimationExporter, "export_animation", return_value=False), \
         patch.object(sys, "argv", ["test_animation_export.py"]):
        runpy.run_path(str(ROOT / "backend/test_animation_export.py"), run_name="__main__")
    print("Animation script terminated normally despite forced export failure.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe-tests", action="store_true")
    args = parser.parse_args()
    source_checks()
    if args.probe_tests:
        probe_tests()
