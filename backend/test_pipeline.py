#!/usr/bin/env python3
"""
Test script for the SwingCoach analysis pipeline.
Runs the full analysis on a local video file without needing R2 or the API server.

Usage:
    python test_pipeline.py [path_to_video]
    
If no video path is provided, uses the default test video.
"""

import sys
import json
import logging
from pathlib import Path
from typing import Union

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Add parent to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from analysis import (
    FrameExtractor,
    PoseDetector,
    EventDetector,
    MetricsCalculator,
    SwingCoach,
)


def analyze_video(video_path: Union[str, Path], vantage: str = "DTL") -> dict:
    """
    Run the full analysis pipeline on a video file.
    
    Args:
        video_path: Path to video file
        vantage: "DTL" or "FO"
        
    Returns:
        Dict with analysis results
    """
    path = Path(video_path)
    if not path.exists():
        raise FileNotFoundError(f"Video not found: {path}")
    
    logger.info(f"Analyzing video: {path}")
    logger.info(f"Vantage: {vantage}")
    logger.info("-" * 50)
    
    # Step 1: Extract video info
    logger.info("Step 1: Getting video info...")
    frame_extractor = FrameExtractor()
    video_info = frame_extractor.get_video_info_from_file(path)
    logger.info(f"  Resolution: {video_info['width']}x{video_info['height']}")
    logger.info(f"  FPS: {video_info['fps']}")
    logger.info(f"  Duration: {video_info['duration']:.2f}s")
    logger.info(f"  Frame count: {video_info['frame_count']}")
    
    # Step 2: Extract frames
    fps = video_info["fps"]
    frame_count = video_info["frame_count"]
    sample_rate = max(1, frame_count // 30)  # Target ~30 frames
    
    logger.info(f"\nStep 2: Extracting frames (sample_rate={sample_rate})...")
    frames = frame_extractor.extract_from_file(
        path, 
        sample_rate=sample_rate, 
        max_frames=40
    )
    logger.info(f"  Extracted {len(frames)} frames")
    
    # Step 3: Run pose detection
    logger.info("\nStep 3: Running pose detection...")
    with PoseDetector() as pose_detector:
        poses = pose_detector.detect_poses_batch(frames)
    
    detected = sum(1 for p in poses if p is not None)
    logger.info(f"  Detected poses in {detected}/{len(frames)} frames")
    
    # Step 4: Detect swing events
    logger.info("\nStep 4: Detecting swing events...")
    event_detector = EventDetector(fps=fps / sample_rate)
    events = event_detector.detect_events(poses, vantage=vantage)
    
    logger.info(f"  Address: frame {events.address.frame_index if events.address else 'N/A'} "
                f"(t={events.address.timestamp:.2f}s)" if events.address else "  Address: Not detected")
    logger.info(f"  Top: frame {events.top.frame_index if events.top else 'N/A'} "
                f"(t={events.top.timestamp:.2f}s)" if events.top else "  Top: Not detected")
    logger.info(f"  Impact: frame {events.impact.frame_index if events.impact else 'N/A'} "
                f"(t={events.impact.timestamp:.2f}s)" if events.impact else "  Impact: Not detected")
    logger.info(f"  Finish: frame {events.finish.frame_index if events.finish else 'N/A'} "
                f"(t={events.finish.timestamp:.2f}s)" if events.finish else "  Finish: Not detected")
    
    # Step 5: Get poses at key events
    key_poses = {}
    for event_name, event in [
        ("address", events.address),
        ("top", events.top),
        ("impact", events.impact),
        ("finish", events.finish)
    ]:
        if event:
            for i, p in enumerate(poses):
                if p and p.frame_index == event.frame_index:
                    key_poses[event_name] = p
                    break
            else:
                key_poses[event_name] = None
        else:
            key_poses[event_name] = None
    
    # Step 6: Calculate metrics
    logger.info("\nStep 5: Calculating metrics...")
    metrics_calculator = MetricsCalculator(
        frame_width=video_info["width"],
        frame_height=video_info["height"]
    )
    metrics = metrics_calculator.calculate_metrics(key_poses, events, vantage=vantage)
    
    metrics_dict = metrics.to_dict()
    for name, value in metrics_dict.items():
        if value is not None:
            logger.info(f"  {name}: {value:.2f}")
    
    # Step 7: Generate coaching feedback
    logger.info("\nStep 6: Generating coaching feedback...")
    coach = SwingCoach(use_llm=False)  # Use rule-based for testing (no API key needed)
    feedback = coach.generate_feedback(metrics, events, vantage=vantage)
    
    logger.info(f"\n{'='*50}")
    logger.info("ANALYSIS RESULTS")
    logger.info(f"{'='*50}")
    logger.info(f"\nSummary: {feedback.summary}")
    logger.info(f"\nDiagnosis: {feedback.diagnosis}")
    
    if feedback.key_issues:
        logger.info(f"\nIssues identified:")
        for issue in feedback.key_issues:
            logger.info(f"  - {issue}")
    
    if feedback.positives:
        logger.info(f"\nPositives:")
        for pos in feedback.positives:
            logger.info(f"  + {pos}")
    
    if feedback.drills:
        logger.info(f"\nRecommended drills:")
        for drill in feedback.drills:
            logger.info(f"  - {drill.title}: {drill.description}")
    
    # Display formatted metrics
    logger.info(f"\nMetrics (formatted):")
    for name, value in metrics.to_display_dict().items():
        logger.info(f"  {name}: {value}")
    
    return {
        "video_info": video_info,
        "events": events.to_dict(),
        "metrics": metrics.to_dict(),
        "metrics_display": metrics.to_display_dict(),
        "feedback": {
            "summary": feedback.summary,
            "diagnosis": feedback.diagnosis,
            "key_issues": feedback.key_issues,
            "positives": feedback.positives,
            "drills": [{"id": d.id, "title": d.title, "description": d.description} for d in feedback.drills]
        }
    }


def main():
    # Default test video
    default_video = Path(__file__).parent / "swingVideos" / "IMG_0737.mov"
    
    if len(sys.argv) > 1:
        video_path = sys.argv[1]
    elif default_video.exists():
        video_path = str(default_video)
    else:
        print("Usage: python test_pipeline.py <path_to_video>")
        print(f"\nNo video found at default location: {default_video}")
        sys.exit(1)
    
    try:
        result = analyze_video(video_path, vantage="DTL")
        
        # Save results to JSON
        output_file = Path(video_path).stem + "_analysis.json"
        with open(output_file, "w") as f:
            json.dump(result, f, indent=2, default=str)
        logger.info(f"\nResults saved to: {output_file}")
        
    except Exception as e:
        logger.exception(f"Analysis failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
