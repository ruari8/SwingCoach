#!/usr/bin/env python3
"""
Generate fully annotated golf swing video.

Annotations included:
- Pose skeleton (MediaPipe)
- Reference lines (shoulder plane, spine angle)
- Plane line (from address frame, fixed throughout video)

Usage:
    # Full video (all frames)
    python test_full_annotation.py

    # Sampled mode (faster dev feedback, ~10-15 frames)
    python test_full_annotation.py --sample

    # Custom sample rate (every Nth frame)
    python test_full_annotation.py --sample 10

    # Custom video path
    python test_full_annotation.py path/to/video.mov
"""

import sys
import argparse
import logging
from pathlib import Path
from typing import Optional, List, Tuple

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

sys.path.insert(0, str(Path(__file__).parent))


def annotate_video(
    video_path: Path,
    output_path: Path,
    sample_rate: int = 1,
) -> bool:
    """
    Generate fully annotated video.

    Args:
        video_path: Path to input video
        output_path: Path for output MP4
        sample_rate: 1 = all frames, N = every Nth frame

    Returns:
        True if successful
    """
    from analysis import (
        FrameExtractor,
        PoseDetector,
        ClubAnalyzer,
        SwingVisualizer,
        VideoExporter,
    )
    from analysis.equipment_tracker import EquipmentTracker

    # Step 1: Get video info
    logger.info(f"Input video: {video_path}")
    extractor = FrameExtractor()
    video_info = extractor.get_video_info_from_file(video_path)
    
    total_frames = video_info['frame_count']
    fps = video_info['fps']
    width = video_info['width']
    height = video_info['height']
    
    logger.info(f"Video info: {width}x{height}, {fps:.1f} fps, {total_frames} frames")
    
    # Step 2: Extract frames
    if sample_rate == 1:
        logger.info("Extracting ALL frames...")
        max_frames = None
    else:
        logger.info(f"Extracting frames (sample rate: every {sample_rate} frames)...")
        max_frames = None  # Let sample_rate handle it
    
    frames = extractor.extract_from_file(
        video_path,
        sample_rate=sample_rate,
        max_frames=max_frames
    )
    logger.info(f"Extracted {len(frames)} frames")
    
    if len(frames) == 0:
        logger.error("No frames extracted!")
        return False

    # Step 3: Detect shaft in frame 0 → calculate plane line
    logger.info("Detecting club shaft in address frame (frame 0)...")
    plane_line: Optional[Tuple[Tuple[int, int], Tuple[int, int]]] = None
    
    with EquipmentTracker() as tracker:
        shaft_detection = tracker.detect_shaft(frames[0], frame_index=0)
    
    if shaft_detection is not None:
        analyzer = ClubAnalyzer()
        plane = analyzer.get_extended_plane_line(
            shaft_detection.mask, width, height
        )
        if plane is not None:
            plane_line = (plane.line_start, plane.line_end)
            logger.info(f"Plane line: {plane.line_start} -> {plane.line_end} ({plane.angle_degrees:.1f} degrees)")
        else:
            logger.warning("Could not calculate plane line from shaft mask")
    else:
        logger.warning("No shaft detected in frame 0 - plane line will not be drawn")

    # Step 4: Run pose detection on all frames
    logger.info("Running pose detection...")
    with PoseDetector() as detector:
        poses = []
        for i, frame in enumerate(frames):
            pose = detector.detect_pose(frame)
            poses.append(pose)
            
            # Progress every 30 frames
            if (i + 1) % 30 == 0 or (i + 1) == len(frames):
                detected = sum(1 for p in poses if p is not None)
                logger.info(f"Pose detection: {i + 1}/{len(frames)} frames ({detected} poses detected)")
    
    detected_count = sum(1 for p in poses if p is not None)
    logger.info(f"Pose detection complete: {detected_count}/{len(frames)} frames with poses")

    # Step 5: Draw overlays on each frame
    logger.info("Drawing annotations...")
    visualizer = SwingVisualizer(frame_width=width, frame_height=height)
    annotated_frames: List[bytes] = []
    
    for i, (frame, pose) in enumerate(zip(frames, poses)):
        # Draw all layers
        result = frame
        
        # Layer 1: Skeleton
        if pose is not None:
            result = visualizer.draw_skeleton(result, pose)
        
        # Layer 2: Reference lines (shoulder plane, spine)
        if pose is not None:
            result = visualizer.draw_reference_lines(result, pose)
        
        # Layer 3: Plane line (fixed from frame 0)
        if plane_line is not None:
            result = visualizer.draw_club_plane(result, plane_line[0], plane_line[1])
        
        annotated_frames.append(result)
        
        # Progress every 30 frames
        if (i + 1) % 30 == 0 or (i + 1) == len(frames):
            logger.info(f"Annotation: {i + 1}/{len(frames)} frames")

    # Step 6: Export to MP4
    logger.info("Exporting video...")
    exporter = VideoExporter()
    
    # Adjust FPS for sampled video
    output_fps = fps if sample_rate == 1 else fps / sample_rate
    
    video_bytes = exporter.export_video(annotated_frames, fps=output_fps)
    
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(video_bytes)
    
    size_mb = len(video_bytes) / (1024 * 1024)
    logger.info(f"Saved: {output_path} ({size_mb:.1f} MB)")
    
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Generate fully annotated golf swing video",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument(
        'video',
        nargs='?',
        default=None,
        help='Path to video file (default: swingVideos/IMG_0737.mov)'
    )
    parser.add_argument(
        '--sample',
        nargs='?',
        const=0,
        type=int,
        metavar='N',
        help='Sample frames for faster processing. No value = auto (~10-15 frames), or specify rate N'
    )
    
    args = parser.parse_args()
    
    # Determine video path
    if args.video:
        video_path = Path(args.video)
    else:
        video_path = Path(__file__).parent / "swingVideos" / "IMG_0737.mov"
    
    if not video_path.exists():
        logger.error(f"Video not found: {video_path}")
        sys.exit(1)
    
    # Get frame count to determine sample rate
    from analysis import FrameExtractor
    extractor = FrameExtractor()
    video_info = extractor.get_video_info_from_file(video_path)
    total_frames = video_info['frame_count']
    
    # Determine sample rate and output path
    output_dir = Path(__file__).parent / "output"
    
    if args.sample is None:
        # Full mode - all frames
        sample_rate = 1
        output_path = output_dir / "full_annotation.mp4"
        logger.info("Mode: FULL (all frames)")
    elif args.sample == 0:
        # Auto sample - target ~10-15 frames
        sample_rate = max(1, total_frames // 12)
        output_path = output_dir / "full_annotation_sampled.mp4"
        logger.info(f"Mode: SAMPLED (auto, every {sample_rate} frames, ~{total_frames // sample_rate} frames)")
    else:
        # Custom sample rate
        sample_rate = args.sample
        output_path = output_dir / "full_annotation_sampled.mp4"
        logger.info(f"Mode: SAMPLED (every {sample_rate} frames, ~{total_frames // sample_rate} frames)")
    
    # Run annotation
    success = annotate_video(video_path, output_path, sample_rate)
    
    if success:
        logger.info("Done!")
        sys.exit(0)
    else:
        logger.error("Annotation failed")
        sys.exit(1)


if __name__ == "__main__":
    main()
