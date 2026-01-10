"""
3D Body Pose Detection using SAM 3D Body (Meta).

Provides true 3D joint positions for accurate golf swing analysis,
unlike MediaPipe which only provides pseudo-3D from 2D inference.
"""

import sys
import logging
from pathlib import Path
from typing import Optional, Dict, List, Any
from dataclasses import dataclass, field
import numpy as np

logger = logging.getLogger(__name__)

# Add sam_3d_body to path
_BACKEND_DIR = Path(__file__).parent.parent
_SAM3D_PATH = _BACKEND_DIR / "sam_3d_body"
if str(_SAM3D_PATH) not in sys.path:
    sys.path.insert(0, str(_SAM3D_PATH))

# Check availability
SAM3D_AVAILABLE = False
try:
    import torch
    from sam_3d_body.build_models import load_sam_3d_body
    from sam_3d_body.sam_3d_body_estimator import SAM3DBodyEstimator
    SAM3D_AVAILABLE = True
except ImportError as e:
    logger.warning(f"SAM 3D Body not available: {e}")


# MHR70 joint indices for golf-relevant keypoints
class MHR70Joints:
    """MHR70 skeleton joint indices."""
    # Head/Face
    NOSE = 0
    LEFT_EYE = 1
    RIGHT_EYE = 2
    LEFT_EAR = 3
    RIGHT_EAR = 4
    
    # Upper body
    LEFT_SHOULDER = 5
    RIGHT_SHOULDER = 6
    LEFT_ELBOW = 7
    RIGHT_ELBOW = 8
    NECK = 69
    LEFT_ACROMION = 67  # Top of shoulder
    RIGHT_ACROMION = 68
    
    # Lower body
    LEFT_HIP = 9
    RIGHT_HIP = 10
    LEFT_KNEE = 11
    RIGHT_KNEE = 12
    LEFT_ANKLE = 13
    RIGHT_ANKLE = 14
    
    # Feet
    LEFT_BIG_TOE = 15
    LEFT_SMALL_TOE = 16
    LEFT_HEEL = 17
    RIGHT_BIG_TOE = 18
    RIGHT_SMALL_TOE = 19
    RIGHT_HEEL = 20
    
    # Wrists (important for club tracking)
    RIGHT_WRIST = 41
    LEFT_WRIST = 62
    
    # Elbows (anatomy points)
    LEFT_OLECRANON = 63  # Back of elbow
    RIGHT_OLECRANON = 64
    LEFT_CUBITAL_FOSSA = 65  # Inside elbow
    RIGHT_CUBITAL_FOSSA = 66


# Golf-specific joint groups
GOLF_JOINTS = {
    'shoulders': [MHR70Joints.LEFT_SHOULDER, MHR70Joints.RIGHT_SHOULDER],
    'hips': [MHR70Joints.LEFT_HIP, MHR70Joints.RIGHT_HIP],
    'wrists': [MHR70Joints.LEFT_WRIST, MHR70Joints.RIGHT_WRIST],
    'elbows': [MHR70Joints.LEFT_ELBOW, MHR70Joints.RIGHT_ELBOW],
    'spine': [MHR70Joints.NECK],
    'feet': [MHR70Joints.LEFT_ANKLE, MHR70Joints.RIGHT_ANKLE],
}


@dataclass
class Keypoint3D:
    """A single 3D body keypoint."""
    x: float  # meters, camera coordinate system
    y: float
    z: float
    name: str
    confidence: float = 1.0
    
    def to_array(self) -> np.ndarray:
        return np.array([self.x, self.y, self.z])


