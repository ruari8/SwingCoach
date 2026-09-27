"""Video evidence -> source-backed coaching -> mobile playback artifacts."""
from __future__ import annotations

from dataclasses import dataclass, asdict
import logging
import math
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from .artifact_renderer import ArtifactRenderer
from .coach_response_builder import CoachResponseBuilder, CoachingBundle
from .frame_extractor import FrameExtractor
from .metrics_engine import MetricCard
from .run_store import RunStore
from .video_observations import measure_poses

logger = logging.getLogger(__name__)


@dataclass
class Pipeline3DResult:
    run_id: str
    metrics: List[MetricCard]
    coaching: CoachingBundle
    artifacts: Dict[str, Optional[str]]
    quality: Dict[str, Any]
    run_dir: str


class SwingCoachPipeline3D:
    """Knowledge-backed 2D coaching foundation; no uncalibrated 3D claims."""

    def __init__(self, output_root=None, *, pose_detector_factory=None, coach_builder=None):
        self.output_root = Path(output_root) if output_root else Path(__file__).parent.parent / "output/runs"
        self.frame_extractor = FrameExtractor()
        self.artifact_renderer = ArtifactRenderer()
        self.pose_detector_factory = pose_detector_factory
        self.coach_builder = coach_builder

    def analyze_video(self, video_bytes: bytes, vantage="DTL", requested_fps=None,
                      student_goal=None, progress_callback=None, golfer_context=None) -> Pipeline3DResult:
        run_store = RunStore(self.output_root)
        warnings = []

        def emit(stage, progress, message):
            if progress_callback:
                progress_callback(stage, progress, message)

        emit("video_info", 0.05, "Reading video metadata")
        with run_store.stage("video_info"):
            info = self.frame_extractor.get_video_info(video_bytes)
            # Metadata FPS determines playback and timestamp alignment. A caller's
            # capture FPS can differ for slow-motion export; never silently retime.
            fps = float(info.get("fps") or requested_fps or 30)
            if not math.isfinite(fps) or fps <= 0:
                raise ValueError("Video frame rate must be positive")
            if requested_fps and abs(requested_fps - fps) > 0.1:
                warnings.append("Capture FPS differs from the file; measurements use the file playback timeline.")
            width, height = int(info["width"]), int(info["height"])
            run_store.save_json("input_meta.json", {**info, "fps": fps, "requested_fps": requested_fps,
                               "vantage": vantage, "student_goal": student_goal,
                               "golfer_context": golfer_context or {}, "pipeline_mode": "knowledge_coaching_v1"})

        emit("artifact_frames", 0.15, "Preparing video frames")
        with run_store.stage("artifact_frames"):
            frames = self.frame_extractor.extract_frames(video_bytes, sample_rate=1)
            if not frames:
                raise ValueError("Could not extract frames from uploaded video")
        # At most 180 pose samples covering the entire clip, normally about 15 Hz.
        interval = max(1, math.ceil(fps / 15), math.ceil(len(frames) / 180))
        indices = list(range(0, len(frames), interval))
        poses = []
        emit("observations", 0.3, "Tracking body movement and reference positions")
        with run_store.stage("observations"):
            try:
                factory = self.pose_detector_factory
                if factory is None:
                    from .pose_detector import PoseDetector
                    factory = PoseDetector
                with factory() as detector:
                    for index in indices:
                        pose = detector.detect_pose(frames[index], frame_index=index)
                        if pose is not None:
                            poses.append(pose)
            except (ImportError, FileNotFoundError, RuntimeError) as exc:
                logger.warning("Body tracking unavailable: %s", type(exc).__name__)
                warnings.append("Body tracking is unavailable for this run. No body measurements were inferred.")
                poses = []
            evidence = measure_poses(poses, fps=fps, width=width, height=height, vantage=vantage)
            warnings.extend(evidence.warnings)
            run_store.save_json("observations.json", {"version": 1, "samples": evidence.samples,
                                "observations": evidence.observations, "sample_interval": interval,
                                "sampled_frames": indices, "vantage": vantage})
            run_store.save_json("metrics.json", {"cards": evidence.metrics,
                                "raw": {c.key: c.value for c in evidence.metrics}})
            run_store.save_json("events.json", {"phases": [], "reason": "No validated phase detector in this pass"})

        emit("artifacts", 0.6, "Writing reference overlays and playback video")
        with run_store.stage("artifacts"):
            rendered = self.artifact_renderer.render(
                run_store=run_store, frames=frames, frame_indices=list(range(len(frames))),
                video_fps=fps, frame_width=width, frame_height=height,
                layers_by_frame=evidence.layers_by_frame, sample_interval=interval,
            )
        emit("coaching", 0.8, "Reviewing evidence against coaching cases")
        with run_store.stage("coaching"):
            builder = self.coach_builder or CoachResponseBuilder()
            # Evenly spaced source frames, bounded independently of source FPS.
            visual_indices = sorted({round(i * (len(frames) - 1) / max(min(24, len(frames)) - 1, 1))
                                     for i in range(min(24, len(frames)))})
            coaching = builder.build_coaching_bundle(
                evidence.metrics, warnings, student_goal,
                observations=evidence.observations, frames=[(i, frames[i]) for i in visual_indices],
                fps=fps, vantage=vantage, golfer_context=golfer_context,
            )
            run_store.save_json("coach_summary.json", asdict(coaching))
        run_store.finalize_timings()
        quality = {"warnings": warnings, "missing_data": ["clubface", "shaft", "pressure", "ball flight", "validated phases"],
                   "timings": run_store.timings,
                   "flags": {"pipeline_mode": "knowledge_coaching_v1", "annotations_enabled": bool(evidence.layers_by_frame),
                             "metrics_enabled": bool(evidence.metrics), "export_baked_overlays": False}}
        emit("pipeline_complete", 1.0, "Video evidence and coaching ready")
        return Pipeline3DResult(
            run_id=run_store.run_id, metrics=evidence.metrics, coaching=coaching, quality=quality,
            run_dir=str(run_store.run_dir), artifacts={
                "base_video_path": rendered.base_video_filename,
                "annotated_video_path": rendered.annotated_video_filename,
                "swing_3d_path": rendered.swing_3d_filename,
                "annotation_tracks_path": rendered.annotation_tracks_filename,
                "debug_paths": rendered.debug_files,
                "annotation_metadata": rendered.annotation_metadata,
            },
        )
