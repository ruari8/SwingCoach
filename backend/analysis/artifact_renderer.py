"""Render annotated 2D video and 3D replay artifacts."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple

import numpy as np

from .animation_exporter import export_swing_animation
from .video_exporter import VideoExporter
from .visualizer import SwingVisualizer


@dataclass
class ArtifactRenderResult:
    annotated_video_filename: Optional[str]
    swing_3d_filename: Optional[str]
    debug_files: List[str]


@dataclass
class _SwingPathProxy:
    points_with_frame: List[Tuple[int, int, int]]

    def get_pixel_points_up_to_frame(self, frame_index: int) -> List[Tuple[int, int]]:
        return [(x, y) for fi, x, y in self.points_with_frame if fi <= frame_index]


class ArtifactRenderer:
    """Renders coach-facing visual artifacts from pipeline outputs."""

    def _speed_map(self, club3d_frames: List[Any], fps: float) -> Tuple[Dict[int, float], Optional[float], Optional[int]]:
        speed_map: Dict[int, float] = {}
        if len(club3d_frames) < 2:
            return speed_map, None, None

        peak_speed = 0.0
        peak_frame = None
        prev = None
        for frame in club3d_frames:
            head = np.array(frame.clubhead_point, dtype=np.float32)
            if prev is None:
                prev = (frame.frame_index, head)
                continue
            prev_idx, prev_head = prev
            dt_frames = max(1, frame.frame_index - prev_idx)
            dt = dt_frames / max(fps, 1e-6)
            speed_mps = np.linalg.norm((head - prev_head) / max(dt, 1e-6))
            speed_mph = float(speed_mps * 2.23693629)
            speed_map[frame.frame_index] = speed_mph
            if speed_mph > peak_speed:
                peak_speed = speed_mph
                peak_frame = frame.frame_index
            prev = (frame.frame_index, head)

        return speed_map, (peak_speed if peak_speed > 0 else None), peak_frame

    def render(
        self,
        run_store: Any,
        frames: List[bytes],
        poses2d: List[Optional[Any]],
        frame_indices: List[int],
        video_fps: float,
        frame_width: int,
        frame_height: int,
        club2d_frames: List[Any],
        poses3d: List[Optional[Any]],
        club3d_frames: List[Any],
    ) -> ArtifactRenderResult:
        debug_files: List[str] = []

        # Plane line can be added in a future pass when persistent shaft masks are stored.
        club_plane_line = None

        path_points = []
        for item in club2d_frames:
            if item.clubhead_centroid_px is None:
                continue
            x, y = item.clubhead_centroid_px
            relative_idx = max(0, item.frame_index - frame_indices[0])
            path_points.append((relative_idx, x, y))

        swing_path = _SwingPathProxy(points_with_frame=path_points) if path_points else None

        speed_data, peak_speed, peak_frame = self._speed_map(club3d_frames, fps=video_fps)

        visualizer = SwingVisualizer(frame_width=frame_width, frame_height=frame_height)
        annotated_frames = visualizer.draw_complete_analysis_batch(
            frames=frames,
            poses=poses2d,
            club_plane_line=club_plane_line,
            swing_path=swing_path,
            club_masks=None,
            draw_skeleton=True,
            draw_reference_lines=True,
            draw_club_plane=False,
            draw_swing_path=True,
            draw_club_mask=False,
            min_visibility=0.5,
            speed_data=speed_data,
            peak_speed=peak_speed,
            peak_speed_frame=peak_frame,
            draw_speed=bool(speed_data),
        )

        video_bytes = VideoExporter().export_video(annotated_frames, fps=video_fps)
        run_store.save_bytes("annotated.mp4", video_bytes)

        swing_3d_name: Optional[str] = None
        if poses3d and any(p is not None for p in poses3d):
            valid_poses = [p for p in poses3d if p is not None]
            if valid_poses:
                swing_3d_name = "swing_3d.gltf"
                export_swing_animation(
                    poses=valid_poses,
                    filename=swing_3d_name,
                    fps=video_fps,
                    output_dir=str(run_store.run_dir),
                    club_frames=club3d_frames,
                )

        return ArtifactRenderResult(
            annotated_video_filename="annotated.mp4",
            swing_3d_filename=swing_3d_name,
            debug_files=debug_files,
        )
