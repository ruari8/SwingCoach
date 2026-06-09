#!/usr/bin/env python3
"""Local integration test for unified SwingCoachPipeline3D."""

from __future__ import annotations

import argparse
import logging
from pathlib import Path

from analysis.pipeline_3d import SwingCoachPipeline3D

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def test_pipeline_reset_mode_is_annotation_free() -> None:
    pipeline = SwingCoachPipeline3D()

    assert not hasattr(pipeline, "_capped_dense_indices")
    assert not hasattr(pipeline, "metrics_engine")
    assert not hasattr(pipeline, "coach_builder")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run unified 3D pipeline on a local video")
    parser.add_argument(
        "video_path",
        nargs="?",
        default=str(Path(__file__).parent / "swingVideos" / "IMG_0737.mov"),
        help="Path to local swing video",
    )
    parser.add_argument("--vantage", default="DTL", choices=["DTL", "FO"], help="Camera vantage")
    parser.add_argument("--fps", type=float, default=None, help="Override fps")
    parser.add_argument("--goal", type=str, default=None, help="Student goal for coaching summary")
    parser.add_argument(
        "--max-dense",
        type=int,
        default=12,
        help="Cap dense frames for faster test runs (default: 12)",
    )

    args = parser.parse_args()

    video_path = Path(args.video_path)
    if not video_path.exists():
        logger.error("Video not found: %s", video_path)
        return 1

    pipeline = SwingCoachPipeline3D()
    result = pipeline.analyze_video(
        video_bytes=video_path.read_bytes(),
        vantage=args.vantage,
        requested_fps=args.fps,
        student_goal=args.goal,
        max_dense_frames=args.max_dense,
    )

    logger.info("Run complete: %s", result.run_id)
    logger.info("Run dir: %s", result.run_dir)

    logger.info("Metrics:")
    for metric in result.metrics:
        logger.info(
            "- %s: %s %s (confidence %.2f)",
            metric.name,
            metric.value,
            metric.unit,
            metric.confidence,
        )

    logger.info("Summary: %s", result.coaching.summary)
    logger.info("Top priorities: %s", result.coaching.top_priorities)
    logger.info("Artifacts: %s", result.artifacts)
    logger.info("Warnings: %s", result.quality.get("warnings", []))
    return 0


if __name__ == "__main__":
    test_pipeline_reset_mode_is_annotation_free()
    raise SystemExit(main())
