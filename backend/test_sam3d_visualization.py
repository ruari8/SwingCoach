#!/usr/bin/env python3
"""
Test script: 3D body mesh visualization from golf swing video.

Extracts a frame from a golf swing video, runs SAM 3D Body inference,
and generates an interactive 3D mesh with skeleton overlay.

Usage:
    python test_sam3d_visualization.py [--video-path PATH] [--frame-index INDEX] [--output-dir DIR]
"""

import sys
import argparse
import logging
from pathlib import Path
import numpy as np

try:
    import cv2
    CV2_AVAILABLE = True
except ImportError:
    CV2_AVAILABLE = False
    try:
        import imageio
    except ImportError:
        imageio = None

# Setup imports
backend_dir = Path(__file__).parent
sys.path.insert(0, str(backend_dir))

from analysis.body_3d import Body3DDetector, Pose3DResult
from analysis.visualization_3d import Mesh3DVisualizer

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_frame(video_path: str, frame_index: int = 0) -> np.ndarray:
    """Extract a single frame from video."""
    if CV2_AVAILABLE:
        cap = cv2.VideoCapture(video_path)
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
        ret, frame = cap.read()
        cap.release()

        if not ret:
            raise ValueError(f"Could not extract frame {frame_index} from {video_path}")

        # Convert BGR to RGB
        return cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

    elif imageio is not None:
        reader = imageio.get_reader(video_path)
        frame = reader.get_data(frame_index)
        reader.close()
        # imageio typically returns RGB already
        return frame
    else:
        raise RuntimeError(
            "Need either opencv-python or imageio to extract video frames.\n"
            "Install with: pip install opencv-python  (or imageio)"
        )


def main():
    parser = argparse.ArgumentParser(
        description="Generate 3D mesh from golf swing video"
    )
    parser.add_argument(
        "--video-path",
        type=str,
        default="/Users/ruari/Documents/Startups/SwingCoach/backend/swingVideos/IMG_0737.mov",
        help="Path to input video file",
    )
    parser.add_argument(
        "--frame-index", type=int, default=30, help="Frame index to extract (default: 30)"
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default="/output",
        help="Output directory for 3D model (default: /output)",
    )

    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    logger.info(f"Loading video: {args.video_path}")
    image = extract_frame(args.video_path, args.frame_index)
    logger.info(f"Extracted frame {args.frame_index}: {image.shape}")

    logger.info("Initializing SAM 3D Body detector...")
    detector = Body3DDetector()

    logger.info("Running 3D pose detection...")
    pose_result = detector.detect(image, frame_index=args.frame_index)

    if pose_result is None:
        logger.error("Failed to detect pose in frame")
        return 1

    logger.info(
        f"Detected pose with {len(pose_result.keypoints_3d)} keypoints"
    )
    logger.info(f"Mesh vertices: {pose_result.vertices.shape if pose_result.vertices is not None else 'None'}")

    # Create visualizer
    logger.info("Creating 3D visualization...")
    visualizer = Mesh3DVisualizer()

    # Export to output directory
    output_path = visualizer.export_for_viewer(
        pose_result, output_dir=str(output_dir)
    )
    logger.info(f"✓ 3D model saved to: {output_path}")
    logger.info(f"✓ View the model in any 3D viewer (e.g., view.babylon.com)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
