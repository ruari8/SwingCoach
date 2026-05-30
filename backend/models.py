"""
Pydantic models for API request/response schemas.
"""

from pydantic import BaseModel, Field
from typing import Optional, Dict, List
from enum import Enum


class Vantage(str, Enum):
    """Camera vantage point."""
    DTL = "DTL"
    FACE_ON = "FO"


class UploadURLResponse(BaseModel):
    """Response containing pre-signed upload URL."""
    upload_url: str = Field(..., description="Pre-signed URL for video upload")
    video_key: str = Field(..., description="Unique key identifying the video in storage")


class AnalyzeRequest(BaseModel):
    """Request to analyze a swing video."""
    video_key: str = Field(..., description="Key of the video in R2 storage")
    vantage: Vantage = Field(..., description="Camera vantage point (DTL or Face-On)")
    fps: Optional[float] = Field(None, description="Video FPS (auto-detected if not provided)")


class DrillLink(BaseModel):
    """A recommended drill with link."""
    id: str
    title: str
    description: str
    url: Optional[str] = None
    platform: str = "youtube"


class SwingEventData(BaseModel):
    """Data for a single swing event."""
    frame: int
    timestamp: float
    confidence: float


class SwingEventsResponse(BaseModel):
    """All detected swing events (legacy 4-event system)."""
    address: Optional[SwingEventData] = None
    top: Optional[SwingEventData] = None
    impact: Optional[SwingEventData] = None
    finish: Optional[SwingEventData] = None


class SwingPhaseData(BaseModel):
    """Data for a single swing phase (P1-P10)."""
    phase: int = Field(..., description="Phase number (1-10)")
    name: str = Field(..., description="Phase name (address, takeaway, etc.)")
    frame: int = Field(..., description="Frame index")
    timestamp: float = Field(..., description="Time in seconds")
    confidence: float = Field(..., description="Detection confidence")
    description: str = Field("", description="Human-readable description")


class SwingPhasesResponse(BaseModel):
    """All 10 swing phases (P1-P10)."""
    phases: List[SwingPhaseData] = Field(default_factory=list, description="List of detected phases")
    phase_count: int = Field(0, description="Number of phases detected")


class AnalysisResult(BaseModel):
    """Result of swing analysis."""
    swing_id: str = Field(..., description="Unique ID for this analysis")
    summary: str = Field(..., description="Brief summary of the analysis")
    diagnosis: str = Field(..., description="Detailed coaching diagnosis")
    events: SwingEventsResponse = Field(..., description="Detected swing events (legacy)")
    phases: Optional[SwingPhasesResponse] = Field(None, description="All 10 swing phases (P1-P10)")
    metrics: Dict[str, Optional[float]] = Field(..., description="Raw calculated metrics")
    metrics_display: Dict[str, str] = Field(..., description="Formatted metrics for display")
    key_issues: List[str] = Field(default_factory=list, description="Identified swing issues")
    positives: List[str] = Field(default_factory=list, description="Positive aspects of swing")
    drill_links: List[DrillLink] = Field(default_factory=list, description="Recommended drills")
    video_info: Optional[Dict] = Field(None, description="Video metadata")


class HealthResponse(BaseModel):
    """Health check response."""
    status: str
    r2_configured: bool
    analysis_ready: bool = False


class VisualizationLayerInfo(BaseModel):
    """Information about a visualization layer."""
    name: str = Field(..., description="Layer identifier (skeleton, club_plane, etc.)")
    color: str = Field(..., description="Hex color code for the layer")
    description: str = Field(..., description="Human-readable description")
    enabled: bool = Field(..., description="Whether this layer is rendered")


