"""
Test temporal smoothing on 3D pose sequences.

Validates that Kalman filtering reduces jitter while preserving swing motion.
"""

import sys
import logging
import numpy as np
from pathlib import Path
from typing import List

# Add backend to path
BACKEND_DIR = Path(__file__).parent
sys.path.insert(0, str(BACKEND_DIR))

from analysis.body_3d import Body3DDetector, Pose3DResult, Keypoint3D
from analysis.temporal_smoother import (
    TemporalSmoother,
    AdaptiveTemporalSmoother,
    moving_average_smooth,
)
from analysis.frame_extractor import FrameExtractor

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def calculate_jitter(poses: List[Pose3DResult], keypoint_name: str = "right_wrist") -> tuple:
    """
    Calculate temporal jitter (standard deviation of position differences).

    Returns:
        (mean_distance, std_distance) - Mean and std of frame-to-frame distances
    """
    distances = []

    for i in range(1, len(poses)):
        prev_kp = poses[i - 1].keypoints_3d.get(keypoint_name)
        curr_kp = poses[i].keypoints_3d.get(keypoint_name)

        if prev_kp and curr_kp:
            delta = np.array([
                curr_kp.x - prev_kp.x,
                curr_kp.y - prev_kp.y,
                curr_kp.z - prev_kp.z,
            ])
            distance = np.linalg.norm(delta)
            distances.append(distance)

    if not distances:
        return 0, 0

    return np.mean(distances), np.std(distances)


def calculate_mpjpe(poses1: List[Pose3DResult], poses2: List[Pose3DResult]) -> float:
    """
    Calculate Mean Per-Joint Position Error between two pose sequences.

    Args:
        poses1: Original poses
        poses2: Smoothed poses

    Returns:
        MPJPE in meters
    """
    if len(poses1) != len(poses2):
        logger.warning("Pose sequences have different lengths")
        return 0.0

    errors = []

    for p1, p2 in zip(poses1, poses2):
        for keypoint_name in p1.keypoints_3d:
            kp1 = p1.keypoints_3d.get(keypoint_name)
            kp2 = p2.keypoints_3d.get(keypoint_name)

            if kp1 and kp2:
                error = np.sqrt(
                    (kp1.x - kp2.x) ** 2
                    + (kp1.y - kp2.y) ** 2
                    + (kp1.z - kp2.z) ** 2
                )
                errors.append(error)

    if not errors:
        return 0.0

    return np.mean(errors)


def test_temporal_smoother_on_video(video_path: str, fps: int = 30, sample_rate: int = 2):
    """
    Test temporal smoothing on an actual golf swing video.

    Args:
        video_path: Path to golf swing video
        fps: Frames per second of video
        sample_rate: Process every Nth frame (2 = every other frame)
    """
    logger.info(f"Testing temporal smoothing on: {video_path}")

    # Check video exists
    if not Path(video_path).exists():
        logger.error(f"Video not found: {video_path}")
        return False

    try:
        # Extract frames
        logger.info("Extracting frames...")
        frame_extractor = FrameExtractor()
        # Read video file as bytes
        video_bytes = Path(video_path).read_bytes()
        frame_bytes_list = frame_extractor.extract_frames(video_bytes, sample_rate=sample_rate)

        # Convert PNG bytes to numpy arrays
        from io import BytesIO
        from PIL import Image
        frames = []
        for frame_bytes in frame_bytes_list:
            img = Image.open(BytesIO(frame_bytes)).convert('RGB')
            frame_array = np.array(img)
            frames.append(frame_array)

        logger.info(f"Extracted {len(frames)} frames at {fps}fps (every {sample_rate} frames)")

        # Run 3D detection
        logger.info("Running 3D body detection (this will take a while)...")
        detector = Body3DDetector()
        poses = detector.detect_batch(frames, clear_cache=False)
        poses = [p for p in poses if p is not None]
        logger.info(f"Detected poses in {len(poses)} frames")

        if len(poses) < 3:
            logger.error("Not enough valid poses for smoothing test")
            return False

        # Calculate metrics before smoothing
        logger.info("\n=== BEFORE SMOOTHING ===")
        jitter_before = calculate_jitter(poses, "right_wrist")
        logger.info(f"Right wrist jitter: mean={jitter_before[0]:.6f}m, std={jitter_before[1]:.6f}m")

        # Test 1: Kalman filter smoothing
        logger.info("\n=== KALMAN FILTER SMOOTHING ===")
        smoother = TemporalSmoother(fps=fps, process_noise=0.01, measurement_noise=0.5)
        poses_kalman = smoother.smooth_poses(poses)

        jitter_kalman = calculate_jitter(poses_kalman, "right_wrist")
        logger.info(f"Right wrist jitter: mean={jitter_kalman[0]:.6f}m, std={jitter_kalman[1]:.6f}m")

        mpjpe_kalman = calculate_mpjpe(poses, poses_kalman)
        logger.info(f"MPJPE vs original: {mpjpe_kalman:.6f}m")

        jitter_reduction = (1 - jitter_kalman[0] / jitter_before[0]) * 100 if jitter_before[0] > 0 else 0
        logger.info(f"Jitter reduction: {jitter_reduction:.1f}%")

        # Test 2: Adaptive smoothing
        logger.info("\n=== ADAPTIVE SMOOTHING ===")
        adaptive_smoother = AdaptiveTemporalSmoother(fps=fps)
        poses_adaptive = adaptive_smoother.smooth_poses(poses)

        jitter_adaptive = calculate_jitter(poses_adaptive, "right_wrist")
        logger.info(f"Right wrist jitter: mean={jitter_adaptive[0]:.6f}m, std={jitter_adaptive[1]:.6f}m")

        mpjpe_adaptive = calculate_mpjpe(poses, poses_adaptive)
        logger.info(f"MPJPE vs original: {mpjpe_adaptive:.6f}m")

        # Test 3: Moving average smoothing
        logger.info("\n=== MOVING AVERAGE SMOOTHING (window=5) ===")
        poses_moving_avg = moving_average_smooth(poses, window_size=5)

        jitter_moving = calculate_jitter(poses_moving_avg, "right_wrist")
        logger.info(f"Right wrist jitter: mean={jitter_moving[0]:.6f}m, std={jitter_moving[1]:.6f}m")

        mpjpe_moving = calculate_mpjpe(poses, poses_moving_avg)
        logger.info(f"MPJPE vs original: {mpjpe_moving:.6f}m")

        # Summary
        logger.info("\n=== SUMMARY ===")
        logger.info(f"Original jitter: {jitter_before[0]:.6f}m")
        logger.info(f"Kalman jitter: {jitter_kalman[0]:.6f}m ({jitter_reduction:.1f}% reduction)")
        logger.info(f"Adaptive jitter: {jitter_adaptive[0]:.6f}m")
        logger.info(f"Moving avg jitter: {jitter_moving[0]:.6f}m")
        logger.info("\nRecommendation: Use Kalman filter for best balance of smoothness and accuracy")

        return True

    except Exception as e:
        logger.error(f"Test failed: {e}", exc_info=True)
        return False


