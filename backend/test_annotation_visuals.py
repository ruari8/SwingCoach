#!/usr/bin/env python3
"""Pixel-level regression checks for rendered annotation overlays."""

from __future__ import annotations

import io

import numpy as np
from PIL import Image

from analysis.pose_detector import Keypoint, PoseResult
from analysis.visualizer import SwingVisualizer


def _blank_frame(width: int = 320, height: int = 180) -> bytes:
    image = Image.new("RGB", (width, height), (18, 22, 24))
    output = io.BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def _kp(name: str, x: float, y: float, visibility: float = 0.98) -> Keypoint:
    return Keypoint(x=x, y=y, z=0.0, visibility=visibility, name=name)


def _pose(frame_index: int = 0) -> PoseResult:
    return PoseResult(
        frame_index=frame_index,
        confidence=0.9,
        keypoints={
            "left_shoulder": _kp("left_shoulder", 0.38, 0.30),
            "right_shoulder": _kp("right_shoulder", 0.56, 0.32),
            "left_elbow": _kp("left_elbow", 0.42, 0.44),
            "right_elbow": _kp("right_elbow", 0.58, 0.46),
            "left_wrist": _kp("left_wrist", 0.45, 0.58),
            "right_wrist": _kp("right_wrist", 0.60, 0.58),
            "left_hip": _kp("left_hip", 0.42, 0.60),
            "right_hip": _kp("right_hip", 0.55, 0.61),
            "left_knee": _kp("left_knee", 0.40, 0.76),
            "right_knee": _kp("right_knee", 0.56, 0.76),
            "left_ankle": _kp("left_ankle", 0.38, 0.91),
            "right_ankle": _kp("right_ankle", 0.58, 0.91),
        },
    )


def _rgb_array(frame_bytes: bytes) -> np.ndarray:
    return np.array(Image.open(io.BytesIO(frame_bytes)).convert("RGB"))


def _count_pixels_near(image: np.ndarray, rgb: tuple[int, int, int], tolerance: int = 12) -> int:
    target = np.array(rgb, dtype=np.int16)
    diff = np.abs(image.astype(np.int16) - target.reshape(1, 1, 3))
    return int(np.sum(np.all(diff <= tolerance, axis=2)))


def test_complete_analysis_draws_core_overlay_pixels() -> None:
    visualizer = SwingVisualizer(frame_width=320, frame_height=180)
    rendered = visualizer.draw_complete_analysis(
        frame_bytes=_blank_frame(),
        pose=_pose(),
        club_plane_line=((25, 150), (230, 42)),
        swing_path_points=[(70, 126), (105, 112), (145, 100), (190, 84)],
        draw_skeleton=True,
        draw_reference_lines=True,
        draw_club_plane=True,
        draw_swing_path=True,
        draw_club_mask=False,
        current_speed=None,
        draw_speed=False,
    )
    pixels = _rgb_array(rendered)

    assert _count_pixels_near(pixels, (0, 255, 255)) > 90, "skeleton cyan pixels missing"
    assert _count_pixels_near(pixels, (255, 255, 0)) > 90, "reference-line yellow pixels missing"
    assert _count_pixels_near(pixels, (255, 165, 0)) > 130, "club-plane orange pixels missing"
    assert _count_pixels_near(pixels, (255, 0, 0)) > 80, "swing-path red pixels missing"


def test_layer_flags_can_remove_rendered_overlays() -> None:
    visualizer = SwingVisualizer(frame_width=320, frame_height=180)
    rendered = visualizer.draw_complete_analysis(
        frame_bytes=_blank_frame(),
        pose=_pose(),
        club_plane_line=((25, 150), (230, 42)),
        swing_path_points=[(70, 126), (105, 112), (145, 100), (190, 84)],
        draw_skeleton=False,
        draw_reference_lines=False,
        draw_club_plane=False,
        draw_swing_path=False,
        draw_club_mask=False,
        current_speed=None,
        draw_speed=False,
    )
    pixels = _rgb_array(rendered)

    assert _count_pixels_near(pixels, (0, 255, 255)) == 0
    assert _count_pixels_near(pixels, (255, 255, 0)) == 0
    assert _count_pixels_near(pixels, (255, 165, 0)) == 0
    assert _count_pixels_near(pixels, (255, 0, 0)) == 0


if __name__ == "__main__":
    test_complete_analysis_draws_core_overlay_pixels()
    test_layer_flags_can_remove_rendered_overlays()
    print("annotation visual regression checks passed")