class VisualizationOptions(BaseModel):
    """Options for video annotation."""
    draw_skeleton: bool = Field(True, description="Draw body pose skeleton")
    draw_reference_lines: bool = Field(True, description="Draw shoulder plane and spine angle")
    draw_club_plane: bool = Field(True, description="Draw club plane line from address")
    draw_swing_path: bool = Field(True, description="Draw club head trajectory")
    draw_club_mask: bool = Field(False, description="Draw club segmentation mask overlay")
    min_visibility: float = Field(0.5, description="Minimum keypoint visibility threshold")


class VelocityDataPoint(BaseModel):
    """Velocity data at a specific frame for UI playback."""
    frame_index: int = Field(..., description="Frame number")
    speed_mph: Optional[float] = Field(None, description="Club speed at this frame")


class VelocityData(BaseModel):
    """Clubhead velocity data for UI display."""
    peak_speed_mph: Optional[float] = Field(None, description="Maximum club speed")
    peak_speed_frame: Optional[int] = Field(None, description="Frame where peak speed occurred")
    impact_speed_mph: Optional[float] = Field(None, description="Club speed at impact")
    confidence: float = Field(0.0, description="Detection confidence (0-1)")
    speed_profile: List[VelocityDataPoint] = Field(default_factory=list, description="Speed at each frame for playback")


class AnnotatedVideoMetadata(BaseModel):
    """Metadata about the annotated video for UI consumption."""
    layers: List[VisualizationLayerInfo] = Field(default_factory=list, description="Active visualization layers")
    club_plane_angle_degrees: Optional[float] = Field(None, description="Club shaft angle at address")
    swing_path_point_count: int = Field(0, description="Number of points in swing path")
    video_fps: Optional[float] = Field(None, description="Video frames per second")
    frame_count: int = Field(0, description="Total frames in video")
    velocity: Optional[VelocityData] = Field(None, description="Clubhead velocity data")


class AnnotatedVideoResult(BaseModel):
    """Result containing annotated video and metadata."""
    video_url: Optional[str] = Field(None, description="URL to download annotated video")
    video_key: Optional[str] = Field(None, description="Storage key for annotated video")
    metadata: AnnotatedVideoMetadata = Field(..., description="Visualization metadata for UI")


class AnalyzeRequestWithVideo(BaseModel):
    """Extended request to analyze a swing video with video output."""
    video_key: str = Field(..., description="Key of the video in R2 storage")
    vantage: Vantage = Field(..., description="Camera vantage point (DTL or Face-On)")
    fps: Optional[float] = Field(None, description="Video FPS (auto-detected if not provided)")
    generate_video: bool = Field(False, description="Whether to generate annotated video")
    visualization: Optional[VisualizationOptions] = Field(None, description="Video annotation options")


class FullAnalysisResult(BaseModel):
    """Full analysis result including optional annotated video."""
    swing_id: str = Field(..., description="Unique ID for this analysis")
    summary: str = Field(..., description="Brief summary of the analysis")
    diagnosis: str = Field(..., description="Detailed coaching diagnosis")
    events: SwingEventsResponse = Field(..., description="Detected swing events (legacy)")
    phases: Optional[SwingPhasesResponse] = Field(None, description="All 10 swing phases (P1-P10)")
    metrics: Dict[str, Optional[float]] = Field(..., description="Raw calculated metrics")
    metrics_display: Dict[str, str] = Field(..., description="Formatted metrics for display")
    key_issues: List[str] = Field(default_factory=list, description="Identified swing issues")
    positives: List[str] = Field(default_factory=list, description="Positive aspects of swing")
    drill_links: List[DrillLink] = Field(default_factory=list, description="Recommended drills")
    video_info: Optional[Dict] = Field(None, description="Video metadata")
    annotated_video: Optional[AnnotatedVideoResult] = Field(None, description="Annotated video if requested")


class AnalysisMetric(BaseModel):
    """Display-ready metric for the mobile MVP response."""
    key: str
    name: str
    value: str


class AnalysisDrill(BaseModel):
    """Lightweight drill suggestion for the mobile MVP response."""
    title: str
    summary: str