@dataclass 
class Pose3DResult:
    """3D pose detection result for a single frame."""
    keypoints_3d: Dict[str, Keypoint3D]  # 70 MHR keypoints
    keypoints_2d: Dict[str, tuple]  # 2D projections (x, y in pixels)
    frame_index: int
    bbox: np.ndarray  # Detection bounding box
    focal_length: float
    camera_translation: np.ndarray  # Camera translation vector
    
    # Raw outputs for advanced use
    vertices: Optional[np.ndarray] = None  # Full mesh vertices
    joint_coords: Optional[np.ndarray] = None  # Joint coordinates
    global_rotations: Optional[np.ndarray] = None  # Per-joint rotation matrices
    
    def get_joint(self, name: str) -> Optional[Keypoint3D]:
        """Get a keypoint by name."""
        return self.keypoints_3d.get(name)
    
    def get_shoulder_line(self) -> tuple:
        """Get 3D shoulder line (left_shoulder, right_shoulder)."""
        left = self.keypoints_3d.get('left_shoulder')
        right = self.keypoints_3d.get('right_shoulder')
        if left and right:
            return (left.to_array(), right.to_array())
        return None
    
    def get_hip_line(self) -> tuple:
        """Get 3D hip line (left_hip, right_hip)."""
        left = self.keypoints_3d.get('left_hip')
        right = self.keypoints_3d.get('right_hip')
        if left and right:
            return (left.to_array(), right.to_array())
        return None


# MHR70 joint names (for indexing)
MHR70_NAMES = [
    "nose", "left_eye", "right_eye", "left_ear", "right_ear",
    "left_shoulder", "right_shoulder", "left_elbow", "right_elbow",
    "left_hip", "right_hip", "left_knee", "right_knee",
    "left_ankle", "right_ankle",
    "left_big_toe", "left_small_toe", "left_heel",
    "right_big_toe", "right_small_toe", "right_heel",
    # Right hand (21-41)
    "right_thumb_tip", "right_thumb_first", "right_thumb_second", "right_thumb_third",
    "right_index_tip", "right_index_first", "right_index_second", "right_index_third",
    "right_middle_tip", "right_middle_first", "right_middle_second", "right_middle_third",
    "right_ring_tip", "right_ring_first", "right_ring_second", "right_ring_third",
    "right_pinky_tip", "right_pinky_first", "right_pinky_second", "right_pinky_third",
    "right_wrist",
    # Left hand (42-62)
    "left_thumb_tip", "left_thumb_first", "left_thumb_second", "left_thumb_third",
    "left_index_tip", "left_index_first", "left_index_second", "left_index_third",
    "left_middle_tip", "left_middle_first", "left_middle_second", "left_middle_third",
    "left_ring_tip", "left_ring_first", "left_ring_second", "left_ring_third",
    "left_pinky_tip", "left_pinky_first", "left_pinky_second", "left_pinky_third",
    "left_wrist",
    # Extra points (63-69)
    "left_olecranon", "right_olecranon",
    "left_cubital_fossa", "right_cubital_fossa",
    "left_acromion", "right_acromion",
    "neck",
]


def get_default_checkpoint_path() -> tuple:
    """Get paths to default SAM 3D Body checkpoint files."""
    model_dir = _BACKEND_DIR / "models" / "sam-3d-body-dinov3"
    checkpoint = model_dir / "model.ckpt"
    mhr_model = model_dir / "assets" / "mhr_model.pt"
    
    if not checkpoint.exists():
        raise FileNotFoundError(
            f"SAM 3D Body checkpoint not found at {checkpoint}.\n"
            "Download with: huggingface-cli download facebook/sam-3d-body-dinov3 "
            "--local-dir backend/models/sam-3d-body-dinov3"
        )
    
    return str(checkpoint), str(mhr_model)


