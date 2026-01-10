"""
Swing analysis modules.
"""

from .frame_extractor import FrameExtractor
from .pose_detector import PoseDetector
from .event_detector import (
    EventDetector,
    SwingEvent,
    SwingEvents,
    SwingPhase,
    SwingPhases,
    PHASE_NAMES,
    PHASE_DESCRIPTIONS,
)
from .metrics import MetricsCalculator
from .coach import SwingCoach
from .visualizer import SwingVisualizer
from .visualization_config import (
    VisualizationConfig,
    LayerInfo,
    VisualizationMetadata,
    LAYER_DEFINITIONS,
)
from .club_analyzer import ClubAnalyzer, ClubPlane
from .video_exporter import VideoExporter
from .velocity_estimator import VelocityEstimator, VelocityMetrics, VelocityPoint

__all__ = [
    "FrameExtractor",
    "PoseDetector",
    "EventDetector",
    "SwingEvent",
    "SwingEvents",
    "SwingPhase",
    "SwingPhases",
    "PHASE_NAMES",
    "PHASE_DESCRIPTIONS",
    "MetricsCalculator",
    "SwingCoach",
    "SwingVisualizer",
    "VisualizationConfig",
    "LayerInfo",
    "VisualizationMetadata",
    "LAYER_DEFINITIONS",
    "ClubAnalyzer",
    "ClubPlane",
    "VideoExporter",
    "VelocityEstimator",
    "VelocityMetrics",
    "VelocityPoint",
]
