#!/usr/bin/env python3
"""
Test script for skeleton visualization.
Extracts a few frames, runs pose detection, and saves annotated images.
"""

import sys
import logging
from pathlib import Path

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Add parent to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from analysis import FrameExtractor, PoseDetector, SwingVisualizer


def test_visualization(video_path: str, output_dir: str = "output"):
    """
    Test skeleton visualization on a few frames.
    
    Args:
        video_path: Path to video file
        output_dir: Directory to save output images
    """
    path = Path(video_path)
    if not path.exists():
        raise FileNotFoundError(f"Video not found: {path}")
    
    output_path = Path(output_dir)
    output_path.mkdir(exist_ok=True)
    
    logger.info(f"Testing visualization on: {path}")
    logger.info(f"Output directory: {output_path}")
    logger.info("-" * 50)
    
    # Step 1: Get video info
    logger.info("Step 1: Getting video info...")
    frame_extractor = FrameExtractor()
    video_info = frame_extractor.get_video_info_from_file(path)
    logger.info(f"  Resolution: {video_info['width']}x{video_info['height']}")
    logger.info(f"  FPS: {video_info['fps']}")
    logger.info(f"  Frame count: {video_info['frame_count']}")
    
    # Step 2: Extract just a few frames for testing
    logger.info("\nStep 2: Extracting 5 test frames...")
    sample_rate = video_info["frame_count"] // 5  # Get 5 evenly spaced frames
    frames = frame_extractor.extract_from_file(path, sample_rate=sample_rate, max_frames=5)
    logger.info(f"  Extracted {len(frames)} frames")
    
    # Step 3: Run pose detection
    logger.info("\nStep 3: Running pose detection...")
    with PoseDetector() as pose_detector:
        poses = pose_detector.detect_poses_batch(frames)
    
    detected = sum(1 for p in poses if p is not None)
    logger.info(f"  Detected poses in {detected}/{len(frames)} frames")
    
    # Step 4: Draw skeleton overlays
    logger.info("\nStep 4: Drawing skeleton overlays...")
    visualizer = SwingVisualizer(
        frame_width=video_info['width'],
        frame_height=video_info['height']
    )
    
    skeleton_frames = visualizer.draw_skeleton_batch(frames, poses)
    
    # Step 5: Save skeleton-only frames
    logger.info("\nStep 5: Saving skeleton-only frames...")
    skeleton_paths = visualizer.save_frames(skeleton_frames, str(output_path), prefix="skeleton")
    
    # Step 6: Draw full analysis (skeleton + reference lines)
    logger.info("\nStep 6: Drawing full analysis (skeleton + reference lines)...")
    full_analysis_frames = visualizer.draw_full_analysis_batch(
        frames, poses,
        draw_skeleton=True,
        draw_reference_lines=True
    )
    
    # Step 7: Save full analysis frames
    logger.info("\nStep 7: Saving full analysis frames...")
    saved_paths = visualizer.save_frames(full_analysis_frames, str(output_path), prefix="analysis")
    
    for path in saved_paths:
        logger.info(f"  Saved: {path}")
    
    logger.info("\n" + "=" * 50)
    logger.info("VISUALIZATION TEST COMPLETE")
    logger.info(f"Check output in: {output_path}")
    logger.info("=" * 50)
    
    return saved_paths


def main():
    # Default test video
    default_video = Path(__file__).parent / "swingVideos" / "IMG_0737.mov"
    
    if len(sys.argv) > 1:
        video_path = sys.argv[1]
    elif default_video.exists():
        video_path = str(default_video)
    else:
        print("Usage: python test_visualizer.py <path_to_video>")
        print(f"\nNo video found at default location: {default_video}")
        sys.exit(1)
    
    try:
        test_visualization(video_path)
    except Exception as e:
        logger.exception(f"Visualization test failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
