"""Clean playback video plus confidence-gated client annotation tracks."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Optional

from .video_exporter import VideoExporter


@dataclass
class ArtifactRenderResult:
    base_video_filename: str
    annotated_video_filename: Optional[str]
    swing_3d_filename: Optional[str]
    annotation_tracks_filename: Optional[str]
    debug_files: List[str]
    annotation_metadata: Dict[str, Any]


class ArtifactRenderer:
    """Keep pixels clean and render evidence through the mobile overlay contract."""

    def _empty_annotation_tracks(
        self,
        *,
        frame_indices: List[int],
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
        frames: List[bytes],
        frame_indices: List[int],
        video_fps: float,
        frame_width: int,
        frame_height: int,
        layers_by_frame: Optional[Dict[int, Dict[str, Any]]] = None,
        sample_interval: int = 1,
    ) -> ArtifactRenderResult:
        if len(frames) != len(frame_indices):
            frame_indices = list(range(len(frames)))

        exporter = VideoExporter()
        base_video_bytes = exporter.export_video(frames, fps=video_fps)
        run_store.save_bytes("base.mp4", base_video_bytes)

        # Both URLs use clean pixels. The app draws toggleable annotation tracks.
        run_store.save_bytes("annotated.mp4", base_video_bytes)

        supplied_layers = layers_by_frame or {}
        layer_names = sorted({guide["layer"] for layers in supplied_layers.values() for guide in layers.get("guides", [])})
        metadata = {
            "layers": [{"name": name, "color": "#67D6B0" if name == "body_reference" else "#F5C76B",
                        "description": "Body reference · 2D" if name == "body_reference" else "Hand path · 2D",
                        "enabled": True} for name in layer_names],
            "club_plane_angle_degrees": None,
            "swing_path_point_count": 0,
            "video_fps": video_fps,
            "frame_count": len(frames),
            "pipeline_mode": "knowledge_coaching_v1",
            "annotations_enabled": bool(layer_names),
        }
        run_store.save_json("annotation_metadata.json", metadata)

        tracks = self._empty_annotation_tracks(
            frame_indices=frame_indices,
            video_fps=video_fps,
            frame_width=frame_width,
            frame_height=frame_height,
        )
        tracks["guide_layers"] = layer_names
        # A sample is displayed only near its timestamp, never carried through a
        # detector dropout. The nearest sample with absent layers clears overlays.
        for frame in tracks["frames"]:
            nearest = int(round(frame["frame_index"] / max(sample_interval, 1))) * max(sample_interval, 1)
            frame["layers"] = supplied_layers.get(nearest, {})
        run_store.save_json("annotation_tracks.json", tracks)

        return ArtifactRenderResult(
            base_video_filename="base.mp4",
            annotated_video_filename="annotated.mp4",
            swing_3d_filename=None,
            annotation_tracks_filename="annotation_tracks.json",
            debug_files=[],
            annotation_metadata=metadata,
        )
