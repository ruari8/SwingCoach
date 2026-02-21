"""Coachable metric cards with confidence and plain-English guidance."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple

import numpy as np


@dataclass
class MetricCard:
    key: str
    name: str
    value: Optional[float]
    unit: str
    confidence: float
    explanation: str
    fix_hint: str


@dataclass
class MetricsEngineResult:
    metrics: List[MetricCard]
    raw_values: Dict[str, Optional[float]]
    warnings: List[str]


class CoachMetricsEngine:
    """Transforms raw biomechanical outputs into coachable metric cards."""

    def _metric(self, key: str, name: str, value: Optional[float], unit: str, confidence: float, explanation: str, fix_hint: str) -> MetricCard:
        return MetricCard(
            key=key,
            name=name,
            value=value,
            unit=unit,
            confidence=float(max(0.0, min(1.0, confidence))),
            explanation=explanation,
            fix_hint=fix_hint,
        )

    def _club_velocity_profile(self, club_3d_frames: List[Any], fps: float) -> List[Tuple[int, float, np.ndarray]]:
        profile: List[Tuple[int, float, np.ndarray]] = []
        if len(club_3d_frames) < 2:
            return profile

        previous = None
        for frame in club_3d_frames:
            head = np.array(frame.clubhead_point, dtype=np.float32)
            if previous is None:
                previous = (frame.frame_index, head)
                continue

            prev_frame, prev_head = previous
            dt_frames = max(1, frame.frame_index - prev_frame)
            dt = dt_frames / max(fps, 1e-6)
            velocity = (head - prev_head) / max(dt, 1e-6)
            speed_mps = float(np.linalg.norm(velocity))
            speed_mph = speed_mps * 2.23693629
            profile.append((frame.frame_index, speed_mph, velocity))
            previous = (frame.frame_index, head)

        return profile

    def build(
        self,
        base_metrics: Any,
        club_3d_frames: List[Any],
        events: Any,
        fps: float,
        club_detection_confidence: float,
    ) -> MetricsEngineResult:
        warnings: List[str] = []
        cards: List[MetricCard] = []

        tempo = getattr(base_metrics, "tempo_ratio", None)
        head_sway = getattr(base_metrics, "head_sway_inches", None)
        spine_change = getattr(base_metrics, "spine_angle_change", None)
        shoulder_turn = getattr(base_metrics, "shoulder_turn_degrees", None)
        hip_turn = getattr(base_metrics, "hip_turn_degrees", None)

        cards.extend([
            self._metric(
                key="tempo_ratio",
                name="Tempo Ratio",
                value=tempo,
                unit=":1",
                confidence=0.85 if tempo is not None else 0.0,
                explanation="Backswing time compared with downswing time.",
                fix_hint="Aim for a smoother transition and consistent rhythm count.",
            ),
            self._metric(
                key="head_sway_inches",
                name="Head Sway",
                value=head_sway,
                unit="in",
                confidence=0.75 if head_sway is not None else 0.0,
                explanation="How much your head shifts laterally during the swing.",
                fix_hint="Keep pressure centered and rotate around a stable head position.",
            ),
            self._metric(
                key="spine_angle_change",
                name="Spine Angle Change",
                value=spine_change,
                unit="deg",
                confidence=0.8 if spine_change is not None else 0.0,
                explanation="Difference in spine tilt between setup and impact.",
                fix_hint="Maintain posture through impact instead of standing up early.",
            ),
            self._metric(
                key="shoulder_turn_degrees",
                name="Shoulder Turn",
                value=shoulder_turn,
                unit="deg",
                confidence=0.8 if shoulder_turn is not None else 0.0,
                explanation="How far your shoulders rotate at the top.",
                fix_hint="Build a fuller but balanced turn while keeping structure.",
            ),
            self._metric(
                key="hip_turn_degrees",
                name="Hip Turn",
                value=hip_turn,
                unit="deg",
                confidence=0.75 if hip_turn is not None else 0.0,
                explanation="How far your hips rotate at the top.",
                fix_hint="Allow hip rotation without excessive slide.",
            ),
        ])

        profile = self._club_velocity_profile(club_3d_frames, fps=fps)
        if not profile:
            warnings.append("Club 3D track is insufficient for club delivery metrics.")
            cards.extend([
                self._metric("club_speed_mph", "Club Speed", None, "mph", 0.0, "Estimated clubhead speed through downswing.", "Improve club tracking confidence to unlock this metric."),
                self._metric("swing_plane_dev", "Swing Plane Deviation", None, "deg", 0.0, "How far the shaft direction departs from setup plane.", "Improve shaft tracking confidence."),
                self._metric("club_path_deg", "Club Path", None, "deg", 0.0, "Horizontal travel direction of the club through impact.", "Improve club tracking confidence."),
                self._metric("attack_angle_deg", "Attack Angle", None, "deg", 0.0, "Vertical strike angle into impact.", "Improve club tracking confidence."),
            ])
            raw_values = {card.key: card.value for card in cards}
            return MetricsEngineResult(metrics=cards, raw_values=raw_values, warnings=warnings)

        peak_frame, peak_speed, _ = max(profile, key=lambda item: item[1])

        impact_frame = events.impact.frame_index if events and getattr(events, "impact", None) else None
        impact_velocity: Optional[np.ndarray] = None
        impact_speed: Optional[float] = None

        if impact_frame is not None:
            nearest = min(profile, key=lambda item: abs(item[0] - impact_frame))
            if abs(nearest[0] - impact_frame) <= 3:
                impact_speed = nearest[1]
                impact_velocity = nearest[2]
            else:
                warnings.append("Impact frame is outside reliable club velocity samples.")

        # Setup-frame shaft direction used as a baseline swing plane proxy.
        setup_dir = np.array(club_3d_frames[0].shaft_direction, dtype=np.float32)
        setup_dir /= max(np.linalg.norm(setup_dir), 1e-8)

        deviations: List[float] = []
        for frame in club_3d_frames:
            current = np.array(frame.shaft_direction, dtype=np.float32)
            current /= max(np.linalg.norm(current), 1e-8)
            dot = float(np.clip(np.dot(setup_dir, current), -1.0, 1.0))
            deviations.append(np.degrees(np.arccos(dot)))

        swing_plane_dev = float(np.mean(deviations)) if deviations else None

        club_path = None
        attack_angle = None
        if impact_velocity is not None:
            vx, vy, vz = [float(v) for v in impact_velocity]
            horizontal = max(np.sqrt(vx * vx + vz * vz), 1e-8)
            club_path = float(np.degrees(np.arctan2(vx, vz)))
            attack_angle = float(np.degrees(np.arctan2(-vy, horizontal)))

        club_conf = min(1.0, max(0.05, club_detection_confidence))
        cards.extend([
            self._metric(
                key="club_speed_mph",
                name="Club Speed",
                value=peak_speed,
                unit="mph",
                confidence=club_conf,
                explanation="Estimated peak 3D clubhead speed in the dense swing window.",
                fix_hint="Increase speed only after improving face/path consistency.",
            ),
            self._metric(
                key="swing_plane_dev",
                name="Swing Plane Deviation",
                value=swing_plane_dev,
                unit="deg",
                confidence=club_conf * 0.9,
                explanation="Average shaft-direction deviation from setup orientation.",
                fix_hint="Use takeaway and transition drills to keep shaft closer to plane.",
            ),
            self._metric(
                key="club_path_deg",
                name="Club Path",
                value=club_path,
                unit="deg",
                confidence=club_conf * (0.95 if club_path is not None else 0.0),
                explanation="Horizontal direction of club travel near impact.",
                fix_hint="Gate drills help neutralize in-to-out or out-to-in extremes.",
            ),
            self._metric(
                key="attack_angle_deg",
                name="Attack Angle",
                value=attack_angle,
                unit="deg",
                confidence=club_conf * (0.9 if attack_angle is not None else 0.0),
                explanation="Vertical angle of club travel near impact.",
                fix_hint="Match ball position and low-point control to desired strike pattern.",
            ),
        ])

        raw_values = {card.key: card.value for card in cards}
        raw_values["impact_speed_mph"] = impact_speed
        raw_values["peak_speed_frame"] = peak_frame

        return MetricsEngineResult(metrics=cards, raw_values=raw_values, warnings=warnings)

