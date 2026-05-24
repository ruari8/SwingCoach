"""Render annotated 2D video and 3D replay artifacts."""

from __future__ import annotations

import io
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
from PIL import Image

from .animation_exporter import export_swing_animation
from .video_exporter import VideoExporter
from .visualization_config import LAYER_DEFINITIONS, VisualizationConfig, VisualizationMetadata
from .visualizer import HIDDEN_SKELETON_LANDMARKS, POSE_CONNECTIONS, SwingVisualizer


@dataclass
class ArtifactRenderResult:
    base_video_filename: Optional[str]
    annotated_video_filename: Optional[str]
    swing_3d_filename: Optional[str]
    annotation_tracks_filename: Optional[str]
    debug_files: List[str]
    annotation_metadata: Dict[str, Any]


@dataclass
class _SwingPathProxy:
    points_with_frame: List[Tuple[int, int, int]]

    def get_pixel_points_up_to_frame(self, frame_index: int) -> List[Tuple[int, int]]:
        return [(x, y) for fi, x, y in self.points_with_frame if fi <= frame_index]


class ArtifactRenderer:
    """Renders coach-facing visual artifacts from pipeline outputs."""

    def _normalize_point(self, x: float, y: float, frame_width: int, frame_height: int) -> Dict[str, float]:
        return {
            "x": round(float(x) / max(frame_width, 1), 6),
            "y": round(float(y) / max(frame_height, 1), 6),
        }

    def _pose_keypoints(self, pose: Any, min_visibility: float) -> Dict[str, Dict[str, float]]:
        if pose is None:
            return {}

        keypoints: Dict[str, Dict[str, float]] = {}
        for name, kp in pose.keypoints.items():
            if name in HIDDEN_SKELETON_LANDMARKS or kp.visibility < min_visibility:
                continue
            keypoints[name] = {
                "x": round(float(kp.x), 6),
                "y": round(float(kp.y), 6),
                "visibility": round(float(kp.visibility), 4),
            }
        return keypoints

    def _visible_pose_connections(self, keypoints: Dict[str, Dict[str, float]]) -> List[Dict[str, str]]:
        return [
            {"from": start, "to": end}
            for start, end in POSE_CONNECTIONS
            if start in keypoints and end in keypoints
        ]

    def _extend_normalized_line(
        self,
        p1: Dict[str, float],
        p2: Dict[str, float],
        extension: float,
    ) -> Tuple[Dict[str, float], Dict[str, float]]:
        dx = p2["x"] - p1["x"]
        dy = p2["y"] - p1["y"]
        return (
            {
                "x": round(p1["x"] - dx * (extension - 1), 6),
                "y": round(p1["y"] - dy * (extension - 1), 6),
            },
            {
                "x": round(p2["x"] + dx * (extension - 1), 6),
                "y": round(p2["y"] + dy * (extension - 1), 6),
            },
        )

    def _reference_lines(self, keypoints: Dict[str, Dict[str, float]]) -> List[Dict[str, Any]]:
        lines: List[Dict[str, Any]] = []
        left_shoulder = keypoints.get("left_shoulder")
        right_shoulder = keypoints.get("right_shoulder")
        left_hip = keypoints.get("left_hip")
        right_hip = keypoints.get("right_hip")

        if left_shoulder and right_shoulder:
            start, end = self._extend_normalized_line(left_shoulder, right_shoulder, extension=1.5)
            lines.append({"name": "shoulder_plane", "start": start, "end": end})

        if left_shoulder and right_shoulder and left_hip and right_hip:
            shoulder_center = {
                "x": round((left_shoulder["x"] + right_shoulder["x"]) / 2, 6),
                "y": round((left_shoulder["y"] + right_shoulder["y"]) / 2, 6),
            }
            hip_center = {
                "x": round((left_hip["x"] + right_hip["x"]) / 2, 6),
                "y": round((left_hip["y"] + right_hip["y"]) / 2, 6),
            }
            start, end = self._extend_normalized_line(hip_center, shoulder_center, extension=1.3)
            lines.append({"name": "spine_line", "start": start, "end": end})

        return lines

    def _dense_relative_frame(
        self,
        raw_frame: int,
        frame_indices: List[int],
        source_to_relative: Optional[Dict[int, int]] = None,
    ) -> Optional[int]:
        if source_to_relative is None:
            source_to_relative = {int(source): idx for idx, source in enumerate(frame_indices)}
        if raw_frame in source_to_relative:
            return source_to_relative[raw_frame]
        if 0 <= raw_frame < len(frame_indices):
            return raw_frame
        return None

    def _address_source_frame(self, swing_phases: Optional[Any], frame_indices: List[int]) -> Optional[int]:
        if swing_phases is None:
            return None
        source_to_relative = {int(source): idx for idx, source in enumerate(frame_indices)}
        for phase in getattr(swing_phases, "phases", []):
            name = str(getattr(phase, "name", "")).lower()
            phase_number = int(getattr(phase, "phase_number", -1))
            if name not in {"address", "setup"} and phase_number != 1:
                continue
            raw_frame = int(getattr(phase, "frame_index", -1))
            relative_frame = self._dense_relative_frame(raw_frame, frame_indices, source_to_relative)
            if relative_frame is None:
                continue
            return int(frame_indices[relative_frame])
        return None

    def _line_across_frame(
        self,
        anchor: Tuple[float, float],
        direction: Tuple[float, float],
        frame_width: int,
        frame_height: int,
    ) -> Optional[Tuple[Tuple[int, int], Tuple[int, int]]]:
        ax, ay = float(anchor[0]), float(anchor[1])
        dx, dy = float(direction[0]), float(direction[1])
        norm = float(np.hypot(dx, dy))
        if norm < 1e-6:
            return None
        dx /= norm
        dy /= norm

        candidates: List[Tuple[float, Tuple[float, float]]] = []
        bounds = [
            (0.0, frame_width - 1.0, "x"),
            (0.0, frame_height - 1.0, "y"),
        ]
        for boundary, _, axis in bounds:
            if axis == "x" and abs(dx) > 1e-6:
                t = (boundary - ax) / dx
                y = ay + t * dy
                if 0 <= y <= frame_height - 1:
                    candidates.append((t, (boundary, y)))
            if axis == "y" and abs(dy) > 1e-6:
                t = (boundary - ay) / dy
                x = ax + t * dx
                if 0 <= x <= frame_width - 1:
                    candidates.append((t, (x, boundary)))

        for _, boundary, axis in bounds:
            if axis == "x" and abs(dx) > 1e-6:
                t = (boundary - ax) / dx
                y = ay + t * dy
                if 0 <= y <= frame_height - 1:
                    candidates.append((t, (boundary, y)))
            if axis == "y" and abs(dy) > 1e-6:
                t = (boundary - ay) / dy
                x = ax + t * dx
                if 0 <= x <= frame_width - 1:
                    candidates.append((t, (x, boundary)))

        if len(candidates) < 2:
            return None

        candidates.sort(key=lambda item: item[0])
        start = candidates[0][1]
        end = candidates[-1][1]
        return (
            (int(round(start[0])), int(round(start[1]))),
            (int(round(end[0])), int(round(end[1]))),
        )

    def _club_plane_track(
        self,
        club2d_frames: List[Any],
        frame_indices: List[int],
        frame_width: int,
        frame_height: int,
        swing_phases: Optional[Any],
        min_confidence: float = 0.45,
    ) -> Optional[Dict[str, Any]]:
        address_frame = self._address_source_frame(swing_phases, frame_indices)
        best_item = None
        best_score = -1.0

        for item in club2d_frames:
            head = getattr(item, "clubhead_centroid_px", None)
            direction = getattr(item, "shaft_direction_2d", None)
            confidence = float(getattr(item, "shaft_confidence", 0.0))
            if head is None or direction is None or confidence < min_confidence:
                continue

            frame_index = int(getattr(item, "frame_index", -1))
            proximity_bonus = 0.0
            if address_frame is not None:
                proximity_bonus = max(0.0, 1.0 - (abs(frame_index - address_frame) / 12.0)) * 0.25
            elif frame_index == int(frame_indices[0]):
                proximity_bonus = 0.1

            score = confidence + proximity_bonus
            if score > best_score:
                best_score = score
                best_item = item

        if best_item is None:
            return None

        line = self._line_across_frame(
            getattr(best_item, "clubhead_centroid_px"),
            getattr(best_item, "shaft_direction_2d"),
            frame_width,
            frame_height,
        )
        if line is None:
            return None

        start, end = line
        direction = getattr(best_item, "shaft_direction_2d")
        angle = float(np.degrees(np.arctan2(float(direction[1]), float(direction[0]))))
        return {
            "line": {
                "start": self._normalize_point(start[0], start[1], frame_width, frame_height),
                "end": self._normalize_point(end[0], end[1], frame_width, frame_height),
            },
            "pixel_line": line,
            "angle_degrees": round(angle, 2),
            "confidence": round(float(getattr(best_item, "shaft_confidence", 0.0)), 4),
            "frame_index": int(getattr(best_item, "frame_index", frame_indices[0])),
        }

    def _impact_source_frame(self, swing_phases: Optional[Any], frame_indices: List[int]) -> Optional[int]:
        if swing_phases is None:
            return None
        source_to_relative = {int(source): idx for idx, source in enumerate(frame_indices)}
        for phase in getattr(swing_phases, "phases", []):
            name = str(getattr(phase, "name", "")).lower()
            phase_number = int(getattr(phase, "phase_number", -1))
            if name != "impact" and phase_number != 8:
                continue
            raw_frame = int(getattr(phase, "frame_index", -1))
            relative_frame = self._dense_relative_frame(raw_frame, frame_indices, source_to_relative)
            if relative_frame is None:
                continue
            return int(frame_indices[relative_frame])
        return None

    def _frame_luma(self, frame_bytes: bytes) -> np.ndarray:
        return np.array(Image.open(io.BytesIO(frame_bytes)).convert("L"), dtype=np.float32)

    def _mean_luma(self, luma: np.ndarray, center: Tuple[int, int], radius: int) -> Optional[float]:
        height, width = luma.shape[:2]
        cx, cy = int(center[0]), int(center[1])
        x1 = max(0, cx - radius)
        y1 = max(0, cy - radius)
        x2 = min(width, cx + radius + 1)
        y2 = min(height, cy + radius + 1)
        if x2 <= x1 or y2 <= y1:
            return None
        return float(np.mean(luma[y1:y2, x1:x2]))

    def _clubhead_anchor(
        self,
        club2d_frames: List[Any],
        frame_indices: List[int],
        preferred_source_frame: Optional[int],
        min_confidence: float = 0.35,
    ) -> Optional[Any]:
        best_item = None
        best_score = -1.0
        for item in club2d_frames:
            head = getattr(item, "clubhead_centroid_px", None)
            if head is None:
                continue
            confidence = float(getattr(item, "clubhead_confidence", 0.0))
            if confidence < min_confidence:
                continue
            frame_index = int(getattr(item, "frame_index", -1))
            if frame_index not in frame_indices:
                continue
            proximity_bonus = 0.0
            if preferred_source_frame is not None:
                proximity_bonus = max(0.0, 1.0 - (abs(frame_index - preferred_source_frame) / 18.0)) * 0.35
            elif frame_index == int(frame_indices[0]):
                proximity_bonus = 0.15
            score = confidence + proximity_bonus
            if score > best_score:
                best_item = item
                best_score = score
        return best_item

    def _ball_contact_track(
        self,
        frames: List[bytes],
        frame_indices: List[int],
        frame_width: int,
        frame_height: int,
        club2d_frames: List[Any],
        swing_phases: Optional[Any],
    ) -> Optional[Dict[str, Any]]:
        address_frame = self._address_source_frame(swing_phases, frame_indices)
        impact_frame = self._impact_source_frame(swing_phases, frame_indices)
        anchor_item = self._clubhead_anchor(club2d_frames, frame_indices, address_frame)
        if anchor_item is None:
            return None

        anchor_px = getattr(anchor_item, "clubhead_centroid_px")
        anchor_frame = int(getattr(anchor_item, "frame_index", frame_indices[0]))
        source_to_relative = {int(source): idx for idx, source in enumerate(frame_indices)}
        anchor_relative = source_to_relative.get(anchor_frame, 0)
        impact_relative = source_to_relative.get(impact_frame) if impact_frame is not None else None
        radius = max(10, int(round(min(frame_width, frame_height) * 0.014)))

        try:
            baseline_luma = self._mean_luma(self._frame_luma(frames[anchor_relative]), anchor_px, radius)
        except Exception:
            return None
        if baseline_luma is None:
            return None

        frame_layers: Dict[int, Dict[str, Any]] = {}
        max_delta = 0.0
        impact_delta = None
        impact_window_frames: List[int] = []
        for relative_idx, source_frame in enumerate(frame_indices):
            if impact_relative is None:
                is_impact_window = False
            else:
                is_impact_window = abs(relative_idx - impact_relative) <= 3
            if is_impact_window:
                impact_window_frames.append(int(source_frame))

            try:
                current_luma = self._mean_luma(self._frame_luma(frames[relative_idx]), anchor_px, radius)
            except Exception:
                current_luma = None
            if current_luma is None:
                continue

            delta = abs(float(current_luma) - float(baseline_luma))
            max_delta = max(max_delta, delta)
            if impact_relative is not None and relative_idx == impact_relative:
                impact_delta = delta

            frame_layers[relative_idx] = {
                "center": self._normalize_point(anchor_px[0], anchor_px[1], frame_width, frame_height),
                "radius": round(float(radius) / max(min(frame_width, frame_height), 1), 6),
                "current_luma": round(float(current_luma), 2),
                "baseline_luma": round(float(baseline_luma), 2),
                "luma_delta": round(float(delta), 2),
                "is_impact_window": is_impact_window,
            }

        if not frame_layers:
            return None

        evidence_delta = impact_delta if impact_delta is not None else max_delta
        detected = impact_relative is not None and evidence_delta >= 18.0
        confidence = 0.0
        if impact_relative is not None:
            confidence = min(1.0, max(0.2, evidence_delta / 46.0))
            if not detected:
                confidence = min(confidence, 0.45)

        return {
            "summary": {
                "detected": bool(detected),
                "confidence": round(float(confidence), 4),
                "confidence_level": self._confidence_level(confidence if confidence > 0 else None),
                "anchor_frame": anchor_frame,
                "impact_frame": int(impact_frame) if impact_frame is not None else None,
                "impact_window_frames": impact_window_frames,
                "baseline_luma": round(float(baseline_luma), 2),
                "impact_luma_delta": round(float(evidence_delta), 2),
                "anchor_confidence": round(float(getattr(anchor_item, "clubhead_confidence", 0.0)), 4),
            },
            "frames": frame_layers,
        }

    def _speed_map(self, club3d_frames: List[Any], fps: float) -> Tuple[Dict[int, float], Optional[float], Optional[int]]:
        speed_map: Dict[int, float] = {}
        if len(club3d_frames) < 2:
            return speed_map, None, None

        peak_speed = 0.0
        peak_frame = None
        prev = None
        for frame in club3d_frames:
            head = np.array(frame.clubhead_point, dtype=np.float32)
            if prev is None:
                prev = (frame.frame_index, head)
                continue
            prev_idx, prev_head = prev
            dt_frames = max(1, frame.frame_index - prev_idx)
            dt = dt_frames / max(fps, 1e-6)
            speed_mps = np.linalg.norm((head - prev_head) / max(dt, 1e-6))
            speed_mph = float(speed_mps * 2.23693629)
            speed_map[frame.frame_index] = speed_mph
            if speed_mph > peak_speed:
                peak_speed = speed_mph
                peak_frame = frame.frame_index
            prev = (frame.frame_index, head)

        return speed_map, (peak_speed if peak_speed > 0 else None), peak_frame

    def _confidence_level(self, confidence: Optional[float]) -> str:
        if confidence is None:
            return "missing"
        if confidence >= 0.75:
            return "high"
        if confidence >= 0.5:
            return "medium"
        return "low"

    def _nearest_speed(
        self,
        speed_data: Dict[int, float],
        source_frame: Optional[int],
        max_frame_distance: int = 3,
    ) -> Tuple[Optional[float], Optional[int]]:
        if source_frame is None or not speed_data:
            return None, None

        nearest_frame = min(speed_data, key=lambda item: abs(item - source_frame))
        if abs(nearest_frame - source_frame) > max_frame_distance:
            return None, None
        return speed_data[nearest_frame], nearest_frame

    def _confidence_evidence(
        self,
        phase_markers: List[Dict[str, Any]],
        speed_data: Dict[int, float],
        ball_contact: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        ball_summary = ball_contact.get("summary") if ball_contact else None
        if not phase_markers:
            ball_badges = []
            if ball_summary:
                ball_badges.append(
                    {
                        "label": "Ball",
                        "level": ball_summary.get("confidence_level", "missing"),
                        "value": "Moved" if ball_summary.get("detected") else "Unclear",
                    }
                )
            return {
                "level": "missing",
                "phase_confidence": None,
                "impact": {
                    "detected": False,
                    "confidence": None,
                    "confidence_level": "missing",
                    "speed_mph": None,
                    "speed_frame": None,
                    "speed_available": False,
                    "ball_contact_detected": bool(ball_summary.get("detected")) if ball_summary else False,
                    "ball_contact_confidence": ball_summary.get("confidence") if ball_summary else None,
                },
                "badges": [
                    {
                        "label": "Phases",
                        "level": "missing",
                        "value": "No markers",
                    }
                ] + ball_badges,
            }

        mean_phase_confidence = float(np.mean([item["confidence"] for item in phase_markers]))
        impact_marker = next((item for item in phase_markers if item.get("name") == "impact"), None)
        impact_speed, impact_speed_frame = self._nearest_speed(
            speed_data,
            impact_marker.get("frame_index") if impact_marker else None,
        )
        impact_confidence = impact_marker.get("confidence") if impact_marker else None

        badges = [
            {
                "label": "Phases",
                "level": self._confidence_level(mean_phase_confidence),
                "value": f"{round(mean_phase_confidence * 100)}%",
            }
        ]

        if impact_marker is None:
            badges.append({"label": "Impact", "level": "missing", "value": "Not found"})
        elif impact_speed is None:
            badges.append(
                {
                    "label": "Impact",
                    "level": self._confidence_level(impact_confidence),
                    "value": f"{round(float(impact_confidence) * 100)}%" if impact_confidence is not None else "Detected",
                }
            )
        else:
            badges.append(
                {
                    "label": "Impact",
                    "level": self._confidence_level(impact_confidence),
                    "value": f"{round(float(impact_speed))} mph",
                }
            )

        if ball_summary is not None:
            badges.append(
                {
                    "label": "Ball",
                    "level": ball_summary.get("confidence_level", "missing"),
                    "value": "Moved" if ball_summary.get("detected") else "Unclear",
                }
            )

        return {
            "level": self._confidence_level(mean_phase_confidence),
            "phase_confidence": round(mean_phase_confidence, 4),
            "impact": {
                "detected": impact_marker is not None,
                "confidence": round(float(impact_confidence), 4) if impact_confidence is not None else None,
                "confidence_level": self._confidence_level(impact_confidence),
                "speed_mph": round(float(impact_speed), 2) if impact_speed is not None else None,
                "speed_frame": int(impact_speed_frame) if impact_speed_frame is not None else None,
                "speed_available": impact_speed is not None,
                "ball_contact_detected": bool(ball_summary.get("detected")) if ball_summary else False,
                "ball_contact_confidence": ball_summary.get("confidence") if ball_summary else None,
            },
            "badges": badges,
        }

    def _annotation_tracks(
        self,
        poses2d: List[Optional[Any]],
        frame_indices: List[int],
        video_fps: float,
        frame_width: int,
        frame_height: int,
        path_points: List[Tuple[int, int, int]],
        speed_data: Dict[int, float],
        peak_speed: Optional[float],
        peak_frame: Optional[int],
        visualization_config: VisualizationConfig,
        club_plane: Optional[Dict[str, Any]] = None,
        ball_contact: Optional[Dict[str, Any]] = None,
        swing_phases: Optional[Any] = None,
    ) -> Dict[str, Any]:
        path_by_relative_frame = {
            relative_frame: self._normalize_point(x, y, frame_width, frame_height)
            for relative_frame, x, y in path_points
        }
        phase_markers: List[Dict[str, Any]] = []
        if visualization_config.draw_phase_markers and swing_phases is not None:
            source_to_relative = {int(source): idx for idx, source in enumerate(frame_indices)}
            for phase in getattr(swing_phases, "phases", []):
                raw_frame = int(getattr(phase, "frame_index", -1))
                relative_frame = self._dense_relative_frame(raw_frame, frame_indices, source_to_relative)
                if relative_frame is None:
                    continue
                source_frame = int(frame_indices[relative_frame])
                phase_markers.append(
                    {
                        "phase": int(getattr(phase, "phase_number", 0)),
                        "name": getattr(phase, "name", ""),
                        "description": getattr(phase, "description", ""),
                        "frame_index": source_frame,
                        "relative_frame_index": relative_frame,
                        "timestamp": round(float(source_frame) / max(video_fps, 1e-6), 4),
                        "relative_timestamp": round(float(relative_frame) / max(video_fps, 1e-6), 4),
                        "confidence": round(float(getattr(phase, "confidence", 0.0)), 4),
                    }
                )
            phase_markers.sort(key=lambda item: item["relative_frame_index"])
        confidence_evidence = (
            self._confidence_evidence(phase_markers, speed_data, ball_contact=ball_contact)
            if visualization_config.draw_confidence
            else None
        )
        ball_contact_frames = ball_contact.get("frames", {}) if ball_contact else {}

        frames: List[Dict[str, Any]] = []
        for relative_idx, (source_frame, pose) in enumerate(zip(frame_indices, poses2d)):
            layers: Dict[str, Any] = {}

            if visualization_config.draw_skeleton or visualization_config.draw_reference_lines:
                keypoints = self._pose_keypoints(pose, visualization_config.min_visibility)
                if visualization_config.draw_skeleton and keypoints:
                    layers["skeleton"] = {
                        "keypoints": keypoints,
                        "connections": self._visible_pose_connections(keypoints),
                    }
                if visualization_config.draw_reference_lines and keypoints:
                    reference_lines = self._reference_lines(keypoints)
                    if reference_lines:
                        layers["reference_lines"] = {"lines": reference_lines}

            if visualization_config.draw_swing_path:
                points = [
                    point
                    for path_frame, point in path_by_relative_frame.items()
                    if path_frame <= relative_idx
                ]
                if points:
                    layers["swing_path"] = {"points": points}

            if visualization_config.draw_club_plane and club_plane is not None:
                layers["club_plane"] = {
                    "line": club_plane["line"],
                    "angle_degrees": club_plane["angle_degrees"],
                    "confidence": club_plane["confidence"],
                    "frame_index": club_plane["frame_index"],
                }

            if visualization_config.draw_ball_contact and relative_idx in ball_contact_frames:
                layers["ball_contact"] = ball_contact_frames[relative_idx]

            frame_speed = speed_data.get(source_frame)
            if frame_speed is not None:
                layers["speed"] = {
                    "speed_mph": round(float(frame_speed), 2),
                    "is_peak": bool(peak_frame is not None and source_frame == peak_frame),
                }

            frames.append(
                {
                    "frame_index": int(source_frame),
                    "relative_frame_index": int(relative_idx),
                    "timestamp": round(float(source_frame) / max(video_fps, 1e-6), 4),
                    "relative_timestamp": round(float(relative_idx) / max(video_fps, 1e-6), 4),
                    "layers": layers,
                }
            )

        return {
            "version": 1,
            "coordinate_space": "normalized",
            "frame_width": frame_width,
            "frame_height": frame_height,
            "fps": video_fps,
            "peak_speed_mph": round(float(peak_speed), 2) if peak_speed is not None else None,
            "peak_speed_frame": peak_frame,
            "ball_contact": ball_contact.get("summary") if ball_contact else None,
            "phase_markers": phase_markers,
            "confidence_evidence": confidence_evidence,
            "frames": frames,
        }

    def render(
        self,
        run_store: Any,
        frames: List[bytes],
        poses2d: List[Optional[Any]],
        frame_indices: List[int],
        video_fps: float,
        frame_width: int,
        frame_height: int,
        club2d_frames: List[Any],
        poses3d: List[Optional[Any]],
        club3d_frames: List[Any],
        swing_phases: Optional[Any] = None,
    ) -> ArtifactRenderResult:
        debug_files: List[str] = []

        path_points = []
        source_to_relative = {int(source): idx for idx, source in enumerate(frame_indices)}
        for item in club2d_frames:
            if item.clubhead_centroid_px is None:
                continue
            x, y = item.clubhead_centroid_px
            relative_idx = source_to_relative.get(int(item.frame_index))
            if relative_idx is not None:
                path_points.append((relative_idx, x, y))

        swing_path = _SwingPathProxy(points_with_frame=path_points) if path_points else None
        club_plane = self._club_plane_track(
            club2d_frames=club2d_frames,
            frame_indices=frame_indices,
            frame_width=frame_width,
            frame_height=frame_height,
            swing_phases=swing_phases,
        )
        club_plane_line = club_plane["pixel_line"] if club_plane is not None else None
        ball_contact = self._ball_contact_track(
            frames=frames,
            frame_indices=frame_indices,
            frame_width=frame_width,
            frame_height=frame_height,
            club2d_frames=club2d_frames,
            swing_phases=swing_phases,
        )

        speed_data, peak_speed, peak_frame = self._speed_map(club3d_frames, fps=video_fps)
        relative_speed_data = {
            max(0, frame_index - frame_indices[0]): speed
            for frame_index, speed in speed_data.items()
        }
        relative_peak_frame = peak_frame - frame_indices[0] if peak_frame is not None else None

        visualization_config = VisualizationConfig(
            draw_skeleton=True,
            draw_reference_lines=True,
            draw_club_plane=club_plane is not None,
            draw_swing_path=True,
            draw_ball_contact=ball_contact is not None,
            draw_phase_markers=True,
            draw_confidence=True,
            draw_club_mask=False,
            min_visibility=0.5,
        )

        exporter = VideoExporter()
        base_video_bytes = exporter.export_video(frames, fps=video_fps)
        run_store.save_bytes("base.mp4", base_video_bytes)

        visualizer = SwingVisualizer(frame_width=frame_width, frame_height=frame_height)
        annotated_frames = visualizer.draw_complete_analysis_batch(
            frames=frames,
            poses=poses2d,
            club_plane_line=club_plane_line,
            swing_path=swing_path,
            club_masks=None,
            draw_skeleton=visualization_config.draw_skeleton,
            draw_reference_lines=visualization_config.draw_reference_lines,
            draw_club_plane=visualization_config.draw_club_plane,
            draw_swing_path=visualization_config.draw_swing_path,
            draw_club_mask=visualization_config.draw_club_mask,
            min_visibility=visualization_config.min_visibility,
            speed_data=relative_speed_data,
            peak_speed=peak_speed,
            peak_speed_frame=relative_peak_frame,
            draw_speed=bool(speed_data),
        )

        video_bytes = exporter.export_video(annotated_frames, fps=video_fps)
        run_store.save_bytes("annotated.mp4", video_bytes)

        swing_3d_name: Optional[str] = None
        if poses3d and any(p is not None for p in poses3d):
            valid_poses = [p for p in poses3d if p is not None]
            if valid_poses:
                swing_3d_name = "swing_3d.gltf"
                export_swing_animation(
                    poses=valid_poses,
                    filename=swing_3d_name,
                    fps=video_fps,
                    output_dir=str(run_store.run_dir),
                    club_frames=club3d_frames,
                )

        metadata = VisualizationMetadata.from_config(visualization_config)
        metadata.video_fps = video_fps
        metadata.frame_count = len(frames)
        metadata.swing_path_point_count = len(path_points)
        if club_plane is not None:
            metadata.club_plane_angle_degrees = club_plane["angle_degrees"]
        if speed_data and not any(layer.name == "speed" for layer in metadata.layers):
            metadata.layers.append(LAYER_DEFINITIONS["speed"])
        run_store.save_json("annotation_metadata.json", metadata.to_dict())
        annotation_tracks = self._annotation_tracks(
            poses2d=poses2d,
            frame_indices=frame_indices,
            video_fps=video_fps,
            frame_width=frame_width,
            frame_height=frame_height,
            path_points=path_points,
            speed_data=speed_data,
            peak_speed=peak_speed,
            peak_frame=peak_frame,
            visualization_config=visualization_config,
            club_plane=club_plane,
            ball_contact=ball_contact,
            swing_phases=swing_phases,
        )
        run_store.save_json("annotation_tracks.json", annotation_tracks)

        return ArtifactRenderResult(
            base_video_filename="base.mp4",
            annotated_video_filename="annotated.mp4",
            swing_3d_filename=swing_3d_name,
            annotation_tracks_filename="annotation_tracks.json",
            debug_files=debug_files,
            annotation_metadata=metadata.to_dict(),
        )
