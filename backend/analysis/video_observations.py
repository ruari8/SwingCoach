"""Calculate image-space observations and explanatory overlays from pose samples.

No fault thresholds, physical distances, pressure estimates or impact claims are
derived from these 2D landmarks. Every measurement retains its sample timestamps.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
from statistics import mean

from .metrics_engine import MetricCard


VISIBILITY_MIN = 0.65
BODY_POINTS = ("nose", "left_shoulder", "right_shoulder", "left_hip", "right_hip",
               "left_wrist", "right_wrist", "left_ankle", "right_ankle")


@dataclass
class VideoObservations:
    samples: list[dict]
    metrics: list[MetricCard]
    observations: list[dict]
    layers_by_frame: dict[int, dict]
    warnings: list[str]


def measure_poses(poses, *, fps: float, width: int, height: int, vantage: str) -> VideoObservations:
    samples = []
    for pose in poses:
        points = {name: {"x": p.x, "y": p.y, "confidence": p.visibility}
                  for name in BODY_POINTS if (p := pose.keypoints.get(name)) is not None
                  and p.visibility >= VISIBILITY_MIN
                  and math.isfinite(p.x) and math.isfinite(p.y)
                  and 0 <= p.x <= 1 and 0 <= p.y <= 1}
        if points:
            samples.append({"frame_index": pose.frame_index, "timestamp": pose.frame_index / fps,
                            "points": points})
    samples.sort(key=lambda sample: sample["frame_index"])
    observations, metrics, layers = [], [], {}

    def midpoint(sample, part):
        left, right = (sample["points"].get(f"{side}_{part}") for side in ("left", "right"))
        if not left or not right:
            return None
        return {"x": (left["x"] + right["x"]) / 2, "y": (left["y"] + right["y"]) / 2,
                "confidence": min(left["confidence"], right["confidence"])}

    def metric(key, name, values, unit, explanation):
        if len(values) < 4:
            return
        low, high = min(values, key=lambda v: v[0]), max(values, key=lambda v: v[0])
        confidence = min(mean(v[2] for v in values), 0.85)
        value = round(high[0] - low[0], 2)
        metrics.append(MetricCard(key, name, value, unit, confidence, explanation,
                                  "Compare like-for-like recordings and ball outcome before changing this movement."))
        observations.append({"id": key, "kind": "measured_2d", "description": explanation,
                             "value": value, "unit": unit, "confidence": confidence,
                             "frame_indices": [low[1], high[1]], "vantage": vantage,
                             "method": "range_across_visible_samples_not_phase_specific",
                             "limitations": ["Includes setup and follow-through; not a fault score.",
                                             "Camera movement and perspective affect this quantity."]})

    for axis, dimension in (("x", "width"), ("y", "height")):
        values = [(s["points"]["nose"][axis] * 100, s["frame_index"], s["points"]["nose"]["confidence"])
                  for s in samples if "nose" in s["points"]]
        metric(f"head_{axis}_range_pct", f"Head {('horizontal' if axis == 'x' else 'vertical')} range",
               values, f"% frame {dimension}", f"Nose landmark movement across the visible clip, as a percentage of image {dimension}.")
    torso_values = []
    for s in samples:
        shoulder, hip = midpoint(s, "shoulder"), midpoint(s, "hip")
        if shoulder and hip:
            dx, dy = (shoulder["x"] - hip["x"]) * width, (hip["y"] - shoulder["y"]) * height
            if math.hypot(dx, dy) >= height * 0.05:
                torso_values.append((math.degrees(math.atan2(dx, dy)), s["frame_index"],
                                     min(shoulder["confidence"], hip["confidence"])))
    metric("torso_image_angle_range_deg", "Torso image-angle range", torso_values, "deg",
           "Change in the projected shoulder-to-hip line across the clip. This is not 3D spine tilt or rotation.")

    # The baseline is explicitly the first reliable sample, not an assumed address.
    baseline = next((s for s in samples if "nose" in s["points"] and midpoint(s, "hip") and midpoint(s, "shoulder")), None)
    hand_path = []
    last_frame = None
    for sample in samples:
        guides = []
        frame = sample["frame_index"]
        if last_frame is not None and frame - last_frame > fps * 0.25:
            hand_path = []  # Do not draw a line through a detector dropout.
        hands = midpoint(sample, "wrist")
        if hands:
            hand_path.append({"x": hands["x"], "y": hands["y"]})
            hand_path = hand_path[-12:]
            guides.append({"id": "hands", "layer": "hand_path", "kind": "polyline",
                           "points": list(hand_path), "label": "Hands · 2D", "color": "#F5C76B",
                           "confidence": hands["confidence"]})
        else:
            hand_path = []
        shoulder, hip = midpoint(sample, "shoulder"), midpoint(sample, "hip")
        if shoulder and hip:
            guides.append({"id": "torso", "layer": "body_reference", "kind": "line",
                           "points": [shoulder, hip], "label": "Torso · 2D", "color": "#67D6B0",
                           "confidence": min(shoulder["confidence"], hip["confidence"])})
        if baseline is not None and frame >= baseline["frame_index"] and "nose" in sample["points"]:
            nose = baseline["points"]["nose"]
            guides.append({"id": "head_reference", "layer": "body_reference", "kind": "circle",
                           "center": {"x": nose["x"], "y": nose["y"]}, "radius": 0.025,
                           "label": "First visible head position", "color": "#D6E4ED",
                           "confidence": nose["confidence"], "style": "dashed"})
        if guides:
            layers[frame] = {"guides": guides}
        last_frame = frame
    warnings = ["Image-space measurements are descriptive, not validated diagnoses.",
                "Clubface, shaft, pressure, mobility and ball flight are not measured by this body-pose pass."]
    if not metrics:
        warnings.append("Too few reliable body samples to calculate movement measurements.")
    return VideoObservations(samples, metrics, observations, layers, warnings)
