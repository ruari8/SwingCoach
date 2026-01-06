"""
Golf equipment tracking using SAM3 (Segment Anything Model 3).
Detects and tracks golf club and ball in video frames using point/box prompts.

Model Loading Options:
    1. HuggingFace cache (default): Loads from ~/.cache/huggingface/
    2. Local path: Set SAM3_MODEL_PATH env var, or pass model_path to EquipmentTracker
    
    Example:
        # Option 1: HuggingFace cache
        tracker = EquipmentTracker()
        
        # Option 2: Local path via env var
        export SAM3_MODEL_PATH=/path/to/backend/models/sam3
        tracker = EquipmentTracker()
        
        # Option 3: Local path via argument
        tracker = EquipmentTracker(model_path="backend/models/sam3")
"""

import io
import os
from typing import List, Dict, Optional, Tuple, Any
from dataclasses import dataclass
from pathlib import Path
import logging

logger = logging.getLogger(__name__)

# Environment variable for local model path (optional)
SAM3_MODEL_PATH_ENV = "SAM3_MODEL_PATH"

# Lazy imports for optional SAM3 dependency
SAM3_AVAILABLE = False
torch: Any = None
np: Any = None
Image: Any = None
build_sam3_image_model: Any = None
Sam3Processor: Any = None


def _init_sam3():
    """Lazy initialization of SAM3 dependencies."""
    global SAM3_AVAILABLE, torch, np, Image, build_sam3_image_model, Sam3Processor

    if SAM3_AVAILABLE:
        return True

    try:
        import torch as _torch
        import numpy as _np
        from PIL import Image as _Image
        from sam3.model_builder import build_sam3_image_model as _build
        from sam3.model.sam3_image_processor import Sam3Processor as _Processor

        torch = _torch
        np = _np
        Image = _Image
        build_sam3_image_model = _build
        Sam3Processor = _Processor
        SAM3_AVAILABLE = True
        return True
    except ImportError as e:
        logger.warning(f"SAM3 not available: {e}")
        return False


@dataclass
class ClubDetection:
    """Detection result for golf club in a single frame."""
    mask: Any  # np.ndarray - Binary mask of club
    centroid: Tuple[float, float]  # Center of club mask (normalized 0-1)
    bbox: Tuple[int, int, int, int]  # Bounding box (x1, y1, x2, y2) in pixels
    confidence: float  # Detection confidence
    frame_index: int  # Which frame this is from


@dataclass
class ShaftDetection:
    """Detection result for club shaft in a single frame."""
    mask: Any  # np.ndarray - Binary mask of shaft
    confidence: float  # Detection confidence
    frame_index: int  # Which frame this is from


@dataclass
class ClubheadDetection:
    """Detection result for clubhead in a single frame."""
    mask: Any  # np.ndarray - Binary mask of clubhead
    centroid: Tuple[float, float]  # Center of clubhead (normalized 0-1)
    centroid_pixels: Tuple[int, int]  # Center in pixel coordinates
    confidence: float  # Detection confidence
    frame_index: int  # Which frame this is from


@dataclass
class BallDetection:
    """Detection result for golf ball in a single frame."""
    mask: Any  # np.ndarray - Binary mask of ball
    centroid: Tuple[float, float]  # Center of ball (normalized 0-1)
    bbox: Tuple[int, int, int, int]  # Bounding box (x1, y1, x2, y2) in pixels
    confidence: float  # Detection confidence
    frame_index: int  # Which frame this is from


def get_device() -> str:
    """Auto-detect best available device."""
    if not _init_sam3():
        return "cpu"

    if torch.backends.mps.is_available():
        return "mps"
    elif torch.cuda.is_available():
        return "cuda"
    return "cpu"


