"""
Swing visualization module.
Draws skeleton overlays, reference lines, and annotations on video frames.
"""

import io
import math
from typing import Any, Dict, List, Optional, Tuple
from dataclasses import dataclass
import logging

logger = logging.getLogger(__name__)

# Optional imports for visualization
PIL_AVAILABLE = False
Image: Any = None
ImageDraw: Any = None
ImageFont: Any = None
np: Any = None

try:
    from PIL import Image, ImageDraw, ImageFont  # type: ignore
    import numpy as np  # type: ignore
    PIL_AVAILABLE = True
except ImportError:
    logger.warning("PIL not installed. Visualization will be unavailable.")

from .pose_detector import PoseResult, Keypoint


# MediaPipe pose connections for skeleton drawing
# Each tuple is (start_landmark, end_landmark)
POSE_CONNECTIONS = [
    # Face
    ("nose", "left_eye_inner"),
    ("left_eye_inner", "left_eye"),
    ("left_eye", "left_eye_outer"),
    ("left_eye_outer", "left_ear"),
    ("nose", "right_eye_inner"),
    ("right_eye_inner", "right_eye"),
    ("right_eye", "right_eye_outer"),
    ("right_eye_outer", "right_ear"),
    ("mouth_left", "mouth_right"),
    
    # Torso
    ("left_shoulder", "right_shoulder"),
    ("left_shoulder", "left_hip"),
    ("right_shoulder", "right_hip"),
    ("left_hip", "right_hip"),
    
    # Left arm
    ("left_shoulder", "left_elbow"),
    ("left_elbow", "left_wrist"),
    ("left_wrist", "left_pinky"),
    ("left_wrist", "left_index"),
    ("left_wrist", "left_thumb"),
    ("left_pinky", "left_index"),
    
    # Right arm
    ("right_shoulder", "right_elbow"),
    ("right_elbow", "right_wrist"),
    ("right_wrist", "right_pinky"),
    ("right_wrist", "right_index"),
    ("right_wrist", "right_thumb"),
    ("right_pinky", "right_index"),
    
    # Left leg
    ("left_hip", "left_knee"),
    ("left_knee", "left_ankle"),
    ("left_ankle", "left_heel"),
    ("left_ankle", "left_foot_index"),
    ("left_heel", "left_foot_index"),
    
    # Right leg
    ("right_hip", "right_knee"),
    ("right_knee", "right_ankle"),
    ("right_ankle", "right_heel"),
    ("right_ankle", "right_foot_index"),
    ("right_heel", "right_foot_index"),
]

# Color scheme for different body parts (RGB)
COLORS = {
    "face": (0, 255, 255),       # Cyan
    "torso": (255, 0, 128),      # Magenta/Red - core stability
    "left_arm": (0, 255, 255),   # Cyan
    "right_arm": (0, 255, 255),  # Cyan
    "left_leg": (0, 255, 255),   # Cyan
    "right_leg": (0, 255, 255),  # Cyan
    "reference": (255, 255, 0),  # Yellow - reference lines
    "text": (255, 255, 255),     # White
    "club_plane": (255, 165, 0), # Orange - club plane line
    "swing_path": (255, 0, 0),   # Red - swing path trajectory
    "club_mask": (0, 255, 0),    # Green - club mask overlay
    "speed": (0, 255, 128),      # Green-cyan - speed display
    "speed_peak": (255, 215, 0), # Gold - peak speed highlight
}

