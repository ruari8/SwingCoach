"""
Test animation export functionality.

Exports smoothed 3D poses to animated GLTF/GLB files.
"""

import sys
import logging
import numpy as np
from pathlib import Path

# Add backend to path
BACKEND_DIR = Path(__file__).parent
sys.path.insert(0, str(BACKEND_DIR))

from analysis.body_3d import Body3DDetector, Pose3DResult, Keypoint3D
from analysis.temporal_smoother import TemporalSmoother
from analysis.animation_exporter import AnimationExporter, export_swing_animation
from analysis.frame_extractor import FrameExtractor

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def create_synthetic_swing_poses(num_frames: int = 60) -> list:
    """
    Create synthetic golf swing poses for testing.

    Simulates a swing motion with varying club speed.
    """
    poses = []

    for i in range(num_frames):
        t = i / num_frames  # 0 to 1

        # Simple swing arc simulation
        # Right wrist moves in a downswing pattern
        wrist_x = 0.1 * np.sin(t * np.pi)  # Side to side
        wrist_y = 0.5 - 0.3 * t  # Down motion
        wrist_z = -0.5 + t * 1.0  # Forward motion

        # Add small amount of noise for realism
        wrist_x += np.random.normal(0, 0.01)
        wrist_y += np.random.normal(0, 0.01)
        wrist_z += np.random.normal(0, 0.01)

        # Simple body pose
        pose = Pose3DResult(
            keypoints_3d={
                "nose": Keypoint3D(x=0.0, y=1.7, z=-0.5, name="nose", confidence=1.0),
                "left_shoulder": Keypoint3D(
                    x=-0.2, y=1.4, z=-0.5, name="left_shoulder", confidence=1.0
                ),
                "right_shoulder": Keypoint3D(
                    x=0.2, y=1.4, z=-0.5, name="right_shoulder", confidence=1.0
                ),
                "left_hip": Keypoint3D(
                    x=-0.15, y=0.8, z=-0.5, name="left_hip", confidence=1.0
                ),
                "right_hip": Keypoint3D(
                    x=0.15, y=0.8, z=-0.5, name="right_hip", confidence=1.0
                ),
                "right_wrist": Keypoint3D(
                    x=wrist_x, y=wrist_y, z=wrist_z, name="right_wrist", confidence=1.0
                ),
                "left_wrist": Keypoint3D(
                    x=-0.1, y=0.9, z=-0.5, name="left_wrist", confidence=1.0
                ),
                "right_elbow": Keypoint3D(
                    x=wrist_x + 0.05, y=wrist_y + 0.3, z=-0.5, name="right_elbow", confidence=1.0
                ),
            },
            keypoints_2d={},
            frame_index=i,
            bbox=np.array([0, 0, 1, 1]),
            focal_length=500,
            camera_translation=np.array([0, 0, 0]),
        )
        poses.append(pose)

    logger.info(f"Created {len(poses)} synthetic swing poses")
    return poses


def test_animation_export_synthetic():
    """Test animation export with synthetic poses."""
    logger.info("=" * 60)
    logger.info("TEST 1: Animation Export (Synthetic Poses)")
    logger.info("=" * 60)

    try:
        # Create synthetic poses
        poses = create_synthetic_swing_poses(60)

        # Smooth them
        logger.info("Smoothing poses...")
        smoother = TemporalSmoother(fps=30)
        poses_smooth = smoother.smooth_poses(poses)

        # Export to animation
        logger.info("Exporting to animated GLTF...")
        filename = "swing_animation_synthetic.gltf"
        exporter = AnimationExporter()
        success = exporter.export_animation(
            poses_smooth,
            filename,
            fps=30,
            joint_subset=[
                "right_wrist",
                "left_wrist",
                "right_elbow",
                "right_shoulder",
                "left_shoulder",
            ],
        )

        if success:
            output_path = Path(__file__).parent / "output" / filename
            if output_path.exists():
                file_size = output_path.stat().st_size
                logger.info(f"✓ Animation exported: {output_path} ({file_size / 1024:.1f} KB)")
            logger.info(f"✓ File can be viewed in: https://gltf-viewer.donmccurdy.com/")
            return True
        else:
            logger.error("Export failed or file not created")
            return False

    except Exception as e:
        logger.error(f"Test failed: {e}", exc_info=True)
        return False


