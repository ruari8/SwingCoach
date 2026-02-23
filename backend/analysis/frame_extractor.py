"""
Frame extraction from video using ffmpeg.
Extracts frames at specified intervals for analysis.
Supports multiple video formats: .mp4, .mov, .m4v, etc.
"""

import subprocess
import tempfile
import re
from pathlib import Path
from typing import List, Optional, Union
import logging

logger = logging.getLogger(__name__)

# Supported video extensions (ffmpeg handles these natively)
SUPPORTED_EXTENSIONS = {'.mp4', '.mov', '.m4v', '.avi', '.mkv', '.webm'}


def detect_video_extension(video_bytes: bytes) -> str:
    """Detect video format from magic bytes."""
    if len(video_bytes) < 12:
        return '.mp4'  # default
    
    # Check for MOV/MP4 (ftyp box)
    if video_bytes[4:8] == b'ftyp':
        ftyp = video_bytes[8:12]
        if ftyp in (b'qt  ', b'mqt '):
            return '.mov'
        return '.mp4'
    
    # Check for AVI
    if video_bytes[0:4] == b'RIFF' and video_bytes[8:12] == b'AVI ':
        return '.avi'
    
    # Check for MKV/WebM
    if video_bytes[0:4] == b'\x1a\x45\xdf\xa3':
        return '.mkv'
    
    return '.mp4'  # default


