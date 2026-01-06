"""
Video export functionality using ffmpeg.
Assembles annotated frames into MP4 video output.
"""

import io
import os
import subprocess
import tempfile
import shutil
from pathlib import Path
from typing import List, Optional, Tuple
import logging

logger = logging.getLogger(__name__)


class VideoExporter:
    """Exports annotated frames to video using ffmpeg."""

    def __init__(
        self,
        crf: int = 23,
        preset: str = "medium",
        pixel_format: str = "yuv420p"
    ):
        """
        Initialize the video exporter.

        Args:
            crf: Constant Rate Factor for x264 (0-51, lower = better quality, 23 is default)
            preset: Encoding preset (ultrafast, fast, medium, slow, veryslow)
            pixel_format: Output pixel format (yuv420p for compatibility)
        """
        self.crf = crf
        self.preset = preset
        self.pixel_format = pixel_format

        # Verify ffmpeg is available
        if not self._check_ffmpeg():
            raise RuntimeError(
                "ffmpeg not found. Install via: brew install ffmpeg (macOS) "
                "or apt install ffmpeg (Linux)"
            )

    def _check_ffmpeg(self) -> bool:
        """Check if ffmpeg is installed and accessible."""
        try:
            result = subprocess.run(
                ["ffmpeg", "-version"],
                capture_output=True,
                text=True
            )
            return result.returncode == 0
        except FileNotFoundError:
            return False

    def export_video(
        self,
        frames: List[bytes],
        fps: float,
        output_path: Optional[str] = None
    ) -> bytes:
        """
        Export annotated frames to MP4 video.

        Args:
            frames: List of PNG image bytes (annotated frames)
            fps: Frames per second for output video
            output_path: Optional path to save video file. If None, returns bytes.

        Returns:
            Video file as bytes

        Raises:
            RuntimeError: If ffmpeg encoding fails
        """
        if not frames:
            raise ValueError("No frames provided for video export")

        logger.info(f"Exporting {len(frames)} frames at {fps:.1f} fps")

        # Create temporary directory for frame files
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)

            # Write frames as numbered PNG files
            for i, frame_bytes in enumerate(frames):
                frame_file = temp_path / f"frame_{i:04d}.png"
                frame_file.write_bytes(frame_bytes)

            # Output file path
            if output_path:
                output_file = Path(output_path)
            else:
                output_file = temp_path / "output.mp4"

            # Build ffmpeg command
            cmd = [
                "ffmpeg",
                "-y",  # Overwrite output
                "-framerate", str(fps),
                "-i", str(temp_path / "frame_%04d.png"),
                "-c:v", "libx264",
                "-crf", str(self.crf),
                "-preset", self.preset,
                "-pix_fmt", self.pixel_format,
                "-movflags", "+faststart",  # Enable streaming
                str(output_file)
            ]

            logger.debug(f"Running: {' '.join(cmd)}")

            # Run ffmpeg
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True
            )

            if result.returncode != 0:
                logger.error(f"ffmpeg stderr: {result.stderr}")
                raise RuntimeError(f"ffmpeg encoding failed: {result.stderr}")

            # Read output video
            video_bytes = output_file.read_bytes()
            logger.info(f"Video exported: {len(video_bytes) / 1024 / 1024:.1f} MB")

            return video_bytes

    def export_video_with_audio(
        self,
        frames: List[bytes],
        fps: float,
        audio_path: str,
        output_path: Optional[str] = None
    ) -> bytes:
        """
        Export annotated frames to MP4 video with audio from original video.

        Args:
            frames: List of PNG image bytes (annotated frames)
            fps: Frames per second for output video
            audio_path: Path to original video to extract audio from
            output_path: Optional path to save video file

        Returns:
            Video file as bytes
        """
        if not frames:
            raise ValueError("No frames provided for video export")

        logger.info(f"Exporting {len(frames)} frames at {fps:.1f} fps with audio")

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)

            # Write frames
            for i, frame_bytes in enumerate(frames):
                frame_file = temp_path / f"frame_{i:04d}.png"
                frame_file.write_bytes(frame_bytes)

            # Intermediate video (no audio)
            video_only = temp_path / "video_only.mp4"

            # Final output
            if output_path:
                output_file = Path(output_path)
            else:
                output_file = temp_path / "output.mp4"

            # Step 1: Create video from frames
            cmd1 = [
                "ffmpeg", "-y",
                "-framerate", str(fps),
                "-i", str(temp_path / "frame_%04d.png"),
                "-c:v", "libx264",
                "-crf", str(self.crf),
                "-preset", self.preset,
                "-pix_fmt", self.pixel_format,
                str(video_only)
            ]

            result1 = subprocess.run(cmd1, capture_output=True, text=True)
            if result1.returncode != 0:
                raise RuntimeError(f"ffmpeg video encoding failed: {result1.stderr}")

            # Step 2: Combine with audio
            cmd2 = [
                "ffmpeg", "-y",
                "-i", str(video_only),
                "-i", audio_path,
                "-c:v", "copy",
                "-c:a", "aac",
                "-shortest",  # Match shortest stream
                "-movflags", "+faststart",
                str(output_file)
            ]

            result2 = subprocess.run(cmd2, capture_output=True, text=True)
            if result2.returncode != 0:
                # Fall back to video without audio
                logger.warning(f"Could not add audio: {result2.stderr}")
                shutil.copy(video_only, output_file)

            video_bytes = output_file.read_bytes()
            logger.info(f"Video exported: {len(video_bytes) / 1024 / 1024:.1f} MB")

            return video_bytes

    def get_video_dimensions(self, frame_bytes: bytes) -> Tuple[int, int]:
        """
        Get dimensions from a frame image.

        Args:
            frame_bytes: PNG image bytes

        Returns:
            (width, height) tuple
        """
        from PIL import Image
        img = Image.open(io.BytesIO(frame_bytes))
        return img.size

    def estimate_output_size(
        self,
        frame_count: int,
        width: int,
        height: int,
        fps: float
    ) -> int:
        """
        Estimate output video size in bytes.

        Args:
            frame_count: Number of frames
            width: Frame width
            height: Frame height
            fps: Frames per second

        Returns:
            Estimated size in bytes
        """
        duration = frame_count / fps

        # Rough estimate based on CRF and resolution
        # CRF 23 typically yields ~0.1-0.3 bits per pixel
        bits_per_pixel = 0.15  # Conservative estimate
        bitrate = width * height * bits_per_pixel * fps

        estimated_bytes = int(bitrate * duration / 8)

        return estimated_bytes