def test_animation_export_real_video(sample_rate: int = 8):
    """Test animation export with real golf swing video."""
    logger.info("\n" + "=" * 60)
    logger.info(f"TEST 2: Animation Export (Real Video, sample_rate={sample_rate})")
    logger.info("=" * 60)

    video_path = "swingVideos/IMG_0737.mov"
    logger.info(f"Sample rate: {sample_rate} (extracting every {sample_rate}th frame)")

    if not Path(video_path).exists():
        logger.warning(f"Video not found: {video_path}")
        return False

    try:
        # Extract frames
        logger.info("Extracting frames...")
        frame_extractor = FrameExtractor()
        video_bytes = Path(video_path).read_bytes()
        frame_bytes_list = frame_extractor.extract_frames(video_bytes, sample_rate=sample_rate)

        # Convert to numpy arrays
        from io import BytesIO
        from PIL import Image

        frames = []
        for frame_bytes in frame_bytes_list:
            img = Image.open(BytesIO(frame_bytes)).convert("RGB")
            frame_array = np.array(img)
            frames.append(frame_array)

        logger.info(f"Extracted {len(frames)} frames")

        # Run 3D detection
        logger.info("Running 3D body detection...")
        detector = Body3DDetector()
        poses = detector.detect_batch(frames, clear_cache=False)
        poses = [p for p in poses if p is not None]
        logger.info(f"Detected poses in {len(poses)} frames")

        if len(poses) < 3:
            logger.error("Not enough valid poses")
            return False

        # Check if we have mesh data - if so, skip smoothing to keep joints synced with mesh
        has_mesh = poses[0].vertices is not None
        if has_mesh:
            logger.info("Mesh data detected - skipping temporal smoothing to keep joints synced")
            poses_to_export = poses
        else:
            logger.info("Smoothing poses (no mesh data)...")
            smoother = TemporalSmoother(fps=240, process_noise=0.01, measurement_noise=0.5)
            poses_to_export = smoother.smooth_poses(poses)

        # Export
        logger.info("Exporting to animated GLTF...")
        filename = f"swing_animation_real_sr{sample_rate}.gltf"
        fps_effective = 240 // sample_rate
        success = export_swing_animation(poses_to_export, filename, fps=fps_effective)

        if success:
            output_path = Path(__file__).parent / "output" / filename
            if output_path.exists():
                file_size = output_path.stat().st_size
                logger.info(f"✓ Animation exported: {output_path} ({file_size / 1024:.1f} KB)")
            logger.info(f"✓ Duration: {len(poses_to_export) / fps_effective:.2f}s")
            logger.info(f"✓ File can be viewed in: https://gltf-viewer.donmccurdy.com/")
            return True
        else:
            logger.error("Export failed")
            return False

    except Exception as e:
        logger.error(f"Test failed: {e}", exc_info=True)
        return False


if __name__ == "__main__":
    logger.info("\n🎬 ANIMATION EXPORT TEST SUITE\n")

    # Test 1: Synthetic (always runs, fast)
    test1_pass = test_animation_export_synthetic()

    # Test 2: Real video (slow, optional)
    test2_pass = False
    sample_rate = 8  # Default: quick test
    if len(sys.argv) > 1:
        if sys.argv[1] == "--with-video":
            test2_pass = test_animation_export_real_video(sample_rate=sample_rate)
        elif sys.argv[1] == "--full":
            sample_rate = 1
            test2_pass = test_animation_export_real_video(sample_rate=sample_rate)

    # Summary
    logger.info("\n" + "=" * 60)
    logger.info("SUMMARY")
    logger.info("=" * 60)
    logger.info(f"Synthetic test: {'✓ PASS' if test1_pass else '✗ FAIL'}")
    if test2_pass or (len(sys.argv) > 1 and sys.argv[1] == "--with-video"):
        logger.info(f"Real video test: {'✓ PASS' if test2_pass else '✗ FAIL'}")
    else:
        logger.info("Real video test: Skipped")
        logger.info("  To test: python test_animation_export.py --with-video  (quick, sample_rate=8)")
        logger.info("  Or:      python test_animation_export.py --full        (full quality, sample_rate=1)")

    logger.info("\nNext: Review exported animation files in 3D viewer")
    logger.info("Files saved to: backend/output/")
    logger.info("View in: https://gltf-viewer.donmccurdy.com/")