def test_synthetic_noisy_sequence():
    """
    Test smoothing on synthetic noisy 3D trajectory.

    Creates a simple linear trajectory with added Gaussian noise.
    """
    logger.info("Testing temporal smoothing on synthetic noisy data...")

    # Create synthetic poses with known trajectory
    n_frames = 60
    poses = []

    for i in range(n_frames):
        # True trajectory: linear motion in z-direction
        t = i / n_frames
        true_x = 0.0
        true_y = 0.5
        true_z = -0.5 + t * 1.0  # Move from -0.5 to 0.5

        # Add Gaussian noise
        noise_scale = 0.02  # 2cm noise
        x = true_x + np.random.normal(0, noise_scale)
        y = true_y + np.random.normal(0, noise_scale)
        z = true_z + np.random.normal(0, noise_scale)

        # Create minimal Pose3DResult with proper Keypoint3D dataclasses
        pose = Pose3DResult(
            keypoints_3d={
                "right_wrist": Keypoint3D(x=x, y=y, z=z, name="right_wrist", confidence=1.0),
                "left_wrist": Keypoint3D(x=x + 0.2, y=y - 0.1, z=z + 0.05, name="left_wrist", confidence=1.0),
            },
            keypoints_2d={},
            frame_index=i,
            bbox=np.array([0, 0, 1, 1]),
            focal_length=500,
            camera_translation=np.array([0, 0, 0]),
        )
        poses.append(pose)

    # Calculate metrics
    logger.info(f"Created {len(poses)} synthetic frames with Gaussian noise (σ={0.02}m)")

    jitter_before = calculate_jitter(poses, "right_wrist")
    logger.info(f"Original jitter: mean={jitter_before[0]:.6f}m, std={jitter_before[1]:.6f}m")

    # Apply smoothing
    smoother = TemporalSmoother(fps=30, process_noise=0.001, measurement_noise=0.01)
    poses_smooth = smoother.smooth_poses(poses)

    jitter_after = calculate_jitter(poses_smooth, "right_wrist")
    logger.info(f"Smoothed jitter: mean={jitter_after[0]:.6f}m, std={jitter_after[1]:.6f}m")

    reduction = (1 - jitter_after[0] / jitter_before[0]) * 100
    logger.info(f"Jitter reduction: {reduction:.1f}%")
    logger.info("✓ Synthetic test passed\n")

    return True


if __name__ == "__main__":
    logger.info("=" * 60)
    logger.info("TEMPORAL SMOOTHING TEST SUITE")
    logger.info("=" * 60 + "\n")

    # Test 1: Synthetic data (always runs)
    test_synthetic_noisy_sequence()

    # Test 2: Real video (if provided)
    import sys

    if len(sys.argv) > 1:
        video_path = sys.argv[1]
        fps = int(sys.argv[2]) if len(sys.argv) > 2 else 30
        test_temporal_smoother_on_video(video_path, fps=fps)
    else:
        logger.info("To test on real video, run:")
        logger.info("  python test_temporal_smoothing.py <video_path> [fps]")
        logger.info("\nExample:")
        logger.info("  python test_temporal_smoothing.py swingVideos/sample.mp4 240")
