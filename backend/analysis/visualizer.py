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