# Map connections to body parts for coloring
def get_connection_color(start: str, end: str) -> Tuple[int, int, int]:
    """Get color for a skeleton connection based on body part."""
    torso_parts = {"left_shoulder", "right_shoulder", "left_hip", "right_hip"}
    left_arm_parts = {"left_shoulder", "left_elbow", "left_wrist", "left_pinky", "left_index", "left_thumb"}
    right_arm_parts = {"right_shoulder", "right_elbow", "right_wrist", "right_pinky", "right_index", "right_thumb"}
    left_leg_parts = {"left_hip", "left_knee", "left_ankle", "left_heel", "left_foot_index"}
    right_leg_parts = {"right_hip", "right_knee", "right_ankle", "right_heel", "right_foot_index"}
    
    # Check if this is a torso connection (connecting torso parts)
    if start in torso_parts and end in torso_parts:
        return COLORS["torso"]
    
    # Arm connections
    if start in left_arm_parts and end in left_arm_parts:
        return COLORS["left_arm"]
    if start in right_arm_parts and end in right_arm_parts:
        return COLORS["right_arm"]
    
    # Leg connections
    if start in left_leg_parts and end in left_leg_parts:
        return COLORS["left_leg"]
    if start in right_leg_parts and end in right_leg_parts:
        return COLORS["right_leg"]
    
    # Default to cyan for face and other connections
    return COLORS["face"]


