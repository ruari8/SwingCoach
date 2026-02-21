"""Helpers to convert sparse event detection into dense frame windows."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


@dataclass
class DenseWindow:
    start_frame: int
    end_frame: int
    sparse_rate: int
    top_frame_estimate: int
    impact_frame_estimate: int


def choose_sparse_sample_rate(fps: float) -> int:
    """Choose sparse scan rate between 6 and 10 frames."""
    if fps >= 200:
        return 10
    if fps >= 120:
        return 8
    return 6


def _coarse_frame(event_frame: Optional[int], sparse_rate: int, fallback: int) -> int:
    if event_frame is None:
        return fallback
    return max(0, int(event_frame) * sparse_rate)


def compute_dense_window(
    frame_count: int,
    fps: float,
    sparse_rate: int,
    top_frame_sparse: Optional[int],
    impact_frame_sparse: Optional[int],
    pre_top_seconds: float = 0.35,
    post_impact_seconds: float = 0.25,
) -> DenseWindow:
    """Compute dense analysis window around top->impact with safety clamps."""
    mid = max(0, frame_count // 2)
    top_frame = _coarse_frame(top_frame_sparse, sparse_rate, max(0, mid - sparse_rate))
    impact_frame = _coarse_frame(impact_frame_sparse, sparse_rate, min(frame_count - 1, mid + sparse_rate))

    if impact_frame <= top_frame:
        impact_frame = min(frame_count - 1, top_frame + max(2, sparse_rate))

    pre_frames = int(max(1.0, pre_top_seconds * max(fps, 1.0)))
    post_frames = int(max(1.0, post_impact_seconds * max(fps, 1.0)))

    start = max(0, top_frame - pre_frames)
    end = min(frame_count - 1, impact_frame + post_frames)

    if end <= start:
        end = min(frame_count - 1, start + max(5, sparse_rate * 2))

    return DenseWindow(
        start_frame=start,
        end_frame=end,
        sparse_rate=sparse_rate,
        top_frame_estimate=top_frame,
        impact_frame_estimate=impact_frame,
    )

