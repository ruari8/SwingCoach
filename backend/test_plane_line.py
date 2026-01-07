#!/usr/bin/env python3
"""Quick test to generate plane_line.png for verification."""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))

from PIL import Image, ImageDraw
import io
import numpy as np

from analysis.frame_extractor import FrameExtractor
from analysis.equipment_tracker import EquipmentTracker
from analysis.club_analyzer import ClubAnalyzer
from analysis.visualizer import SwingVisualizer

VIDEO_PATH = Path(__file__).parent / "swingVideos" / "IMG_0737.mov"
OUTPUT_PATH = Path(__file__).parent / "output" / "plane_line.png"

def main():
    # Extract first frame
    print("Extracting frame...")
    extractor = FrameExtractor()
    video_info = extractor.get_video_info_from_file(VIDEO_PATH)
    frames = extractor.extract_from_file(VIDEO_PATH, sample_rate=1, max_frames=1)
    frame = frames[0]
    
    width, height = video_info['width'], video_info['height']
    print(f"Frame size: {width}x{height}")
    
    # Detect club shaft (NOT "golf club" - we need just the shaft for plane line)
    print("Detecting club SHAFT with SAM3...")
    with EquipmentTracker() as tracker:
        detection = tracker.detect_shaft(frames[0], frame_index=0)
    if detection is None:
        print("No club detected!")
        return
    
    print(f"Club detected with confidence: {detection.confidence:.2f}")
    
    # Get mask and endpoints for debugging
    analyzer = ClubAnalyzer()
    
    # Get shaft endpoints
    endpoints = analyzer.get_shaft_endpoints(detection.mask)
    if endpoints is None:
        print("Could not get shaft endpoints!")
        return
    
    bottom_end, top_end = endpoints
    print(f"Bottom end (clubhead): {bottom_end}")
    print(f"Top end (hands): {top_end}")
    
    # Get PCA result for centroid
    pca_result = analyzer.calculate_shaft_angle_pca(detection.mask)
    if pca_result:
        angle_deg, direction, centroid = pca_result
        print(f"PCA centroid: {centroid}")
        print(f"PCA direction: {direction}")
    
    # Calculate plane line
    print("Calculating plane line...")
    plane = analyzer.get_extended_plane_line(detection.mask, width, height)
    
    if plane is None:
        print("Could not calculate plane line!")
        return
    
    print(f"Plane angle: {plane.angle_degrees:.1f} degrees")
    print(f"Line start (clubhead): {plane.line_start}")
    print(f"Line end (extended past hands): {plane.line_end}")
    
    # Draw everything for debugging
    print("Drawing debug visualization...")
    img = Image.open(io.BytesIO(frame)).convert("RGBA")
    
    # 1. Draw mask overlay (green, semi-transparent)
    mask = detection.mask
    if hasattr(mask, 'cpu'):
        mask = mask.cpu().numpy()
    if len(mask.shape) > 2:
        mask = mask.squeeze()
    
    # Resize mask if needed
    mask_h, mask_w = mask.shape
    if mask_w != width or mask_h != height:
        mask_img = Image.fromarray((mask * 255).astype(np.uint8))
        mask_img = mask_img.resize((width, height), Image.Resampling.NEAREST)
        mask = np.array(mask_img) > 127
    
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    overlay_data = np.array(overlay)
    overlay_data[mask, 0] = 0    # R
    overlay_data[mask, 1] = 255  # G
    overlay_data[mask, 2] = 0    # B
    overlay_data[mask, 3] = 100  # Alpha
    overlay = Image.fromarray(overlay_data, "RGBA")
    img = Image.alpha_composite(img, overlay)
    
    # 2. Draw on top
    draw = ImageDraw.Draw(img)
    
    # 3. Draw orange plane line
    draw.line([plane.line_start, plane.line_end], fill=(255, 165, 0, 255), width=4)
    
    # 4. Draw 3 points on shaft: bottom (red), middle (yellow), top (blue)
    point_radius = 10
    
    # Bottom end (clubhead) - RED
    draw.ellipse([
        bottom_end[0] - point_radius, bottom_end[1] - point_radius,
        bottom_end[0] + point_radius, bottom_end[1] + point_radius
    ], fill=(255, 0, 0, 255), outline=(255, 255, 255, 255))
    
    # Middle (centroid) - YELLOW
    if pca_result is not None:
        angle_deg, direction, centroid = pca_result
        cx, cy = int(centroid[0]), int(centroid[1])
        draw.ellipse([
            cx - point_radius, cy - point_radius,
            cx + point_radius, cy + point_radius
        ], fill=(255, 255, 0, 255), outline=(255, 255, 255, 255))
    
    # Top end (hands) - BLUE
    draw.ellipse([
        top_end[0] - point_radius, top_end[1] - point_radius,
        top_end[0] + point_radius, top_end[1] + point_radius
    ], fill=(0, 0, 255, 255), outline=(255, 255, 255, 255))
    
    # Save
    OUTPUT_PATH.parent.mkdir(exist_ok=True)
    img.convert("RGB").save(OUTPUT_PATH)
    print(f"Saved: {OUTPUT_PATH}")

if __name__ == "__main__":
    main()
