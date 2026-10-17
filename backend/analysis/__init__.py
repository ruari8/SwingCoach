"""Swing analysis modules.

The active pipeline measures 2D video evidence and grounds coaching in source
cases. Heavy detector modules load only when the pipeline requests them; importing
the package does not initialize pose detection.
"""

__all__ = [
    "FrameExtractor",
    "VideoExporter",
    "SwingCoachPipeline3D",
    "Pipeline3DResult",
    "PoseDetector",
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