class FrameExtractor:
    """Extracts frames from video files using ffmpeg."""
    
    def __init__(self, temp_dir: Optional[str] = None):
        self.temp_dir = temp_dir or tempfile.gettempdir()

    @staticmethod
    def _frame_file_sort_key(path: Path) -> int:
        """
        Sort frame files by numeric suffix.

        ffmpeg can emit variable-length numbers (e.g. frame_1040.png, frame_10000.png).
        Numeric sorting is required to preserve chronological frame order.
        """
        match = re.search(r"(\d+)$", path.stem)
        if not match:
            return -1
        return int(match.group(1))
    
    def extract_frames(
        self,
        video_bytes: bytes,
        sample_rate: int = 10,
        max_frames: Optional[int] = None,
        file_extension: Optional[str] = None
    ) -> List[bytes]:
        """
        Extract frames from video at regular intervals.
        
        Args:
            video_bytes: Raw video file bytes
            sample_rate: Extract every Nth frame (default: 10)
            max_frames: Maximum number of frames to extract
            file_extension: Optional file extension hint (e.g., '.mov')
            
        Returns:
            List of frame images as PNG bytes
        """
        ext = file_extension or detect_video_extension(video_bytes)
        
        with tempfile.TemporaryDirectory() as tmpdir:
            video_path = Path(tmpdir) / f"input{ext}"
            frames_dir = Path(tmpdir) / "frames"
            frames_dir.mkdir()
            
            video_path.write_bytes(video_bytes)
            
            cmd = [
                "ffmpeg",
                "-i", str(video_path),
                "-vf", f"select=not(mod(n\\,{sample_rate})),setpts=N/FRAME_RATE/TB",
                "-vsync", "vfr",
                str(frames_dir / "frame_%08d.png"),
                "-y",
                "-loglevel", "error"
            ]
            
            if max_frames:
                cmd[5:5] = ["-frames:v", str(max_frames)]
            
            try:
                subprocess.run(cmd, check=True, capture_output=True)
            except subprocess.CalledProcessError as e:
                logger.error(f"ffmpeg failed: {e.stderr.decode()}")
                raise RuntimeError(f"Frame extraction failed: {e.stderr.decode()}")
            
            frame_files = sorted(frames_dir.glob("frame_*.png"), key=self._frame_file_sort_key)
            frames = [f.read_bytes() for f in frame_files]
            
            logger.info(f"Extracted {len(frames)} frames (sample_rate={sample_rate})")
            return frames
    
    def extract_frames_at_indices(
        self,
        video_bytes: bytes,
        frame_indices: List[int],
        file_extension: Optional[str] = None
    ) -> List[bytes]:
        """
        Extract specific frames by index.
        
        Args:
            video_bytes: Raw video file bytes
            frame_indices: List of frame numbers to extract (0-indexed)
            file_extension: Optional file extension hint (e.g., '.mov')
            
        Returns:
            List of frame images as PNG bytes
        """
        if not frame_indices:
            return []

        ext = file_extension or detect_video_extension(video_bytes)
        
        with tempfile.TemporaryDirectory() as tmpdir:
            video_path = Path(tmpdir) / f"input{ext}"
            frames_dir = Path(tmpdir) / "frames"
            frames_dir.mkdir()
            
            video_path.write_bytes(video_bytes)
            
            select_expr = "+".join([f"eq(n\\,{i})" for i in frame_indices])
            
            cmd = [
                "ffmpeg",
                "-i", str(video_path),
                "-vf", f"select={select_expr},setpts=N/FRAME_RATE/TB",
                "-vsync", "vfr",
                str(frames_dir / "frame_%08d.png"),
                "-y",
                "-loglevel", "error"
            ]
            
            try:
                subprocess.run(cmd, check=True, capture_output=True)
            except subprocess.CalledProcessError as e:
                logger.error(f"ffmpeg failed: {e.stderr.decode()}")
                raise RuntimeError(f"Frame extraction failed: {e.stderr.decode()}")
            
            frame_files = sorted(frames_dir.glob("frame_*.png"), key=self._frame_file_sort_key)
            frames = [f.read_bytes() for f in frame_files]
            
            logger.info(f"Extracted {len(frames)} specific frames")
            return frames
    
    def get_video_info(
        self,
        video_bytes: bytes,
        file_extension: Optional[str] = None
    ) -> dict:
        """
        Get video metadata (fps, duration, frame count).
        
        Args:
            video_bytes: Raw video file bytes
            file_extension: Optional file extension hint (e.g., '.mov')
            
        Returns:
            Dict with 'fps', 'duration', 'frame_count', 'width', 'height'
        """
        ext = file_extension or detect_video_extension(video_bytes)
        
        with tempfile.TemporaryDirectory() as tmpdir:
            video_path = Path(tmpdir) / f"input{ext}"
            video_path.write_bytes(video_bytes)
            
            cmd = [
                "ffprobe",
                "-v", "error",
                "-select_streams", "v:0",
                "-show_entries", "stream=width,height,r_frame_rate,nb_frames,duration:stream_side_data=rotation",
                "-of", "json",
                str(video_path)
            ]
            
            try:
                result = subprocess.run(cmd, check=True, capture_output=True)
                import json
                data = json.loads(result.stdout.decode())
                stream = data["streams"][0]
                
                fps_parts = stream.get("r_frame_rate", "30/1").split("/")
                fps = float(fps_parts[0]) / float(fps_parts[1]) if len(fps_parts) == 2 else 30.0
                
                duration = float(stream.get("duration", 0))
                frame_count = int(stream.get("nb_frames", 0))
                
                if frame_count == 0 and duration > 0:
                    frame_count = int(duration * fps)
                
                width = int(stream.get("width", 0))
                height = int(stream.get("height", 0))
                
                # Check for rotation metadata (common in phone videos)
                # If rotation is 90 or -90 degrees, swap width and height
                side_data = stream.get("side_data_list", [])
                for sd in side_data:
                    if "rotation" in sd:
                        rotation = int(sd["rotation"])
                        if rotation in (90, -90, 270, -270):
                            width, height = height, width
                            logger.debug(f"Video has rotation {rotation}, swapped dimensions to {width}x{height}")
                            break
                
                return {
                    "fps": fps,
                    "duration": duration,
                    "frame_count": frame_count,
                    "width": width,
                    "height": height
                }
            except subprocess.CalledProcessError as e:
                logger.error(f"ffprobe failed: {e.stderr.decode()}")
                raise RuntimeError(f"Video info extraction failed: {e.stderr.decode()}")
    
    def extract_from_file(
        self,
        video_path: Union[str, Path],
        sample_rate: int = 10,
        max_frames: Optional[int] = None
    ) -> List[bytes]:
        """
        Extract frames directly from a file path (for local testing).
        
        Args:
            video_path: Path to video file
            sample_rate: Extract every Nth frame
            max_frames: Maximum frames to extract
            
        Returns:
            List of frame images as PNG bytes
        """
        path = Path(video_path)
        if not path.exists():
            raise FileNotFoundError(f"Video not found: {path}")
        
        video_bytes = path.read_bytes()
        return self.extract_frames(
            video_bytes,
            sample_rate=sample_rate,
            max_frames=max_frames,
            file_extension=path.suffix
        )
    
    def get_video_info_from_file(self, video_path: Union[str, Path]) -> dict:
        """Get video info directly from a file path."""
        path = Path(video_path)
        if not path.exists():
            raise FileNotFoundError(f"Video not found: {path}")
        
        video_bytes = path.read_bytes()
        return self.get_video_info(video_bytes, file_extension=path.suffix)
