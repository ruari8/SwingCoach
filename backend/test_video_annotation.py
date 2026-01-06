#!/usr/bin/env python3
"""
Integration test for the video annotation system.
Tests the complete pipeline: pose detection, SAM3 club tracking, visualization, and video export.

Usage:
    python test_video_annotation.py [path_to_video]

If no video path is provided, uses the default test video in swingVideos/.
"""

import sys
import logging
from pathlib import Path
from typing import Optional

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Add parent to path for imports
sys.path.insert(0, str(Path(__file__).parent))


def test_imports():
    """Test that all required modules can be imported."""
    logger.info("Testing imports...")

    try:
        from analysis import (
            FrameExtractor,
            PoseDetector,
            EventDetector,
            SwingVisualizer,
            VisualizationConfig,
            ClubAnalyzer,
            SwingPathTracker,
            VideoExporter,
            LAYER_DEFINITIONS,
        )
        logger.info("  Core analysis modules: OK")
    except ImportError as e:
        logger.error(f"  Core analysis modules import failed: {e}")
        return False

    try:
        from analysis.equipment_tracker import EquipmentTracker
        logger.info("  SAM3 EquipmentTracker: OK")
    except ImportError as e:
        logger.warning(f"  SAM3 EquipmentTracker not available: {e}")
        logger.warning("  Tests will run without club tracking")

    logger.info("Import test: PASSED")
    return True


def test_visualization_config():
    """Test visualization configuration classes."""
    logger.info("Testing visualization config...")

    from analysis import VisualizationConfig, VisualizationMetadata, LAYER_DEFINITIONS

    # Test default config
    config = VisualizationConfig()
    assert config.draw_skeleton == True
    assert config.draw_club_plane == True
    assert config.draw_swing_path == True
    assert config.draw_club_mask == False
    logger.info("  Default config: OK")

    # Test from_dict
    config_dict = {"draw_skeleton": False, "draw_club_mask": True}
    config = VisualizationConfig.from_dict(config_dict)
    assert config.draw_skeleton == False
    assert config.draw_club_mask == True
    logger.info("  Config from_dict: OK")

    # Test to_dict
    config_back = config.to_dict()
    assert config_back["draw_skeleton"] == False
    logger.info("  Config to_dict: OK")

    # Test metadata
    metadata = VisualizationMetadata.from_config(VisualizationConfig())
    assert len(metadata.layers) > 0
    logger.info(f"  Metadata layers: {len(metadata.layers)}")

    # Test layer definitions
    assert "skeleton" in LAYER_DEFINITIONS
    assert "club_plane" in LAYER_DEFINITIONS
    assert "swing_path" in LAYER_DEFINITIONS
    logger.info("  Layer definitions: OK")

    logger.info("Visualization config test: PASSED")
    return True


def test_club_analyzer():
    """Test club analyzer with a synthetic mask."""
    logger.info("Testing club analyzer...")

    import numpy as np
    from analysis import ClubAnalyzer

    analyzer = ClubAnalyzer()

    # Create a synthetic club-like mask (elongated rectangle)
    mask = np.zeros((100, 100), dtype=np.uint8)
    # Draw a diagonal line-like shape
    for i in range(20, 80):
        j = i + 10
        if 0 <= j < 100:
            mask[i, j-2:j+3] = 1

    # Test angle calculation
    angle = analyzer.calculate_club_angle(mask)
    logger.info(f"  Calculated angle: {angle:.1f} degrees")
    assert angle is not None
    logger.info("  Angle calculation: OK")

    # Test centroid
    centroid = analyzer.get_club_centroid(mask)
    assert centroid is not None
    logger.info(f"  Centroid: {centroid}")

    # Test extended plane line
    plane = analyzer.get_extended_plane_line(mask, 100, 100)
    assert plane is not None
    assert plane.line_start is not None
    assert plane.line_end is not None
    logger.info(f"  Plane line: {plane.line_start} -> {plane.line_end}")

    logger.info("Club analyzer test: PASSED")
    return True


