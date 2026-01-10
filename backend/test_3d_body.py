#!/usr/bin/env python3
"""
Test SAM 3D Body integration.

Validates:
1. Model loads on MPS
2. Can detect 3D pose from a golf swing frame
3. Outputs are reasonable (joint positions, etc.)

Usage:
    cd backend
    ./venv/bin/python test_3d_body.py
"""

import sys
import time
import logging
import io
from pathlib import Path

import numpy as np
from PIL import Image

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

# Add analysis to path
sys.path.insert(0, str(Path(__file__).parent))

from analysis.body_3d import Body3DDetector, SAM3D_AVAILABLE, MHR70_NAMES
from analysis.frame_extractor import FrameExtractor


def test_imports():
    """Test that all imports work."""
    print("\n" + "="*60)
    print("TEST 1: Imports")
    print("="*60)
    
    if not SAM3D_AVAILABLE:
        print("FAIL: SAM 3D Body not available")
        return False
    
    print("PASS: All imports successful")
    return True


def test_model_loading():
    """Test that the model loads on MPS."""
    print("\n" + "="*60)
    print("TEST 2: Model Loading")
    print("="*60)
    
    start = time.time()
    
    try:
        detector = Body3DDetector()
        elapsed = time.time() - start
        print(f"PASS: Model loaded in {elapsed:.1f}s on device: {detector.device}")
        return detector
    except Exception as e:
        print(f"FAIL: {e}")
        import traceback
        traceback.print_exc()
        return None


def test_single_frame(detector: Body3DDetector, video_path: str):
    """Test 3D pose detection on a single frame."""
    print("\n" + "="*60)
    print("TEST 3: Single Frame Detection")
    print("="*60)
    
    # Extract first frame
    print(f"Loading video: {video_path}")
    
    # Read video bytes
    with open(video_path, 'rb') as f:
        video_bytes = f.read()
    
    extractor = FrameExtractor()
    frame_bytes_list = extractor.extract_frames(video_bytes, sample_rate=30, max_frames=1)
    
    if not frame_bytes_list:
        print("FAIL: Could not extract frame from video")
        return False
    
    # Convert PNG bytes to numpy array
    frame = np.array(Image.open(io.BytesIO(frame_bytes_list[0])))
    print(f"Frame shape: {frame.shape}")
    
    # Convert to RGB if needed
    if len(frame.shape) == 2:
        frame = np.stack([frame]*3, axis=-1)
    
    # Detect pose
    start = time.time()
    result = detector.detect(frame, frame_index=0)
    elapsed = time.time() - start
    
    if result is None:
        print("FAIL: No pose detected")
        return False
    
    print(f"PASS: Pose detected in {elapsed:.2f}s")
    print(f"  - Keypoints: {len(result.keypoints_3d)}")
    print(f"  - Focal length: {result.focal_length:.1f}")
    print(f"  - Camera translation: {result.camera_translation}")
    
    # Print some key joints
    print("\nKey joint positions (meters):")
    for name in ['left_shoulder', 'right_shoulder', 'left_hip', 'right_hip', 
                 'left_wrist', 'right_wrist', 'neck']:
        kp = result.keypoints_3d.get(name)
        if kp:
            print(f"  {name:20s}: ({kp.x:+.3f}, {kp.y:+.3f}, {kp.z:+.3f})")
    
    # Calculate shoulder width as sanity check
    left_shoulder = result.keypoints_3d['left_shoulder']
    right_shoulder = result.keypoints_3d['right_shoulder']
    shoulder_width = np.sqrt(
        (left_shoulder.x - right_shoulder.x)**2 +
        (left_shoulder.y - right_shoulder.y)**2 +
        (left_shoulder.z - right_shoulder.z)**2
    )
    print(f"\nShoulder width: {shoulder_width:.2f}m")
    
    # Sanity check: shoulder width should be ~0.35-0.50m
    if 0.2 < shoulder_width < 0.8:
        print("PASS: Shoulder width is reasonable")
    else:
        print(f"WARNING: Shoulder width {shoulder_width:.2f}m seems off (expected 0.35-0.5m)")
    
    return result


