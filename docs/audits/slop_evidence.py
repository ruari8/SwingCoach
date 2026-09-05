#!/usr/bin/env python3
"""Inspect cleanup source references and prove that repaired tests reject faults.

Run with Python for source checks. Add --probe-tests with backend/venv/bin/python
to run output checks and inject faults. Probes use temporary local video and
animation files. No model inference or network requests are performed.
"""

import argparse
import ast
import logging
from pathlib import Path
import re
import subprocess
import sys
from unittest.mock import patch


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


def probe_tests():
    sys.path.insert(0, str(ROOT / "backend"))
    logging.disable(logging.CRITICAL)
    import test_pipeline_3d
    import test_temporal_smoothing
    import test_animation_export

    # A healthy baseline prevents missing dependencies from looking like a
    # successful fault-rejection check.
    test_pipeline_3d.test_pipeline_reset_mode_is_annotation_free()
    test_temporal_smoothing.test_synthetic_noisy_sequence()
    test_animation_export.test_animation_export_synthetic()

    def rejects(label, check):
        try:
            check()
        except AssertionError:
            print(f"PASS: {label} rejected")
        else:
            raise AssertionError(f"Test accepted {label}")

    for label, replacement in [
        ("identity smoothing", lambda self, poses: poses),
        ("frozen movement", lambda self, poses: [poses[0]] * len(poses)),
    ]:
        with patch.object(test_temporal_smoothing.TemporalSmoother, "smooth_poses", replacement):
            rejects(label, test_temporal_smoothing.test_synthetic_noisy_sequence)

    analyze = test_pipeline_3d.SwingCoachPipeline3D.analyze_video

    def unexpected_metrics(self, *args, **kwargs):
        result = analyze(self, *args, **kwargs)
        result.metrics = [object()]
        return result

    with patch.object(test_pipeline_3d.SwingCoachPipeline3D, "analyze_video", unexpected_metrics):
        rejects("metrics in reset output", test_pipeline_3d.test_pipeline_reset_mode_is_annotation_free)

    # Exercise the real command exit status as well as its test function.
    failed_export = subprocess.run([
        sys.executable, "-c",
        "import runpy; from unittest.mock import patch; "
        "from analysis.animation_exporter import AnimationExporter; "
        "patch.object(AnimationExporter, 'export_animation', return_value=False).start(); "
        "runpy.run_path('test_animation_export.py', run_name='__main__')",
    ], cwd=ROOT / "backend", capture_output=True, text=True)
    assert failed_export.returncode != 0
    assert "AssertionError: Animation export failed" in failed_export.stderr
    print("PASS: failed animation export produces a failing command")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe-tests", action="store_true")
    args = parser.parse_args()
    source_checks()
    if args.probe_tests:
        probe_tests()
