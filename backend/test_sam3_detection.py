#!/usr/bin/env python3
"""
Diagnostic script to visualize SAM3 detections on golf swing frames.
Tests different text prompts and draws mask outlines to verify detection accuracy.

Usage:
    python test_sam3_detection.py [path_to_video]
"""

import sys
import io
import logging
from pathlib import Path
from typing import List, Tuple, Optional, Any

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

sys.path.insert(0, str(Path(__file__).parent))

# Colors for different prompts (BGR for OpenCV, but we'll use RGB for PIL)
PROMPT_COLORS = {
    "golf club": (255, 165, 0),      # Orange
    "clubhead": (255, 0, 0),          # Red
    "golf club head": (255, 0, 255),  # Magenta
    "driver": (0, 255, 0),            # Green
    "golf driver": (0, 255, 255),     # Cyan
    "club shaft": (255, 255, 0),      # Yellow
    "golf ball": (255, 255, 255),     # White
}


def draw_mask_outline(
    image_bytes: bytes,
    mask: Any,
    color: Tuple[int, int, int],
    label: str,
    confidence: float
) -> bytes:
    """Draw mask outline on image with label."""
    from PIL import Image, ImageDraw, ImageFont
    import numpy as np
    import cv2

    # Load image
    image = Image.open(io.BytesIO(image_bytes)).convert("RGBA")
    width, height = image.size

    # Ensure mask is numpy array
    if hasattr(mask, 'cpu'):
        mask = mask.cpu().numpy()
    if len(mask.shape) > 2:
        mask = mask.squeeze()

    # Resize mask if needed
    if mask.shape[0] != height or mask.shape[1] != width:
        mask_img = Image.fromarray((mask * 255).astype(np.uint8))
        mask_img = mask_img.resize((width, height), Image.NEAREST)
        mask = np.array(mask_img) > 127

    # Convert to uint8 for cv2
    mask_uint8 = (mask.astype(np.uint8) * 255)

    # Find contours
    contours, _ = cv2.findContours(mask_uint8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    # Create overlay
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    # Draw contours
    for contour in contours:
        if len(contour) < 3:
            continue
        # Convert contour to list of tuples
        points = [(int(p[0][0]), int(p[0][1])) for p in contour]
        if len(points) >= 3:
            # Draw polygon outline
            draw.polygon(points, outline=(*color, 255), fill=(*color, 50))

    # Draw label with confidence
    if contours:
        # Find centroid of largest contour for label placement
        largest = max(contours, key=cv2.contourArea)
        M = cv2.moments(largest)
        if M["m00"] > 0:
            cx = int(M["m10"] / M["m00"])
            cy = int(M["m01"] / M["m00"])
        else:
            cx, cy = width // 2, height // 2

        label_text = f"{label} ({confidence:.2f})"
        # Draw text background
        text_bbox = draw.textbbox((cx, cy), label_text)
        padding = 5
        draw.rectangle(
            [text_bbox[0] - padding, text_bbox[1] - padding,
             text_bbox[2] + padding, text_bbox[3] + padding],
            fill=(0, 0, 0, 200)
        )
        draw.text((cx, cy), label_text, fill=(*color, 255))

    # Composite
    result = Image.alpha_composite(image, overlay)
    result_rgb = result.convert("RGB")

    output = io.BytesIO()
    result_rgb.save(output, format="PNG")
    return output.getvalue()


def test_detection_with_prompt(
    tracker,
    frame_bytes: bytes,
    prompt: str,
    frame_index: int = 0
) -> Tuple[Optional[Any], float, Optional[Any]]:
    """Test detection with a specific prompt."""
    from PIL import Image

    try:
        image = Image.open(io.BytesIO(frame_bytes)).convert("RGB")

        # Set image and run text-prompted segmentation
        inference_state = tracker.processor.set_image(image)
        output = tracker.processor.set_text_prompt(
            state=inference_state,
            prompt=prompt
        )

        masks = output.get("masks", [])
        scores = output.get("scores", [])

        if len(masks) == 0:
            return None, 0.0, None

        # Get best detection
        import numpy as np
        best_idx = 0
        if len(scores) > 0:
            if hasattr(scores, 'cpu'):
                scores_np = scores.cpu().numpy()
            else:
                scores_np = np.array(scores)
            best_idx = int(np.argmax(scores_np))

        mask = masks[best_idx]
        confidence = float(scores_np[best_idx]) if len(scores_np) > best_idx else 0.5

        if hasattr(mask, 'cpu'):
            mask = mask.cpu().numpy()
        if len(mask.shape) > 2:
            mask = mask.squeeze()

        return mask, confidence, output

    except Exception as e:
        logger.error(f"Detection failed for prompt '{prompt}': {e}")
        return None, 0.0, None


def run_diagnostic(video_path: Optional[Path] = None):
    """Run diagnostic on a video to visualize SAM3 detections."""

    if video_path is None:
        video_path = Path(__file__).parent / "swingVideos" / "IMG_0737.mov"

    if not video_path.exists():
        logger.error(f"Video not found: {video_path}")
        return False

    logger.info(f"Running SAM3 detection diagnostic on: {video_path}")

    # Import modules
    from analysis import FrameExtractor
    from analysis.equipment_tracker import EquipmentTracker
    from PIL import Image
    import numpy as np

    # Extract frames
    logger.info("Extracting frames...")
    extractor = FrameExtractor()
    video_info = extractor.get_video_info_from_file(video_path)

    # Get just the first frame (address position) for diagnostic
    frames = extractor.extract_from_file(
        video_path,
        sample_rate=1,
        max_frames=1
    )

    if not frames:
        logger.error("No frames extracted")
        return False

    frame_bytes = frames[0]
    logger.info(f"Frame size: {video_info['width']}x{video_info['height']}")

    # Create output directory
    output_dir = Path(__file__).parent / "output" / "sam3_diagnostic"
    output_dir.mkdir(parents=True, exist_ok=True)

    # Save original frame
    original_path = output_dir / "00_original.png"
    with open(original_path, 'wb') as f:
        f.write(frame_bytes)
    logger.info(f"Saved original frame: {original_path}")

    # Test different prompts
    prompts_to_test = [
        "golf club",
        "clubhead",
        "golf club head",
        "driver",
        "golf driver",
        "club shaft",
        "golf ball",
    ]

    logger.info("Loading SAM3 model...")
    with EquipmentTracker() as tracker:
        results = {}

        for i, prompt in enumerate(prompts_to_test):
            logger.info(f"Testing prompt: '{prompt}'...")

            mask, confidence, output = test_detection_with_prompt(
                tracker, frame_bytes, prompt
            )

            results[prompt] = {
                "detected": mask is not None,
                "confidence": confidence,
                "mask": mask
            }

            if mask is not None:
                logger.info(f"  Detected with confidence: {confidence:.2f}")

                # Draw outline
                color = PROMPT_COLORS.get(prompt, (255, 255, 255))
                annotated = draw_mask_outline(
                    frame_bytes, mask, color, prompt, confidence
                )

                # Save
                output_path = output_dir / f"{i+1:02d}_{prompt.replace(' ', '_')}.png"
                with open(output_path, 'wb') as f:
                    f.write(annotated)
                logger.info(f"  Saved: {output_path}")

                # Also calculate and show the mask area
                mask_area = np.sum(mask > 0)
                total_area = mask.shape[0] * mask.shape[1]
                area_pct = 100 * mask_area / total_area
                logger.info(f"  Mask area: {mask_area} pixels ({area_pct:.1f}% of frame)")
            else:
                logger.info(f"  NOT detected")

    # Create summary image with all detections overlaid
    logger.info("Creating summary image with all detections...")

    summary_image = Image.open(io.BytesIO(frame_bytes)).convert("RGBA")

    for prompt, result in results.items():
        if result["detected"] and result["mask"] is not None:
            # Create overlay for this prompt
            mask = result["mask"]
            color = PROMPT_COLORS.get(prompt, (255, 255, 255))

            # Resize mask if needed
            if mask.shape[0] != summary_image.height or mask.shape[1] != summary_image.width:
                mask_img = Image.fromarray((mask * 255).astype(np.uint8))
                mask_img = mask_img.resize((summary_image.width, summary_image.height), Image.NEAREST)
                mask = np.array(mask_img) > 127

            # Create colored overlay
            overlay = Image.new("RGBA", summary_image.size, (0, 0, 0, 0))
            overlay_data = np.array(overlay)
            overlay_data[mask, 0] = color[0]
            overlay_data[mask, 1] = color[1]
            overlay_data[mask, 2] = color[2]
            overlay_data[mask, 3] = 80  # Semi-transparent
            overlay = Image.fromarray(overlay_data, "RGBA")

            summary_image = Image.alpha_composite(summary_image, overlay)

    # Save summary
    summary_rgb = summary_image.convert("RGB")
    summary_path = output_dir / "99_summary_all_prompts.png"
    summary_rgb.save(summary_path)
    logger.info(f"Saved summary: {summary_path}")

    # Print results table
    logger.info("\n" + "=" * 60)
    logger.info("DETECTION RESULTS SUMMARY")
    logger.info("=" * 60)
    logger.info(f"{'Prompt':<20} {'Detected':<10} {'Confidence':<12}")
    logger.info("-" * 60)
    for prompt, result in results.items():
        detected = "YES" if result["detected"] else "NO"
        conf = f"{result['confidence']:.2f}" if result["detected"] else "-"
        logger.info(f"{prompt:<20} {detected:<10} {conf:<12}")
    logger.info("=" * 60)

    logger.info(f"\nAll outputs saved to: {output_dir}")
    logger.info("Open these images to see what SAM3 is detecting for each prompt.")

    return True


def main():
    video_path = None
    if len(sys.argv) > 1:
        video_path = Path(sys.argv[1])

    success = run_diagnostic(video_path)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
