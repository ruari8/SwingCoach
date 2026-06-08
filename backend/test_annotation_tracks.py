#!/usr/bin/env python3
"""Regression checks for annotation overlay track generation."""

from __future__ import annotations

import io
import json
import tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from PIL import Image, ImageDraw

from analysis.artifact_renderer import ArtifactRenderer
from analysis.pose_detector import Keypoint, PoseResult
from analysis.run_store import RunStore
from analysis.visualization_config import VisualizationConfig


def _kp(name: str, x: float, y: float, visibility: float = 0.95) -> Keypoint:
    return Keypoint(x=x, y=y, z=0.0, visibility=visibility, name=name)


def _pose(frame_index: int, confidence: float = 0.82) -> PoseResult:
    return PoseResult(
        frame_index=frame_index,
        confidence=confidence,
        keypoints={
            "left_shoulder": _kp("left_shoulder", 0.42, 0.35),
            "right_shoulder": _kp("right_shoulder", 0.56, 0.35),
            "left_hip": _kp("left_hip", 0.44, 0.58),
            "right_hip": _kp("right_hip", 0.55, 0.58),
            "left_wrist": _kp("left_wrist", 0.46, 0.48),
            "right_wrist": _kp("right_wrist", 0.52, 0.48),
        },
    )


def _phase(phase_number: int, name: str, frame_index: int, confidence: float = 0.8):
    return SimpleNamespace(
        phase_number=phase_number,
        name=name,
        frame_index=frame_index,
        timestamp=frame_index / 30.0,
        confidence=confidence,
        description=f"P{phase_number} {name}",
    )


def _frame(width: int = 320, height: int = 180, ball: bool = True) -> bytes:
    image = Image.new("RGB", (width, height), (38, 110, 42))
    draw = ImageDraw.Draw(image)
    if ball:
        draw.ellipse((153, 133, 167, 147), fill=(245, 245, 238))
    output = io.BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


class _FakeVideoExporter:
    def export_video(self, frames, fps):
        return f"fake-video:{len(frames)}:{fps}".encode()


class _FakeShaftDetection:
    def __init__(self, mask, confidence: float, frame_index: int):
        self.mask = mask
        self.confidence = confidence
        self.frame_index = frame_index