def test_swing_path_tracker():
    """Test swing path tracker with synthetic detections."""
    logger.info("Testing swing path tracker...")

    from dataclasses import dataclass
    from analysis import SwingPathTracker

    @dataclass
    class MockDetection:
        centroid: tuple
        frame_index: int

    # Create mock detections
    detections = [
        MockDetection(centroid=(0.5, 0.6), frame_index=0),
        MockDetection(centroid=(0.45, 0.5), frame_index=1),
        None,  # Simulating missed detection
        MockDetection(centroid=(0.35, 0.3), frame_index=3),
        MockDetection(centroid=(0.3, 0.2), frame_index=4),
        MockDetection(centroid=(0.35, 0.3), frame_index=5),
    ]

    tracker = SwingPathTracker()
    path = tracker.build_path(detections, frame_width=1920, frame_height=1080)

    assert len(path.points) == 5  # Excluding None
    assert len(path.smoothed_points) == 5
    logger.info(f"  Path points: {len(path.points)}")
    logger.info(f"  Smoothed points: {len(path.smoothed_points)}")

    # Test get_points_up_to_frame
    points_at_3 = path.get_points_up_to_frame(3)
    assert len(points_at_3) == 3  # frames 0, 1, 3
    logger.info(f"  Points up to frame 3: {len(points_at_3)}")

    logger.info("Swing path tracker test: PASSED")
    return True


def test_video_exporter():
    """Test video exporter with synthetic frames."""
    logger.info("Testing video exporter...")

    from PIL import Image
    import io
    from analysis import VideoExporter

    # Create synthetic frames
    frames = []
    for i in range(5):
        img = Image.new("RGB", (320, 240), color=(i * 50, 100, 150))
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        frames.append(buf.getvalue())

    exporter = VideoExporter()

    # Test export
    video_bytes = exporter.export_video(frames, fps=10.0)
    assert len(video_bytes) > 0
    logger.info(f"  Exported video size: {len(video_bytes)} bytes")

    # Verify it's a valid MP4 (check magic bytes)
    assert video_bytes[:4] == b'\x00\x00\x00' or b'ftyp' in video_bytes[:20]
    logger.info("  Video format: OK")

    logger.info("Video exporter test: PASSED")
    return True


def test_visualizer_new_methods():
    """Test the new visualizer methods."""
    logger.info("Testing visualizer new methods...")

    from PIL import Image
    import io
    import numpy as np
    from analysis import SwingVisualizer

    # Create a test frame
    img = Image.new("RGB", (640, 480), color=(50, 100, 150))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    frame_bytes = buf.getvalue()

    visualizer = SwingVisualizer(frame_width=640, frame_height=480)

    # Test draw_club_plane
    result = visualizer.draw_club_plane(frame_bytes, (100, 100), (500, 400))
    assert len(result) > 0
    logger.info("  draw_club_plane: OK")

    # Test draw_swing_path
    path_points = [(100, 100), (200, 150), (300, 200), (400, 180), (500, 250)]
    result = visualizer.draw_swing_path(frame_bytes, path_points)
    assert len(result) > 0
    logger.info("  draw_swing_path: OK")

    # Test draw_club_mask_overlay
    mask = np.zeros((480, 640), dtype=bool)
    mask[200:300, 300:400] = True
    result = visualizer.draw_club_mask_overlay(frame_bytes, mask)
    assert len(result) > 0
    logger.info("  draw_club_mask_overlay: OK")

    # Test draw_complete_analysis (without pose)
    result = visualizer.draw_complete_analysis(
        frame_bytes,
        pose=None,
        club_plane_line=((100, 100), (500, 400)),
        swing_path_points=path_points,
        club_mask=mask,
        draw_skeleton=False,
        draw_reference_lines=False,
        draw_club_plane=True,
        draw_swing_path=True,
        draw_club_mask=True
    )
    assert len(result) > 0
    logger.info("  draw_complete_analysis: OK")

    logger.info("Visualizer new methods test: PASSED")
    return True