class EquipmentTracker:
    """Tracks golf equipment (club, ball) using SAM3 with point/box prompts."""

    def __init__(
        self,
        device: Optional[str] = None,
        confidence_threshold: float = 0.3,
        model_path: Optional[str] = None
    ):
        """
        Initialize the equipment tracker.

        Args:
            device: Device to use ('mps', 'cuda', 'cpu'). Auto-detected if None.
            confidence_threshold: Minimum confidence to accept a detection.
            model_path: Path to local SAM3 model directory. If None, checks 
                        SAM3_MODEL_PATH env var, then falls back to HuggingFace 
                        cache (~/.cache/huggingface/).
        """
        if not _init_sam3():
            raise RuntimeError(
                "SAM3 not installed or not available. "
                "Run: pip install 'git+https://github.com/facebookresearch/sam3.git' "
                "Then: python patch_sam3.py"
            )

        self.device = device or get_device()
        self.confidence_threshold = confidence_threshold

        # Check for env var if no explicit path provided
        if model_path is None:
            model_path = os.environ.get(SAM3_MODEL_PATH_ENV)

        logger.info(f"Initializing EquipmentTracker on device: {self.device}")

        # Build SAM3 model
        if model_path:
            # Load from local path (e.g., backend/models/sam3/)
            model_path = Path(model_path)
            if not model_path.exists():
                raise FileNotFoundError(
                    f"SAM3 model not found at: {model_path}\n"
                    "Either download the model to this location, or set model_path=None "
                    "to use HuggingFace cache (~/.cache/huggingface/)."
                )
            logger.info(f"Loading SAM3 model from local path: {model_path}")
            self.model = build_sam3_image_model(
                device=self.device,
                load_from_HF=False,
                ckpt_path=str(model_path / "sam3.pt") if (model_path / "sam3.pt").exists() else str(model_path)
            )
        else:
            # Load from HuggingFace cache (default)
            logger.info("Loading SAM3 model from HuggingFace cache...")
            self.model = build_sam3_image_model(
                device=self.device,
                load_from_HF=True
            )

        # Create processor for text-prompted segmentation
        self.processor = Sam3Processor(self.model)

        logger.info("EquipmentTracker initialized successfully")

    def _bytes_to_pil(self, frame_bytes: bytes) -> Any:
        """Convert frame bytes to PIL Image."""
        return Image.open(io.BytesIO(frame_bytes)).convert("RGB")

    def _mask_to_bbox(self, mask: Any) -> Tuple[int, int, int, int]:
        """Convert binary mask to bounding box."""
        if hasattr(mask, 'cpu'):
            mask = mask.cpu().numpy()

        if len(mask.shape) > 2:
            mask = mask.squeeze()

        rows = np.any(mask, axis=1)
        cols = np.any(mask, axis=0)

        if not np.any(rows) or not np.any(cols):
            return (0, 0, 0, 0)

        y_min, y_max = np.where(rows)[0][[0, -1]]
        x_min, x_max = np.where(cols)[0][[0, -1]]

        return (int(x_min), int(y_min), int(x_max), int(y_max))

    def _mask_centroid(self, mask: Any, width: int, height: int) -> Tuple[float, float]:
        """Calculate normalized centroid of mask."""
        if hasattr(mask, 'cpu'):
            mask = mask.cpu().numpy()

        if len(mask.shape) > 2:
            mask = mask.squeeze()

        coords = np.argwhere(mask)
        if len(coords) == 0:
            return (0.5, 0.5)

        y_center = coords[:, 0].mean()
        x_center = coords[:, 1].mean()

        # Normalize to 0-1
        return (x_center / width, y_center / height)

    def detect_club(
        self,
        frame_bytes: bytes,
        frame_index: int = 0
    ) -> Optional[ClubDetection]:
        """
        Detect golf club in a single frame using text prompt.

        Args:
            frame_bytes: PNG/JPG image bytes
            frame_index: Index of this frame in the video

        Returns:
            ClubDetection or None if no club detected
        """
        try:
            image = self._bytes_to_pil(frame_bytes)
            width, height = image.size

            # Set image and run text-prompted segmentation
            inference_state = self.processor.set_image(image)
            output = self.processor.set_text_prompt(
                state=inference_state,
                prompt="golf club"
            )

            masks = output.get("masks", [])
            scores = output.get("scores", [])
            boxes = output.get("boxes", [])

            if len(masks) == 0:
                logger.debug(f"No club detected in frame {frame_index}")
                return None

            # Get best detection
            best_idx = 0
            if len(scores) > 0:
                if hasattr(scores, 'cpu'):
                    scores_np = scores.cpu().numpy()
                else:
                    scores_np = np.array(scores)
                best_idx = int(np.argmax(scores_np))

            mask = masks[best_idx]
            confidence = float(scores_np[best_idx]) if len(scores_np) > best_idx else 0.5

            if confidence < self.confidence_threshold:
                logger.debug(f"Club detection below threshold in frame {frame_index}: {confidence:.2f}")
                return None

            # Convert mask to numpy if needed
            if hasattr(mask, 'cpu'):
                mask = mask.cpu().numpy()

            # Ensure 2D mask
            if len(mask.shape) > 2:
                mask = mask.squeeze()

            bbox = self._mask_to_bbox(mask)
            centroid = self._mask_centroid(mask, width, height)

            return ClubDetection(
                mask=mask,
                centroid=centroid,
                bbox=bbox,
                confidence=confidence,
                frame_index=frame_index
            )

        except Exception as e:
            logger.error(f"Error detecting club in frame {frame_index}: {e}")
            import traceback
            traceback.print_exc()
            return None

    def detect_ball(
        self,
        frame_bytes: bytes,
        frame_index: int = 0
    ) -> Optional[BallDetection]:
        """
        Detect golf ball in a single frame using text prompt.

        Args:
            frame_bytes: PNG/JPG image bytes
            frame_index: Index of this frame in the video

        Returns:
            BallDetection or None if no ball detected
        """
        try:
            image = self._bytes_to_pil(frame_bytes)
            width, height = image.size

            # Set image and run text-prompted segmentation
            inference_state = self.processor.set_image(image)
            output = self.processor.set_text_prompt(
                state=inference_state,
                prompt="golf ball"
            )

            masks = output.get("masks", [])
            scores = output.get("scores", [])

            if len(masks) == 0:
                logger.debug(f"No ball detected in frame {frame_index}")
                return None

            # Get best detection
            best_idx = 0
            if len(scores) > 0:
                if hasattr(scores, 'cpu'):
                    scores_np = scores.cpu().numpy()
                else:
                    scores_np = np.array(scores)
                best_idx = int(np.argmax(scores_np))

            mask = masks[best_idx]
            confidence = float(scores_np[best_idx]) if len(scores_np) > best_idx else 0.5

            if confidence < self.confidence_threshold:
                return None

            if hasattr(mask, 'cpu'):
                mask = mask.cpu().numpy()

            if len(mask.shape) > 2:
                mask = mask.squeeze()

            bbox = self._mask_to_bbox(mask)
            centroid = self._mask_centroid(mask, width, height)

            return BallDetection(
                mask=mask,
                centroid=centroid,
                bbox=bbox,
                confidence=confidence,
                frame_index=frame_index
            )

        except Exception as e:
            logger.error(f"Error detecting ball in frame {frame_index}: {e}")
            return None

    def detect_club_batch(
        self,
        frames: List[bytes],
        start_index: int = 0
    ) -> List[Optional[ClubDetection]]:
        """
        Detect golf club in multiple frames.

        Args:
            frames: List of PNG/JPG image bytes
            start_index: Starting frame index for numbering

        Returns:
            List of ClubDetection (or None for failed detections)
        """
        results = []
        for i, frame in enumerate(frames):
            result = self.detect_club(frame, frame_index=start_index + i)
            results.append(result)

            if (i + 1) % 5 == 0:
                logger.info(f"Club detection: {i + 1}/{len(frames)} frames processed")

        detected_count = sum(1 for r in results if r is not None)
        logger.info(f"Club detection complete: {detected_count}/{len(frames)} frames with club")

        return results

    def detect_shaft(
        self,
        frame_bytes: bytes,
        frame_index: int = 0
    ) -> Optional[ShaftDetection]:
        """
        Detect club shaft in a single frame using text prompt "club shaft".

        Use this for calculating the club plane line.

        Args:
            frame_bytes: PNG/JPG image bytes
            frame_index: Index of this frame in the video

        Returns:
            ShaftDetection or None if no shaft detected
        """
        try:
            image = self._bytes_to_pil(frame_bytes)

            inference_state = self.processor.set_image(image)
            output = self.processor.set_text_prompt(
                state=inference_state,
                prompt="club shaft"
            )

            masks = output.get("masks", [])
            scores = output.get("scores", [])

            if len(masks) == 0:
                logger.debug(f"No shaft detected in frame {frame_index}")
                return None

            # Get best detection
            best_idx = 0
            if len(scores) > 0:
                if hasattr(scores, 'cpu'):
                    scores_np = scores.cpu().numpy()
                else:
                    scores_np = np.array(scores)
                best_idx = int(np.argmax(scores_np))

            mask = masks[best_idx]
            confidence = float(scores_np[best_idx]) if len(scores_np) > best_idx else 0.5

            if confidence < self.confidence_threshold:
                logger.debug(f"Shaft detection below threshold: {confidence:.2f}")
                return None

            if hasattr(mask, 'cpu'):
                mask = mask.cpu().numpy()

            if len(mask.shape) > 2:
                mask = mask.squeeze()

            return ShaftDetection(
                mask=mask,
                confidence=confidence,
                frame_index=frame_index
            )

        except Exception as e:
            logger.error(f"Error detecting shaft in frame {frame_index}: {e}")
            return None

    def detect_clubhead(
        self,
        frame_bytes: bytes,
        frame_index: int = 0
    ) -> Optional[ClubheadDetection]:
        """
        Detect clubhead in a single frame using text prompt "clubhead".

        Use this for tracking the clubhead path through the swing.

        Args:
            frame_bytes: PNG/JPG image bytes
            frame_index: Index of this frame in the video

        Returns:
            ClubheadDetection or None if no clubhead detected
        """
        try:
            image = self._bytes_to_pil(frame_bytes)
            width, height = image.size

            inference_state = self.processor.set_image(image)
            output = self.processor.set_text_prompt(
                state=inference_state,
                prompt="clubhead"
            )

            masks = output.get("masks", [])
            scores = output.get("scores", [])

            if len(masks) == 0:
                logger.debug(f"No clubhead detected in frame {frame_index}")
                return None

            # Get best detection
            best_idx = 0
            if len(scores) > 0:
                if hasattr(scores, 'cpu'):
                    scores_np = scores.cpu().numpy()
                else:
                    scores_np = np.array(scores)
                best_idx = int(np.argmax(scores_np))

            mask = masks[best_idx]
            confidence = float(scores_np[best_idx]) if len(scores_np) > best_idx else 0.5

            if confidence < self.confidence_threshold:
                logger.debug(f"Clubhead detection below threshold: {confidence:.2f}")
                return None

            if hasattr(mask, 'cpu'):
                mask = mask.cpu().numpy()

            if len(mask.shape) > 2:
                mask = mask.squeeze()

            # Calculate centroid
            centroid_norm = self._mask_centroid(mask, width, height)
            coords = np.argwhere(mask > 0)
            if len(coords) > 0:
                centroid_px = (int(coords[:, 1].mean()), int(coords[:, 0].mean()))
            else:
                centroid_px = (width // 2, height // 2)

            return ClubheadDetection(
                mask=mask,
                centroid=centroid_norm,
                centroid_pixels=centroid_px,
                confidence=confidence,
                frame_index=frame_index
            )

        except Exception as e:
            logger.error(f"Error detecting clubhead in frame {frame_index}: {e}")
            return None

    def detect_clubhead_batch(
        self,
        frames: List[bytes],
        start_index: int = 0
    ) -> List[Optional[ClubheadDetection]]:
        """
        Detect clubhead in multiple frames.

        Args:
            frames: List of PNG/JPG image bytes
            start_index: Starting frame index for numbering

        Returns:
            List of ClubheadDetection (or None for failed detections)
        """
        results = []
        for i, frame in enumerate(frames):
            result = self.detect_clubhead(frame, frame_index=start_index + i)
            results.append(result)

            if (i + 1) % 5 == 0:
                logger.info(f"Clubhead detection: {i + 1}/{len(frames)} frames processed")

        detected_count = sum(1 for r in results if r is not None)
        logger.info(f"Clubhead detection complete: {detected_count}/{len(frames)} frames with clubhead")

        return results

    def close(self):
        """Release resources."""
        if hasattr(self, 'processor'):
            del self.processor
        if hasattr(self, 'model'):
            del self.model

        # Clear CUDA/MPS cache
        if torch is not None:
            if torch.cuda.is_available():
                torch.cuda.empty_cache()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()