class _FakeEquipmentTracker:
    prompts: list[int] = []

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return None

    def detect_shaft(self, frame_bytes, frame_index: int = 0):
        import numpy as np

        self.prompts.append(frame_index)
        mask = np.zeros((180, 320), dtype=np.uint8)
        for offset in range(0, 130):
            x = min(319, 80 + offset)
            y = min(179, 150 - offset // 2)
            mask[max(0, y - 1): min(180, y + 2), max(0, x - 1): min(320, x + 2)] = 1
        return _FakeShaftDetection(mask=mask, confidence=0.82, frame_index=frame_index)


class _VariableConfidenceShaftTracker:
    def __init__(self, confidences: dict[int, float]):
        self.confidences = confidences
        self.prompts: list[int] = []

    def detect_shaft(self, frame_bytes, frame_index: int = 0):
        import numpy as np

        self.prompts.append(frame_index)
        confidence = self.confidences.get(frame_index)
        if confidence is None:
            return None
        mask = np.zeros((180, 320), dtype=np.uint8)
        for offset in range(0, 130):
            x = min(319, 80 + offset)
            y = min(179, 150 - offset // 2)
            mask[max(0, y - 1): min(180, y + 2), max(0, x - 1): min(320, x + 2)] = 1
        return _FakeShaftDetection(mask=mask, confidence=confidence, frame_index=frame_index)


def test_tracks_include_layers_markers_and_confidence() -> None:
    renderer = ArtifactRenderer()
    frame_indices = [100, 101, 102, 103, 104]
    poses = [_pose(frame_index) for frame_index in frame_indices]

    tracks = renderer._annotation_tracks(
        poses2d=poses,
        frame_indices=frame_indices,
        video_fps=30.0,
        frame_width=1920,
        frame_height=1080,
        path_points=[(0, 800, 600), (2, 860, 580), (3, 910, 560)],
        speed_data={103: 88.4},
        peak_speed=88.4,
        peak_frame=103,
        visualization_config=VisualizationConfig(
            draw_skeleton=True,
            draw_reference_lines=True,
            draw_swing_path=True,
            draw_club_plane=True,
            draw_ball_contact=True,
            draw_phase_markers=True,
            draw_confidence=True,
        ),
        guide_frames={
            0: [
                {
                    "id": "setup_geometry.shoulder_line",
                    "layer": "setup_geometry",
                    "kind": "line",
                    "label": "Shoulder line",
                    "color": "#00E5FF",
                    "confidence": 0.8,
                    "style": "solid",
                    "points": [{"x": 0.4, "y": 0.35}, {"x": 0.6, "y": 0.35}],
                }
            ]
        },
        guide_layers=["setup_geometry"],
        club_plane={
            "line": {
                "start": {"x": 0.1, "y": 0.8},
                "end": {"x": 0.9, "y": 0.2},
            },
            "angle_degrees": -35.0,
            "confidence": 0.73,
            "frame_index": 100,
        },
        ball_contact={
            "summary": {
                "detected": True,
                "confidence": 0.82,
                "confidence_level": "high",
                "anchor_frame": 100,
                "impact_frame": 103,
                "impact_window_frames": [101, 102, 103, 104],
                "baseline_luma": 240.0,
                "impact_luma_delta": 42.0,
                "anchor_confidence": 0.71,
            },
            "frames": {
                3: {
                    "center": {"x": 0.5, "y": 0.78},
                    "radius": 0.01,
                    "current_luma": 120.0,
                    "baseline_luma": 240.0,
                    "luma_delta": 42.0,
                    "is_impact_window": True,
                }
            },
        },
        swing_phases=SimpleNamespace(
            phases=[
                _phase(1, "address", 0, confidence=0.76),
                _phase(8, "impact", 103, confidence=0.84),
            ]
        ),
    )

    assert tracks["coordinate_space"] == "normalized"
    assert len(tracks["frames"]) == len(frame_indices)

    first_layers = tracks["frames"][0]["layers"]
    assert "skeleton" in first_layers
    assert "reference_lines" in first_layers
    assert first_layers["guides"][0]["layer"] == "setup_geometry"
    assert "swing_path" in first_layers
    assert first_layers["club_plane"]["confidence"] == 0.73
    assert first_layers["club_plane"]["line"]["start"]["x"] == 0.1
    assert tracks["guide_layers"] == ["setup_geometry"]
    assert tracks["frames"][3]["layers"]["ball_contact"]["luma_delta"] == 42.0
    assert tracks["ball_contact"]["detected"] is True

    # The renderer accepts both dense-relative phase frames and source-frame phase frames.
    assert tracks["phase_markers"][0]["name"] == "address"
    assert tracks["phase_markers"][0]["relative_frame_index"] == 0
    assert tracks["phase_markers"][1]["name"] == "impact"
    assert tracks["phase_markers"][1]["frame_index"] == 103
    assert tracks["phase_markers"][1]["relative_frame_index"] == 3

    evidence = tracks["confidence_evidence"]
    assert evidence["level"] == "high"
    assert evidence["impact"]["detected"] is True
    assert evidence["impact"]["speed_available"] is True
    assert evidence["impact"]["speed_mph"] == 88.4
    assert {badge["label"] for badge in evidence["badges"]} == {"Phases", "Impact", "Ball"}
    assert evidence["impact"]["ball_contact_detected"] is True


def test_club_plane_prefers_address_near_confident_shaft() -> None:
    renderer = ArtifactRenderer()
    frame_indices = [100, 101, 102, 103, 104]
    club2d_frames = [
        SimpleNamespace(
            frame_index=100,
            shaft_confidence=0.5,
            clubhead_confidence=0.5,
            shaft_direction_2d=(1.0, -0.25),
            clubhead_centroid_px=(900, 700),
        ),
        SimpleNamespace(
            frame_index=102,
            shaft_confidence=0.62,
            clubhead_confidence=0.62,
            shaft_direction_2d=(1.0, -1.0),
            clubhead_centroid_px=(960, 720),
        ),
        SimpleNamespace(
            frame_index=104,
            shaft_confidence=0.6,
            clubhead_confidence=0.6,
            shaft_direction_2d=(1.0, 0.0),
            clubhead_centroid_px=(1000, 740),
        ),
    ]

    club_plane = renderer._club_plane_track(
        club2d_frames=club2d_frames,
        frame_indices=frame_indices,
        frame_width=1920,
        frame_height=1080,
        swing_phases=SimpleNamespace(phases=[_phase(1, "address", 102, confidence=0.8)]),
    )

    assert club_plane is not None
    assert club_plane["frame_index"] == 102
    assert club_plane["confidence"] == 0.62
    assert 0.0 <= club_plane["line"]["start"]["x"] <= 1.0
    assert 0.0 <= club_plane["line"]["end"]["x"] <= 1.0


def test_club_plane_prefers_prompted_shaft_track() -> None:
    renderer = ArtifactRenderer()
    frame_indices = [100, 101, 102]

    club_plane = renderer._club_plane_track(
        club2d_frames=[],
        frame_indices=frame_indices,
        frame_width=320,
        frame_height=180,
        swing_phases=SimpleNamespace(phases=[_phase(1, "address", 100, confidence=0.8)]),
        shaft_track={
            "line": {
                "start": {"x": 0.2, "y": 0.9},
                "end": {"x": 0.8, "y": 0.1},
            },
            "pixel_line": ((64, 162), (256, 18)),
            "angle_degrees": -37.0,
            "confidence": 0.82,
            "frame_index": 100,
        },
    )

    assert club_plane is not None
    assert club_plane["source"] == "shaft_prompt"
    assert club_plane["confidence"] == 0.82


def test_address_shaft_prompt_scans_setup_candidates() -> None:
    renderer = ArtifactRenderer()
    frame_indices = [0, 8, 16, 23, 31, 39, 47, 55, 63, 70, 78, 86, 94, 102, 110, 117, 125, 363]
    frames = [_frame() for _ in frame_indices]
    tracker = _VariableConfidenceShaftTracker({0: 0.62, 94: 0.76, 102: 0.81, 110: 0.84, 117: 0.79})

    candidates = renderer._setup_candidate_relative_indices(frame_indices, max_candidates=12)
    track = renderer._best_address_shaft_track(
        tracker=tracker,
        frames=frames,
        frame_indices=frame_indices,
        candidate_relative_indices=candidates,
        phase_relative_idx=0,
        frame_width=320,
        frame_height=180,
    )

    assert track is not None
    assert track["frame_index"] == 110
    assert track["relative_frame_index"] == frame_indices.index(110)


def test_gapped_analysis_window_suppresses_phase_claims() -> None:
    renderer = ArtifactRenderer()
    frame_indices = [0, 8, 16, 363, 364]
    poses = [_pose(frame_index) for frame_index in frame_indices]
    swing_phases = SimpleNamespace(
        phases=[
            _phase(1, "address", 0, confidence=0.8),
            _phase(5, "top", 363, confidence=0.82),
            _phase(8, "impact", 364, confidence=0.84),
        ]
    )

    tracks = renderer._annotation_tracks(
        poses2d=poses,
        frame_indices=frame_indices,
        video_fps=30.0,
        frame_width=320,
        frame_height=180,
        path_points=[],
        speed_data={},
        peak_speed=None,
        peak_frame=None,
        visualization_config=VisualizationConfig(draw_phase_markers=True, draw_confidence=True),
        swing_phases=swing_phases,
    )

    assert tracks["phase_markers"] == []
    assert tracks["confidence_evidence"]["level"] == "missing"

    guide_frames, _ = renderer._guide_tracks(
        poses2d=poses,
        frame_indices=frame_indices,
        frame_width=320,
        frame_height=180,
        club2d_frames=[],
        path_points=[],
        club_plane={
            "line": {
                "start": {"x": 0.1, "y": 0.8},
                "end": {"x": 0.9, "y": 0.2},
            },
            "confidence": 0.82,
        },
        shaft_prompt_tracks={
            "address": {
                "frame_index": 0,
                "relative_frame_index": 0,
                "line": {
                    "start": {"x": 0.1, "y": 0.8},
                    "end": {"x": 0.9, "y": 0.2},
                },
                "confidence": 0.82,
            },
            "top": {
                "frame_index": 363,
                "relative_frame_index": 3,
                "line": {
                    "start": {"x": 0.2, "y": 0.2},
                    "end": {"x": 0.8, "y": 0.8},
                },
                "confidence": 0.82,
            },
        },
        swing_phases=swing_phases,
    )

    guide_ids = {
        guide["id"]
        for frame_guides in guide_frames.values()
        for guide in frame_guides
    }
    assert "shaft_checkpoints.address_shaft" in guide_ids
    assert "shaft_checkpoints.top_shaft" not in guide_ids
    assert not any(guide_id.startswith("head_reference.top") for guide_id in guide_ids)
    assert not any(guide_id.startswith("hip_depth.impact") for guide_id in guide_ids)


def test_low_confidence_guides_are_omitted() -> None:
    renderer = ArtifactRenderer()
    guide_frames, guide_layers = renderer._guide_tracks(
        poses2d=[_pose(100, confidence=0.2)],
        frame_indices=[100],
        frame_width=320,
        frame_height=180,
        club2d_frames=[],
        path_points=[],
        club_plane={
            "line": {
                "start": {"x": 0.1, "y": 0.8},
                "end": {"x": 0.9, "y": 0.2},
            },
            "confidence": 0.2,
        },
        shaft_prompt_tracks={
            "address": {
                "frame_index": 100,
                "relative_frame_index": 0,
                "line": {
                    "start": {"x": 0.1, "y": 0.8},
                    "end": {"x": 0.9, "y": 0.2},
                },
                "confidence": 0.2,
            }
        },
        swing_phases=SimpleNamespace(phases=[_phase(1, "address", 100, confidence=0.2)]),
    )

    assert guide_layers
    assert guide_frames == {}


def test_head_reference_uses_top_of_head_not_face_center() -> None:
    renderer = ArtifactRenderer()
    pose = _pose(100)
    pose.keypoints.update(
        {
            "nose": _kp("nose", 0.55, 0.31),
            "left_eye": _kp("left_eye", 0.54, 0.29),
            "right_eye": _kp("right_eye", 0.56, 0.29),
            "left_ear": _kp("left_ear", 0.52, 0.30),
            "right_ear": _kp("right_ear", 0.58, 0.30),
            "mouth_left": _kp("mouth_left", 0.54, 0.34),
            "mouth_right": _kp("mouth_right", 0.56, 0.34),
        }
    )

    head_top = renderer._head_top(pose)

    assert head_top is not None
    assert head_top["y"] < 0.29


def test_hip_depth_uses_posterior_edge_not_hip_center() -> None:
    renderer = ArtifactRenderer()
    pose = _pose(100)
    pose.keypoints["left_hip"] = _kp("left_hip", 0.42, 0.58)
    pose.keypoints["right_hip"] = _kp("right_hip", 0.34, 0.58)
    pose.keypoints["left_shoulder"] = _kp("left_shoulder", 0.52, 0.35)
    pose.keypoints["right_shoulder"] = _kp("right_shoulder", 0.46, 0.35)

    hip_depth = renderer._posterior_hip_depth(pose)

    assert hip_depth is not None
    assert hip_depth["x"] < 0.34


def test_ball_contact_tracks_luma_change_near_impact() -> None:
    renderer = ArtifactRenderer()
    frame_indices = [100, 101, 102, 103, 104]
    frames = [_frame(ball=True), _frame(ball=True), _frame(ball=True), _frame(ball=False), _frame(ball=False)]
    club2d_frames = [
        SimpleNamespace(
            frame_index=100,
            shaft_confidence=0.7,
            clubhead_confidence=0.74,
            shaft_direction_2d=(1.0, -0.4),
            clubhead_centroid_px=(160, 140),
        )
    ]

    ball_contact = renderer._ball_contact_track(
        frames=frames,
        frame_indices=frame_indices,
        frame_width=320,
        frame_height=180,
        club2d_frames=club2d_frames,
        swing_phases=SimpleNamespace(
            phases=[
                _phase(1, "address", 100, confidence=0.8),
                _phase(8, "impact", 103, confidence=0.83),
            ]
        ),
    )

    assert ball_contact is not None
    assert ball_contact["summary"]["detected"] is True
    assert ball_contact["summary"]["impact_frame"] == 103
    assert ball_contact["frames"][3]["is_impact_window"] is True
    assert ball_contact["frames"][3]["luma_delta"] >= 18.0


def test_render_writes_aligned_artifact_contract() -> None:
    renderer = ArtifactRenderer()
    frame_indices = [100, 101, 102, 103, 104]
    frames = [_frame(ball=True), _frame(ball=True), _frame(ball=True), _frame(ball=False), _frame(ball=False)]
    artifact_indices = [98, 99, 100, 101, 102, 103, 104, 105]
    artifact_frames = [_frame(ball=True) for _ in artifact_indices]
    poses = [_pose(frame_index) for frame_index in frame_indices]
    club2d_frames = [
        SimpleNamespace(
            frame_index=100,
            shaft_confidence=0.74,
            clubhead_confidence=0.78,
            shaft_direction_2d=(1.0, -0.45),
            clubhead_centroid_px=(160, 140),
        ),
        SimpleNamespace(
            frame_index=102,
            shaft_confidence=0.7,
            clubhead_confidence=0.72,
            shaft_direction_2d=(1.0, -0.8),
            clubhead_centroid_px=(166, 134),
        ),
        SimpleNamespace(
            frame_index=103,
            shaft_confidence=0.68,
            clubhead_confidence=0.71,
            shaft_direction_2d=(1.0, -1.0),
            clubhead_centroid_px=(172, 130),
        ),
    ]
    club3d_frames = [
        SimpleNamespace(
            frame_index=100,
            grip_point=(0.0, 0.0, 0.0),
            clubhead_point=(0.0, 0.0, 0.0),
            shaft_direction=(1.0, 0.0, 0.0),
            confidence=0.75,
        ),
        SimpleNamespace(
            frame_index=103,
            grip_point=(0.0, 0.0, 0.0),
            clubhead_point=(0.45, 0.0, 0.0),
            shaft_direction=(1.0, 0.0, 0.0),
            confidence=0.75,
        ),
    ]

    with (
        tempfile.TemporaryDirectory() as tmp_dir,
        patch("analysis.artifact_renderer.VideoExporter", _FakeVideoExporter),
        patch("analysis.equipment_tracker.EquipmentTracker", _FakeEquipmentTracker),
    ):
        run_store = RunStore(root_dir=Path(tmp_dir), run_id="fixture")
        result = renderer.render(
            run_store=run_store,
            frames=frames,
            poses2d=poses,
            frame_indices=frame_indices,
            video_fps=30.0,
            frame_width=320,
            frame_height=180,
            club2d_frames=club2d_frames,
            poses3d=[],
            club3d_frames=club3d_frames,
            swing_phases=SimpleNamespace(
                phases=[
                    _phase(1, "address", 100, confidence=0.8),
                    _phase(8, "impact", 103, confidence=0.84),
                ]
            ),
            artifact_frames=artifact_frames,
            artifact_frame_indices=artifact_indices,
        )

        assert result.base_video_filename == "base.mp4"
        assert result.annotated_video_filename == "annotated.mp4"
        assert result.annotation_tracks_filename == "annotation_tracks.json"
        assert run_store.path("base.mp4").read_bytes().startswith(b"fake-video:8")
        assert run_store.path("annotated.mp4").read_bytes().startswith(b"fake-video:8")

        metadata = json.loads(run_store.path("annotation_metadata.json").read_text())
        tracks = json.loads(run_store.path("annotation_tracks.json").read_text())

    metadata_layers = {layer["name"] for layer in metadata["layers"]}
    frame_layer_names = set()
    for frame in tracks["frames"]:
        frame_layer_names.update(frame["layers"].keys())
    frame_layer_names.discard("guides")
    top_level_toggle_layers = {
        "phase_markers" if tracks["phase_markers"] else None,
        "confidence" if tracks["confidence_evidence"] else None,
    }
    top_level_toggle_layers.discard(None)

    assert {
        "skeleton",
        "reference_lines",
        "club_plane",
        "ball_contact",
        "swing_path",
        "speed",
        "shaft_checkpoints",
        "clubhead_path",
        "setup_geometry",
        "head_reference",
        "hip_depth",
        "hand_depth",
        "lead_arm_plane",
        "takeaway_checkpoint",
    }.issubset(metadata_layers)
    assert frame_layer_names.union(top_level_toggle_layers).issubset(metadata_layers)
    assert metadata["frame_count"] == len(artifact_indices)
    assert len(tracks["frames"]) == len(artifact_indices)
    assert tracks["phase_markers"][0]["relative_frame_index"] == 2
    assert tracks["phase_markers"][1]["relative_frame_index"] == 5
    assert tracks["ball_contact"]["detected"] is True
    assert any(frame["layers"].get("speed") for frame in tracks["frames"])
    assert "guides" in tracks["frames"][0]["layers"]
    assert "shaft_checkpoints" in tracks["guide_layers"]
    assert tracks["frames"][0]["layers"]["club_plane"]["frame_index"] == 100
    assert tracks["frames"][0]["layers"]["club_plane"]["line"]["name"] == "address_shaft_plane"

    guide_counts: dict[str, int] = {}
    for frame in tracks["frames"]:
        for guide in frame["layers"].get("guides", []):
            guide_counts[guide["id"]] = guide_counts.get(guide["id"], 0) + 1

    assert guide_counts["shaft_checkpoints.address_shaft"] > 1
    assert guide_counts["shaft_checkpoints.impact_shaft"] > 1


if __name__ == "__main__":
    test_tracks_include_layers_markers_and_confidence()
    test_club_plane_prefers_address_near_confident_shaft()
    test_club_plane_prefers_prompted_shaft_track()
    test_address_shaft_prompt_scans_setup_candidates()
    test_gapped_analysis_window_suppresses_phase_claims()
    test_low_confidence_guides_are_omitted()
    test_head_reference_uses_top_of_head_not_face_center()
    test_hip_depth_uses_posterior_edge_not_hip_center()
    test_ball_contact_tracks_luma_change_near_impact()
    test_render_writes_aligned_artifact_contract()
    print("annotation track regression checks passed")
