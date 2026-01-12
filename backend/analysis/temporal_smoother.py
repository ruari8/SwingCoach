"""
Temporal smoothing for 3D pose sequences using Kalman filters.

Eliminates frame-to-frame jitter in SAM 3D Body output while preserving
the natural motion of the golf swing.
"""

import numpy as np
import logging
from typing import List, Dict, Optional
from dataclasses import dataclass, replace
from copy import deepcopy

logger = logging.getLogger(__name__)

try:
    from filterpy.kalman import KalmanFilter
    FILTERPY_AVAILABLE = True
except ImportError:
    FILTERPY_AVAILABLE = False
    logger.warning("filterpy not available. Install with: pip install filterpy")


@dataclass
class KalmanState3D:
    """State of 3D Kalman filter for a single joint."""
    x: float  # Position
    y: float
    z: float
    vx: float = 0.0  # Velocity
    vy: float = 0.0
    vz: float = 0.0


class Keypoint3DFilter:
    """Kalman filter for smoothing a single 3D keypoint trajectory."""

    def __init__(
        self,
        process_noise: float = 0.01,
        measurement_noise: float = 0.5,
        dt: float = 1.0 / 30.0,  # Default to 30fps
    ):
        """
        Initialize Kalman filter for 3D point tracking.

        Args:
            process_noise: How much we expect the object to deviate from prediction
            measurement_noise: How much we trust the measurements
            dt: Time step between frames (seconds)
        """
        if not FILTERPY_AVAILABLE:
            raise RuntimeError(
                "filterpy is required for temporal smoothing. "
                "Install with: pip install filterpy"
            )

        self.dt = dt
        self.filter = KalmanFilter(dim_x=6, dim_z=3)  # 6D state, 3D measurement

        # State: [x, y, z, vx, vy, vz]
        # Measurement: [x, y, z]

        # State transition matrix (constant velocity model)
        self.filter.F = np.array([
            [1, 0, 0, dt, 0, 0],
            [0, 1, 0, 0, dt, 0],
            [0, 0, 1, 0, 0, dt],
            [0, 0, 0, 1, 0, 0],
            [0, 0, 0, 0, 1, 0],
            [0, 0, 0, 0, 0, 1],
        ])

        # Measurement matrix (only observe position, not velocity)
        self.filter.H = np.array([
            [1, 0, 0, 0, 0, 0],
            [0, 1, 0, 0, 0, 0],
            [0, 0, 1, 0, 0, 0],
        ])

        # Process noise covariance
        q = process_noise
        self.filter.Q = np.eye(6) * q

        # Measurement noise covariance
        r = measurement_noise
        self.filter.R = np.eye(3) * r

        # Initial state covariance
        self.filter.P = np.eye(6) * 1.0

        # Initial state
        self.filter.x = np.array([0, 0, 0, 0, 0, 0])

        self.initialized = False

    def predict(self) -> np.ndarray:
        """Predict next position without measurement."""
        self.filter.predict()
        return self.filter.x[:3]  # Return position only

    def update(self, measurement: np.ndarray) -> np.ndarray:
        """
        Update filter with a measurement and return filtered position.

        Args:
            measurement: 3D position [x, y, z]

        Returns:
            Smoothed 3D position
        """
        if not self.initialized:
            # Initialize state with first measurement
            self.filter.x[:3] = measurement
            self.initialized = True

        self.filter.predict()
        self.filter.update(measurement)

        return self.filter.x[:3].copy()

    def get_velocity(self) -> np.ndarray:
        """Get current estimated velocity."""
        return self.filter.x[3:6].copy()


class TemporalSmoother:
    """Smooth 3D pose sequences using Kalman filters for each keypoint."""

    def __init__(
        self,
        process_noise: float = 0.01,
        measurement_noise: float = 0.5,
        fps: float = 30.0,
    ):
        """
        Initialize temporal smoother.

        Args:
            process_noise: Kalman filter process noise
            measurement_noise: Kalman filter measurement noise
            fps: Frames per second of video
        """
        self.process_noise = process_noise
        self.measurement_noise = measurement_noise
        self.fps = fps
        self.dt = 1.0 / fps
        self.filters: Dict[str, Keypoint3DFilter] = {}

    def _get_or_create_filter(self, keypoint_name: str) -> Keypoint3DFilter:
        """Get existing filter or create new one for a keypoint."""
        if keypoint_name not in self.filters:
            self.filters[keypoint_name] = Keypoint3DFilter(
                process_noise=self.process_noise,
                measurement_noise=self.measurement_noise,
                dt=self.dt,
            )
        return self.filters[keypoint_name]

    def smooth_single_pose(self, pose_result) -> None:
        """
        Smooth keypoints in a single pose result IN-PLACE.

        This should be called sequentially on consecutive frames.
        Updates the pose_result.keypoints_3d with smoothed values.

        Args:
            pose_result: Pose3DResult to smooth
        """
        for keypoint_name, keypoint_3d in pose_result.keypoints_3d.items():
            filter_obj = self._get_or_create_filter(keypoint_name)

            measurement = np.array([keypoint_3d.x, keypoint_3d.y, keypoint_3d.z])
            smoothed_pos = filter_obj.update(measurement)

            # Update keypoint with smoothed position
            pose_result.keypoints_3d[keypoint_name] = replace(
                keypoint_3d,
                x=float(smoothed_pos[0]),
                y=float(smoothed_pos[1]),
                z=float(smoothed_pos[2]),
            )

    def smooth_poses(self, poses: List) -> List:
        """
        Smooth a sequence of poses.

        Args:
            poses: List of Pose3DResult objects

        Returns:
            List of smoothed Pose3DResult objects
        """
        if not poses:
            return poses

        smoothed = []
        for pose in poses:
            # Make a deep copy to avoid modifying original
            pose_copy = deepcopy(pose)
            self.smooth_single_pose(pose_copy)
            smoothed.append(pose_copy)

        return smoothed

    def get_velocity(self, keypoint_name: str) -> Optional[np.ndarray]:
        """
        Get current estimated velocity for a keypoint.

        Args:
            keypoint_name: Name of the keypoint

        Returns:
            3D velocity vector or None if not yet filtered
        """
        if keypoint_name not in self.filters:
            return None
        return self.filters[keypoint_name].get_velocity()

    def reset(self):
        """Reset all filters (useful for processing multiple sequences)."""
        self.filters.clear()


