#!/usr/bin/env python3
"""
Test the fixed visualization with proper shaft plane and clubhead tracking.

Usage:
    python test_fixed_visualization.py [path_to_video]
"""

import sys
import io
import logging
from pathlib import Path
from typing import Optional, List, Tuple

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

sys.path.insert(0, str(Path(__file__).parent))


def test_fixed_visualization(video_path: Optional[Path] = None):
    """Test the fixed club plane and clubhead path visualization."""

    if video_path is None:
        video_path = Path(__file__).parent / "swingVideos" / "IMG_0737.mov"

    if not video_path.exists():
        logger.error(f"Video not found: {video_path}")
        return False

    logger.info(f"Testing fixed visualization on: {video_path}")

    from PIL import Image, ImageDraw
    import numpy as np
    from analysis import FrameExtractor, ClubAnalyzer
    from analysis.equipment_tracker import EquipmentTracker

    # Create output directory
    output_dir = Path(__file__).parent / "output" / "fixed_visualization"
    output_dir.mkdir(parents=True, exist_ok=True)

    # Extract frames
    logger.info("Extracting frames...")
    extractor = FrameExtractor()
    video_info = extractor.get_video_info_from_file(video_path)

    # Get more frames for the path visualization
    frames = extractor.extract_from_file(
        video_path,
        sample_rate=max(1, video_info['frame_count'] // 15),
        max_frames=15
    )
    logger.info(f"Extracted {len(frames)} frames")

    frame_width = video_info['width']
    frame_height = video_info['height']

    # Initialize components
    club_analyzer = ClubAnalyzer()

    logger.info("Loading SAM3 model...")
    with EquipmentTracker() as tracker:

        # ===== STEP 1: Detect shaft on first frame (address) =====
        logger.info("\n--- STEP 1: Detecting club shaft for plane line ---")
        shaft_detection = tracker.detect_shaft(frames[0], frame_index=0)

        club_plane = None
        if shaft_detection:
            logger.info(f"Shaft detected with confidence: {shaft_detection.confidence:.2f}")

            # Calculate plane line using PCA
            club_plane = club_analyzer.analyze_address_frame(
                shaft_mask=shaft_detection.mask,
                frame_width=frame_width,
                frame_height=frame_height
            )

            if club_plane:
                logger.info(f"Club plane angle: {club_plane.angle_degrees:.1f}°")
                logger.info(f"Line start (shaft top): {club_plane.line_start}")
                logger.info(f"Line end (extended): {club_plane.line_end}")
            else:
                logger.warning("Failed to calculate club plane from shaft mask")
        else:
            logger.warning("No shaft detected in address frame")

        # ===== STEP 2: Detect clubhead in all frames for path =====
        logger.info("\n--- STEP 2: Detecting clubhead for swing path ---")
        clubhead_detections = tracker.detect_clubhead_batch(frames)

        # Collect centroids for path
        path_points: List[Tuple[int, int]] = []
        for det in clubhead_detections:
            if det is not None:
                path_points.append(det.centroid_pixels)
                logger.info(f"Frame {det.frame_index}: clubhead at {det.centroid_pixels}")

        logger.info(f"Got {len(path_points)} clubhead positions for path")

        # ===== STEP 3: Create visualization =====
        logger.info("\n--- STEP 3: Creating visualization ---")

        # Load first frame
        image = Image.open(io.BytesIO(frames[0])).convert("RGBA")
        overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)

        # Draw club plane line (orange)
        if club_plane:
            draw.line(
                [club_plane.line_start, club_plane.line_end],
                fill=(255, 165, 0, 255),
                width=4
            )
            # Mark the shaft top point
            sx, sy = club_plane.line_start
            draw.ellipse([(sx-6, sy-6), (sx+6, sy+6)], fill=(255, 165, 0, 255))
            logger.info("Drew club plane line (orange)")

        # Draw clubhead path (red)
        if len(path_points) >= 2:
            # Draw path line
            for i in range(len(path_points) - 1):
                # Fade from light to bright red
                alpha = int(100 + 155 * (i / len(path_points)))
                draw.line(
                    [path_points[i], path_points[i + 1]],
                    fill=(255, 0, 0, alpha),
                    width=3
                )

            # Draw points
            for i, pt in enumerate(path_points):
                radius = 5
                draw.ellipse(
                    [(pt[0]-radius, pt[1]-radius), (pt[0]+radius, pt[1]+radius)],
                    fill=(255, 0, 0, 255),
                    outline=(255, 255, 255, 255)
                )
            logger.info(f"Drew clubhead path with {len(path_points)} points (red)")

        # Draw shaft mask outline (yellow) for verification
        if shaft_detection:
            mask = shaft_detection.mask
            if mask.shape[0] != frame_height or mask.shape[1] != frame_width:
                mask_img = Image.fromarray((mask * 255).astype(np.uint8))
                mask_img = mask_img.resize((frame_width, frame_height), Image.NEAREST)
                mask = np.array(mask_img) > 127

            import cv2
            mask_uint8 = (mask.astype(np.uint8) * 255)
            contours, _ = cv2.findContours(mask_uint8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            for contour in contours:
                points = [(int(p[0][0]), int(p[0][1])) for p in contour]
                if len(points) >= 3:
                    draw.polygon(points, outline=(255, 255, 0, 255))
            logger.info("Drew shaft mask outline (yellow)")

        # Composite and save
        result = Image.alpha_composite(image, overlay)
        result_rgb = result.convert("RGB")

        output_path = output_dir / "fixed_visualization.png"
        result_rgb.save(output_path)
        logger.info(f"\nSaved visualization to: {output_path}")

        # Also save individual frames with annotations for comparison
        logger.info("\n--- Creating frame-by-frame visualization ---")

        for i, (frame_bytes, det) in enumerate(zip(frames, clubhead_detections)):
            frame_img = Image.open(io.BytesIO(frame_bytes)).convert("RGBA")
            frame_overlay = Image.new("RGBA", frame_img.size, (0, 0, 0, 0))
            frame_draw = ImageDraw.Draw(frame_overlay)

            # Draw persistent club plane
            if club_plane:
                frame_draw.line(
                    [club_plane.line_start, club_plane.line_end],
                    fill=(255, 165, 0, 200),
                    width=4
                )

            # Draw path up to this frame
            points_so_far = path_points[:i+1] if i < len(path_points) else path_points
            if len(points_so_far) >= 2:
                for j in range(len(points_so_far) - 1):
                    alpha = int(100 + 155 * (j / max(len(points_so_far), 1)))
                    frame_draw.line(
                        [points_so_far[j], points_so_far[j + 1]],
                        fill=(255, 0, 0, alpha),
                        width=3
                    )

            # Draw current clubhead position
            if det:
                px, py = det.centroid_pixels
                frame_draw.ellipse(
                    [(px-8, py-8), (px+8, py+8)],
                    fill=(255, 0, 0, 255),
                    outline=(255, 255, 255, 255)
                )

            frame_result = Image.alpha_composite(frame_img, frame_overlay)
            frame_path = output_dir / f"frame_{i:02d}.png"
            frame_result.convert("RGB").save(frame_path)

        logger.info(f"Saved {len(frames)} annotated frames to {output_dir}")

    logger.info("\n" + "=" * 60)
    logger.info("VISUALIZATION TEST COMPLETE")
    logger.info("=" * 60)
    logger.info(f"Check outputs in: {output_dir}")
    logger.info("- fixed_visualization.png: All annotations on first frame")
    logger.info("- frame_XX.png: Per-frame progressive visualization")

    return True


def main():
    video_path = None
    if len(sys.argv) > 1:
        video_path = Path(sys.argv[1])

    success = test_fixed_visualization(video_path)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
