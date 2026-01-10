"""
Clubhead velocity estimation from frame-to-frame tracking.
Calculates approximate club speed (mph) using SAM3 centroid positions.
"""

from typing import List, Optional, Tuple
from dataclasses import dataclass, field
import math
import logging

logger = logging.getLogger(__name__)

# Import type for ClubheadDetection - avoid circular import
try:
    from .equipment_tracker import ClubheadDetection
except ImportError:
    ClubheadDetection = None


@dataclass
class VelocityPoint:
    """Velocity measurement at a single frame."""
    frame_index: int
    timestamp: float  # seconds
    position: Tuple[int, int]  # pixels (x, y)
    velocity_mph: Optional[float] = None  # None for first frame
    confidence: float = 0.0


@dataclass
class VelocityMetrics:
    """Clubhead velocity measurements across the swing."""
    peak_speed_mph: Optional[float] = None
    peak_speed_frame: Optional[int] = None
    impact_speed_mph: Optional[float] = None
    average_downswing_speed_mph: Optional[float] = None
    speed_profile: List[VelocityPoint] = field(default_factory=list)
    confidence: float = 0.0  # Based on detection success rate

    def to_dict(self) -> dict:
        return {
            "peak_speed_mph": round(self.peak_speed_mph, 1) if self.peak_speed_mph else None,
            "peak_speed_frame": self.peak_speed_frame,
            "impact_speed_mph": round(self.impact_speed_mph, 1) if self.impact_speed_mph else None,
            "average_downswing_speed_mph": round(self.average_downswing_speed_mph, 1) if self.average_downswing_speed_mph else None,
            "confidence": round(self.confidence, 2),
        }


