"""Swing analysis modules.

The active pipeline measures 2D video evidence and grounds coaching in source
cases. Heavy detector modules load only when the pipeline requests them; importing
the package does not initialize pose, event, visualizer or SAM-related code.
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
    "SwingVisualizer",
    "ClubAnalyzer",
    "ClubPlane",
    "MetricCard",
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

    if name == "SwingVisualizer":
        from .visualizer import SwingVisualizer

        return SwingVisualizer

    if name in {"ClubAnalyzer", "ClubPlane"}:
        from .club_analyzer import ClubAnalyzer, ClubPlane

        return {"ClubAnalyzer": ClubAnalyzer, "ClubPlane": ClubPlane}[name]

    if name == "MetricCard":
        from .metrics_engine import MetricCard

        return MetricCard

    if name in {"CoachResponseBuilder", "CoachingBundle", "DrillSuggestion"}:
        from .coach_response_builder import CoachResponseBuilder, CoachingBundle, DrillSuggestion

        return {
            "CoachResponseBuilder": CoachResponseBuilder,
            "CoachingBundle": CoachingBundle,
            "DrillSuggestion": DrillSuggestion,
        }[name]

    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
