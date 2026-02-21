"""Fuse 2D club detections with 3D wrists to create a rigid 3D club track."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, List, Optional, Tuple

import numpy as np

from .equipment_tracker import EquipmentTracker


@dataclass
class Club2DFrame:
    frame_index: int
    shaft_confidence: float
    clubhead_confidence: float
    shaft_direction_2d: Optional[Tuple[float, float]]
    clubhead_centroid_px: Optional[Tuple[int, int]]


@dataclass
class Club3DFrame:
    frame_index: int
    grip_point: Tuple[float, float, float]
    clubhead_point: Tuple[float, float, float]
    shaft_direction: Tuple[float, float, float]
    confidence: float


@dataclass
class ClubFusionResult:
    club_2d: List[Club2DFrame]
    club_3d: List[Club3DFrame]
    valid_3d_frames: int


class Club3DFuser:
    """Creates a temporally stable rigid club estimate."""

    def __init__(
        self,
        club_length_m: float = 1.14,
        direction_alpha: float = 0.6,
        head_alpha: float = 0.7,
        sample_stride: int = 2,
    ):
        self.club_length_m = club_length_m
        self.direction_alpha = direction_alpha
        self.head_alpha = head_alpha
        self.sample_stride = max(1, sample_stride)

    def _shaft_direction_from_mask(self, mask: Any) -> Optional[np.ndarray]:
        if mask is None:
            return None
        mask_np = np.array(mask)
        points = np.argwhere(mask_np > 0)
        if len(points) < 20:
            return None

        # points are (y, x)
        coords = points[:, ::-1].astype(np.float32)  # (x, y)
        center = coords.mean(axis=0)
        centered = coords - center
        cov = np.cov(centered.T)
        eig_vals, eig_vecs = np.linalg.eig(cov)
        axis = eig_vecs[:, np.argmax(eig_vals)].astype(np.float32)
        norm = np.linalg.norm(axis)
        if norm < 1e-8:
            return None
        return axis / norm

    def _build_dir3d(self, dir2d: Optional[np.ndarray], prev_dir3d: Optional[np.ndarray]) -> np.ndarray:
        if dir2d is None:
            if prev_dir3d is not None:
                return prev_dir3d
            return np.array([0.0, -1.0, 0.2], dtype=np.float32)

        # Map image direction into 3D camera-like direction.
        # Y is flipped to graphics convention in export; keep camera sign here.
        candidate = np.array([float(dir2d[0]), float(dir2d[1]), 0.25], dtype=np.float32)
        candidate /= max(np.linalg.norm(candidate), 1e-8)

        if prev_dir3d is None:
            return candidate

        blended = self.direction_alpha * candidate + (1.0 - self.direction_alpha) * prev_dir3d
        blended /= max(np.linalg.norm(blended), 1e-8)
        return blended

    def _grip_from_pose(self, pose3d: Any) -> Optional[np.ndarray]:
        if pose3d is None:
            return None
        left = pose3d.keypoints_3d.get("left_wrist") if hasattr(pose3d, "keypoints_3d") else None
        right = pose3d.keypoints_3d.get("right_wrist") if hasattr(pose3d, "keypoints_3d") else None
        if not left or not right:
            return None
        return np.array([
            (left.x + right.x) * 0.5,
            (left.y + right.y) * 0.5,
            (left.z + right.z) * 0.5,
        ], dtype=np.float32)

    def _grip_2d_from_pose(self, pose3d: Any) -> Optional[np.ndarray]:
        if pose3d is None or not hasattr(pose3d, "keypoints_2d"):
            return None
        left = pose3d.keypoints_2d.get("left_wrist")
        right = pose3d.keypoints_2d.get("right_wrist")
        if not left or not right:
            return None
        return np.array([(left[0] + right[0]) * 0.5, (left[1] + right[1]) * 0.5], dtype=np.float32)

    def _clubhead_px_from_mask(self, mask: Any, grip2d: Optional[np.ndarray]) -> Optional[Tuple[int, int]]:
        if mask is None:
            return None
        points = np.argwhere(np.array(mask) > 0)
        if len(points) == 0:
            return None
        xy_points = points[:, ::-1].astype(np.float32)  # (x, y)
        if grip2d is None:
            # Fallback: lowest point in image space is usually close to clubhead in DTL.
            idx = int(np.argmax(xy_points[:, 1]))
            target = xy_points[idx]
            return int(target[0]), int(target[1])
        d2 = np.sum((xy_points - grip2d.reshape(1, 2)) ** 2, axis=1)
        idx = int(np.argmax(d2))
        target = xy_points[idx]
        return int(target[0]), int(target[1])

    def fuse(self, frame_bytes: List[bytes], frame_indices: List[int], poses3d: List[Optional[Any]]) -> ClubFusionResult:
        club2d_frames: List[Club2DFrame] = []
        club3d_frames: List[Club3DFrame] = []

        prev_dir3d: Optional[np.ndarray] = None
        prev_head3d: Optional[np.ndarray] = None

        with EquipmentTracker() as tracker:
            prev_shaft_dir2d: Optional[np.ndarray] = None
            prev_head_px: Optional[Tuple[int, int]] = None
            prev_confidence = 0.0

            for idx, frame in enumerate(frame_bytes):
                frame_index = frame_indices[idx]
                pose3d = poses3d[idx] if idx < len(poses3d) else None

                do_detect = (idx % self.sample_stride == 0) or (idx == len(frame_bytes) - 1)
                shaft_dir2d = prev_shaft_dir2d
                head_px = prev_head_px
                detection_conf = max(0.0, prev_confidence - 0.05)

                if do_detect:
                    club_det = tracker.detect_club(frame, frame_index=frame_index)
                    if club_det is not None:
                        shaft_dir2d = self._shaft_direction_from_mask(club_det.mask)
                        grip2d = self._grip_2d_from_pose(pose3d)
                        head_px = self._clubhead_px_from_mask(club_det.mask, grip2d)
                        detection_conf = float(club_det.confidence)
                        prev_shaft_dir2d = shaft_dir2d
                        prev_head_px = head_px
                        prev_confidence = detection_conf

                grip = self._grip_from_pose(pose3d)
                shaft_conf = detection_conf
                head_conf = detection_conf

                club2d_frames.append(
                    Club2DFrame(
                        frame_index=frame_index,
                        shaft_confidence=shaft_conf,
                        clubhead_confidence=head_conf,
                        shaft_direction_2d=(float(shaft_dir2d[0]), float(shaft_dir2d[1])) if shaft_dir2d is not None else None,
                        clubhead_centroid_px=head_px,
                    )
                )

                if grip is None:
                    continue

                dir3d = self._build_dir3d(shaft_dir2d, prev_dir3d)
                candidate_head = grip + (dir3d * self.club_length_m)

                if prev_head3d is not None:
                    candidate_head = (self.head_alpha * candidate_head) + ((1.0 - self.head_alpha) * prev_head3d)

                # Enforce rigid-length club after smoothing.
                shaft_vec = candidate_head - grip
                shaft_norm = max(np.linalg.norm(shaft_vec), 1e-8)
                shaft_unit = shaft_vec / shaft_norm
                clubhead = grip + shaft_unit * self.club_length_m

                confidence = float(min(1.0, max(0.05, 0.5 * (shaft_conf + head_conf))))

                club3d_frames.append(
                    Club3DFrame(
                        frame_index=frame_index,
                        grip_point=(float(grip[0]), float(grip[1]), float(grip[2])),
                        clubhead_point=(float(clubhead[0]), float(clubhead[1]), float(clubhead[2])),
                        shaft_direction=(float(shaft_unit[0]), float(shaft_unit[1]), float(shaft_unit[2])),
                        confidence=confidence,
                    )
                )

                prev_dir3d = shaft_unit
                prev_head3d = clubhead

        return ClubFusionResult(
            club_2d=club2d_frames,
            club_3d=club3d_frames,
            valid_3d_frames=len(club3d_frames),
        )
