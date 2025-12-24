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


class DrillLink(BaseModel):
    """A recommended drill with link."""
    title: str
    url: str
    platform: str  # "youtube", "instagram", etc.


class AnalysisResult(BaseModel):
    """Result of swing analysis."""
    summary: str = Field(..., description="Brief summary of the analysis")
    metrics: Dict[str, str] = Field(..., description="Calculated metrics with descriptions")
    drill_links: List[DrillLink] = Field(default_factory=list, description="Recommended drills")
    raw_response: Optional[str] = Field(None, description="Raw analysis data for debugging")


class HealthResponse(BaseModel):
    """Health check response."""
    status: str
    r2_configured: bool
