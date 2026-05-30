"""Unified orchestrator for coachable swing analysis."""

from __future__ import annotations

import io
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional

import numpy as np
from PIL import Image

from .artifact_renderer import ArtifactRenderer
from .body3d_runner import Body3DRunner
from .club3d_fuser import Club3DFuser
from .coach_response_builder import CoachResponseBuilder, CoachingBundle
from .event_detector import EventDetector
from .event_window_selector import choose_sparse_sample_rate, compute_dense_window
from .frame_extractor import FrameExtractor
from .metrics import MetricsCalculator
from .metrics_engine import CoachMetricsEngine, MetricCard
from .pose_detector import PoseDetector
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
    """Single source-of-truth backend pipeline."""

    def __init__(self, output_root: Optional[str] = None):
        from pathlib import Path

        self.output_root = Path(output_root) if output_root else (Path(__file__).parent.parent / "output" / "runs")
        self.frame_extractor = FrameExtractor()
        self.metrics_engine = CoachMetricsEngine()
        self.coach_builder = CoachResponseBuilder()
        self.artifact_renderer = ArtifactRenderer()
        self.max_dense_frames = 64

    def _frame_bytes_to_rgb(self, frame_bytes: bytes) -> np.ndarray:
        return np.array(Image.open(io.BytesIO(frame_bytes)).convert("RGB"))

    def _serialize_pose2d(self, pose: Any) -> Optional[Dict[str, Any]]:
        if pose is None:
            return None
        return {
            "frame_index": pose.frame_index,
            "confidence": pose.confidence,
            "keypoints": {
                name: {
                    "x": kp.x,
                    "y": kp.y,
                    "z": kp.z,
                    "visibility": kp.visibility,
                }
                for name, kp in pose.keypoints.items()
            },
        }

    def _serialize_pose3d(self, pose: Any) -> Optional[Dict[str, Any]]:
        if pose is None:
            return None

        return {
            "frame_index": pose.frame_index,
            "focal_length": pose.focal_length,
            "camera_translation": np.array(pose.camera_translation).tolist() if pose.camera_translation is not None else None,
            "bbox": np.array(pose.bbox).tolist() if pose.bbox is not None else None,
            "keypoints_3d": {
                name: {
                    "x": kp.x,
                    "y": kp.y,
                    "z": kp.z,
                    "confidence": kp.confidence,
                }
                for name, kp in pose.keypoints_3d.items()
            },
        }

    def _key_poses_from_events(self, poses_dense: List[Any], events: Any) -> Dict[str, Optional[Any]]:
        by_frame = {pose.frame_index: pose for pose in poses_dense if pose is not None}
        key_poses = {}
        for name in ["address", "top", "impact", "finish"]:
            event = getattr(events, name, None)
            key_poses[name] = by_frame.get(event.frame_index) if event else None
        return key_poses

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
        warnings: List[str] = []

        def emit(stage: str, progress: float, message: str) -> None:
            if progress_callback:
                progress_callback(stage, max(0.0, min(1.0, progress)), message)

        emit("video_info", 0.02, "Reading video metadata")
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
                },
            )

        sparse_rate = choose_sparse_sample_rate(fps)

        emit("sparse_scan", 0.07, "Finding rough swing phases")
        with run_store.stage("sparse_scan", {"sparse_rate": sparse_rate}):
            sparse_frames = self.frame_extractor.extract_frames(video_bytes, sample_rate=sparse_rate)
            with PoseDetector() as pose_detector:
                sparse_poses = pose_detector.detect_poses_batch(sparse_frames, start_index=0)
            sparse_detector = EventDetector(fps=max(1.0, fps / max(1, sparse_rate)))
            sparse_phases = sparse_detector.detect_phases(sparse_poses, vantage=vantage)
            sparse_events = sparse_phases.to_events()

        dense_window = compute_dense_window(
            frame_count=frame_count,
            fps=fps,
            sparse_rate=sparse_rate,
            top_frame_sparse=sparse_events.top.frame_index if sparse_events.top else None,
            impact_frame_sparse=sparse_events.impact.frame_index if sparse_events.impact else None,
        )

        dense_frame_cap = max_dense_frames or self.max_dense_frames
        dense_start = dense_window.start_frame
        dense_end = dense_window.end_frame
        dense_count = dense_end - dense_start + 1
        if dense_count > dense_frame_cap:
            focus_mid = (dense_window.top_frame_estimate + dense_window.impact_frame_estimate) // 2
            half = dense_frame_cap // 2
            dense_start = max(0, focus_mid - half)
            dense_end = min(frame_count - 1, dense_start + dense_frame_cap - 1)
            dense_start = max(0, dense_end - dense_frame_cap + 1)
            warnings.append(
                f"Dense window capped from {dense_count} to {dense_frame_cap} frames for runtime stability."
            )

        dense_indices = list(range(dense_start, dense_end + 1))
        if not dense_indices:
            dense_indices = list(range(0, min(frame_count, max(12, sparse_rate * 2))))
            warnings.append("Dense window fallback used because event-derived window was empty.")

        emit("dense_scan", 0.18, "Analyzing the swing window")
        with run_store.stage("dense_scan", {"dense_frame_count": len(dense_indices)}):
            dense_frames = self.frame_extractor.extract_frames_at_indices(video_bytes, dense_indices)
            with PoseDetector() as pose_detector:
                dense_poses = pose_detector.detect_poses_batch(dense_frames, start_index=dense_start)
            dense_detector = EventDetector(fps=fps)
            dense_phases = dense_detector.detect_phases(dense_poses, vantage=vantage)
            dense_events = dense_phases.to_events()

        run_store.save_json(
            "events.json",
            {
                "sparse": sparse_events.to_dict(),
                "dense": dense_events.to_dict(),
                "dense_window": {
                    "start": dense_window.start_frame,
                    "end": dense_window.end_frame,
                    "actual_start": dense_start,
                    "actual_end": dense_end,
                    "sparse_rate": dense_window.sparse_rate,
                    "top_estimate": dense_window.top_frame_estimate,
                    "impact_estimate": dense_window.impact_frame_estimate,
                },
            },
        )

        run_store.save_npz(
            "poses_2d.npz",
            sparse=[self._serialize_pose2d(p) for p in sparse_poses],
            dense=[self._serialize_pose2d(p) for p in dense_poses],
        )

        poses3d: List[Optional[Any]] = [None] * len(dense_frames)
        emit("body_3d", 0.32, "Estimating body motion")
        with run_store.stage("body_3d"):
            try:
                dense_rgb = [self._frame_bytes_to_rgb(frame) for frame in dense_frames]
                body_runner = Body3DRunner()
                body3d_result = body_runner.run(dense_rgb)
                poses3d = body3d_result.poses
                run_store.add_timing_details(
                    "body_3d",
                    {
                        "detected_frames": body3d_result.detected_count,
                        "reused_bbox_frames": body3d_result.reused_bbox_frames,
                        "fallback_full_frames": body3d_result.fallback_full_frames,
                    },
                )
            except Exception as exc:
                warnings.append(f"3D body stage unavailable: {exc}")

        run_store.save_npz(
            "poses_3d.npz",
            dense=[self._serialize_pose3d(p) for p in poses3d],
        )

        club2d_frames: List[Any] = []
        club3d_frames: List[Any] = []
        club_confidence = 0.0
        emit("club_3d_fusion", 0.48, "Tracking club and shaft")
        with run_store.stage("club_3d_fusion"):
            try:
                fuser = Club3DFuser()
                fusion = fuser.fuse(
                    frame_bytes=dense_frames,
                    frame_indices=dense_indices,
                    poses3d=poses3d,
                    progress_callback=lambda done, total: emit(
                        "club_3d_fusion",
                        0.48 + (0.14 * (done / max(1, total))),
                        f"Tracking club and shaft ({done}/{total})",
                    ),
                )
                club2d_frames = fusion.club_2d
                club3d_frames = fusion.club_3d
                if club2d_frames:
                    club_confidence = float(
                        np.mean(
                            [
                                0.5 * (item.shaft_confidence + item.clubhead_confidence)
                                for item in club2d_frames
                            ]
                        )
                    )
                run_store.add_timing_details("club_3d_fusion", {"valid_3d_frames": fusion.valid_3d_frames})
            except Exception as exc:
                warnings.append(f"Club 3D fusion unavailable: {exc}")

        run_store.save_npz("club_2d.npz", frames=[item.__dict__ for item in club2d_frames])
        run_store.save_npz("club_3d.npz", frames=[item.__dict__ for item in club3d_frames])

        emit("metrics", 0.64, "Calculating coachable metrics")
        with run_store.stage("metrics"):
            key_poses = self._key_poses_from_events(dense_poses, dense_events)
            base_metrics = MetricsCalculator(frame_width=frame_width, frame_height=frame_height).calculate_metrics(
                key_poses, dense_events, vantage=vantage
            )
            metrics_result = self.metrics_engine.build(
                base_metrics=base_metrics,
                club_3d_frames=club3d_frames,
                events=dense_events,
                fps=fps,
                club_detection_confidence=club_confidence,
            )
            warnings.extend(metrics_result.warnings)

        run_store.save_json(
            "metrics.json",
            {
                "cards": [card.__dict__ for card in metrics_result.metrics],
                "raw": metrics_result.raw_values,
            },
        )

        emit("artifacts", 0.76, "Rendering annotation overlays")
        with run_store.stage("artifacts"):
            rendered = self.artifact_renderer.render(
                run_store=run_store,
                frames=dense_frames,
                poses2d=dense_poses,
                frame_indices=dense_indices,
                video_fps=fps,
                frame_width=frame_width,
                frame_height=frame_height,
                club2d_frames=club2d_frames,
                poses3d=poses3d,
                club3d_frames=club3d_frames,
                swing_phases=dense_phases,
            )

        emit("coaching", 0.88, "Building coach summary")
        with run_store.stage("coaching"):
            coaching = self.coach_builder.build_coaching_bundle(
                metric_cards=metrics_result.metrics,
                quality_warnings=warnings,
                student_goal=student_goal,
            )
            run_store.save_json(
                "coach_summary.json",
                {
                    "summary": coaching.summary,
                    "top_priorities": coaching.top_priorities,
                    "drills": [drill.__dict__ for drill in coaching.drills],
                },
            )

        run_store.finalize_timings()

        quality = {
            "warnings": warnings,
            "missing_data": [card.name for card in metrics_result.metrics if card.value is None],
            "timings": run_store.timings,
        }

        emit("pipeline_complete", 0.90, "Pipeline complete")
        return Pipeline3DResult(
            run_id=run_store.run_id,
            metrics=metrics_result.metrics,
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
