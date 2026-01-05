"""
FastAPI backend for SwingCoach.
Handles video upload orchestration and swing analysis.
"""

import uuid
import logging
from typing import Dict, Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from models import (
    UploadURLResponse,
    AnalyzeRequest,
    AnalysisResult,
    DrillLink,
    HealthResponse,
    SwingEventsResponse,
    SwingEventData,
)
from r2_client import get_r2_client

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ANALYSIS_AVAILABLE = False
try:
    from analysis import (
        FrameExtractor,
        PoseDetector,
        EventDetector,
        MetricsCalculator,
        SwingCoach,
    )
    ANALYSIS_AVAILABLE = True
    logger.info("Analysis modules loaded successfully")
except ImportError as e:
    logger.warning(f"Analysis modules not available: {e}")
    logger.warning("Install dependencies: pip install mediapipe numpy pillow")

app = FastAPI(
    title="SwingCoach API",
    description="Backend for golf swing analysis",
    version="0.2.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    """Root endpoint - API info."""
    return {
        "name": "SwingCoach API",
        "version": "0.2.0",
        "analysis_available": ANALYSIS_AVAILABLE,
        "endpoints": {
            "health": "/health",
            "upload_url": "/upload-url",
            "analyze": "/analyze"
        }
    }


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint."""
    try:
        r2 = get_r2_client()
        r2_configured = True
    except Exception as e:
        logger.error(f"R2 not configured: {e}")
        r2_configured = False
    
    return HealthResponse(
        status="healthy" if r2_configured else "degraded",
        r2_configured=r2_configured,
        analysis_ready=ANALYSIS_AVAILABLE
    )


@app.get("/upload-url", response_model=UploadURLResponse)
async def get_upload_url():
    """Generate a pre-signed URL for uploading a swing video."""
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
    
    Pipeline:
    1. Download video from R2
    2. Extract frames (sampled)
    3. Run pose detection on frames
    4. Detect swing events (address, top, impact, finish)
    5. Calculate metrics at key positions
    6. Generate coaching feedback and drill recommendations
    """
    if not ANALYSIS_AVAILABLE:
        raise HTTPException(
            status_code=503,
            detail="Analysis not available. Install dependencies: pip install mediapipe numpy pillow"
        )
    
    try:
        r2 = get_r2_client()
        
        if not r2.video_exists(request.video_key):
            raise HTTPException(status_code=404, detail="Video not found in storage")
        
        logger.info(f"Analyzing swing: {request.video_key} (vantage: {request.vantage})")
        
        swing_id = str(uuid.uuid4())[:8]
        
        logger.info("Downloading video from R2...")
        video_bytes = r2.download_video(request.video_key)
        logger.info(f"Downloaded {len(video_bytes) / 1024 / 1024:.1f} MB")
        
        frame_extractor = FrameExtractor()
        video_info = frame_extractor.get_video_info(video_bytes)
        logger.info(f"Video info: {video_info}")
        
        fps = request.fps or video_info.get("fps", 30.0)
        frame_count = video_info.get("frame_count", 300)
        
        sample_rate = max(1, frame_count // 30)
        logger.info(f"Extracting frames (sample_rate={sample_rate})...")
        frames = frame_extractor.extract_frames(video_bytes, sample_rate=sample_rate, max_frames=40)
        logger.info(f"Extracted {len(frames)} frames")
        
        logger.info("Running pose detection...")
        with PoseDetector() as pose_detector:
            poses = pose_detector.detect_poses_batch(frames)
        
        logger.info("Detecting swing events...")
        event_detector = EventDetector(fps=fps / sample_rate)
        events = event_detector.detect_events(poses, vantage=request.vantage.value)
        
        key_poses: Dict[str, Optional[object]] = {}
        for event_name, event in [
            ("address", events.address),
            ("top", events.top),
            ("impact", events.impact),
            ("finish", events.finish)
        ]:
            if event:
                pose_idx = None
                for i, p in enumerate(poses):
                    if p and p.frame_index == event.frame_index:
                        pose_idx = i
                        break
                if pose_idx is not None:
                    key_poses[event_name] = poses[pose_idx]
                else:
                    key_poses[event_name] = None
            else:
                key_poses[event_name] = None
        
        logger.info("Calculating metrics...")
        metrics_calculator = MetricsCalculator(
            frame_width=video_info.get("width", 1920),
            frame_height=video_info.get("height", 1080)
        )
        metrics = metrics_calculator.calculate_metrics(
            key_poses, events, vantage=request.vantage.value
        )
        
        logger.info("Generating coaching feedback...")
        coach = SwingCoach(use_llm=True)
        feedback = coach.generate_feedback(metrics, events, vantage=request.vantage.value)
        
        events_response = SwingEventsResponse(
            address=_event_to_response(events.address),
            top=_event_to_response(events.top),
            impact=_event_to_response(events.impact),
            finish=_event_to_response(events.finish)
        )
        
        drill_links = [
            DrillLink(
                id=d.id,
                title=d.title,
                description=d.description,
                url=d.url,
                platform=d.platform
            )
            for d in feedback.drills
        ]
        
        result = AnalysisResult(
            swing_id=swing_id,
            summary=feedback.summary,
            diagnosis=feedback.diagnosis,
            events=events_response,
            metrics=metrics.to_dict(),
            metrics_display=metrics.to_display_dict(),
            key_issues=feedback.key_issues,
            positives=feedback.positives,
            drill_links=drill_links,
            video_info=video_info
        )
        
        logger.info(f"Analysis complete for {request.video_key} (swing_id={swing_id})")
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        logger.exception(f"Analysis failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


def _event_to_response(event) -> Optional[SwingEventData]:
    """Convert SwingEvent to response model."""
    if event is None:
        return None
    return SwingEventData(
        frame=event.frame_index,
        timestamp=event.timestamp,
        confidence=event.confidence
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