class SwingVisualizer:
    """Draws overlays on video frames for swing analysis feedback."""
    
    def __init__(self, frame_width: int = 1920, frame_height: int = 1080):
        if not PIL_AVAILABLE:
            raise RuntimeError("PIL not installed. Run: pip install Pillow")
        
        self.frame_width = frame_width
        self.frame_height = frame_height
        
        # Line thickness scales with frame size
        self.line_width = max(2, frame_width // 400)
        self.point_radius = max(4, frame_width // 300)
    
    def draw_skeleton(
        self,
        frame_bytes: bytes,
        pose: PoseResult,
        min_visibility: float = 0.5
    ) -> bytes:
        """
        Draw skeleton overlay on a frame.
        
        Args:
            frame_bytes: PNG image bytes
            pose: PoseResult with keypoints
            min_visibility: Minimum visibility threshold to draw a keypoint
            
        Returns:
            PNG bytes with skeleton overlay
        """
        # Load image
        image = Image.open(io.BytesIO(frame_bytes)).convert("RGBA")
        width, height = image.size
        
        # Create overlay for drawing (with transparency support)
        overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        
        # Draw connections (bones)
        for start_name, end_name in POSE_CONNECTIONS:
            start_kp = pose.keypoints.get(start_name)
            end_kp = pose.keypoints.get(end_name)
            
            if start_kp is None or end_kp is None:
                continue
            
            # Check visibility
            if start_kp.visibility < min_visibility or end_kp.visibility < min_visibility:
                continue
            
            # Convert normalized coords to pixel coords
            x1 = int(start_kp.x * width)
            y1 = int(start_kp.y * height)
            x2 = int(end_kp.x * width)
            y2 = int(end_kp.y * height)
            
            # Get color for this connection
            color = get_connection_color(start_name, end_name)
            
            # Draw line
            draw.line([(x1, y1), (x2, y2)], fill=color, width=self.line_width)
        
        # Draw keypoints (joints)
        for name, kp in pose.keypoints.items():
            if kp.visibility < min_visibility:
                continue
            
            x = int(kp.x * width)
            y = int(kp.y * height)
            
            # Draw circle at joint
            draw.ellipse(
                [(x - self.point_radius, y - self.point_radius),
                 (x + self.point_radius, y + self.point_radius)],
                fill=COLORS["face"],
                outline=(255, 255, 255)
            )
        
        # Composite overlay onto original image
        result = Image.alpha_composite(image, overlay)
        
        # Convert back to RGB and return as PNG bytes
        result_rgb = result.convert("RGB")
        output = io.BytesIO()
        result_rgb.save(output, format="PNG")
        return output.getvalue()
    
    def draw_skeleton_batch(
        self,
        frames: List[bytes],
        poses: List[Optional[PoseResult]],
        min_visibility: float = 0.5
    ) -> List[bytes]:
        """
        Draw skeleton overlays on multiple frames.
        
        Args:
            frames: List of PNG image bytes
            poses: List of PoseResult (or None for frames without poses)
            min_visibility: Minimum visibility threshold
            
        Returns:
            List of PNG bytes with skeleton overlays
        """
        result_frames = []
        
        for i, (frame, pose) in enumerate(zip(frames, poses)):
            if pose is None:
                # No pose detected, return original frame
                result_frames.append(frame)
            else:
                annotated = self.draw_skeleton(frame, pose, min_visibility)
                result_frames.append(annotated)
            
            if (i + 1) % 10 == 0:
                logger.info(f"Annotated {i + 1}/{len(frames)} frames")
        
        return result_frames
    
    def save_frame(self, frame_bytes: bytes, output_path: str) -> None:
        """Save a frame to disk."""
        image = Image.open(io.BytesIO(frame_bytes))
        image.save(output_path)
        logger.info(f"Saved frame to: {output_path}")
    
    def save_frames(
        self,
        frames: List[bytes],
        output_dir: str,
        prefix: str = "frame"
    ) -> List[str]:
        """Save multiple frames to a directory."""
        import os
        os.makedirs(output_dir, exist_ok=True)
        
        paths = []
        for i, frame in enumerate(frames):
            path = os.path.join(output_dir, f"{prefix}_{i:04d}.png")
            self.save_frame(frame, path)
            paths.append(path)
        
        return paths
    
    def _get_keypoint_pixel(
        self,
        pose: PoseResult,
        name: str,
        width: int,
        height: int
    ) -> Optional[Tuple[int, int]]:
        """Get pixel coordinates for a keypoint."""
        kp = pose.keypoints.get(name)
        if kp is None:
            return None
        return (int(kp.x * width), int(kp.y * height))
    
    def _get_midpoint(
        self,
        p1: Tuple[int, int],
        p2: Tuple[int, int]
    ) -> Tuple[int, int]:
        """Get midpoint between two points."""
        return ((p1[0] + p2[0]) // 2, (p1[1] + p2[1]) // 2)
    
    def _extend_line(
        self,
        p1: Tuple[int, int],
        p2: Tuple[int, int],
        extension: float = 2.0
    ) -> Tuple[Tuple[int, int], Tuple[int, int]]:
        """
        Extend a line segment beyond its endpoints.
        
        Args:
            p1, p2: Line endpoints
            extension: How much to extend (1.0 = no extension, 2.0 = double length each direction)
            
        Returns:
            New extended endpoints
        """
        dx = p2[0] - p1[0]
        dy = p2[1] - p1[1]
        
        # Extend in both directions
        new_p1 = (
            int(p1[0] - dx * (extension - 1)),
            int(p1[1] - dy * (extension - 1))
        )
        new_p2 = (
            int(p2[0] + dx * (extension - 1)),
            int(p2[1] + dy * (extension - 1))
        )
        
        return new_p1, new_p2
    
    def draw_reference_lines(
        self,
        frame_bytes: bytes,
        pose: PoseResult,
        draw_shoulder_plane: bool = True,
        draw_spine_line: bool = True,
        draw_hip_line: bool = False,  # Disabled by default - less useful
        line_color: Tuple[int, int, int] = (255, 255, 0),  # Yellow
        min_visibility: float = 0.5
    ) -> bytes:
        """
        Draw reference/analysis lines on a frame.
        
        Args:
            frame_bytes: PNG image bytes
            pose: PoseResult with keypoints
            draw_shoulder_plane: Draw line through shoulders, extended
            draw_spine_line: Draw line from hip center to shoulder center
            draw_hip_line: Draw line through hips, extended
            line_color: RGB color for reference lines
            min_visibility: Minimum visibility threshold
            
        Returns:
            PNG bytes with reference lines overlay
        """
        # Load image
        image = Image.open(io.BytesIO(frame_bytes)).convert("RGBA")
        width, height = image.size
        
        # Create overlay for drawing
        overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        
        # Reference lines slightly thicker than skeleton
        ref_line_width = max(3, self.line_width)
        
        # Get key points
        left_shoulder = self._get_keypoint_pixel(pose, "left_shoulder", width, height)
        right_shoulder = self._get_keypoint_pixel(pose, "right_shoulder", width, height)
        left_hip = self._get_keypoint_pixel(pose, "left_hip", width, height)
        right_hip = self._get_keypoint_pixel(pose, "right_hip", width, height)
        
        # Shoulder plane line
        if draw_shoulder_plane and left_shoulder and right_shoulder:
            ext_p1, ext_p2 = self._extend_line(left_shoulder, right_shoulder, extension=1.5)
            draw.line([ext_p1, ext_p2], fill=line_color, width=ref_line_width)
        
        # Hip line (disabled by default)
        if draw_hip_line and left_hip and right_hip:
            ext_p1, ext_p2 = self._extend_line(left_hip, right_hip, extension=1.5)
            draw.line([ext_p1, ext_p2], fill=line_color, width=ref_line_width)
        
        # Spine line (hip center to shoulder center)
        if draw_spine_line and left_shoulder and right_shoulder and left_hip and right_hip:
            shoulder_center = self._get_midpoint(left_shoulder, right_shoulder)
            hip_center = self._get_midpoint(left_hip, right_hip)
            # Extend slightly beyond both ends
            ext_p1, ext_p2 = self._extend_line(hip_center, shoulder_center, extension=1.3)
            draw.line([ext_p1, ext_p2], fill=line_color, width=ref_line_width)
        
        # Composite overlay onto original image
        result = Image.alpha_composite(image, overlay)
        
        # Convert back to RGB and return as PNG bytes
        result_rgb = result.convert("RGB")
        output = io.BytesIO()
        result_rgb.save(output, format="PNG")
        return output.getvalue()
    
    def draw_full_analysis(
        self,
        frame_bytes: bytes,
        pose: PoseResult,
        draw_skeleton: bool = True,
        draw_reference_lines: bool = True,
        min_visibility: float = 0.5
    ) -> bytes:
        """
        Draw complete analysis overlay (skeleton + reference lines).
        
        Args:
            frame_bytes: PNG image bytes
            pose: PoseResult with keypoints
            draw_skeleton: Whether to draw skeleton
            draw_reference_lines: Whether to draw reference lines
            min_visibility: Minimum visibility threshold
            
        Returns:
            PNG bytes with full analysis overlay
        """
        result = frame_bytes
        
        if draw_skeleton:
            result = self.draw_skeleton(result, pose, min_visibility)
        
        if draw_reference_lines:
            result = self.draw_reference_lines(result, pose, min_visibility=min_visibility)
        
        return result
    
    def draw_full_analysis_batch(
        self,
        frames: List[bytes],
        poses: List[Optional[PoseResult]],
        draw_skeleton: bool = True,
        draw_reference_lines: bool = True,
        min_visibility: float = 0.5
    ) -> List[bytes]:
        """
        Draw complete analysis overlays on multiple frames.

        Args:
            frames: List of PNG image bytes
            poses: List of PoseResult (or None for frames without poses)
            draw_skeleton: Whether to draw skeleton
            draw_reference_lines: Whether to draw reference lines
            min_visibility: Minimum visibility threshold

        Returns:
            List of PNG bytes with full analysis overlays
        """
        result_frames = []

        for i, (frame, pose) in enumerate(zip(frames, poses)):
            if pose is None:
                result_frames.append(frame)
            else:
                annotated = self.draw_full_analysis(
                    frame, pose,
                    draw_skeleton=draw_skeleton,
                    draw_reference_lines=draw_reference_lines,
                    min_visibility=min_visibility
                )
                result_frames.append(annotated)

            if (i + 1) % 10 == 0:
                logger.info(f"Annotated {i + 1}/{len(frames)} frames")

        return result_frames

    def draw_club_plane(
        self,
        frame_bytes: bytes,
        line_start: Tuple[int, int],
        line_end: Tuple[int, int],
        color: Tuple[int, int, int] = None
    ) -> bytes:
        """
        Draw club plane line on a frame.

        Args:
            frame_bytes: PNG image bytes
            line_start: Start point (x, y) in pixels
            line_end: End point (x, y) in pixels
            color: RGB color (default: orange)

        Returns:
            PNG bytes with club plane line overlay
        """
        if color is None:
            color = COLORS["club_plane"]

        image = Image.open(io.BytesIO(frame_bytes)).convert("RGBA")
        overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)

        # Draw club plane line (thicker for visibility)
        plane_line_width = max(4, self.line_width + 2)
        draw.line([line_start, line_end], fill=color, width=plane_line_width)

        result = Image.alpha_composite(image, overlay)
        result_rgb = result.convert("RGB")
        output = io.BytesIO()
        result_rgb.save(output, format="PNG")
        return output.getvalue()

    def draw_swing_path(
        self,
        frame_bytes: bytes,
        path_points: List[Tuple[int, int]],
        fade_trail: bool = True,
        color: Tuple[int, int, int] = None
    ) -> bytes:
        """
        Draw swing path trajectory on a frame.

        Args:
            frame_bytes: PNG image bytes
            path_points: List of (x, y) pixel coordinates up to current frame
            fade_trail: Whether to fade older points
            color: RGB color (default: red)

        Returns:
            PNG bytes with swing path overlay
        """
        if color is None:
            color = COLORS["swing_path"]

        if len(path_points) < 2:
            return frame_bytes

        image = Image.open(io.BytesIO(frame_bytes)).convert("RGBA")
        overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)

        path_line_width = max(3, self.line_width)

        if fade_trail and len(path_points) > 2:
            # Draw segments with fading alpha
            for i in range(len(path_points) - 1):
                # Calculate alpha based on position in path
                progress = i / (len(path_points) - 1)
                alpha = int(80 + 175 * progress)  # 80 to 255

                segment_color = (*color, alpha)
                draw.line(
                    [path_points[i], path_points[i + 1]],
                    fill=segment_color,
                    width=path_line_width
                )
        else:
            # Draw solid path
            draw.line(path_points, fill=(*color, 255), width=path_line_width)

        # Draw current position indicator (larger dot at end)
        if path_points:
            end_point = path_points[-1]
            indicator_radius = max(6, self.point_radius + 2)
            draw.ellipse(
                [(end_point[0] - indicator_radius, end_point[1] - indicator_radius),
                 (end_point[0] + indicator_radius, end_point[1] + indicator_radius)],
                fill=(*color, 255),
                outline=(255, 255, 255, 255)
            )

        result = Image.alpha_composite(image, overlay)
        result_rgb = result.convert("RGB")
        output = io.BytesIO()
        result_rgb.save(output, format="PNG")
        return output.getvalue()

    def draw_club_mask_overlay(
        self,
        frame_bytes: bytes,
        mask: Any,
        color: Tuple[int, int, int] = None,
        alpha: int = 100
    ) -> bytes:
        """
        Draw semi-transparent club mask overlay on a frame.

        Args:
            frame_bytes: PNG image bytes
            mask: Binary mask (numpy array) of club segmentation
            color: RGB color (default: green)
            alpha: Transparency level (0-255)

        Returns:
            PNG bytes with mask overlay
        """
        if color is None:
            color = COLORS["club_mask"]

        if mask is None:
            return frame_bytes

        image = Image.open(io.BytesIO(frame_bytes)).convert("RGBA")
        width, height = image.size

        # Ensure mask is numpy array
        if hasattr(mask, 'cpu'):
            mask = mask.cpu().numpy()

        if len(mask.shape) > 2:
            mask = mask.squeeze()

        # Resize mask if needed
        mask_h, mask_w = mask.shape
        if mask_w != width or mask_h != height:
            from PIL import Image as PILImage
            mask_img = PILImage.fromarray((mask * 255).astype(np.uint8))
            mask_img = mask_img.resize((width, height), PILImage.NEAREST)
            mask = np.array(mask_img) > 127

        # Create colored overlay where mask is True
        overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
        overlay_data = np.array(overlay)

        # Apply color where mask is True
        overlay_data[mask, 0] = color[0]
        overlay_data[mask, 1] = color[1]
        overlay_data[mask, 2] = color[2]
        overlay_data[mask, 3] = alpha

        overlay = Image.fromarray(overlay_data, "RGBA")

        result = Image.alpha_composite(image, overlay)
        result_rgb = result.convert("RGB")
        output = io.BytesIO()
        result_rgb.save(output, format="PNG")
        return output.getvalue()

    def draw_speed_overlay(
        self,
        frame_bytes: bytes,
        current_speed: Optional[float],
        peak_speed: Optional[float] = None,
        is_peak_frame: bool = False
    ) -> bytes:
        """
        Draw speed indicator overlay on frame.

        Args:
            frame_bytes: PNG image bytes
            current_speed: Current clubhead speed in mph (or None)
            peak_speed: Peak speed for reference (or None)
            is_peak_frame: Whether this frame is at/near peak speed

        Returns:
            PNG bytes with speed overlay
        """
        if not PIL_AVAILABLE:
            return frame_bytes

        if current_speed is None:
            return frame_bytes

        image = Image.open(io.BytesIO(frame_bytes)).convert("RGBA")
        draw = ImageDraw.Draw(image)

        # Choose color based on whether this is peak
        if is_peak_frame:
            color = COLORS["speed_peak"]
        else:
            color = COLORS["speed"]

        # Try to load a font, fall back to default
        try:
            font_size = max(24, self.frame_height // 30)
            font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
        except (OSError, IOError):
            try:
                font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 24)
            except (OSError, IOError):
                font = ImageFont.load_default()

        # Format speed text
        speed_text = f"{current_speed:.0f} mph"

        # Position in top-left corner with padding
        padding = 20
        x = padding
        y = padding

        # Draw background rectangle for better visibility
        bbox = draw.textbbox((x, y), speed_text, font=font)
        bg_padding = 8
        draw.rectangle(
            [
                bbox[0] - bg_padding,
                bbox[1] - bg_padding,
                bbox[2] + bg_padding,
                bbox[3] + bg_padding
            ],
            fill=(0, 0, 0, 180)
        )

        # Draw the speed text
        draw.text((x, y), speed_text, fill=color, font=font)

        # If peak speed provided, show it below
        if peak_speed is not None and not is_peak_frame:
            peak_text = f"Peak: {peak_speed:.0f} mph"
            try:
                small_font_size = max(16, self.frame_height // 45)
                small_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", small_font_size)
            except (OSError, IOError):
                small_font = font

            y2 = bbox[3] + bg_padding + 5
            draw.text((x, y2), peak_text, fill=COLORS["text"], font=small_font)

        result_rgb = image.convert("RGB")
        output = io.BytesIO()
        result_rgb.save(output, format="PNG")
        return output.getvalue()

    def draw_complete_analysis(
        self,
        frame_bytes: bytes,
        pose: Optional[PoseResult],
        club_plane_line: Optional[Tuple[Tuple[int, int], Tuple[int, int]]] = None,
        swing_path_points: Optional[List[Tuple[int, int]]] = None,
        club_mask: Optional[Any] = None,
        draw_skeleton: bool = True,
        draw_reference_lines: bool = True,
        draw_club_plane: bool = True,
        draw_swing_path: bool = True,
        draw_club_mask: bool = False,
        min_visibility: float = 0.5,
        current_speed: Optional[float] = None,
        peak_speed: Optional[float] = None,
        is_peak_frame: bool = False,
        draw_speed: bool = True
    ) -> bytes:
        """
        Draw complete analysis overlay with all visualization layers.

        Args:
            frame_bytes: PNG image bytes
            pose: PoseResult with keypoints (or None)
            club_plane_line: (start, end) tuple for club plane
            swing_path_points: List of (x, y) points for swing path
            club_mask: Binary mask for club overlay
            draw_skeleton: Whether to draw skeleton
            draw_reference_lines: Whether to draw reference lines
            draw_club_plane: Whether to draw club plane line
            draw_swing_path: Whether to draw swing path
            draw_club_mask: Whether to draw club mask
            min_visibility: Minimum visibility threshold
            current_speed: Current clubhead speed in mph
            peak_speed: Peak speed for reference display
            is_peak_frame: Whether this is the peak speed frame
            draw_speed: Whether to draw speed overlay

        Returns:
            PNG bytes with all overlays
        """
        result = frame_bytes

        # Layer order: mask (bottom) -> skeleton -> reference -> club plane -> swing path -> speed (top)

        # 1. Club mask overlay (if enabled and available)
        if draw_club_mask and club_mask is not None:
            result = self.draw_club_mask_overlay(result, club_mask)

        # 2. Skeleton
        if draw_skeleton and pose is not None:
            result = self.draw_skeleton(result, pose, min_visibility)

        # 3. Reference lines
        if draw_reference_lines and pose is not None:
            result = self.draw_reference_lines(result, pose, min_visibility=min_visibility)

        # 4. Club plane line
        if draw_club_plane and club_plane_line is not None:
            result = self.draw_club_plane(result, club_plane_line[0], club_plane_line[1])

        # 5. Swing path
        if draw_swing_path and swing_path_points and len(swing_path_points) >= 2:
            result = self.draw_swing_path(result, swing_path_points)

        # 6. Speed overlay
        if draw_speed and current_speed is not None:
            result = self.draw_speed_overlay(result, current_speed, peak_speed, is_peak_frame)

        return result

    def draw_complete_analysis_batch(
        self,
        frames: List[bytes],
        poses: List[Optional[PoseResult]],
        club_plane_line: Optional[Tuple[Tuple[int, int], Tuple[int, int]]] = None,
        swing_path: Optional[Any] = None,  # SwingPath object
        club_masks: Optional[List[Any]] = None,
        draw_skeleton: bool = True,
        draw_reference_lines: bool = True,
        draw_club_plane: bool = True,
        draw_swing_path: bool = True,
        draw_club_mask: bool = False,
        min_visibility: float = 0.5,
        speed_data: Optional[Dict[int, float]] = None,
        peak_speed: Optional[float] = None,
        peak_speed_frame: Optional[int] = None,
        draw_speed: bool = True
    ) -> List[bytes]:
        """
        Draw complete analysis overlays on multiple frames.

        Args:
            frames: List of PNG image bytes
            poses: List of PoseResult (or None)
            club_plane_line: (start, end) tuple for persistent club plane
            swing_path: SwingPath object with trajectory data
            club_masks: List of masks (or None) for each frame
            draw_skeleton: Whether to draw skeleton
            draw_reference_lines: Whether to draw reference lines
            draw_club_plane: Whether to draw club plane line
            draw_swing_path: Whether to draw swing path
            draw_club_mask: Whether to draw club mask
            min_visibility: Minimum visibility threshold
            speed_data: Dict mapping frame index to speed in mph
            peak_speed: Peak speed for display reference
            peak_speed_frame: Frame index where peak speed occurred
            draw_speed: Whether to draw speed overlay

        Returns:
            List of PNG bytes with all overlays
        """
        result_frames = []

        for i, (frame, pose) in enumerate(zip(frames, poses)):
            # Get swing path points up to this frame
            path_points = None
            if swing_path is not None and hasattr(swing_path, 'get_pixel_points_up_to_frame'):
                # Assuming frame indices match array indices (may need adjustment)
                path_points = swing_path.get_pixel_points_up_to_frame(i)

            # Get club mask for this frame
            mask = None
            if club_masks is not None and i < len(club_masks):
                mask = club_masks[i]

            # Get speed for this frame
            current_speed = None
            is_peak_frame = False
            if speed_data is not None and i in speed_data:
                current_speed = speed_data[i]
                is_peak_frame = (peak_speed_frame is not None and i == peak_speed_frame)

            annotated = self.draw_complete_analysis(
                frame,
                pose,
                club_plane_line=club_plane_line,
                swing_path_points=path_points,
                club_mask=mask,
                draw_skeleton=draw_skeleton,
                draw_reference_lines=draw_reference_lines,
                draw_club_plane=draw_club_plane,
                draw_swing_path=draw_swing_path,
                draw_club_mask=draw_club_mask,
                min_visibility=min_visibility,
                current_speed=current_speed,
                peak_speed=peak_speed,
                is_peak_frame=is_peak_frame,
                draw_speed=draw_speed
            )
            result_frames.append(annotated)

            if (i + 1) % 10 == 0:
                logger.info(f"Complete analysis annotated {i + 1}/{len(frames)} frames")

        return result_frames
