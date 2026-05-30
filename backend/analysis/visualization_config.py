"""
Configuration and metadata for swing visualization layers.
"""

from dataclasses import dataclass, field
from typing import List, Dict, Optional, Any


@dataclass
class VisualizationConfig:
    """Configuration for which visualization layers to render."""
    draw_skeleton: bool = True
    draw_reference_lines: bool = True  # shoulder plane, spine angle
    draw_club_plane: bool = True       # Extended orange line from address
    draw_swing_path: bool = True       # Red trajectory curve
    draw_ball_contact: bool = True     # Ball/contact evidence near impact
    draw_phase_markers: bool = True    # P1-P10 event markers
    draw_confidence: bool = True       # Confidence and evidence badges
    draw_guides: bool = True           # Generic checkpoint guide shapes
    draw_club_mask: bool = False       # Semi-transparent mask overlay (disabled by default)
    min_visibility: float = 0.5        # Keypoint visibility threshold

    @classmethod
    def from_dict(cls, config_dict: Optional[Dict[str, Any]]) -> "VisualizationConfig":
        """Create config from dictionary, using defaults for missing keys."""
        if config_dict is None:
            return cls()

        return cls(
            draw_skeleton=config_dict.get("draw_skeleton", True),
            draw_reference_lines=config_dict.get("draw_reference_lines", True),
            draw_club_plane=config_dict.get("draw_club_plane", True),
            draw_swing_path=config_dict.get("draw_swing_path", True),
            draw_ball_contact=config_dict.get("draw_ball_contact", True),
            draw_phase_markers=config_dict.get("draw_phase_markers", True),
            draw_confidence=config_dict.get("draw_confidence", True),
            draw_guides=config_dict.get("draw_guides", True),
            draw_club_mask=config_dict.get("draw_club_mask", False),
            min_visibility=config_dict.get("min_visibility", 0.5),
        )

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "draw_skeleton": self.draw_skeleton,
            "draw_reference_lines": self.draw_reference_lines,
            "draw_club_plane": self.draw_club_plane,
            "draw_swing_path": self.draw_swing_path,
            "draw_ball_contact": self.draw_ball_contact,
            "draw_phase_markers": self.draw_phase_markers,
            "draw_confidence": self.draw_confidence,
            "draw_guides": self.draw_guides,
            "draw_club_mask": self.draw_club_mask,
            "min_visibility": self.min_visibility,
        }


@dataclass
class LayerInfo:
    """Info about a single visualization layer for UI display."""
    name: str           # "skeleton", "reference_lines", "club_plane", etc.
    color: str          # Hex color for UI legend (e.g., "#00FFFF")
    description: str    # Tooltip text for UI
    enabled: bool       # Whether this layer is rendered

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "name": self.name,
            "color": self.color,
            "description": self.description,
            "enabled": self.enabled,
        }


