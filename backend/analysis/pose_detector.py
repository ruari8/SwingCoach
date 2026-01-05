"""
Pose detection using MediaPipe Tasks API.
Extracts 2D body keypoints from frames.
"""

import io
import os
from typing import List, Dict, Optional, Tuple, Any
from dataclasses import dataclass
from pathlib import Path
import logging
import math

logger = logging.getLogger(__name__)

MEDIAPIPE_AVAILABLE = False
mp: Any = None
mp_python: Any = None
vision: Any = None
np: Any = None
Image: Any = None

try:
    import mediapipe as mp
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision
    import numpy as np
    from PIL import Image
    MEDIAPIPE_AVAILABLE = True
except ImportError:
    logger.warning("MediaPipe not installed. Pose detection will be unavailable.")


@dataclass
class Keypoint:
    """A single body keypoint."""
    x: float
    y: float
    z: float
    visibility: float
    name: str


@dataclass
class PoseResult:
    """Pose detection result for a single frame."""
    keypoints: Dict[str, Keypoint]
    frame_index: int
    confidence: float


# MediaPipe pose landmark names (33 landmarks)
LANDMARK_NAMES = [
    "nose",
    "left_eye_inner", "left_eye", "left_eye_outer",
    "right_eye_inner", "right_eye", "right_eye_outer",
    "left_ear", "right_ear",
    "mouth_left", "mouth_right",
    "left_shoulder", "right_shoulder",
    "left_elbow", "right_elbow",
    "left_wrist", "right_wrist",
    "left_pinky", "right_pinky",
    "left_index", "right_index",
    "left_thumb", "right_thumb",
    "left_hip", "right_hip",
    "left_knee", "right_knee",
    "left_ankle", "right_ankle",
    "left_heel", "right_heel",
    "left_foot_index", "right_foot_index",
]


def get_default_model_path() -> str:
    """Get path to the default pose landmarker model."""
    # Look in models directory relative to this file
    module_dir = Path(__file__).parent.parent
    model_path = module_dir / "models" / "pose_landmarker_heavy.task"
    
    if model_path.exists():
        return str(model_path)
    
    # Try current working directory
    cwd_model = Path("models") / "pose_landmarker_heavy.task"
    if cwd_model.exists():
        return str(cwd_model)
    
    raise FileNotFoundError(
        "Pose landmarker model not found. Download it with:\n"
        "curl -L -o models/pose_landmarker_heavy.task "
        "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task"
    )


class PoseDetector:
    """Detects body pose keypoints using MediaPipe Tasks API."""
    
    def __init__(self, model_path: Optional[str] = None):
        if not MEDIAPIPE_AVAILABLE:
            raise RuntimeError("MediaPipe not installed. Run: pip install mediapipe")
        
        model_path = model_path or get_default_model_path()
        logger.info(f"Loading pose model from: {model_path}")
        
        # Create PoseLandmarker options
        base_options = mp_python.BaseOptions(model_asset_path=model_path)
        options = vision.PoseLandmarkerOptions(
            base_options=base_options,
            running_mode=vision.RunningMode.IMAGE,
            num_poses=1,
            min_pose_detection_confidence=0.5,
            min_pose_presence_confidence=0.5,
            min_tracking_confidence=0.5,
            output_segmentation_masks=False
        )
        
        self.landmarker = vision.PoseLandmarker.create_from_options(options)
    
    def detect_pose(self, frame_bytes: bytes, frame_index: int = 0) -> Optional[PoseResult]:
        """
        Detect pose in a single frame.
        
        Args:
            frame_bytes: PNG image bytes
            frame_index: Index of this frame in the video
            
        Returns:
            PoseResult or None if no pose detected
        """
        # Load image
        pil_image = Image.open(io.BytesIO(frame_bytes))
        image_np = np.array(pil_image)
        
        # Convert RGBA to RGB if needed
        if len(image_np.shape) == 3 and image_np.shape[2] == 4:
            image_np = image_np[:, :, :3]
        
        # Create MediaPipe Image
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=image_np)
        
        # Detect pose
        detection_result = self.landmarker.detect(mp_image)
        
        if not detection_result.pose_landmarks or len(detection_result.pose_landmarks) == 0:
            logger.debug(f"No pose detected in frame {frame_index}")
            return None
        
        # Get first pose (we configured for single pose)
        landmarks = detection_result.pose_landmarks[0]
        
        keypoints = {}
        total_visibility = 0.0
        
        for idx, landmark in enumerate(landmarks):
            name = LANDMARK_NAMES[idx] if idx < len(LANDMARK_NAMES) else f"landmark_{idx}"
            # Note: In Tasks API, visibility might be named 'presence' or accessed differently
            visibility = getattr(landmark, 'visibility', 0.5)
            if visibility is None:
                visibility = 0.5
            
            keypoints[name] = Keypoint(
                x=landmark.x,
                y=landmark.y,
                z=landmark.z,
                visibility=visibility,
                name=name
            )
            total_visibility += visibility
        
        avg_visibility = total_visibility / len(landmarks) if landmarks else 0.5
        
        return PoseResult(
            keypoints=keypoints,
            frame_index=frame_index,
            confidence=avg_visibility
        )
    
    def detect_poses_batch(
        self,
        frames: List[bytes],
        start_index: int = 0
    ) -> List[Optional[PoseResult]]:
        """
        Detect poses in multiple frames.
        
        Args:
            frames: List of PNG image bytes
            start_index: Starting frame index for numbering
            
        Returns:
            List of PoseResult (or None for failed detections)
        """
        results = []
        for i, frame in enumerate(frames):
            result = self.detect_pose(frame, frame_index=start_index + i)
            results.append(result)
            
            if (i + 1) % 10 == 0:
                logger.info(f"Processed {i + 1}/{len(frames)} frames")
        
        detected_count = sum(1 for r in results if r is not None)
        logger.info(f"Pose detection complete: {detected_count}/{len(frames)} frames with poses")
        
        return results
    
    def get_joint_position(
        self,
        pose: PoseResult,
        joint_name: str
    ) -> Optional[Tuple[float, float]]:
        """Get normalized (0-1) x,y position of a joint."""
        if joint_name in pose.keypoints:
            kp = pose.keypoints[joint_name]
            return (kp.x, kp.y)
        return None
    
    def get_joint_angle(
        self,
        pose: PoseResult,
        joint1: str,
        joint2: str,
        joint3: str
    ) -> Optional[float]:
        """
        Calculate angle at joint2 formed by joint1-joint2-joint3.
        
        Returns angle in degrees.
        """
        p1 = self.get_joint_position(pose, joint1)
        p2 = self.get_joint_position(pose, joint2)
        p3 = self.get_joint_position(pose, joint3)
        
        if p1 is None or p2 is None or p3 is None:
            return None
        
        v1 = (p1[0] - p2[0], p1[1] - p2[1])
        v2 = (p3[0] - p2[0], p3[1] - p2[1])
        
        dot = v1[0] * v2[0] + v1[1] * v2[1]
        mag1 = math.sqrt(v1[0]**2 + v1[1]**2)
        mag2 = math.sqrt(v2[0]**2 + v2[1]**2)
        
        if mag1 == 0 or mag2 == 0:
            return None
        
        cos_angle = max(-1, min(1, dot / (mag1 * mag2)))
        angle = math.degrees(math.acos(cos_angle))
        
        return angle
    
    def close(self):
        """Release resources."""
        if hasattr(self, 'landmarker'):
            self.landmarker.close()
    
    def __enter__(self):
        return self
    
    def __exit__(self, *args):
        self.close()
