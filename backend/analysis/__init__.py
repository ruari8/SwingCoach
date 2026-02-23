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
    "SwingCoachPipeline3D",
    "Pipeline3DResult",
    "CoachMetricsEngine",
    "MetricCard",
    "MetricsEngineResult",
    "CoachResponseBuilder",
    "CoachingBundle",
    "DrillSuggestion",
]


def __getattr__(name):
    """
    Lazily import heavyweight modules.

    This avoids importing optional 3D-related dependencies when callers only
    need lightweight utilities (e.g., frame extraction or 2D annotation tests).
    """
    if name in {"SwingCoachPipeline3D", "Pipeline3DResult"}:
        from .pipeline_3d import Pipeline3DResult, SwingCoachPipeline3D

        return {
            "SwingCoachPipeline3D": SwingCoachPipeline3D,
            "Pipeline3DResult": Pipeline3DResult,
        }[name]

    if name in {"CoachMetricsEngine", "MetricCard", "MetricsEngineResult"}:
        from .metrics_engine import CoachMetricsEngine, MetricCard, MetricsEngineResult

        return {
            "CoachMetricsEngine": CoachMetricsEngine,
            "MetricCard": MetricCard,
            "MetricsEngineResult": MetricsEngineResult,
        }[name]

    if name in {"CoachResponseBuilder", "CoachingBundle", "DrillSuggestion"}:
        from .coach_response_builder import CoachResponseBuilder, CoachingBundle, DrillSuggestion

        return {
            "CoachResponseBuilder": CoachResponseBuilder,
            "CoachingBundle": CoachingBundle,
            "DrillSuggestion": DrillSuggestion,
        }[name]

    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
