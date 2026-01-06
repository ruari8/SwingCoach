"""
Swing path tracking for golf swing visualization.
Builds and smooths the trajectory of the club head through the swing.
"""

from dataclasses import dataclass, field
from typing import List, Tuple, Optional, Any
import logging

logger = logging.getLogger(__name__)

# Lazy imports
np: Any = None


def _init_numpy():
    """Lazy initialization of numpy."""
    global np
    if np is None:
        import numpy as _np
        np = _np


@dataclass
class SwingPath:
    """Represents the club head trajectory through a swing."""
    points: List[Tuple[float, float]]  # Raw centroid points (normalized 0-1)
    frame_indices: List[int]  # Which frame each point came from
    smoothed_points: List[Tuple[float, float]] = field(default_factory=list)  # After smoothing
    pixel_points: List[Tuple[int, int]] = field(default_factory=list)  # In pixel coords

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "points": [list(p) for p in self.points],
            "frame_indices": self.frame_indices,
            "smoothed_points": [list(p) for p in self.smoothed_points],
            "pixel_points": [list(p) for p in self.pixel_points],
            "point_count": len(self.points),
        }

    def get_points_up_to_frame(self, frame_index: int) -> List[Tuple[float, float]]:
        """
        Get path points up to and including a specific frame.
        Used for drawing progressive path during video.

        Args:
            frame_index: Frame index to stop at

        Returns:
            List of points (smoothed if available, else raw)
        """
        points_to_use = self.smoothed_points if self.smoothed_points else self.points

        result = []
        for i, fi in enumerate(self.frame_indices):
            if fi <= frame_index and i < len(points_to_use):
                result.append(points_to_use[i])

        return result

    def get_pixel_points_up_to_frame(self, frame_index: int) -> List[Tuple[int, int]]:
        """
        Get pixel coordinate points up to a specific frame.

        Args:
            frame_index: Frame index to stop at

        Returns:
            List of pixel coordinate points
        """
        if not self.pixel_points:
            return []

        result = []
        for i, fi in enumerate(self.frame_indices):
            if fi <= frame_index and i < len(self.pixel_points):
                result.append(self.pixel_points[i])

        return result


class SwingPathTracker:
    """Tracks and smooths the club head trajectory through a golf swing."""

    def __init__(self, smoothing_window: int = 3):
        """
        Initialize the swing path tracker.

        Args:
            smoothing_window: Window size for moving average smoothing (must be odd)
        """
        _init_numpy()
        self.smoothing_window = smoothing_window if smoothing_window % 2 == 1 else smoothing_window + 1

    def build_path(
        self,
        club_detections: List[Any],  # List[Optional[ClubDetection]]
        frame_width: int = 1,
        frame_height: int = 1
    ) -> SwingPath:
        """
        Build a swing path from club detection results.

        Args:
            club_detections: List of ClubDetection objects (or None for missed frames)
            frame_width: Frame width for pixel conversion (default 1 for normalized)
            frame_height: Frame height for pixel conversion (default 1 for normalized)

        Returns:
            SwingPath with raw and smoothed points
        """
        _init_numpy()

        points = []
        frame_indices = []

        for detection in club_detections:
            if detection is not None and hasattr(detection, 'centroid'):
                points.append(detection.centroid)
                frame_indices.append(detection.frame_index)

        if len(points) == 0:
            logger.warning("No valid club detections to build path from")
            return SwingPath(points=[], frame_indices=[], smoothed_points=[])

        logger.info(f"Building swing path from {len(points)} detection points")

        # Create path object
        path = SwingPath(points=points, frame_indices=frame_indices)

        # Apply smoothing
        path.smoothed_points = self.smooth_path(points)

        # Convert to pixel coordinates
        path.pixel_points = [
            (int(p[0] * frame_width), int(p[1] * frame_height))
            for p in path.smoothed_points
        ]

        return path

    def smooth_path(self, points: List[Tuple[float, float]]) -> List[Tuple[float, float]]:
        """
        Apply moving average smoothing to path points.

        Args:
            points: List of (x, y) points (normalized 0-1)

        Returns:
            Smoothed list of (x, y) points
        """
        _init_numpy()

        if len(points) < 3:
            return points.copy()

        points_array = np.array(points)
        window = min(self.smoothing_window, len(points))
        if window % 2 == 0:
            window -= 1
        if window < 1:
            window = 1

        # Simple moving average
        smoothed = np.copy(points_array)

        half_window = window // 2
        for i in range(half_window, len(points) - half_window):
            smoothed[i] = np.mean(points_array[i - half_window:i + half_window + 1], axis=0)

        return [(float(p[0]), float(p[1])) for p in smoothed]

    def interpolate_gaps(
        self,
        path: SwingPath,
        max_gap: int = 3
    ) -> SwingPath:
        """
        Interpolate missing points in the path where detection failed.

        Args:
            path: SwingPath with gaps
            max_gap: Maximum gap size to interpolate (frames)

        Returns:
            SwingPath with interpolated points
        """
        _init_numpy()

        if len(path.points) < 2:
            return path

        # Find gaps in frame indices
        new_points = []
        new_frame_indices = []

        for i in range(len(path.frame_indices)):
            new_points.append(path.points[i])
            new_frame_indices.append(path.frame_indices[i])

            if i < len(path.frame_indices) - 1:
                current_frame = path.frame_indices[i]
                next_frame = path.frame_indices[i + 1]
                gap = next_frame - current_frame - 1

                if 0 < gap <= max_gap:
                    # Interpolate
                    for j in range(1, gap + 1):
                        t = j / (gap + 1)
                        x = path.points[i][0] + t * (path.points[i + 1][0] - path.points[i][0])
                        y = path.points[i][1] + t * (path.points[i + 1][1] - path.points[i][1])
                        new_points.append((x, y))
                        new_frame_indices.append(current_frame + j)

        # Re-smooth the interpolated path
        smoothed = self.smooth_path(new_points)

        return SwingPath(
            points=new_points,
            frame_indices=new_frame_indices,
            smoothed_points=smoothed,
            pixel_points=path.pixel_points  # Will need to be recalculated
        )

    def get_path_segment(
        self,
        path: SwingPath,
        start_frame: int,
        end_frame: int
    ) -> List[Tuple[float, float]]:
        """
        Get a segment of the path between two frames.

        Args:
            path: SwingPath object
            start_frame: Starting frame index
            end_frame: Ending frame index

        Returns:
            List of points in the segment
        """
        points_to_use = path.smoothed_points if path.smoothed_points else path.points

        segment = []
        for i, fi in enumerate(path.frame_indices):
            if start_frame <= fi <= end_frame and i < len(points_to_use):
                segment.append(points_to_use[i])

        return segment