# Pre-defined layer information
LAYER_DEFINITIONS = {
    "skeleton": LayerInfo(
        name="skeleton",
        color="#00FFFF",  # Cyan
        description="Body pose skeleton showing joint positions",
        enabled=True,
    ),
    "reference_lines": LayerInfo(
        name="reference_lines",
        color="#FFFF00",  # Yellow
        description="Shoulder plane and spine angle reference lines",
        enabled=True,
    ),
    "club_plane": LayerInfo(
        name="club_plane",
        color="#FFA500",  # Orange
        description="Club shaft angle at address, extended as reference plane",
        enabled=True,
    ),
    "swing_path": LayerInfo(
        name="swing_path",
        color="#FF0000",  # Red
        description="Trajectory of club head through the swing",
        enabled=True,
    ),
    "speed": LayerInfo(
        name="speed",
        color="#00FF80",
        description="Estimated clubhead speed overlay",
        enabled=True,
    ),
    "ball_contact": LayerInfo(
        name="ball_contact",
        color="#FFFFFF",
        description="Ball/contact evidence near the detected impact window",
        enabled=True,
    ),
    "phase_markers": LayerInfo(
        name="phase_markers",
        color="#FFFFFF",
        description="Detected P1-P10 swing phase markers",
        enabled=True,
    ),
    "confidence": LayerInfo(
        name="confidence",
        color="#00FF80",
        description="Confidence and evidence badges for phase and impact detection",
        enabled=True,
    ),
    "shaft_checkpoints": LayerInfo(
        name="shaft_checkpoints",
        color="#FFD400",
        description="Shaft checkpoints at key swing phases",
        enabled=True,
    ),
    "clubhead_path": LayerInfo(
        name="clubhead_path",
        color="#FF3B30",
        description="Clubhead trace through the analyzed swing window",
        enabled=True,
    ),
    "setup_geometry": LayerInfo(
        name="setup_geometry",
        color="#00E5FF",
        description="Setup posture, stance, and alignment references",
        enabled=True,
    ),
    "head_reference": LayerInfo(
        name="head_reference",
        color="#FFFFFF",
        description="Address head reference compared with later swing positions",
        enabled=True,
    ),
    "hip_depth": LayerInfo(
        name="hip_depth",
        color="#FF9500",
        description="Address hip-depth reference for posture and early-extension checks",
        enabled=True,
    ),
    "hand_depth": LayerInfo(
        name="hand_depth",
        color="#BF5AF2",
        description="Hand-depth path and top-position checkpoint",
        enabled=True,
    ),
    "lead_arm_plane": LayerInfo(
        name="lead_arm_plane",
        color="#34C759",
        description="Lead-arm plane compared with shoulder plane at the top",
        enabled=True,
    ),
    "takeaway_checkpoint": LayerInfo(
        name="takeaway_checkpoint",
        color="#FFD60A",
        description="Takeaway hand and shaft relationship checkpoint",
        enabled=True,
    ),
    "club_mask": LayerInfo(
        name="club_mask",
        color="#00FF0064",  # Green with alpha
        description="Detected club segmentation mask overlay",
        enabled=False,
    ),
}

GUIDE_LAYER_NAMES = [
    "club_plane",
    "shaft_checkpoints",
    "clubhead_path",
    "setup_geometry",
    "head_reference",
    "hip_depth",
    "hand_depth",
    "lead_arm_plane",
    "takeaway_checkpoint",
]


@dataclass
class VisualizationMetadata:
    """Metadata describing the visualization output for UI consumption."""
    layers: List[LayerInfo] = field(default_factory=list)
    club_plane_angle_degrees: Optional[float] = None
    swing_path_point_count: int = 0
    video_fps: Optional[float] = None
    frame_count: int = 0

    @classmethod
    def from_config(cls, config: VisualizationConfig) -> "VisualizationMetadata":
        """Create metadata from config, populating layer info."""
        layers = []

        if config.draw_skeleton:
            layers.append(LAYER_DEFINITIONS["skeleton"])
        if config.draw_reference_lines:
            layers.append(LAYER_DEFINITIONS["reference_lines"])
        if config.draw_club_plane:
            layers.append(LAYER_DEFINITIONS["club_plane"])
        if config.draw_swing_path:
            layers.append(LAYER_DEFINITIONS["swing_path"])
        if config.draw_ball_contact:
            layers.append(LAYER_DEFINITIONS["ball_contact"])
        if config.draw_phase_markers:
            layers.append(LAYER_DEFINITIONS["phase_markers"])
        if config.draw_confidence:
            layers.append(LAYER_DEFINITIONS["confidence"])
        if config.draw_club_mask:
            layers.append(LAYER_DEFINITIONS["club_mask"])
        if config.draw_guides:
            for layer_name in GUIDE_LAYER_NAMES:
                if not any(layer.name == layer_name for layer in layers):
                    layers.append(LAYER_DEFINITIONS[layer_name])

        return cls(layers=layers)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "layers": [layer.to_dict() for layer in self.layers],
            "club_plane_angle_degrees": self.club_plane_angle_degrees,
            "swing_path_point_count": self.swing_path_point_count,
            "video_fps": self.video_fps,
            "frame_count": self.frame_count,
        }
