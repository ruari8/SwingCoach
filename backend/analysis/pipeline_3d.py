"""Baseline orchestrator for SwingCoach video analysis.

The prior annotation implementation is preserved in git history. This pipeline
keeps the API and artifact contract alive while annotation semantics are rebuilt
from a clean specification.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional

from .artifact_renderer import ArtifactRenderer
from .coach_response_builder import CoachingBundle
from .frame_extractor import FrameExtractor
from .metrics_engine import MetricCard
from .run_store import RunStore


@dataclass
class Pipeline3DResult:
    run_id: str
    metrics: List[MetricCard]
    coaching: CoachingBundle
    artifacts: Dict[str, Optional[str]]
    quality: Dict[str, Any]
    run_dir: str


class SwingCoachPipeline3D:
    """Current backend pipeline: clean video artifacts, no generated annotations."""

    def __init__(self, output_root: Optional[str] = None):
        from pathlib import Path

        self.output_root = Path(output_root) if output_root else (Path(__file__).parent.parent / "output" / "runs")
        self.frame_extractor = FrameExtractor()
        self.artifact_renderer = ArtifactRenderer()

    def analyze_video(
        self,
        video_bytes: bytes,
        vantage: str = "DTL",
        requested_fps: Optional[float] = None,
        student_goal: Optional[str] = None,
        max_dense_frames: Optional[int] = None,
        progress_callback: Optional[Callable[[str, float, str], None]] = None,
    ) -> Pipeline3DResult:
        run_store = RunStore(self.output_root)
        warnings = ["Annotation generation is disabled while the annotation contract is being rebuilt."]

        def emit(stage: str, progress: float, message: str) -> None:
            if progress_callback:
                progress_callback(stage, max(0.0, min(1.0, progress)), message)

        emit("video_info", 0.05, "Reading video metadata")
        with run_store.stage("video_info"):
            video_info = self.frame_extractor.get_video_info(video_bytes)
            fps = float(requested_fps or video_info.get("fps") or 30.0)
            frame_count = int(video_info.get("frame_count") or 0)
            frame_width = int(video_info.get("width") or 1920)
            frame_height = int(video_info.get("height") or 1080)
            run_store.save_json(
                "input_meta.json",
                {
                    "vantage": vantage,
                    "fps": fps,
                    "frame_count": frame_count,
                    "frame_width": frame_width,
                    "frame_height": frame_height,
                    "requested_fps": requested_fps,
                    "student_goal": student_goal,
                    "max_dense_frames": max_dense_frames,
                    "pipeline_mode": "annotation_reset",
                },
            )

        emit("artifact_frames", 0.35, "Preparing clean video artifact")
        with run_store.stage("artifact_frames"):
            artifact_frames = self.frame_extractor.extract_frames(video_bytes, sample_rate=1)
            artifact_indices = list(range(len(artifact_frames)))
            if not artifact_frames:
                raise ValueError("Could not extract frames from uploaded video.")

        run_store.save_json(
            "events.json",
            {
                "sparse": {},
                "dense": {},
                "dense_window": None,
                "pipeline_mode": "annotation_reset",
            },
        )
        run_store.save_npz("poses_2d.npz", sparse=[], dense=[])
        run_store.save_npz("poses_3d.npz", dense=[])
        run_store.save_npz("club_2d.npz", frames=[])
        run_store.save_npz("club_3d.npz", frames=[])
        run_store.save_json("metrics.json", {"cards": [], "raw": {"metrics_enabled": False}})

        emit("artifacts", 0.75, "Writing clean artifact contract")
        with run_store.stage("artifacts"):
            rendered = self.artifact_renderer.render(
                run_store=run_store,
                frames=artifact_frames,
                poses2d=[],
                frame_indices=artifact_indices,
                video_fps=fps,
                frame_width=frame_width,
                frame_height=frame_height,
                club2d_frames=[],
                poses3d=[],
                club3d_frames=[],
                swing_phases=None,
                artifact_frames=artifact_frames,
                artifact_frame_indices=artifact_indices,
                export_baked_overlays=False,
            )

        emit("coaching", 0.9, "Building reset summary")
        coaching = CoachingBundle(
            summary=(
                "Clean swing video is ready. Generated annotations are temporarily disabled "
                "while the annotation set is rebuilt from a fresh specification."
            ),
            top_priorities=[
                "Define the next annotation contract before enabling automatic overlay generation."
            ],
            drills=[],
        )
        with run_store.stage("coaching"):
            run_store.save_json(
                "coach_summary.json",
                {
                    "summary": coaching.summary,
                    "top_priorities": coaching.top_priorities,
                    "drills": [],
                },
            )

        run_store.finalize_timings()

        quality = {
            "warnings": warnings,
            "missing_data": [],
            "timings": run_store.timings,
            "flags": {
                "pipeline_mode": "annotation_reset",
                "annotations_enabled": False,
                "metrics_enabled": False,
                "export_baked_overlays": False,
            },
        }

        emit("pipeline_complete", 1.0, "Pipeline complete")
        return Pipeline3DResult(
            run_id=run_store.run_id,
            metrics=[],
            coaching=coaching,
            artifacts={
                "base_video_path": rendered.base_video_filename,
                "annotated_video_path": rendered.annotated_video_filename,
                "swing_3d_path": rendered.swing_3d_filename,
                "annotation_tracks_path": rendered.annotation_tracks_filename,
                "debug_paths": rendered.debug_files,
                "annotation_metadata": rendered.annotation_metadata,
            },
            quality=quality,
            run_dir=str(run_store.run_dir),
        )
