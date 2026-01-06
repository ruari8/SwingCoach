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
    AnalyzeRequestWithVideo,
    FullAnalysisResult,
    AnnotatedVideoResult,
    AnnotatedVideoMetadata,
    VisualizationLayerInfo,
    VisualizationOptions,
)
from r2_client import get_r2_client

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ANALYSIS_AVAILABLE = False
SAM3_AVAILABLE = False

try:
    from analysis import (
        FrameExtractor,
        PoseDetector,
        EventDetector,
        MetricsCalculator,
        SwingCoach,
        SwingVisualizer,
        VisualizationConfig,
        VisualizationMetadata,
        LAYER_DEFINITIONS,
        ClubAnalyzer,
        SwingPathTracker,
        VideoExporter,
    )
    ANALYSIS_AVAILABLE = True
    logger.info("Analysis modules loaded successfully")
except ImportError as e:
    logger.warning(f"Analysis modules not available: {e}")
    logger.warning("Install dependencies: pip install mediapipe numpy pillow")

try:
    from analysis.equipment_tracker import EquipmentTracker
    SAM3_AVAILABLE = True
    logger.info("SAM3 equipment tracking available")
except ImportError as e:
    logger.warning(f"SAM3 not available: {e}")
    logger.warning("SAM3 needed for club tracking. See SAM3_SETUP.md")

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
        "version": "0.3.0",
        "analysis_available": ANALYSIS_AVAILABLE,
        "sam3_available": SAM3_AVAILABLE,
        "endpoints": {
            "health": "/health",
            "upload_url": "/upload-url",
            "analyze": "/analyze",
            "analyze_video": "/analyze-video"
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


@app.post("/analyze-video", response_model=FullAnalysisResult)
async def analyze_swing_with_video(request: AnalyzeRequestWithVideo):
    """
    Analyze a swing video with optional annotated video output.

    Pipeline:
    1. Download video from R2
    2. Extract frames (sampled)
    3. Run pose detection on frames
    4. Detect swing events (address, top, impact, finish)
    5. Calculate metrics at key positions
    6. Generate coaching feedback and drill recommendations
    7. (Optional) Run SAM3 club detection
    8. (Optional) Generate annotated video with overlays
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

        logger.info(f"Analyzing swing with video: {request.video_key} (vantage: {request.vantage})")

        swing_id = str(uuid.uuid4())[:8]

        # Download video
        logger.info("Downloading video from R2...")
        video_bytes = r2.download_video(request.video_key)
        logger.info(f"Downloaded {len(video_bytes) / 1024 / 1024:.1f} MB")

        # Extract frames
        frame_extractor = FrameExtractor()
        video_info = frame_extractor.get_video_info(video_bytes)
        logger.info(f"Video info: {video_info}")

        fps = request.fps or video_info.get("fps", 30.0)
        frame_count = video_info.get("frame_count", 300)

        sample_rate = max(1, frame_count // 30)
        logger.info(f"Extracting frames (sample_rate={sample_rate})...")
        frames = frame_extractor.extract_frames(video_bytes, sample_rate=sample_rate, max_frames=40)
        logger.info(f"Extracted {len(frames)} frames")

        # Pose detection
        logger.info("Running pose detection...")
        with PoseDetector() as pose_detector:
            poses = pose_detector.detect_poses_batch(frames)

        # Event detection
        logger.info("Detecting swing events...")
        event_detector = EventDetector(fps=fps / sample_rate)
        events = event_detector.detect_events(poses, vantage=request.vantage.value)

        # Get key poses
        key_poses: Dict[str, Optional[object]] = {}
        address_frame_idx = None
        for event_name, event in [
            ("address", events.address),
            ("top", events.top),
            ("impact", events.impact),
            ("finish", events.finish)
        ]:
            if event:
                if event_name == "address":
                    address_frame_idx = event.frame_index
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

        # Calculate metrics
        logger.info("Calculating metrics...")
        metrics_calculator = MetricsCalculator(
            frame_width=video_info.get("width", 1920),
            frame_height=video_info.get("height", 1080)
        )
        metrics = metrics_calculator.calculate_metrics(
            key_poses, events, vantage=request.vantage.value
        )

        # Generate coaching feedback
        logger.info("Generating coaching feedback...")
        coach = SwingCoach(use_llm=True)
        feedback = coach.generate_feedback(metrics, events, vantage=request.vantage.value)

        # Prepare base response
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

        # Optional video generation
        annotated_video_result = None
        if request.generate_video:
            annotated_video_result = await _generate_annotated_video(
                frames=frames,
                poses=poses,
                events=events,
                address_frame_idx=address_frame_idx,
                video_info=video_info,
                fps=fps / sample_rate,
                swing_id=swing_id,
                r2=r2,
                visualization_options=request.visualization
            )

        result = FullAnalysisResult(
            swing_id=swing_id,
            summary=feedback.summary,
            diagnosis=feedback.diagnosis,
            events=events_response,
            metrics=metrics.to_dict(),
            metrics_display=metrics.to_display_dict(),
            key_issues=feedback.key_issues,
            positives=feedback.positives,
            drill_links=drill_links,
            video_info=video_info,
            annotated_video=annotated_video_result
        )

        logger.info(f"Analysis complete for {request.video_key} (swing_id={swing_id})")

        return result

    except HTTPException:
        raise
    except Exception as e:
        logger.exception(f"Analysis failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


async def _generate_annotated_video(
    frames: list,
    poses: list,
    events,
    address_frame_idx: Optional[int],
    video_info: dict,
    fps: float,
    swing_id: str,
    r2,
    visualization_options: Optional[VisualizationOptions] = None
) -> Optional[AnnotatedVideoResult]:
    """Generate annotated video with visualization overlays."""
    try:
        # Get visualization config
        if visualization_options:
            vis_config = VisualizationConfig(
                draw_skeleton=visualization_options.draw_skeleton,
                draw_reference_lines=visualization_options.draw_reference_lines,
                draw_club_plane=visualization_options.draw_club_plane,
                draw_swing_path=visualization_options.draw_swing_path,
                draw_club_mask=visualization_options.draw_club_mask,
                min_visibility=visualization_options.min_visibility
            )
        else:
            vis_config = VisualizationConfig()

        frame_width = video_info.get("width", 1920)
        frame_height = video_info.get("height", 1080)

        # Initialize components
        visualizer = SwingVisualizer(frame_width=frame_width, frame_height=frame_height)
        club_analyzer = ClubAnalyzer()
        path_tracker = SwingPathTracker()

        club_plane_line = None
        swing_path = None
        club_masks = None
        club_plane_angle = None

        # Run SAM3 club detection if available and needed
        if SAM3_AVAILABLE and (vis_config.draw_club_plane or vis_config.draw_swing_path or vis_config.draw_club_mask):
            logger.info("Running SAM3 club detection...")
            try:
                with EquipmentTracker() as tracker:
                    club_detections = tracker.detect_club_batch(frames)

                    # Get club plane at address
                    if vis_config.draw_club_plane and address_frame_idx is not None:
                        # Find detection at address frame
                        address_detection = None
                        for det in club_detections:
                            if det and det.frame_index == address_frame_idx:
                                address_detection = det
                                break

                        # If exact match not found, use the closest frame's detection
                        if address_detection is None:
                            for i, det in enumerate(club_detections):
                                if det is not None:
                                    address_detection = det
                                    break

                        if address_detection and address_detection.mask is not None:
                            club_plane = club_analyzer.analyze_address_frame(
                                address_detection.mask,
                                frame_width,
                                frame_height
                            )
                            if club_plane:
                                club_plane_line = (club_plane.line_start, club_plane.line_end)
                                club_plane_angle = club_plane.angle_degrees
                                logger.info(f"Club plane angle: {club_plane_angle:.1f} degrees")

                    # Build swing path
                    if vis_config.draw_swing_path:
                        swing_path = path_tracker.build_path(
                            club_detections,
                            frame_width=frame_width,
                            frame_height=frame_height
                        )
                        logger.info(f"Swing path: {len(swing_path.points)} points")

                    # Collect masks if needed
                    if vis_config.draw_club_mask:
                        club_masks = [det.mask if det else None for det in club_detections]

            except Exception as e:
                logger.warning(f"SAM3 detection failed, continuing without club tracking: {e}")

        # Generate annotated frames
        logger.info("Generating annotated frames...")
        annotated_frames = visualizer.draw_complete_analysis_batch(
            frames=frames,
            poses=poses,
            club_plane_line=club_plane_line,
            swing_path=swing_path,
            club_masks=club_masks,
            draw_skeleton=vis_config.draw_skeleton,
            draw_reference_lines=vis_config.draw_reference_lines,
            draw_club_plane=vis_config.draw_club_plane,
            draw_swing_path=vis_config.draw_swing_path,
            draw_club_mask=vis_config.draw_club_mask,
            min_visibility=vis_config.min_visibility
        )

        # Export to video
        logger.info("Exporting video...")
        video_exporter = VideoExporter()
        video_bytes = video_exporter.export_video(annotated_frames, fps)

        # Upload to R2
        annotated_key = f"annotated/{swing_id}.mp4"
        logger.info(f"Uploading annotated video to R2: {annotated_key}")
        r2.upload_video(annotated_key, video_bytes)

        # Generate download URL
        video_url = r2.generate_download_url(annotated_key)

        # Build metadata
        layers = []
        if vis_config.draw_skeleton:
            layer_def = LAYER_DEFINITIONS["skeleton"]
            layers.append(VisualizationLayerInfo(
                name=layer_def.name,
                color=layer_def.color,
                description=layer_def.description,
                enabled=True
            ))
        if vis_config.draw_reference_lines:
            layer_def = LAYER_DEFINITIONS["reference_lines"]
            layers.append(VisualizationLayerInfo(
                name=layer_def.name,
                color=layer_def.color,
                description=layer_def.description,
                enabled=True
            ))
        if vis_config.draw_club_plane and club_plane_line:
            layer_def = LAYER_DEFINITIONS["club_plane"]
            layers.append(VisualizationLayerInfo(
                name=layer_def.name,
                color=layer_def.color,
                description=layer_def.description,
                enabled=True
            ))
        if vis_config.draw_swing_path and swing_path:
            layer_def = LAYER_DEFINITIONS["swing_path"]
            layers.append(VisualizationLayerInfo(
                name=layer_def.name,
                color=layer_def.color,
                description=layer_def.description,
                enabled=True
            ))
        if vis_config.draw_club_mask:
            layer_def = LAYER_DEFINITIONS["club_mask"]
            layers.append(VisualizationLayerInfo(
                name=layer_def.name,
                color=layer_def.color,
                description=layer_def.description,
                enabled=True
            ))

        metadata = AnnotatedVideoMetadata(
            layers=layers,
            club_plane_angle_degrees=club_plane_angle,
            swing_path_point_count=len(swing_path.points) if swing_path else 0,
            video_fps=fps,
            frame_count=len(annotated_frames)
        )

        return AnnotatedVideoResult(
            video_url=video_url,
            video_key=annotated_key,
            metadata=metadata
        )

    except Exception as e:
        logger.error(f"Failed to generate annotated video: {e}")
        import traceback
        traceback.print_exc()
        return None


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