class VelocityEstimator:
    """
    Estimates clubhead velocity from frame-to-frame position tracking.

    Uses SAM3 clubhead centroid positions and known scale factor to
    calculate speed in mph.
    """

    # Conversion constant: inches/second to mph
    # 1 mph = 17.6 inches/second
    # So: mph = in/s / 17.6 = in/s * 0.0568182
    INCHES_PER_SEC_TO_MPH = 1 / 17.6

    def __init__(
        self,
        fps: float,
        scale_factor: float,
        frame_width: int = 1920,
        frame_height: int = 1080
    ):
        """
        Initialize velocity estimator.

        Args:
            fps: Video frames per second
            scale_factor: Inches per pixel (from shoulder width calibration)
            frame_width: Video width in pixels
            frame_height: Video height in pixels
        """
        self.fps = fps
        self.scale_factor = scale_factor
        self.frame_width = frame_width
        self.frame_height = frame_height

        # Time between frames in seconds
        self.frame_interval = 1.0 / fps

        logger.debug(
            f"VelocityEstimator initialized: fps={fps}, scale_factor={scale_factor:.6f}, "
            f"frame_interval={self.frame_interval:.4f}s"
        )

    def estimate_from_detections(
        self,
        detections: List[Optional["ClubheadDetection"]],
        impact_frame: Optional[int] = None,
        top_frame: Optional[int] = None,
        smoothing_window: int = 3
    ) -> VelocityMetrics:
        """
        Estimate velocity metrics from clubhead detections.

        Args:
            detections: List of ClubheadDetection (or None for missed frames)
            impact_frame: Frame index of impact (for impact speed)
            top_frame: Frame index of top of backswing (for downswing analysis)
            smoothing_window: Number of frames for moving average smoothing

        Returns:
            VelocityMetrics with calculated speeds
        """
        if not detections:
            logger.warning("No detections provided for velocity estimation")
            return VelocityMetrics(confidence=0.0)

        # Build velocity profile from valid detections
        speed_profile = self._build_speed_profile(detections)

        if len(speed_profile) < 2:
            logger.warning("Insufficient detections for velocity estimation")
            return VelocityMetrics(
                speed_profile=speed_profile,
                confidence=self._calculate_confidence(detections)
            )

        # Apply smoothing to reduce noise
        smoothed_profile = self._smooth_velocities(speed_profile, smoothing_window)

        # Find peak speed
        peak_speed, peak_frame = self._find_peak_speed(smoothed_profile)

        # Find impact speed
        impact_speed = self._find_speed_at_frame(smoothed_profile, impact_frame)

        # Calculate average downswing speed
        avg_downswing = self._calculate_downswing_average(
            smoothed_profile, top_frame, impact_frame
        )

        confidence = self._calculate_confidence(detections)

        logger.info(
            f"Velocity estimation complete: peak={peak_speed:.1f} mph @ frame {peak_frame}, "
            f"impact={impact_speed:.1f if impact_speed else 'N/A'} mph, confidence={confidence:.2f}"
        )

        return VelocityMetrics(
            peak_speed_mph=peak_speed,
            peak_speed_frame=peak_frame,
            impact_speed_mph=impact_speed,
            average_downswing_speed_mph=avg_downswing,
            speed_profile=smoothed_profile,
            confidence=confidence
        )

    def _build_speed_profile(
        self,
        detections: List[Optional["ClubheadDetection"]]
    ) -> List[VelocityPoint]:
        """Build velocity profile from consecutive detections."""
        profile = []
        prev_detection = None

        for i, detection in enumerate(detections):
            if detection is None:
                continue

            # Get pixel position
            if hasattr(detection, 'centroid_pixels') and detection.centroid_pixels:
                position = detection.centroid_pixels
            elif hasattr(detection, 'centroid') and detection.centroid:
                # Convert normalized to pixels
                position = (
                    int(detection.centroid[0] * self.frame_width),
                    int(detection.centroid[1] * self.frame_height)
                )
            else:
                continue

            frame_idx = detection.frame_index if hasattr(detection, 'frame_index') else i
            timestamp = frame_idx / self.fps
            confidence = detection.confidence if hasattr(detection, 'confidence') else 0.5

            velocity_mph = None

            if prev_detection is not None:
                # Calculate displacement
                prev_pos = prev_detection['position']
                displacement_pixels = math.sqrt(
                    (position[0] - prev_pos[0]) ** 2 +
                    (position[1] - prev_pos[1]) ** 2
                )

                # Convert to inches
                displacement_inches = displacement_pixels * self.scale_factor

                # Calculate frames between detections
                frames_elapsed = frame_idx - prev_detection['frame_index']
                if frames_elapsed <= 0:
                    frames_elapsed = 1

                time_elapsed = frames_elapsed * self.frame_interval

                # Velocity in inches per second
                velocity_in_per_sec = displacement_inches / time_elapsed

                # Convert to mph
                velocity_mph = velocity_in_per_sec * self.INCHES_PER_SEC_TO_MPH

            profile.append(VelocityPoint(
                frame_index=frame_idx,
                timestamp=timestamp,
                position=position,
                velocity_mph=velocity_mph,
                confidence=confidence
            ))

            prev_detection = {
                'position': position,
                'frame_index': frame_idx
            }

        return profile

    def _smooth_velocities(
        self,
        profile: List[VelocityPoint],
        window: int
    ) -> List[VelocityPoint]:
        """Apply moving average smoothing to velocity values."""
        if window <= 1 or len(profile) < window:
            return profile

        smoothed = []
        velocities = [p.velocity_mph for p in profile]

        for i, point in enumerate(profile):
            if point.velocity_mph is None:
                smoothed.append(point)
                continue

            # Collect values in window
            start = max(0, i - window // 2)
            end = min(len(velocities), i + window // 2 + 1)

            window_values = [
                v for v in velocities[start:end]
                if v is not None
            ]

            if window_values:
                avg_velocity = sum(window_values) / len(window_values)
                smoothed.append(VelocityPoint(
                    frame_index=point.frame_index,
                    timestamp=point.timestamp,
                    position=point.position,
                    velocity_mph=avg_velocity,
                    confidence=point.confidence
                ))
            else:
                smoothed.append(point)

        return smoothed

    def _find_peak_speed(
        self,
        profile: List[VelocityPoint]
    ) -> Tuple[Optional[float], Optional[int]]:
        """Find maximum velocity and the frame it occurred at."""
        peak_speed = 0.0
        peak_frame = None

        for point in profile:
            if point.velocity_mph is not None and point.velocity_mph > peak_speed:
                peak_speed = point.velocity_mph
                peak_frame = point.frame_index

        return (peak_speed if peak_speed > 0 else None, peak_frame)

    def _find_speed_at_frame(
        self,
        profile: List[VelocityPoint],
        target_frame: Optional[int]
    ) -> Optional[float]:
        """Find velocity at or near a specific frame."""
        if target_frame is None:
            return None

        # Look for exact match first
        for point in profile:
            if point.frame_index == target_frame and point.velocity_mph is not None:
                return point.velocity_mph

        # Find closest frame within tolerance
        tolerance = 3  # frames
        closest_point = None
        closest_distance = float('inf')

        for point in profile:
            if point.velocity_mph is None:
                continue
            distance = abs(point.frame_index - target_frame)
            if distance < closest_distance and distance <= tolerance:
                closest_distance = distance
                closest_point = point

        return closest_point.velocity_mph if closest_point else None

    def _calculate_downswing_average(
        self,
        profile: List[VelocityPoint],
        top_frame: Optional[int],
        impact_frame: Optional[int]
    ) -> Optional[float]:
        """Calculate average speed during downswing phase."""
        if top_frame is None or impact_frame is None:
            return None

        downswing_speeds = [
            p.velocity_mph for p in profile
            if p.velocity_mph is not None
            and top_frame <= p.frame_index <= impact_frame
        ]

        if not downswing_speeds:
            return None

        return sum(downswing_speeds) / len(downswing_speeds)

    def _calculate_confidence(
        self,
        detections: List[Optional["ClubheadDetection"]]
    ) -> float:
        """Calculate confidence based on detection success rate."""
        if not detections:
            return 0.0

        valid_count = sum(1 for d in detections if d is not None)
        detection_rate = valid_count / len(detections)

        # Also factor in average detection confidence
        confidences = [
            d.confidence for d in detections
            if d is not None and hasattr(d, 'confidence')
        ]
        avg_confidence = sum(confidences) / len(confidences) if confidences else 0.5

        # Combined confidence
        return detection_rate * avg_confidence


def estimate_velocity_from_positions(
    positions: List[Tuple[int, int]],
    fps: float,
    scale_factor: float,
    frame_indices: Optional[List[int]] = None
) -> VelocityMetrics:
    """
    Convenience function to estimate velocity from raw pixel positions.

    Args:
        positions: List of (x, y) pixel coordinates
        fps: Video frames per second
        scale_factor: Inches per pixel
        frame_indices: Optional list of frame indices (defaults to 0, 1, 2, ...)

    Returns:
        VelocityMetrics
    """
    if frame_indices is None:
        frame_indices = list(range(len(positions)))

    # Create mock detections
    class MockDetection:
        def __init__(self, pos, idx):
            self.centroid_pixels = pos
            self.frame_index = idx
            self.confidence = 1.0

    detections = [
        MockDetection(pos, idx)
        for pos, idx in zip(positions, frame_indices)
    ]

    estimator = VelocityEstimator(fps=fps, scale_factor=scale_factor)
    return estimator.estimate_from_detections(detections)
