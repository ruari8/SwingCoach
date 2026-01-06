#!/usr/bin/env python3
"""
Test script for SAM3 equipment tracking.
Tests golf club detection on video frames using point/box prompts.

Usage:
    python test_sam3.py [path_to_video]

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


def test_sam3_import():
    """Test that SAM3 can be imported."""
    logger.info("Testing SAM3 import...")

    try:
        import torch
        logger.info(f"  PyTorch version: {torch.__version__}")
        logger.info(f"  MPS available: {torch.backends.mps.is_available()}")
        logger.info(f"  CUDA available: {torch.cuda.is_available()}")
    except ImportError as e:
        logger.error(f"  PyTorch import failed: {e}")
        return False

    try:
        from sam3.model_builder import build_sam3_image_model
        logger.info("  SAM3 model builder: OK")
    except ImportError as e:
        logger.error(f"  SAM3 model builder import failed: {e}")
        return False

    try:
        from sam3.model_builder import SAM3InteractiveImagePredictor
        logger.info("  SAM3 predictor: OK")
    except ImportError as e:
        logger.error(f"  SAM3 predictor import failed: {e}")
        return False

    logger.info("SAM3 import test: PASSED")
    return True


def test_equipment_tracker_import():
    """Test that EquipmentTracker can be imported."""
    logger.info("Testing EquipmentTracker import...")

    try:
        from analysis.equipment_tracker import EquipmentTracker, ClubDetection
        logger.info("  EquipmentTracker: OK")
        logger.info("  ClubDetection: OK")
    except ImportError as e:
        logger.error(f"  Import failed: {e}")
        return False

    logger.info("EquipmentTracker import test: PASSED")
    return True


def test_model_loading():
    """Test that SAM3 model can be loaded."""
    logger.info("Testing SAM3 model loading...")
    logger.info("  (This may take 30-60 seconds on first run)")

    try:
        from analysis.equipment_tracker import EquipmentTracker

        tracker = EquipmentTracker()
        logger.info(f"  Device: {tracker.device}")
        logger.info("  Model loaded successfully")

        tracker.close()
        logger.info("Model loading test: PASSED")
        return True

    except Exception as e:
        logger.error(f"  Model loading failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_club_detection(video_path: Optional[Path] = None):
    """Test text-prompted club detection on video frames."""
    logger.info("Testing club detection...")

    # Find test video
    if video_path is None:
        video_path = Path(__file__).parent / "swingVideos" / "IMG_0737.mov"

    if not video_path.exists():
        logger.error(f"  Test video not found: {video_path}")
        return False

    logger.info(f"  Using video: {video_path}")

    try:
        from analysis.frame_extractor import FrameExtractor
        from analysis.equipment_tracker import EquipmentTracker

        # Extract a few frames
        logger.info("  Extracting frames...")
        extractor = FrameExtractor()
        video_info = extractor.get_video_info_from_file(video_path)
        logger.info(f"  Video: {video_info['width']}x{video_info['height']}, {video_info['fps']:.1f} fps")

        # Extract just 2 frames for quick test
        frames = extractor.extract_from_file(
            video_path,
            sample_rate=max(1, video_info['frame_count'] // 2),
            max_frames=2
        )
        logger.info(f"  Extracted {len(frames)} frames")

        # Run detection
        logger.info("  Loading SAM3 model...")
        with EquipmentTracker() as tracker:
            logger.info("  Running club detection with text prompt 'golf club'...")

            for i, frame in enumerate(frames):
                logger.info(f"  Processing frame {i+1}/{len(frames)}...")

                # Detect club using text prompt
                detection = tracker.detect_club(frame, frame_index=i)

                if detection:
                    logger.info(f"    Club detected!")
                    logger.info(f"    Confidence: {detection.confidence:.2f}")
                    logger.info(f"    Centroid: ({detection.centroid[0]:.3f}, {detection.centroid[1]:.3f})")
                    logger.info(f"    Bbox: {detection.bbox}")
                else:
                    logger.info(f"    No club detected in frame {i+1}")

        logger.info("Club detection test: PASSED")
        return True

    except Exception as e:
        logger.error(f"  Club detection failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_save_visualization(video_path: Optional[Path] = None):
    """Test saving a visualization of detection."""
    logger.info("Testing visualization output...")

    if video_path is None:
        video_path = Path(__file__).parent / "swingVideos" / "IMG_0737.mov"

    if not video_path.exists():
        logger.error(f"  Test video not found: {video_path}")
        return False

    try:
        from analysis.frame_extractor import FrameExtractor
        from analysis.equipment_tracker import EquipmentTracker
        from PIL import Image
        import numpy as np
        import io

        # Extract one frame
        extractor = FrameExtractor()
        video_info = extractor.get_video_info_from_file(video_path)
        frames = extractor.extract_from_file(
            video_path,
            sample_rate=video_info['frame_count'] // 2,  # Get middle frame
            max_frames=1
        )

        if not frames:
            logger.error("  No frames extracted")
            return False

        frame_bytes = frames[0]
        original_image = Image.open(io.BytesIO(frame_bytes)).convert("RGB")

        # Detect club using text prompt
        logger.info("  Running detection...")
        with EquipmentTracker() as tracker:
            detection = tracker.detect_club(frame_bytes, frame_index=0)

            if detection and detection.mask is not None:
                # Create overlay visualization
                logger.info("  Creating visualization...")

                mask = detection.mask

                # Resize mask to match image if needed
                if mask.shape != (original_image.height, original_image.width):
                    mask_img = Image.fromarray((mask * 255).astype(np.uint8))
                    mask_img = mask_img.resize((original_image.width, original_image.height))
                    mask = np.array(mask_img) > 127

                # Create colored overlay
                overlay = np.array(original_image).copy()
                overlay[mask] = [255, 0, 0]  # Red overlay

                # Blend with original
                alpha = 0.5
                result = (alpha * overlay + (1 - alpha) * np.array(original_image)).astype(np.uint8)
                result_image = Image.fromarray(result)

                # Save output
                output_path = Path(__file__).parent / "output" / "sam3_test_output.png"
                output_path.parent.mkdir(exist_ok=True)
                result_image.save(output_path)

                logger.info(f"  Saved visualization to: {output_path}")
                logger.info("Visualization test: PASSED")
                return True
            else:
                logger.warning("  No detection - skipping visualization")
                logger.info("Visualization test: SKIPPED (no detection)")
                return True

    except Exception as e:
        logger.error(f"  Visualization failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def main():
    """Run all SAM3 tests."""
    logger.info("=" * 60)
    logger.info("SAM3 Equipment Tracker Test Suite")
    logger.info("=" * 60)

    # Get video path from args
    video_path = None
    if len(sys.argv) > 1:
        video_path = Path(sys.argv[1])

    results = {}

    # Test 1: Import
    results['import'] = test_sam3_import()
    logger.info("")

    if not results['import']:
        logger.error("SAM3 import failed - cannot continue")
        sys.exit(1)

    # Test 2: Equipment tracker import
    results['tracker_import'] = test_equipment_tracker_import()
    logger.info("")

    # Test 3: Model loading
    results['model_loading'] = test_model_loading()
    logger.info("")

    if not results['model_loading']:
        logger.error("Model loading failed - cannot continue with detection tests")
        sys.exit(1)

    # Test 4: Club detection
    results['club_detection'] = test_club_detection(video_path)
    logger.info("")

    # Test 5: Visualization
    results['visualization'] = test_save_visualization(video_path)
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
