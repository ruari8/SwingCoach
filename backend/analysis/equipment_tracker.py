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
import sys
from contextlib import redirect_stdout
from typing import List, Dict, Optional, Tuple, Any
from dataclasses import dataclass
from pathlib import Path
import logging

logger = logging.getLogger(__name__)

# Environment variable for local model path (optional)
SAM3_MODEL_PATH_ENV = "SAM3_MODEL_PATH"
SAM3_RUNTIME_ENV = "SAM3_RUNTIME"
MLX_SAM3_REPO_ENV = "MLX_SAM3_REPO"
MLX_SAM3_WEIGHTS_DIR_ENV = "MLX_SAM3_WEIGHTS_DIR"
MLX_SAM3_MAX_SIDE_ENV = "MLX_SAM3_MAX_SIDE"

# Default local model path relative to backend directory
DEFAULT_LOCAL_MODEL_PATH = Path(__file__).parent.parent / "models" / "models--facebook--sam3"
DEFAULT_MLX_REPO_PATH = Path(__file__).resolve().parents[2] / "detector_model" / "mlx_sam3"

# Lazy imports for optional SAM3 dependency
SAM3_AVAILABLE = False
MLX_SAM3_AVAILABLE = False
MLX_SAM3_IMPORT_ATTEMPTED = False
torch: Any = None
np: Any = None
Image: Any = None
build_sam3_image_model: Any = None
Sam3Processor: Any = None
mlx_build_sam3_image_model: Any = None
MlxSam3Processor: Any = None
mx: Any = None


def _init_torch_sam3():
    """Lazy initialization of the Meta PyTorch SAM3 dependency."""
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


def _remove_sam3_modules() -> None:
    """Remove cached sam3 modules so the chosen runtime can own the package name."""
    for name in list(sys.modules):
        if name == "sam3" or name.startswith("sam3."):
            del sys.modules[name]


