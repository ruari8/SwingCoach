"""Clean artifact renderer used while annotations are being redesigned."""

from __future__ import annotations

from dataclasses import dataclass
from collections.abc import Sequence
from typing import Any, Dict, List, Optional

from .video_exporter import VideoExporter
from .frame_extractor import FrameExtractor


@dataclass
class ArtifactRenderResult:
    base_video_filename: str
    annotated_video_filename: Optional[str]
    swing_3d_filename: Optional[str]
    annotation_tracks_filename: Optional[str]
    debug_files: List[str]
    annotation_metadata: Dict[str, Any]


class ArtifactRenderer:
    """Write clean playback artifacts with an intentionally empty overlay contract."""

    def _empty_annotation_tracks(
        self,
        *,
        frame_indices: Sequence[int],
        video_fps: float,
        frame_width: int,
        frame_height: int,
    ) -> Dict[str, Any]:
        return {
            "version": 1,
            "coordinate_space": "normalized",
            "frame_width": frame_width,
            "frame_height": frame_height,
            "fps": video_fps,
            "peak_speed_mph": None,
            "peak_speed_frame": None,
            "ball_contact": None,
            "guide_layers": [],
            "phase_markers": [],
            "confidence_evidence": None,
            "frames": [
                {
                    "frame_index": int(source_frame),
                    "relative_frame_index": int(relative_idx),
                    "timestamp": round(float(source_frame) / max(video_fps, 1e-6), 4),
                    "relative_timestamp": round(float(relative_idx) / max(video_fps, 1e-6), 4),
                    "layers": {},
                }
                for relative_idx, source_frame in enumerate(frame_indices)
            ],
        }

    def render(
        self,
        run_store: Any,
        video_bytes: bytes,
        video_fps: float,
    ) -> ArtifactRenderResult:
        exporter = VideoExporter()
        base_video_bytes = exporter.export_clean_video(video_bytes, fps=video_fps)
        # The encoded MP4 supplies the actual count and display dimensions. Input
        # container metadata can omit counts or describe an unrotated image.
        output_info = FrameExtractor().get_video_info(base_video_bytes)
        frame_count = output_info["frame_count"]
        if frame_count <= 0:
            raise ValueError("Could not encode frames from uploaded video.")
        run_store.save_bytes("base.mp4", base_video_bytes)

        # Keep the legacy annotated-video URL usable, but make it the same clean
        # video while generated overlays are disabled.
        run_store.save_bytes("annotated.mp4", base_video_bytes)

        metadata = {
            "layers": [],
            "club_plane_angle_degrees": None,
            "swing_path_point_count": 0,
            "video_fps": video_fps,
            "frame_count": frame_count,
            "pipeline_mode": "annotation_reset",
            "annotations_enabled": False,
        }
        run_store.save_json("annotation_metadata.json", metadata)

        tracks = self._empty_annotation_tracks(
            frame_indices=range(frame_count),
            video_fps=video_fps,
            frame_width=output_info["width"],
            frame_height=output_info["height"],
        )
        run_store.save_json("annotation_tracks.json", tracks)

        return ArtifactRenderResult(
            base_video_filename="base.mp4",
            annotated_video_filename="annotated.mp4",
            swing_3d_filename=None,
            annotation_tracks_filename="annotation_tracks.json",
            debug_files=[],
            annotation_metadata=metadata,
        )
