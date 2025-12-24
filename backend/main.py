"""
FastAPI backend for SwingCoach.
Handles video upload orchestration and swing analysis.
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import logging

from models import (
    UploadURLResponse,
    AnalyzeRequest,
    AnalysisResult,
    DrillLink,
    HealthResponse
)
from r2_client import get_r2_client

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(
    title="SwingCoach API",
    description="Backend for golf swing analysis",
    version="0.1.0"
)

# CORS configuration (allow iOS app to call API)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify your iOS app's domain
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    """Root endpoint - API info."""
    return {
        "name": "SwingCoach API",
        "version": "0.1.0",
        "endpoints": {
            "health": "/health",
            "upload_url": "/upload-url",
            "analyze": "/analyze"
        }
    }


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """
    Health check endpoint.
    Verifies R2 connection is configured.
    """
    try:
        r2 = get_r2_client()
        r2_configured = True
    except Exception as e:
        logger.error(f"R2 not configured: {e}")
        r2_configured = False
    
    return HealthResponse(
        status="healthy" if r2_configured else "degraded",
        r2_configured=r2_configured
    )


@app.get("/upload-url", response_model=UploadURLResponse)
async def get_upload_url():
    """
    Generate a pre-signed URL for uploading a swing video.
    
    The iOS app will:
    1. Call this endpoint to get an upload URL
    2. PUT the video file directly to that URL (bypassing this backend)
    3. Call /analyze with the returned video_key
    """
    try:
        r2 = get_r2_client()
        result = r2.generate_upload_url()
        
        logger.info(f"Generated upload URL for key: {result['video_key']}")
        
        return UploadURLResponse(
            upload_url=result["upload_url"],
            video_key=result["video_key"]
        )
    except Exception as e:
        logger.error(f"Failed to generate upload URL: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/analyze", response_model=AnalysisResult)
async def analyze_swing(request: AnalyzeRequest):
    """
    Analyze a swing video that has been uploaded to R2.
    
    This is the main analysis endpoint. It will:
    1. Download the video from R2
    2. Extract frames
    3. Run pose detection
    4. Calculate metrics
    5. Generate recommendations
    
    Currently returns mock data - analysis pipeline to be implemented.
    """
    try:
        r2 = get_r2_client()
        
        # Verify video exists
        if not r2.video_exists(request.video_key):
            raise HTTPException(status_code=404, detail="Video not found in storage")
        
        logger.info(f"Analyzing swing: {request.video_key} (vantage: {request.vantage})")
        
        # TODO: Implement actual analysis pipeline
        # For now, return mock data
        
        # Download video (will be used for analysis)
        # video_bytes = r2.download_video(request.video_key)
        # ... process video ...
        
        # Mock response
        result = AnalysisResult(
            summary="Your swing is trash",
            metrics={
                "Head Sway": "4.2 inches (too much)",
                "Hip Slide": "2.1 inches",
                "Shaft Lean": "-3° (flipping)",
                "Tempo": "2.8:1 (rushed)"
            },
            drill_links=[
                DrillLink(
                    title="Fix Your Early Extension",
                    url="https://youtube.com/watch?v=example1",
                    platform="youtube"
                ),
                DrillLink(
                    title="Stop Flipping - Shaft Lean Drill",
                    url="https://youtube.com/watch?v=example2",
                    platform="youtube"
                )
            ],
            raw_response='{"status": "mock", "vantage": "' + request.vantage + '"}'
        )
        
        logger.info(f"Analysis complete for {request.video_key}")
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Analysis failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