class Body3DDetector:
    """
    3D body pose detector using SAM 3D Body.
    
    Provides true 3D joint positions in camera coordinates.
    Falls back to MediaPipe if SAM 3D Body is unavailable.
    """
    
    def __init__(
        self,
        checkpoint_path: Optional[str] = None,
        mhr_path: Optional[str] = None,
        device: Optional[str] = None,
    ):
        """
        Initialize the 3D body detector.
        
        Args:
            checkpoint_path: Path to model.ckpt
            mhr_path: Path to mhr_model.pt
            device: Device to use ('cuda', 'mps', 'cpu', or None for auto)
        """
        if not SAM3D_AVAILABLE:
            raise RuntimeError(
                "SAM 3D Body not available. Install dependencies with:\n"
                "pip install -r requirements-3d.txt"
            )
        
        # Get default paths if not provided
        if checkpoint_path is None or mhr_path is None:
            default_ckpt, default_mhr = get_default_checkpoint_path()
            checkpoint_path = checkpoint_path or default_ckpt
            mhr_path = mhr_path or default_mhr
        
        # Auto-detect device
        if device is None:
            if torch.cuda.is_available():
                device = "cuda"
            elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
                device = "mps"
            else:
                device = "cpu"
        
        self.device = device
        logger.info(f"Loading SAM 3D Body on device: {device}")
        
        # Load model
        self.model, self.cfg = load_sam_3d_body(
            checkpoint_path=checkpoint_path,
            device=device,
            mhr_path=mhr_path,
        )
        
        # Create estimator (handles preprocessing)
        self.estimator = SAM3DBodyEstimator(
            sam_3d_body_model=self.model,
            model_cfg=self.cfg,
            human_detector=None,  # We'll provide bboxes
            human_segmentor=None,
            fov_estimator=None,
        )
        
        logger.info("SAM 3D Body model loaded successfully")
    
    def detect(
        self,
        image: np.ndarray,
        bbox: Optional[np.ndarray] = None,
        frame_index: int = 0,
    ) -> Optional[Pose3DResult]:
        """
        Detect 3D body pose in an image.
        
        Args:
            image: RGB image as numpy array (H, W, 3)
            bbox: Optional bounding box [x1, y1, x2, y2]. If None, uses full image.
            frame_index: Frame index for tracking
            
        Returns:
            Pose3DResult or None if no person detected
        """
        height, width = image.shape[:2]
        
        # Default bbox is full image
        if bbox is None:
            bbox = np.array([[0, 0, width, height]])
        else:
            bbox = np.array(bbox).reshape(-1, 4)
        
        # Run inference
        outputs = self.estimator.process_one_image(
            img=image,
            bboxes=bbox,
            inference_type="body",  # Full body, no separate hand inference
        )
        
        if not outputs:
            return None
        
        # Take first detection
        out = outputs[0]
        
        # Build keypoints dict
        keypoints_3d = {}
        keypoints_2d = {}
        
        kp3d = out['pred_keypoints_3d']  # (70, 3)
        kp2d = out['pred_keypoints_2d']  # (70, 2)
        
        for i, name in enumerate(MHR70_NAMES):
            keypoints_3d[name] = Keypoint3D(
                x=float(kp3d[i, 0]),
                y=float(kp3d[i, 1]),
                z=float(kp3d[i, 2]),
                name=name,
            )
            keypoints_2d[name] = (float(kp2d[i, 0]), float(kp2d[i, 1]))
        
        return Pose3DResult(
            keypoints_3d=keypoints_3d,
            keypoints_2d=keypoints_2d,
            frame_index=frame_index,
            bbox=out['bbox'],
            focal_length=float(out['focal_length']),
            camera_translation=out['pred_cam_t'],
            vertices=out.get('pred_vertices'),
            joint_coords=out.get('pred_joint_coords'),
            global_rotations=out.get('pred_global_rots'),
        )
    
    def detect_batch(
        self,
        images: List[np.ndarray],
        bboxes: Optional[List[np.ndarray]] = None,
    ) -> List[Optional[Pose3DResult]]:
        """
        Detect 3D poses in multiple images.
        
        For efficiency, processes images one at a time but reuses the model.
        """
        results = []
        for i, image in enumerate(images):
            bbox = bboxes[i] if bboxes else None
            result = self.detect(image, bbox=bbox, frame_index=i)
            results.append(result)
        return results
    
    def __enter__(self):
        return self
    
    def __exit__(self, *args):
        # Clean up GPU memory
        if hasattr(self, 'model'):
            del self.model
            del self.estimator
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
