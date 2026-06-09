"""Swing analysis modules.

The active backend pipeline is currently in annotation-reset mode. Heavy legacy
analysis modules remain importable lazily for experiments, but importing the
package no longer initializes pose, event, visualizer, or SAM-related code.
"""

__all__ = [
    "FrameExtractor",
    "VideoExporter",
    "SwingCoachPipeline3D",
    "Pipeline3DResult",
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
    "VelocityEstimator",
    "VelocityMetrics",
    "VelocityPoint",
    "CoachMetricsEngine",
    "MetricCard",
    "MetricsEngineResult",
    "CoachResponseBuilder",
    "CoachingBundle",
    "DrillSuggestion",
]


def __getattr__(name):
    if name == "FrameExtractor":
        from .frame_extractor import FrameExtractor

        return FrameExtractor

    if name == "VideoExporter":
        from .video_exporter import VideoExporter

        return VideoExporter

    if name in {"SwingCoachPipeline3D", "Pipeline3DResult"}:
        from .pipeline_3d import Pipeline3DResult, SwingCoachPipeline3D

        return {
            "SwingCoachPipeline3D": SwingCoachPipeline3D,
            "Pipeline3DResult": Pipeline3DResult,
        }[name]

    if name == "PoseDetector":
        from .pose_detector import PoseDetector

        return PoseDetector

    if name in {"EventDetector", "SwingEvent", "SwingEvents", "SwingPhase", "SwingPhases", "PHASE_NAMES", "PHASE_DESCRIPTIONS"}:
        from .event_detector import (
            EventDetector,
            PHASE_DESCRIPTIONS,
            PHASE_NAMES,
            SwingEvent,
            SwingEvents,
            SwingPhase,
            SwingPhases,
        )

        return {
            "EventDetector": EventDetector,
            "SwingEvent": SwingEvent,
            "SwingEvents": SwingEvents,
            "SwingPhase": SwingPhase,
            "SwingPhases": SwingPhases,
            "PHASE_NAMES": PHASE_NAMES,
            "PHASE_DESCRIPTIONS": PHASE_DESCRIPTIONS,
        }[name]

    if name == "MetricsCalculator":
        from .metrics import MetricsCalculator

        return MetricsCalculator

    if name == "SwingCoach":
        from .coach import SwingCoach

        return SwingCoach

    if name == "SwingVisualizer":
        from .visualizer import SwingVisualizer

        return SwingVisualizer

    if name in {"VisualizationConfig", "LayerInfo", "VisualizationMetadata", "LAYER_DEFINITIONS"}:
        from .visualization_config import LAYER_DEFINITIONS, LayerInfo, VisualizationConfig, VisualizationMetadata

        return {
            "VisualizationConfig": VisualizationConfig,
            "LayerInfo": LayerInfo,
            "VisualizationMetadata": VisualizationMetadata,
            "LAYER_DEFINITIONS": LAYER_DEFINITIONS,
        }[name]

    if name in {"ClubAnalyzer", "ClubPlane"}:
        from .club_analyzer import ClubAnalyzer, ClubPlane

        return {"ClubAnalyzer": ClubAnalyzer, "ClubPlane": ClubPlane}[name]

    if name in {"VelocityEstimator", "VelocityMetrics", "VelocityPoint"}:
        from .velocity_estimator import VelocityEstimator, VelocityMetrics, VelocityPoint

        return {
            "VelocityEstimator": VelocityEstimator,
            "VelocityMetrics": VelocityMetrics,
            "VelocityPoint": VelocityPoint,
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