class AnalysisVideo(BaseModel):
    """Signed video URL plus durable storage key."""
    key: str
    url: str
    base_key: Optional[str] = Field(
        None,
        description="Storage key for clean base video used with client-side overlays",
    )
    base_url: Optional[str] = Field(
        None,
        description="Signed URL for clean base video used with client-side overlays",
    )
    tracks_key: Optional[str] = Field(
        None,
        description="Storage key for machine-readable annotation overlay tracks",
    )
    tracks_url: Optional[str] = Field(
        None,
        description="Signed URL for machine-readable annotation overlay tracks",
    )
    layers: List[VisualizationLayerInfo] = Field(
        default_factory=list,
        description="Visualization layers rendered into this annotated video",
    )


class AnalyzeResponse(BaseModel):
    """Lightweight app-facing response used by /analyze."""
    analysis_id: str
    summary: str
    metrics: List[AnalysisMetric] = Field(default_factory=list)
    annotated_video: Optional[AnalysisVideo] = None
    drills: List[AnalysisDrill] = Field(default_factory=list)


class AnalysisRunCreateResponse(BaseModel):
    """Response returned after queuing an async analysis run."""
    run_id: str
    status: str
    status_url: str
    events_url: str


class AnalysisRunStatusResponse(BaseModel):
    """Current state for an async analysis run."""
    run_id: str
    status: str
    stage: str
    progress: float = Field(..., ge=0.0, le=1.0)
    message: str
    error: Optional[str] = None
    result: Optional[AnalyzeResponse] = None
    created_at: float
    started_at: Optional[float] = None
    completed_at: Optional[float] = None
    sequence: int


class ArtifactURLRequest(BaseModel):
    """Request a fresh signed URL for a stored artifact."""
    key: str


class ArtifactURLResponse(BaseModel):
    """Fresh signed URL for a stored artifact."""
    key: str
    url: str


class CoachableMetricCard(BaseModel):
    """Coachable metric card returned by the unified pipeline."""
    key: str
    name: str
    value: Optional[float] = None
    unit: str
    confidence: float = Field(..., ge=0.0, le=1.0)
    explanation: str
    fix_hint: str


class CoachableDrill(BaseModel):
    """Grounded drill suggestion."""
    id: str
    title: str
    source: str
    summary: str


class CoachingBundleResponse(BaseModel):
    """Top-level coaching guidance payload."""
    summary: str
    top_priorities: List[str] = Field(default_factory=list)
    drills: List[CoachableDrill] = Field(default_factory=list)


class ArtifactBundleResponse(BaseModel):
    """Artifact URLs and local keys for run outputs."""
    base_video_url: Optional[str] = None
    base_video_key: Optional[str] = None
    annotated_video_url: Optional[str] = None
    annotated_video_key: Optional[str] = None
    annotation_tracks_url: Optional[str] = None
    annotation_tracks_key: Optional[str] = None
    swing_3d_url: Optional[str] = None
    swing_3d_key: Optional[str] = None
    debug_urls: List[str] = Field(default_factory=list)


class QualityBundleResponse(BaseModel):
    """Quality and traceability metadata."""
    warnings: List[str] = Field(default_factory=list)
    missing_data: List[str] = Field(default_factory=list)
    timings: Dict[str, Dict] = Field(default_factory=dict)


class CoachableAnalysisResponse(BaseModel):
    """Unified backend response used by /analyze."""
    run_id: str
    metrics: List[CoachableMetricCard] = Field(default_factory=list)
    coaching: CoachingBundleResponse
    artifacts: ArtifactBundleResponse
    quality: QualityBundleResponse


class CoachChatRequest(BaseModel):
    """Follow-up coaching chat request grounded in a prior run."""
    run_id: str
    question: str
    student_goal: Optional[str] = None


class CoachChatResponse(BaseModel):
    """Grounded coaching chat response."""
    run_id: str
    answer: str