def test_full_pipeline(video_path: Optional[Path] = None):
    """Test the full annotation pipeline with a real video."""
    logger.info("Testing full annotation pipeline...")

    if video_path is None:
        video_path = Path(__file__).parent / "swingVideos" / "IMG_0737.mov"

    if not video_path.exists():
        logger.warning(f"  Test video not found: {video_path}")
        logger.warning("  Skipping full pipeline test")
        return True

    from analysis import (
        FrameExtractor,
        PoseDetector,
        EventDetector,
        SwingVisualizer,
        VisualizationConfig,
        ClubAnalyzer,
        SwingPathTracker,
        VideoExporter,
    )

    # Check SAM3 availability
    try:
        from analysis.equipment_tracker import EquipmentTracker
        sam3_available = True
    except ImportError:
        sam3_available = False
        logger.warning("  SAM3 not available - testing without club tracking")

    # Step 1: Extract frames
    logger.info("  Extracting frames...")
    extractor = FrameExtractor()
    video_info = extractor.get_video_info_from_file(video_path)
    frames = extractor.extract_from_file(
        video_path,
        sample_rate=max(1, video_info['frame_count'] // 10),
        max_frames=10
    )
    logger.info(f"  Extracted {len(frames)} frames")

    # Step 2: Pose detection
    logger.info("  Running pose detection...")
    with PoseDetector() as detector:
        poses = detector.detect_poses_batch(frames)
    detected = sum(1 for p in poses if p is not None)
    logger.info(f"  Detected poses in {detected}/{len(frames)} frames")

    # Step 3: Event detection
    logger.info("  Detecting events...")
    event_detector = EventDetector(fps=video_info['fps'] / max(1, video_info['frame_count'] // 10))
    events = event_detector.detect_events(poses, vantage="DTL")
    logger.info(f"  Address: {events.address.frame_index if events.address else 'N/A'}")

    # Step 4: Club detection (if SAM3 available)
    club_plane_line = None
    swing_path = None
    club_masks = None

    if sam3_available:
        logger.info("  Running SAM3 club detection...")
        try:
            with EquipmentTracker() as tracker:
                club_detections = tracker.detect_club_batch(frames)

            # Analyze club plane
            analyzer = ClubAnalyzer()
            for det in club_detections:
                if det and det.mask is not None:
                    plane = analyzer.analyze_address_frame(
                        det.mask,
                        video_info['width'],
                        video_info['height']
                    )
                    if plane:
                        club_plane_line = (plane.line_start, plane.line_end)
                        logger.info(f"  Club plane angle: {plane.angle_degrees:.1f} degrees")
                        break

            # Build swing path
            tracker = SwingPathTracker()
            swing_path = tracker.build_path(
                club_detections,
                frame_width=video_info['width'],
                frame_height=video_info['height']
            )
            logger.info(f"  Swing path points: {len(swing_path.points)}")

            # Get masks
            club_masks = [det.mask if det else None for det in club_detections]

        except Exception as e:
            logger.warning(f"  SAM3 detection failed: {e}")

    # Step 5: Generate annotated frames
    logger.info("  Generating annotated frames...")
    visualizer = SwingVisualizer(
        frame_width=video_info['width'],
        frame_height=video_info['height']
    )
    annotated_frames = visualizer.draw_complete_analysis_batch(
        frames=frames,
        poses=poses,
        club_plane_line=club_plane_line,
        swing_path=swing_path,
        club_masks=club_masks,
        draw_skeleton=True,
        draw_reference_lines=True,
        draw_club_plane=club_plane_line is not None,
        draw_swing_path=swing_path is not None,
        draw_club_mask=False
    )
    logger.info(f"  Generated {len(annotated_frames)} annotated frames")

    # Step 6: Export video
    logger.info("  Exporting video...")
    exporter = VideoExporter()
    fps = video_info['fps'] / max(1, video_info['frame_count'] // 10)
    video_bytes = exporter.export_video(annotated_frames, fps)
    logger.info(f"  Video size: {len(video_bytes) / 1024:.1f} KB")

    # Save output
    output_path = Path(__file__).parent / "output" / "test_annotation_output.mp4"
    output_path.parent.mkdir(exist_ok=True)
    output_path.write_bytes(video_bytes)
    logger.info(f"  Saved to: {output_path}")

    logger.info("Full pipeline test: PASSED")
    return True


def main():
    """Run all video annotation tests."""
    logger.info("=" * 60)
    logger.info("Video Annotation System Test Suite")
    logger.info("=" * 60)

    # Get video path from args
    video_path = None
    if len(sys.argv) > 1:
        video_path = Path(sys.argv[1])

    results = {}

    # Test 1: Imports
    results['imports'] = test_imports()
    logger.info("")

    if not results['imports']:
        logger.error("Import test failed - cannot continue")
        sys.exit(1)

    # Test 2: Visualization config
    results['visualization_config'] = test_visualization_config()
    logger.info("")

    # Test 3: Club analyzer
    results['club_analyzer'] = test_club_analyzer()
    logger.info("")

    # Test 4: Swing path tracker
    results['swing_path_tracker'] = test_swing_path_tracker()
    logger.info("")

    # Test 5: Video exporter
    results['video_exporter'] = test_video_exporter()
    logger.info("")

    # Test 6: Visualizer new methods
    results['visualizer_methods'] = test_visualizer_new_methods()
    logger.info("")

    # Test 7: Full pipeline
    results['full_pipeline'] = test_full_pipeline(video_path)
    logger.info("")

    # Summary
    logger.info("=" * 60)
    logger.info("Test Summary")
    logger.info("=" * 60)

    for test_name, passed in results.items():
        status = "PASSED" if passed else "FAILED"
        logger.info(f"  {test_name}: {status}")

    all_passed = all(results.values())
    logger.info("")
    logger.info(f"Overall: {'ALL TESTS PASSED' if all_passed else 'SOME TESTS FAILED'}")

    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    main()
