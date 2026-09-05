#!/usr/bin/env python3
"""Exercise the annotation-reset pipeline on synthetic video or a supplied clip."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import tempfile

from analysis.pipeline_3d import SwingCoachPipeline3D


def test_pipeline_reset_mode_is_annotation_free() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        source = root / "source.mp4"
        subprocess.run([
            "ffmpeg", "-v", "error", "-f", "lavfi", "-i",
            "color=c=green:s=96x64:r=12:d=1", "-c:v", "libx264",
            "-pix_fmt", "yuv420p", str(source),
        ], check=True)
        pipeline = SwingCoachPipeline3D(output_root=str(root / "runs"))
        progress = []
        result = pipeline.analyze_video(
            source.read_bytes(),
            progress_callback=lambda stage, fraction, message: progress.append((stage, fraction)),
        )
        run = Path(result.run_dir)
        base = (run / "base.mp4").read_bytes()
        assert base == (run / "annotated.mp4").read_bytes()
        info = pipeline.frame_extractor.get_video_info(base)
        assert info["frame_count"] == 12
        assert info["width"] == 96 and info["height"] == 64
        assert abs(info["fps"] - 12) < 0.01
        assert result.metrics == [] and result.coaching.drills == []
        assert result.quality["flags"]["annotations_enabled"] is False
        assert result.quality["flags"]["metrics_enabled"] is False
        assert progress[-1] == ("pipeline_complete", 1.0)
        metadata = json.loads((run / "annotation_metadata.json").read_text())
        tracks = json.loads((run / "annotation_tracks.json").read_text())
        assert metadata["layers"] == [] and metadata["annotations_enabled"] is False
        assert tracks["guide_layers"] == [] and tracks["phase_markers"] == []
        assert len(tracks["frames"]) == 12
        assert all(frame["layers"] == {} for frame in tracks["frames"])
        assert [frame["frame_index"] for frame in tracks["frames"]] == list(range(12))
        assert abs(tracks["frames"][-1]["timestamp"] - 11 / 12) < 0.0001
        # Check actual decoded pixels as well as metadata: an overlay must not
        # sneak into both compatibility files while they still compare equal.
        decoded = subprocess.check_output([
            "ffmpeg", "-v", "error", "-i", str(run / "base.mp4"),
            "-f", "rawvideo", "-pix_fmt", "rgb24", "-",
        ])
        original = subprocess.check_output([
            "ffmpeg", "-v", "error", "-i", str(source),
            "-f", "rawvideo", "-pix_fmt", "rgb24", "-",
        ])
        assert len(decoded) == len(original) == 12 * 96 * 64 * 3
        assert max(abs(a - b) for a, b in zip(decoded, original)) <= 5


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video_path", nargs="?", type=Path,
                        help="Optional local clip for a manual pipeline run")
    parser.add_argument("--vantage", default="DTL", choices=["DTL", "FO"])
    parser.add_argument("--fps", type=float)
    parser.add_argument("--goal")
    args = parser.parse_args()
    test_pipeline_reset_mode_is_annotation_free()
    print("Synthetic pipeline output checks passed")
    if args.video_path is not None:
        result = SwingCoachPipeline3D().analyze_video(
            args.video_path.read_bytes(), vantage=args.vantage,
            requested_fps=args.fps, student_goal=args.goal,
        )
        print(f"Manual run artifacts: {result.run_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
