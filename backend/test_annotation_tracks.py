#!/usr/bin/env python3
"""Exercise real FFmpeg output and the reset pipeline without cloud credentials."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np

from analysis.frame_extractor import FrameExtractor
from analysis.pipeline_3d import SwingCoachPipeline3D
from analysis.video_exporter import VideoExporter


def ffmpeg(*args: str) -> bytes:
    return subprocess.run(
        ["ffmpeg", "-v", "error", "-nostdin", "-y", *args],
        check=True, capture_output=True,
    ).stdout


def decoded_frames(path: Path) -> np.ndarray:
    return np.frombuffer(ffmpeg("-i", str(path), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"), dtype=np.uint8)


class CleanArtifactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        cls.source = cls.root / "source.mp4"
        ffmpeg(
            "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=30:duration=0.4",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.4",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", str(cls.source),
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def check_pipeline(self, source: Path, fps: float = 30, dimensions=(320, 180), count=12) -> Path:
        progress = []
        with patch.object(FrameExtractor, "extract_frames", side_effect=AssertionError("PNG extraction returned")):
            result = SwingCoachPipeline3D(str(self.root / "runs")).analyze_video(
                source.read_bytes(), requested_fps=fps,
                progress_callback=lambda stage, fraction, message: progress.append((stage, fraction)),
            )
        run = Path(result.run_dir)
        video = run / "base.mp4"
        data = json.loads(subprocess.run([
            "ffprobe", "-v", "error", "-count_frames", "-show_streams", "-of", "json", str(video),
        ], check=True, capture_output=True).stdout)
        self.assertEqual(len(data["streams"]), 1, "The existing artifact contract is silent video")
        stream = data["streams"][0]
        self.assertEqual(stream["codec_name"], "h264")
        self.assertEqual(stream["pix_fmt"], "yuv420p")
        self.assertEqual(int(stream["nb_read_frames"]), count)
        self.assertEqual((stream["width"], stream["height"]), dimensions)
        self.assertAlmostEqual(float(stream["duration"]), count / fps, places=4)
        self.assertFalse(any(item.get("rotation", 0) for item in stream.get("side_data_list", [])))
        self.assertEqual(video.read_bytes(), (run / "annotated.mp4").read_bytes())
        payload = video.read_bytes()
        self.assertLess(payload.index(b"moov"), payload.index(b"mdat"), "MP4 must support progressive playback")
        tracks = json.loads((run / "annotation_tracks.json").read_text())
        metadata = json.loads((run / "annotation_metadata.json").read_text())
        self.assertEqual(metadata["frame_count"], count)
        self.assertFalse(metadata["annotations_enabled"])
        self.assertEqual(metadata["layers"], [])
        self.assertEqual((tracks["frame_width"], tracks["frame_height"]), dimensions)
        self.assertEqual(tracks["fps"], fps)
        self.assertEqual(tracks["guide_layers"], [])
        self.assertEqual(tracks["phase_markers"], [])
        self.assertIsNone(tracks["confidence_evidence"])
        self.assertIsNone(tracks["ball_contact"])
        self.assertEqual(tracks["frames"], [
            {"frame_index": i, "relative_frame_index": i, "timestamp": round(i / fps, 4),
             "relative_timestamp": round(i / fps, 4), "layers": {}}
            for i in range(count)
        ])
        self.assertEqual(result.metrics, [])
        self.assertEqual(result.coaching.drills, [])
        self.assertEqual(progress[-1], ("pipeline_complete", 1.0))
        self.assertEqual([value for _, value in progress], sorted(value for _, value in progress))
        self.assertIn("artifacts", json.loads((run / "timings.json").read_text()))
        return video

    def test_clean_video_and_contract(self):
        self.check_pipeline(self.source)

    def test_fps_override_retains_every_frame(self):
        for fps in (15, 60, 30000 / 1001):
            with self.subTest(fps=fps):
                self.check_pipeline(self.source, fps=fps)

    def test_rotation_is_applied_once(self):
        for angle, dimensions in ((90, (180, 320)), (180, (320, 180)), (270, (180, 320))):
            with self.subTest(angle=angle):
                rotated = self.root / f"rotated-{angle}.mov"
                ffmpeg("-display_rotation", str(angle), "-i", str(self.source), "-c", "copy", str(rotated))
                source_info = FrameExtractor().get_video_info(rotated.read_bytes())
                self.assertEqual((source_info["width"], source_info["height"]), dimensions)
                output = self.check_pipeline(rotated, dimensions=dimensions)
                self.assert_pixels_match(rotated, output)

    def test_variable_timestamps_and_missing_input_frame_count(self):
        source = self.root / "variable.mkv"
        ffmpeg("-i", str(self.source), "-an", "-vf", "setpts=if(lt(N\\,6)\\,N\\,N+6)/(30*TB)",
               "-fps_mode", "vfr", "-c:v", "libx264", str(source))
        self.check_pipeline(source)

    def assert_pixels_match(self, source: Path, output: Path):
        expected = decoded_frames(source).astype(np.float32)
        actual = decoded_frames(output).astype(np.float32)
        self.assertEqual(actual.shape, expected.shape)
        # A lossy encode may change pixels. This catches rotation, frame-order,
        # and severe color regressions while allowing normal H.264 loss.
        mse = np.mean((actual - expected) ** 2)
        psnr = float(10 * np.log10(255 ** 2 / max(mse, 1e-10)))
        self.assertGreater(psnr, 30, f"Decoded RGB PSNR {psnr:.2f} dB")

    def test_pixels_and_order_against_previous_png_path(self):
        output = self.check_pipeline(self.source)
        previous = self.root / "previous.mp4"
        frames = FrameExtractor().extract_frames(self.source.read_bytes(), sample_rate=1)
        previous.write_bytes(VideoExporter().export_video(frames, fps=30))
        self.assert_pixels_match(previous, output)
        self.assert_pixels_match(self.source, output)

    def test_invalid_video_fails(self):
        with self.assertRaises(RuntimeError):
            SwingCoachPipeline3D(str(self.root / "runs")).analyze_video(b"not a video")
        with self.assertRaises(RuntimeError):
            VideoExporter().export_clean_video(b"not a video", fps=30)

    def test_invalid_fps_fails(self):
        for fps in (-1, 0, float("nan"), float("inf")):
            with self.subTest(fps=fps), self.assertRaises(ValueError):
                VideoExporter().export_clean_video(self.source.read_bytes(), fps=fps)


if __name__ == "__main__":
    unittest.main()