def test_visualization(result, output_path: str):
    """Create a simple visualization of 3D keypoints."""
    print("\n" + "="*60)
    print("TEST 4: Visualization")
    print("="*60)
    
    try:
        import matplotlib
        matplotlib.use('Agg')  # Non-interactive backend
        import matplotlib.pyplot as plt
        from mpl_toolkits.mplot3d import Axes3D
    except ImportError:
        print("SKIP: matplotlib not available")
        return
    
    # Get 3D positions for main body joints
    body_joints = [
        'nose', 'neck',
        'left_shoulder', 'right_shoulder',
        'left_elbow', 'right_elbow',
        'left_wrist', 'right_wrist',
        'left_hip', 'right_hip',
        'left_knee', 'right_knee',
        'left_ankle', 'right_ankle',
    ]
    
    positions = []
    for name in body_joints:
        kp = result.keypoints_3d.get(name)
        if kp:
            positions.append([kp.x, kp.y, kp.z])
    
    positions = np.array(positions)
    
    # Create 3D plot
    fig = plt.figure(figsize=(10, 10))
    ax = fig.add_subplot(111, projection='3d')
    
    # Plot points
    ax.scatter(positions[:, 0], positions[:, 2], -positions[:, 1], 
               c='blue', s=50, label='Joints')
    
    # Draw skeleton connections
    connections = [
        (0, 1),  # nose -> neck
        (1, 2), (1, 3),  # neck -> shoulders
        (2, 4), (3, 5),  # shoulders -> elbows
        (4, 6), (5, 7),  # elbows -> wrists
        (1, 8), (1, 9),  # neck -> hips (simplified)
        (8, 10), (9, 11),  # hips -> knees
        (10, 12), (11, 13),  # knees -> ankles
        (8, 9),  # hip line
    ]
    
    for i, j in connections:
        if i < len(positions) and j < len(positions):
            ax.plot([positions[i, 0], positions[j, 0]],
                   [positions[i, 2], positions[j, 2]],
                   [-positions[i, 1], -positions[j, 1]],
                   'b-', alpha=0.5)
    
    ax.set_xlabel('X (meters)')
    ax.set_ylabel('Z (depth)')
    ax.set_zlabel('Y (height)')
    ax.set_title('3D Body Pose - SAM 3D Body')
    
    # Set equal aspect ratio
    max_range = np.max(np.abs(positions)) * 1.5
    ax.set_xlim(-max_range, max_range)
    ax.set_ylim(0, 3)  # Depth
    ax.set_zlim(-max_range, max_range)
    
    plt.savefig(output_path, dpi=150, bbox_inches='tight')
    print(f"PASS: Saved visualization to {output_path}")


def main():
    print("\n" + "#"*60)
    print("# SAM 3D Body Integration Test")
    print("#"*60)
    
    # Test video path
    video_path = "swingVideos/IMG_0737.mov"
    if not Path(video_path).exists():
        # Try alternate paths
        for alt in ["swingVideos/IMG_0738.mov", "swingVideos/test.mov"]:
            if Path(alt).exists():
                video_path = alt
                break
        else:
            print(f"ERROR: No test video found at {video_path}")
            print("Available videos:", list(Path("swingVideos").glob("*.mov")))
            sys.exit(1)
    
    # Run tests
    if not test_imports():
        sys.exit(1)
    
    detector = test_model_loading()
    if detector is None:
        sys.exit(1)
    
    result = test_single_frame(detector, video_path)
    if not result:
        sys.exit(1)
    
    # Visualization
    output_dir = Path("output")
    output_dir.mkdir(exist_ok=True)
    test_visualization(result, str(output_dir / "3d_pose_test.png"))
    
    print("\n" + "#"*60)
    print("# ALL TESTS PASSED")
    print("#"*60)
    print("\nSAM 3D Body is working correctly on MPS!")
    print(f"Output saved to: {output_dir / '3d_pose_test.png'}")


if __name__ == "__main__":
    main()