class AdaptiveTemporalSmoother:
    """
    More sophisticated smoother that adapts smoothing strength based on motion speed.

    For slow motion (setup), uses stronger smoothing.
    For fast motion (downswing), uses lighter smoothing to preserve club speed.
    """

    def __init__(self, fps: float = 30.0):
        """Initialize adaptive smoother."""
        self.fps = fps
        self.dt = 1.0 / fps

    def smooth_poses(
        self,
        poses: List,
        fast_motion_threshold: float = 0.5,  # meters per second
    ) -> List:
        """
        Smooth poses with adaptive filtering based on motion speed.

        Args:
            poses: List of Pose3DResult objects
            fast_motion_threshold: Speed threshold for switching to lighter smoothing (m/s)

        Returns:
            List of smoothed Pose3DResult objects
        """
        if not poses:
            return poses

        smoothed = []
        prev_pose = None

        for i, pose in enumerate(poses):
            if prev_pose is None:
                smoothed.append(deepcopy(pose))
                prev_pose = pose
                continue

            # Estimate motion speed from wrist position (fastest moving joint)
            prev_wrist = prev_pose.keypoints_3d.get("right_wrist")
            curr_wrist = pose.keypoints_3d.get("right_wrist")

            if prev_wrist and curr_wrist:
                delta = np.array([
                    curr_wrist.x - prev_wrist.x,
                    curr_wrist.y - prev_wrist.y,
                    curr_wrist.z - prev_wrist.z,
                ])
                speed = np.linalg.norm(delta) / self.dt  # m/s

                # Choose smoothing strength based on speed
                if speed > fast_motion_threshold:
                    # Light smoothing for fast motion (preserve club speed detail)
                    alpha = 0.7  # Keep 70% of current measurement
                else:
                    # Stronger smoothing for slow motion (reduce jitter)
                    alpha = 0.5  # Keep 50% of current measurement
            else:
                alpha = 0.5

            # Apply exponential smoothing to each keypoint
            pose_copy = deepcopy(pose)
            for keypoint_name, curr_keypoint in pose_copy.keypoints_3d.items():
                prev_keypoint = prev_pose.keypoints_3d.get(keypoint_name)

                if prev_keypoint:
                    # Exponential smoothing: new = alpha * current + (1-alpha) * previous
                    smoothed_x = alpha * curr_keypoint.x + (1 - alpha) * prev_keypoint.x
                    smoothed_y = alpha * curr_keypoint.y + (1 - alpha) * prev_keypoint.y
                    smoothed_z = alpha * curr_keypoint.z + (1 - alpha) * prev_keypoint.z

                    pose_copy.keypoints_3d[keypoint_name] = replace(
                        curr_keypoint,
                        x=float(smoothed_x),
                        y=float(smoothed_y),
                        z=float(smoothed_z),
                    )

            smoothed.append(pose_copy)
            prev_pose = pose_copy

        return smoothed


def moving_average_smooth(poses: List, window_size: int = 3) -> List:
    """
    Simple moving average smoothing (lightweight alternative to Kalman).

    Args:
        poses: List of Pose3DResult objects
        window_size: Number of frames to average (odd numbers work best)

    Returns:
        List of smoothed Pose3DResult objects
    """
    if not poses or window_size < 1:
        return poses

    window_size = min(window_size, len(poses))
    if window_size % 2 == 0:
        window_size -= 1  # Make odd

    radius = window_size // 2
    smoothed = []

    for i, pose in enumerate(poses):
        pose_copy = deepcopy(pose)

        # Calculate window range (center on current frame)
        start = max(0, i - radius)
        end = min(len(poses), i + radius + 1)

        # Average keypoints in window
        for keypoint_name in pose_copy.keypoints_3d:
            positions = []
            for j in range(start, end):
                kp = poses[j].keypoints_3d.get(keypoint_name)
                if kp:
                    positions.append([kp.x, kp.y, kp.z])

            if positions:
                avg_pos = np.mean(positions, axis=0)
                curr_kp = pose_copy.keypoints_3d[keypoint_name]
                pose_copy.keypoints_3d[keypoint_name] = replace(
                    curr_kp,
                    x=float(avg_pos[0]),
                    y=float(avg_pos[1]),
                    z=float(avg_pos[2]),
                )

        smoothed.append(pose_copy)

    return smoothed
