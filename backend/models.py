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
    """All detected swing events."""
    address: Optional[SwingEventData] = None
    top: Optional[SwingEventData] = None
    impact: Optional[SwingEventData] = None
    finish: Optional[SwingEventData] = None


class AnalysisResult(BaseModel):
    """Result of swing analysis."""
    swing_id: str = Field(..., description="Unique ID for this analysis")
    summary: str = Field(..., description="Brief summary of the analysis")
    diagnosis: str = Field(..., description="Detailed coaching diagnosis")
    events: SwingEventsResponse = Field(..., description="Detected swing events")
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
