#!/usr/bin/env python3
"""Regression checks for the annotation-reset artifact contract."""

from __future__ import annotations

import io
import json
import tempfile
from pathlib import Path
from unittest.mock import patch

from PIL import Image

from analysis.artifact_renderer import ArtifactRenderer
from analysis.run_store import RunStore


def _frame(width: int = 320, height: int = 180) -> bytes:
    image = Image.new("RGB", (width, height), (38, 110, 42))
    output = io.BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


class _FakeVideoExporter:
    def export_video(self, frames, fps):
        return f"fake-video:{len(frames)}:{fps}".encode()


def test_render_writes_clean_reset_contract() -> None:
    renderer = ArtifactRenderer()
    frames = [_frame(), _frame(), _frame()]
    frame_indices = [0, 1, 2]

    with (
        tempfile.TemporaryDirectory() as tmp_dir,
        patch("analysis.artifact_renderer.VideoExporter", _FakeVideoExporter),
    ):
        run_store = RunStore(root_dir=Path(tmp_dir), run_id="fixture")
        result = renderer.render(
            run_store=run_store,
            frames=frames,
            poses2d=[],
            frame_indices=frame_indices,
            video_fps=30.0,
            frame_width=320,
            frame_height=180,
            club2d_frames=[],
            poses3d=[],
            club3d_frames=[],
        )

        metadata = json.loads(run_store.path("annotation_metadata.json").read_text())
        tracks = json.loads(run_store.path("annotation_tracks.json").read_text())

        assert result.base_video_filename == "base.mp4"
        assert result.annotated_video_filename == "annotated.mp4"
        assert result.swing_3d_filename is None
        assert result.annotation_tracks_filename == "annotation_tracks.json"
        assert run_store.path("base.mp4").read_bytes() == b"fake-video:3:30.0"
        assert run_store.path("annotated.mp4").read_bytes() == b"fake-video:3:30.0"

    assert metadata["layers"] == []
    assert metadata["annotations_enabled"] is False
    assert metadata["pipeline_mode"] == "annotation_reset"
    assert metadata["frame_count"] == 3

    assert tracks["guide_layers"] == []
    assert tracks["phase_markers"] == []
    assert tracks["confidence_evidence"] is None
    assert tracks["ball_contact"] is None
    assert len(tracks["frames"]) == 3
    assert all(frame["layers"] == {} for frame in tracks["frames"])


if __name__ == "__main__":
    test_render_writes_clean_reset_contract()
    print("annotation reset contract checks passed")
