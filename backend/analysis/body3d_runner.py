"""3D body detection runner with ROI reuse and timing-friendly stats."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, List, Optional

import numpy as np

from .body_3d import Body3DDetector


@dataclass
class Body3DRunResult:
    poses: List[Optional[Any]]
    detected_count: int
    reused_bbox_frames: int
    fallback_full_frames: int


class Body3DRunner:
    """Runs SAM 3D Body across a dense frame window."""

    def __init__(self, bbox_padding_ratio: float = 0.12):
        self.bbox_padding_ratio = bbox_padding_ratio

    def _bbox_to_full(self, image: np.ndarray) -> np.ndarray:
        h, w = image.shape[:2]
        return np.array([[0, 0, w, h]], dtype=np.float32)

    def _expand_bbox(self, bbox: np.ndarray, image: np.ndarray) -> np.ndarray:
        h, w = image.shape[:2]
        raw = np.array(bbox, dtype=np.float32).reshape(-1, 4)[0]
        x1, y1, x2, y2 = raw.tolist()

        bw = max(1.0, x2 - x1)
        bh = max(1.0, y2 - y1)
        px = bw * self.bbox_padding_ratio
        py = bh * self.bbox_padding_ratio

        ex1 = max(0.0, x1 - px)
        ey1 = max(0.0, y1 - py)
        ex2 = min(float(w), x2 + px)
        ey2 = min(float(h), y2 + py)

        if ex2 <= ex1 or ey2 <= ey1:
            return self._bbox_to_full(image)

        return np.array([[ex1, ey1, ex2, ey2]], dtype=np.float32)

    def run(self, frames_rgb: List[np.ndarray]) -> Body3DRunResult:
        """Run 3D body detection with ROI reuse between consecutive frames."""
        poses: List[Optional[Any]] = []
        reused_bbox_frames = 0
        fallback_full_frames = 0
        previous_bbox: Optional[np.ndarray] = None

        with Body3DDetector() as detector:
            for frame in frames_rgb:
                if previous_bbox is None:
                    bbox = self._bbox_to_full(frame)
                    fallback_full_frames += 1
                else:
                    bbox = previous_bbox
                    reused_bbox_frames += 1

                result = detector.detect(frame, bbox=bbox)

                if result is not None and result.bbox is not None:
                    previous_bbox = self._expand_bbox(result.bbox, frame)
                else:
                    previous_bbox = None

                poses.append(result)

        detected_count = sum(1 for pose in poses if pose is not None)
        return Body3DRunResult(
            poses=poses,
            detected_count=detected_count,
            reused_bbox_frames=reused_bbox_frames,
            fallback_full_frames=fallback_full_frames,
        )

