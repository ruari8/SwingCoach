#!/usr/bin/env python3
"""Regression checks for swing phase detection edge cases."""

from __future__ import annotations

from analysis.event_detector import EventDetector
from analysis.pose_detector import Keypoint, PoseResult


def _kp(name: str, x: float, y: float, visibility: float = 0.95) -> Keypoint:
    return Keypoint(x=x, y=y, z=0.0, visibility=visibility, name=name)


def _pose(frame_index: int, hand_y: float, confidence: float = 0.82) -> PoseResult:
    return PoseResult(
        frame_index=frame_index,
        confidence=confidence,
        keypoints={
            "left_wrist": _kp("left_wrist", 0.46, hand_y),
            "right_wrist": _kp("right_wrist", 0.52, hand_y),
        },
    )


def test_detect_phases_omits_impact_when_top_is_last_frame() -> None:
    detector = EventDetector(fps=30.0)
    poses = [
        _pose(0, 0.60),
        _pose(1, 0.45),
        _pose(2, 0.30),
        _pose(3, 0.20),
    ]

    phases = detector.detect_phases(poses, vantage="DTL")
    phase_names = {phase.name for phase in phases.phases}

    assert "top" in phase_names
    assert "impact" not in phase_names
    assert all(0 <= phase.frame_index < len(poses) for phase in phases.phases)


def test_downswing_position_rejects_out_of_range_impact() -> None:
    detector = EventDetector(fps=30.0)

    result = detector._find_downswing_position(
        hand_positions=[(0.5, 0.4), (0.5, 0.3)],
        top_idx=1,
        impact_idx=2,
        target_ratio=0.5,
    )

    assert result is None


if __name__ == "__main__":
    test_detect_phases_omits_impact_when_top_is_last_frame()
    test_downswing_position_rejects_out_of_range_impact()
    print("event detector regression checks passed")