def _init_mlx_sam3(repo_path: Optional[Path] = None):
    """Lazy initialization of the MLX SAM3 image runtime."""
    global MLX_SAM3_AVAILABLE, MLX_SAM3_IMPORT_ATTEMPTED
    global np, Image, mlx_build_sam3_image_model, MlxSam3Processor, mx

    if MLX_SAM3_AVAILABLE:
        return True
    if MLX_SAM3_IMPORT_ATTEMPTED:
        return False

    MLX_SAM3_IMPORT_ATTEMPTED = True
    resolved_repo = Path(
        os.environ.get(MLX_SAM3_REPO_ENV)
        or repo_path
        or DEFAULT_MLX_REPO_PATH
    ).resolve()
    if not resolved_repo.exists():
        logger.info("MLX SAM3 repo not found at %s", resolved_repo)
        return False

    repo_str = str(resolved_repo)
    added_to_path = False
    if repo_str not in sys.path:
        sys.path.insert(0, repo_str)
        added_to_path = True

    existing = sys.modules.get("sam3")
    if existing is not None:
        existing_file = Path(getattr(existing, "__file__", "")).resolve()
        if repo_str not in str(existing_file):
            _remove_sam3_modules()

    try:
        import numpy as _np
        from PIL import Image as _Image
        import mlx.core as _mx
        from sam3 import build_sam3_image_model as _mlx_build
        from sam3.model.sam3_image_processor import Sam3Processor as _MlxProcessor

        module_file = Path(sys.modules["sam3"].__file__).resolve()
        if repo_str not in str(module_file):
            raise ImportError(f"sam3 resolved to {module_file}, not MLX repo {resolved_repo}")

        np = _np
        Image = _Image
        mx = _mx
        mlx_build_sam3_image_model = _mlx_build
        MlxSam3Processor = _MlxProcessor
        MLX_SAM3_AVAILABLE = True
        return True
    except Exception as e:
        logger.warning("MLX SAM3 not available: %s", e)
        if added_to_path:
            try:
                sys.path.remove(repo_str)
            except ValueError:
                pass
        _remove_sam3_modules()
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
    if not _init_torch_sam3():
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
        model_path: Optional[str] = None,
        runtime: Optional[str] = None,
        mlx_repo_path: Optional[str] = None,
        mlx_max_side: Optional[int] = None,
    ):
        """
        Initialize the equipment tracker.

        Args:
            device: Device to use ('mps', 'cuda', 'cpu'). Auto-detected if None.
            confidence_threshold: Minimum confidence to accept a detection.
            model_path: Path to local SAM3 model directory. If None, checks 
                        SAM3_MODEL_PATH env var, then falls back to HuggingFace 
                        cache (~/.cache/huggingface/).
            runtime: 'auto', 'mlx', or 'torch'. Auto prefers MLX when available.
            mlx_repo_path: Optional path to the local MLX SAM3 repo.
            mlx_max_side: Resize longest image side before MLX inference for speed.
        """
        requested_runtime = (runtime or os.environ.get(SAM3_RUNTIME_ENV) or "auto").lower()
        self.confidence_threshold = confidence_threshold
        self.runtime_name = self._select_runtime(requested_runtime, mlx_repo_path)

        if self.runtime_name == "mlx":
            self.device = "mlx"
            self.mlx_max_side = int(
                mlx_max_side
                or os.environ.get(MLX_SAM3_MAX_SIDE_ENV)
                or 960
            )
            weights_dir = os.environ.get(MLX_SAM3_WEIGHTS_DIR_ENV)
            logger.info(
                "Initializing EquipmentTracker with MLX SAM3 runtime (max_side=%s)",
                self.mlx_max_side,
            )
            self.model = mlx_build_sam3_image_model(
                local_weights_dir=weights_dir,
            )
            self.processor = MlxSam3Processor(
                self.model,
                confidence_threshold=self.confidence_threshold,
            )
            logger.info("EquipmentTracker initialized successfully with MLX SAM3")
            return

        if not _init_torch_sam3():
            raise RuntimeError(
                "SAM3 not installed or not available. "
                "Run: pip install 'git+https://github.com/facebookresearch/sam3.git' "
                "Then: python patch_sam3.py"
            )

        self.device = device or get_device()

        # Resolve model path: explicit arg > env var > default local path > HuggingFace
        resolved_path: Optional[Path] = None
        
        if model_path is not None:
            resolved_path = Path(model_path)
        elif os.environ.get(SAM3_MODEL_PATH_ENV):
            resolved_path = Path(os.environ[SAM3_MODEL_PATH_ENV])
        elif DEFAULT_LOCAL_MODEL_PATH.exists():
            resolved_path = DEFAULT_LOCAL_MODEL_PATH
            logger.info(f"Found local SAM3 model at default location: {resolved_path}")

        logger.info(f"Initializing EquipmentTracker with PyTorch SAM3 on device: {self.device}")

        # Build SAM3 model
        if resolved_path:
            # Handle HuggingFace cache folder structure (models--org--name/snapshots/hash/)
            checkpoint_path = self._resolve_checkpoint_path(resolved_path)
            if checkpoint_path is None:
                raise FileNotFoundError(
                    f"SAM3 model not found at: {resolved_path}\n"
                    "Either download the model to this location, or set model_path=None "
                    "to use HuggingFace cache (~/.cache/huggingface/)."
                )
            logger.info(f"Loading SAM3 model from: {checkpoint_path}")
            self.model = build_sam3_image_model(
                device=self.device,
                load_from_HF=False,
                checkpoint_path=str(checkpoint_path)
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

    def _select_runtime(self, requested_runtime: str, mlx_repo_path: Optional[str]) -> str:
        """Select the SAM3 runtime, preferring MLX for local Apple Silicon analysis."""
        if requested_runtime not in {"auto", "mlx", "torch", "pytorch"}:
            logger.warning("Unknown SAM3_RUNTIME=%s; falling back to auto", requested_runtime)
            requested_runtime = "auto"

        if requested_runtime in {"torch", "pytorch"}:
            return "torch"

        if _init_mlx_sam3(Path(mlx_repo_path) if mlx_repo_path else None):
            return "mlx"

        if requested_runtime == "mlx":
            raise RuntimeError(
                "SAM3_RUNTIME=mlx was requested, but MLX SAM3 could not be initialized. "
                f"Set {MLX_SAM3_REPO_ENV} or clone the repo to {DEFAULT_MLX_REPO_PATH}."
            )

        return "torch"

    def _resolve_checkpoint_path(self, model_path: Path) -> Optional[Path]:
        """
        Resolve the actual checkpoint path from various folder structures.
        
        Handles:
        - Direct path to sam3.pt file
        - Folder containing sam3.pt
        - HuggingFace cache structure (models--org--name/snapshots/hash/)
        
        Returns:
            Path to the checkpoint file, or None if not found.
        """
        # If it's already a file, return it directly
        if model_path.is_file():
            return model_path
        
        # Check for sam3.pt directly in the folder
        direct_checkpoint = model_path / "sam3.pt"
        if direct_checkpoint.exists():
            return direct_checkpoint
        
        # Handle HuggingFace cache structure: models--org--name/snapshots/hash/
        snapshots_dir = model_path / "snapshots"
        if snapshots_dir.exists():
            # Get the latest snapshot (there's usually only one)
            snapshot_dirs = [d for d in snapshots_dir.iterdir() if d.is_dir() and not d.name.startswith('.')]
            if snapshot_dirs:
                # Use the first (or only) snapshot directory
                snapshot_path = snapshot_dirs[0]
                checkpoint = snapshot_path / "sam3.pt"
                if checkpoint.exists():
                    logger.info(f"Resolved HuggingFace cache structure: {checkpoint}")
                    return checkpoint
        
        # Try treating the path itself as a checkpoint
        if model_path.exists():
            return model_path
        
        return None

    def _bytes_to_pil(self, frame_bytes: bytes) -> Any:
        """Convert frame bytes to PIL Image."""
        return Image.open(io.BytesIO(frame_bytes)).convert("RGB")

    def _resize_for_mlx(self, image: Any) -> Tuple[Any, float]:
        """Resize large frames before MLX prompting and return image plus scale."""
        width, height = image.size
        longest = max(width, height)
        if longest <= self.mlx_max_side:
            return image, 1.0
        scale = self.mlx_max_side / longest
        resized = image.resize(
            (int(round(width * scale)), int(round(height * scale))),
            Image.Resampling.BILINEAR,
        )
        return resized, scale

    def _resize_mask(self, mask: Any, width: int, height: int) -> Any:
        """Resize a binary mask back to the source frame size."""
        mask_np = np.array(mask > 0, dtype=np.uint8) * 255
        mask_image = Image.fromarray(mask_np)
        resized = mask_image.resize((width, height), Image.Resampling.NEAREST)
        return np.array(resized) > 0

    def _scores_to_numpy(self, scores: Any, count: int) -> Any:
        if scores is None or len(scores) == 0:
            return np.full(count, 0.5, dtype=np.float32)
        if hasattr(scores, 'cpu'):
            scores = scores.cpu().numpy()
        return np.array(scores, dtype=np.float32)

    def _run_prompt(self, frame_bytes: bytes, prompt: str, frame_index: int) -> Optional[Tuple[Any, float, int, int]]:
        """Run the configured SAM3 runtime for one text prompt."""
        image = self._bytes_to_pil(frame_bytes)
        width, height = image.size

        try:
            if self.runtime_name == "mlx":
                sam_image, scale = self._resize_for_mlx(image)
                sam_width, sam_height = sam_image.size
                with redirect_stdout(io.StringIO()):
                    inference_state = self.processor.set_image(sam_image)
                output = self.processor.set_text_prompt(prompt, inference_state)
                mask_width, mask_height = sam_width, sam_height
            else:
                inference_state = self.processor.set_image(image)
                output = self.processor.set_text_prompt(
                    state=inference_state,
                    prompt=prompt,
                )
                scale = 1.0
                mask_width, mask_height = width, height

            masks = output.get("masks", [])
            scores = output.get("scores", [])
            if len(masks) == 0:
                logger.debug("No %s detected in frame %s", prompt, frame_index)
                return None

            scores_np = self._scores_to_numpy(scores, len(masks))
            best_idx = int(np.argmax(scores_np)) if len(scores_np) else 0
            confidence = float(scores_np[best_idx]) if len(scores_np) > best_idx else 0.5
            if confidence < self.confidence_threshold:
                logger.debug(
                    "%s detection below threshold in frame %s: %.2f",
                    prompt,
                    frame_index,
                    confidence,
                )
                return None

            mask = self._normalize_mask(masks[best_idx], mask_width, mask_height)
            if self.runtime_name == "mlx" and scale != 1.0:
                mask = self._resize_mask(mask, width, height)

            return mask, confidence, width, height
        except Exception as e:
            logger.error("Error detecting %s in frame %s: %s", prompt, frame_index, e)
            return None

    def _normalize_mask(self, mask: Any, image_width: int, image_height: int) -> Any:
        """
        Normalize mask to correct (height, width) format.
        
        SAM3 sometimes returns masks in (width, height) format, but numpy/image 
        convention expects (height, width). This method detects and fixes the issue.
        """
        if hasattr(mask, 'cpu'):
            mask = mask.cpu().numpy()

        if len(mask.shape) > 2:
            mask = mask.squeeze()

        # Check if dimensions are swapped: (width, height) vs expected (height, width)
        # For a 1920x1080 image, mask should be (1080, 1920) not (1920, 1080)
        if mask.shape == (image_width, image_height) and image_width != image_height:
            mask = mask.T  # Transpose to (height, width)

        return mask

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
        result = self._run_prompt(frame_bytes, "golf club", frame_index)
        if result is None:
            return None
        mask, confidence, width, height = result
        return ClubDetection(
            mask=mask,
            centroid=self._mask_centroid(mask, width, height),
            bbox=self._mask_to_bbox(mask),
            confidence=confidence,
            frame_index=frame_index,
        )

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
        result = self._run_prompt(frame_bytes, "golf ball", frame_index)
        if result is None:
            return None
        mask, confidence, width, height = result
        return BallDetection(
            mask=mask,
            centroid=self._mask_centroid(mask, width, height),
            bbox=self._mask_to_bbox(mask),
            confidence=confidence,
            frame_index=frame_index,
        )

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
        result = self._run_prompt(frame_bytes, "club shaft", frame_index)
        if result is None:
            return None
        mask, confidence, _, _ = result
        return ShaftDetection(
            mask=mask,
            confidence=confidence,
            frame_index=frame_index,
        )

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
        result = self._run_prompt(frame_bytes, "clubhead", frame_index)
        if result is None:
            return None
        mask, confidence, width, height = result
        coords = np.argwhere(mask > 0)
        if len(coords) > 0:
            centroid_px = (int(coords[:, 1].mean()), int(coords[:, 0].mean()))
        else:
            centroid_px = (width // 2, height // 2)

        return ClubheadDetection(
            mask=mask,
            centroid=self._mask_centroid(mask, width, height),
            centroid_pixels=centroid_px,
            confidence=confidence,
            frame_index=frame_index,
        )

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
        if mx is not None and hasattr(mx, "clear_cache"):
            mx.clear_cache()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()
