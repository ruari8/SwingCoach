"""
Club angle analysis for swing visualization.
Uses PCA (Principal Component Analysis) to fit a line through shaft mask pixels.
"""

import math
from dataclasses import dataclass
from typing import Tuple, Optional, Any, List
import logging

logger = logging.getLogger(__name__)

# Lazy imports
cv2: Any = None
np: Any = None


def _init_cv2():
    """Lazy initialization of cv2 and numpy."""
    global cv2, np
    if cv2 is None:
        import cv2 as _cv2
        import numpy as _np
        cv2 = _cv2
        np = _np


@dataclass
class ClubPlane:
    """Represents the club plane line for visualization."""
    angle_degrees: float  # Angle from vertical (0 = straight up, positive = leaning right)
    line_start: Tuple[int, int]  # Start point (x, y) in pixels - the shaft end (near hands)
    line_end: Tuple[int, int]  # End point (x, y) in pixels - extended upward/left
    centroid: Tuple[int, int]  # Center of the club mask (x, y) in pixels

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "angle_degrees": self.angle_degrees,
            "line_start": list(self.line_start),
            "line_end": list(self.line_end),
            "centroid": list(self.centroid),
        }


class ClubAnalyzer:
    """Analyzes golf club shaft from segmentation mask to extract angle and plane line."""

    def __init__(self):
        _init_cv2()

    def _get_mask_pixels(self, mask: Any) -> Optional[Any]:
        """Extract pixel coordinates from mask."""
        _init_cv2()

        if mask is None:
            return None

        if hasattr(mask, 'cpu'):
            mask = mask.cpu().numpy()

        if len(mask.shape) > 2:
            mask = mask.squeeze()

        coords = np.argwhere(mask > 0)  # Returns (row, col) = (y, x)
        if len(coords) < 10:  # Need minimum points for PCA
            return None

        return coords

    def calculate_shaft_angle_pca(self, mask: Any) -> Optional[Tuple[float, Any, Any]]:
        """
        Calculate the club shaft angle using PCA (Principal Component Analysis).

        PCA finds the direction of maximum variance in the mask pixels,
        which corresponds to the shaft's long axis.

        Args:
            mask: Binary mask (numpy array) of the club shaft segmentation

        Returns:
            Tuple of (angle_degrees, direction_vector, centroid) or None if invalid
            - angle_degrees: Angle from vertical (0 = straight up, positive = leaning right)
            - direction_vector: Unit vector along shaft direction (dx, dy)
            - centroid: Center point (x, y)
        """
        _init_cv2()

        coords = self._get_mask_pixels(mask)
        if coords is None:
            return None

        # coords is (N, 2) with (y, x) - convert to (x, y) for easier math
        points = coords[:, ::-1].astype(np.float64)  # Now (N, 2) with (x, y)

        # Calculate centroid
        centroid = points.mean(axis=0)

        # Center the points
        centered = points - centroid

        # PCA: compute covariance matrix and find eigenvectors
        cov_matrix = np.cov(centered.T)
        
        # Check for valid covariance matrix
        if np.any(np.isnan(cov_matrix)) or np.any(np.isinf(cov_matrix)):
            logger.warning("Invalid covariance matrix in PCA")
            return None
        
        eigenvalues, eigenvectors = np.linalg.eigh(cov_matrix)

        # The eigenvector with largest eigenvalue is the principal direction
        # eigh returns eigenvalues in ascending order, so take the last one
        principal_direction = eigenvectors[:, -1]
        
        # Validate the direction vector
        if np.any(np.isnan(principal_direction)) or np.any(np.isinf(principal_direction)):
            logger.warning("Invalid principal direction from PCA")
            return None
        
        # Ensure it's a proper unit vector (should be from eigh, but double-check)
        norm = np.linalg.norm(principal_direction)
        if norm < 1e-10:
            logger.warning("Principal direction has near-zero norm")
            return None
        principal_direction = principal_direction / norm

        # principal_direction is (dx, dy) - the direction of the shaft
        dx, dy = principal_direction

        # Calculate angle from vertical
        # Vertical is (0, -1) in image coords (y increases downward)
        # angle = atan2(dx, -dy) gives angle from vertical
        angle_rad = math.atan2(dx, -dy)
        angle_degrees = math.degrees(angle_rad)

        logger.debug(f"PCA shaft angle: {angle_degrees:.1f}° from vertical")

        return angle_degrees, principal_direction, centroid

    def get_shaft_endpoints(self, mask: Any) -> Optional[Tuple[Tuple[int, int], Tuple[int, int]]]:
        """
        Find the two endpoints of the shaft mask along the principal axis.

        Returns:
            Tuple of ((x1, y1), (x2, y2)) - the two ends of the shaft
            The first point is the "bottom" end (closer to clubhead, higher y value)
            The second point is the "top" end (closer to hands, lower y value)
        """
        _init_cv2()

        coords = self._get_mask_pixels(mask)
        if coords is None:
            return None

        result = self.calculate_shaft_angle_pca(mask)
        if result is None:
            return None

        angle_deg, direction, centroid = result

        # Convert coords to (x, y) format
        points = coords[:, ::-1].astype(np.float64)

        # Project all points onto the principal axis
        centered = points - centroid
        
        # Validate centered points before matrix multiplication
        if np.any(np.isnan(centered)) or np.any(np.isinf(centered)):
            logger.warning("Invalid centered points in shaft endpoint calculation")
            return None
        
        # Suppress numerical warnings - we handle invalid results below
        with np.errstate(divide='ignore', over='ignore', invalid='ignore'):
            projections = centered @ direction  # Dot product with direction vector
        
        # Validate projections
        if np.any(np.isnan(projections)) or np.any(np.isinf(projections)):
            logger.warning("Invalid projections in shaft endpoint calculation")
            return None

        # Find the points with min and max projection (the endpoints)
        min_idx = np.argmin(projections)
        max_idx = np.argmax(projections)

        endpoint1 = (int(points[min_idx, 0]), int(points[min_idx, 1]))
        endpoint2 = (int(points[max_idx, 0]), int(points[max_idx, 1]))

        # Determine which is "top" (closer to hands) vs "bottom" (closer to clubhead)
        # In a golf swing, the hands are higher (lower y value) than the clubhead
        if endpoint1[1] < endpoint2[1]:
            top_end = endpoint1
            bottom_end = endpoint2
        else:
            top_end = endpoint2
            bottom_end = endpoint1

        return bottom_end, top_end

    def get_extended_plane_line(
        self,
        mask: Any,
        frame_width: int,
        frame_height: int,
        extend_length: int = 500
    ) -> Optional[ClubPlane]:
        """
        Calculate the club plane line, starting at clubhead and extending past hands.

        The line starts at the clubhead end of the shaft and extends through
        the shaft and beyond the hands end.

        Args:
            mask: Binary mask of the club SHAFT (use "club shaft" prompt)
            frame_width: Width of the video frame in pixels
            frame_height: Height of the video frame in pixels
            extend_length: How far to extend the line beyond the hands end in pixels

        Returns:
            ClubPlane with angle and line endpoints, or None if invalid
        """
        _init_cv2()

        result = self.calculate_shaft_angle_pca(mask)
        if result is None:
            return None

        angle_deg, direction, centroid = result

        endpoints = self.get_shaft_endpoints(mask)
        if endpoints is None:
            return None

        bottom_end, top_end = endpoints

        # Direction vector pointing from bottom (clubhead) to top (hands)
        dx = top_end[0] - bottom_end[0]
        dy = top_end[1] - bottom_end[1]
        length = math.sqrt(dx*dx + dy*dy)

        if length < 1:
            return None

        # Normalize direction vector
        dx /= length
        dy /= length

        # Line starts at the clubhead (bottom_end) - NO extension past clubhead
        # Line extends beyond the hands (top_end) by extend_length
        line_start = bottom_end
        line_end = (
            int(top_end[0] + dx * extend_length),
            int(top_end[1] + dy * extend_length)
        )

        # Clip line_end to frame bounds
        line_end = (
            max(0, min(frame_width - 1, line_end[0])),
            max(0, min(frame_height - 1, line_end[1]))
        )

        return ClubPlane(
            angle_degrees=angle_deg,
            line_start=line_start,
            line_end=line_end,
            centroid=(int(centroid[0]), int(centroid[1]))
        )

    def analyze_address_frame(
        self,
        shaft_mask: Any,
        frame_width: int,
        frame_height: int
    ) -> Optional[ClubPlane]:
        """
        Analyze the club shaft position at the address frame.

        This is the key frame where we capture the club plane that will
        persist throughout the visualization.

        Args:
            shaft_mask: Binary mask of the club SHAFT at address (use "club shaft" prompt)
            frame_width: Frame width in pixels
            frame_height: Frame height in pixels

        Returns:
            ClubPlane for the address position
        """
        return self.get_extended_plane_line(
            mask=shaft_mask,
            frame_width=frame_width,
            frame_height=frame_height,
            extend_length=800  # Extend generously for the plane line
        )

    def get_clubhead_centroid(self, mask: Any) -> Optional[Tuple[int, int]]:
        """
        Get the centroid of the clubhead mask.

        This is used for tracking the clubhead path through the swing.

        Args:
            mask: Binary mask of the clubhead (use "clubhead" prompt)

        Returns:
            (x, y) centroid in pixels, or None if invalid
        """
        coords = self._get_mask_pixels(mask)
        if coords is None:
            return None

        # coords is (y, x), convert to (x, y)
        x_center = int(coords[:, 1].mean())
        y_center = int(coords[:, 0].mean())

        return (x_center, y_center)
