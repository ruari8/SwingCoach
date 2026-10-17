#!/usr/bin/env python3
"""Regression checks for run artifact upload and the app-facing video contract."""

from __future__ import annotations

import json
import tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import main


class _RecordingStorage:
    def __init__(self) -> None:
        self.uploads: list[tuple[str, str]] = []

    def upload_video(self, key, payload, content_type="video/mp4"):
        self.uploads.append((key, content_type))

    def upload_bytes(self, key, payload, content_type="application/octet-stream"):
        self.uploads.append((key, content_type))

    def generate_download_url(self, key, expiration=3600):
        return f"https://signed.example/{key}"


def test_analyze_response_uploads_one_video_and_points_annotated_video_at_it() -> None:
    storage = _RecordingStorage()
    with tempfile.TemporaryDirectory() as tmp_dir:
        run_dir = Path(tmp_dir)
        (run_dir / "base.mp4").write_bytes(b"video")
        (run_dir / "annotation_tracks.json").write_text(json.dumps({"frames": []}))
        result = SimpleNamespace(
            run_id="fixture",
            run_dir=str(run_dir),
            artifacts={"annotation_metadata": {"layers": []}},
            metrics=[],
            coaching=SimpleNamespace(summary="Summary", detail=None, drills=[]),
        )
        with patch.object(main, "get_r2_client", lambda: storage):
            response = main._build_analyze_response(result)

    base_key = "analysis_runs/fixture/base.mp4"
    tracks_key = "analysis_runs/fixture/annotation_tracks.json"
    assert storage.uploads == [(base_key, "video/mp4"), (tracks_key, "application/json")]

    # The app plays `base_url ?? url` and refreshes `key`, so both resolve to the base upload.
    video = response.annotated_video
    assert video.key == video.base_key == base_key
    assert video.url == video.base_url == f"https://signed.example/{base_key}"
    assert video.tracks_key == tracks_key


if __name__ == "__main__":
    test_analyze_response_uploads_one_video_and_points_annotated_video_at_it()
    print("artifact upload regression checks passed")
