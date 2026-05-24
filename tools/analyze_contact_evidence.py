#!/usr/bin/env python3
"""Score simple ball/contact pixel evidence for swing-detector fixture reports."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import cv2
import numpy as np

try:
    import mediapipe as mp
except ImportError:  # pragma: no cover - optional local diagnostic dependency.
    mp = None

_POSE_MODEL: Any | None = None


@dataclass(frozen=True)
class BlobEvidence:
    center_x: float
    center_y: float
    area: int
    width: int
    height: int
    pre_luma: float
    stable_luma: float
    post_luma: float
    final_luma: float
    stable_delta: float
    transient_luma_delta: float
    luma_delta: float
    shaft_support: float

    def to_dict(self) -> dict[str, Any]:
        return {
            "center": [round(self.center_x, 1), round(self.center_y, 1)],
            "area": self.area,
            "size": [self.width, self.height],
            "pre_luma": round(self.pre_luma, 2),
            "stable_luma": round(self.stable_luma, 2),
            "post_luma": round(self.post_luma, 2),
            "final_luma": round(self.final_luma, 2),
            "stable_delta": round(self.stable_delta, 2),
            "transient_luma_delta": round(self.transient_luma_delta, 2),
            "luma_delta": round(self.luma_delta, 2),
            "shaft_support": round(self.shaft_support, 3),
        }


def read_frame(video: Path, time_seconds: float) -> np.ndarray:
    capture = cv2.VideoCapture(str(video))
    if not capture.isOpened():
        raise RuntimeError(f"failed to open video: {video}")

    capture.set(cv2.CAP_PROP_POS_MSEC, max(0.0, time_seconds) * 1000.0)
    ok, frame = capture.read()
    capture.release()
    if not ok or frame is None:
        raise RuntimeError(f"failed to read frame at {time_seconds:.3f}s from {video}")
    return frame


def mat_roi(frame: np.ndarray) -> tuple[int, int, int, int]:
    height, width = frame.shape[:2]
    lower_half_y = int(height * 0.52)
    search = frame[lower_half_y:, :]
    hsv = cv2.cvtColor(search, cv2.COLOR_BGR2HSV)
    green = cv2.inRange(hsv, np.array([35, 35, 35]), np.array([95, 255, 230]))
    green = cv2.morphologyEx(green, cv2.MORPH_CLOSE, np.ones((11, 11), np.uint8))

    contours, _ = cv2.findContours(green, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return (int(width * 0.05), int(height * 0.55), int(width * 0.95), int(height * 0.94))

    contour = max(contours, key=cv2.contourArea)
    x, y, w, h = cv2.boundingRect(contour)
    min_x = max(0, x - 20)
    max_x = min(width, x + w + 20)
    min_y = max(0, lower_half_y + y - 20)
    max_y = min(height, lower_half_y + y + h + 20)

    # Avoid the bottom platform edge and side walls where white borders/screws can dominate.
    return (
        max(min_x, int(width * 0.05)),
        max(min_y, int(height * 0.55)),
        min(max_x, int(width * 0.95)),
        min(max_y, int(height * 0.94)),
    )


def bright_ball_blobs(
    frame: np.ndarray,
    roi: tuple[int, int, int, int],
    excluded_points: list[tuple[float, float]],
    exclusion_radius: float,
) -> list[tuple[int, int, int, int, int]]:
    min_x, min_y, max_x, max_y = roi
    crop = frame[min_y:max_y, min_x:max_x]
    hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
    yuv = cv2.cvtColor(crop, cv2.COLOR_BGR2YUV)
    luma = yuv[:, :, 0]

    bright = cv2.inRange(hsv, np.array([0, 0, 135]), np.array([179, 115, 255]))
    bright = cv2.bitwise_and(bright, cv2.inRange(luma, 145, 255))
    bright = cv2.morphologyEx(bright, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    bright = cv2.morphologyEx(bright, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))

    contours, _ = cv2.findContours(bright, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    blobs: list[tuple[int, int, int, int, int]] = []
    for contour in contours:
        area = int(cv2.contourArea(contour))
        if area < 18 or area > 900:
            continue

        x, y, w, h = cv2.boundingRect(contour)
        if w < 5 or h < 5 or w > 55 or h > 55:
            continue

        aspect = w / max(1, h)
        if aspect < 0.45 or aspect > 2.2:
            continue

        fill = area / max(1, w * h)
        if fill < 0.24:
            continue

        global_x = min_x + x
        global_y = min_y + y
        center_x = global_x + w / 2
        center_y = global_y + h / 2
        if is_near_excluded_point(center_x, center_y, excluded_points, exclusion_radius):
            continue
        mat_like_min_y = max(frame.shape[0] * 0.70, min_y + (max_y - min_y) * 0.18)
        if center_y < mat_like_min_y:
            continue
        # Exclude the mat border/tee holes at the very bottom.
        if global_y + h > int(frame.shape[0] * 0.90):
            continue
        if green_support_ratio(frame, global_x, global_y, w, h) < 0.22:
            continue
        blobs.append((global_x, global_y, w, h, area))

    return blobs


def is_near_excluded_point(
    center_x: float,
    center_y: float,
    points: list[tuple[float, float]],
    radius: float,
) -> bool:
    return any(float(np.hypot(center_x - point_x, center_y - point_y)) <= radius for point_x, point_y in points)


def lower_body_exclusion_points(frame: np.ndarray) -> list[tuple[float, float]]:
    if mp is None or not hasattr(mp, "solutions"):
        return []

    global _POSE_MODEL
    if _POSE_MODEL is None:
        _POSE_MODEL = mp.solutions.pose.Pose(
            static_image_mode=True,
            model_complexity=1,
            enable_segmentation=False,
            min_detection_confidence=0.35,
        )

    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    result = _POSE_MODEL.process(rgb)
    if not result.pose_landmarks:
        return []

    height, width = frame.shape[:2]
    landmark_names = mp.solutions.pose.PoseLandmark
    lower_landmarks = [
        landmark_names.LEFT_ANKLE,
        landmark_names.RIGHT_ANKLE,
        landmark_names.LEFT_HEEL,
        landmark_names.RIGHT_HEEL,
        landmark_names.LEFT_FOOT_INDEX,
        landmark_names.RIGHT_FOOT_INDEX,
    ]
    points: list[tuple[float, float]] = []
    for name in lower_landmarks:
        landmark = result.pose_landmarks.landmark[name.value]
        if landmark.visibility < 0.28:
            continue
        points.append((landmark.x * width, landmark.y * height))

    return points


def green_support_ratio(frame: np.ndarray, x: int, y: int, w: int, h: int) -> float:
    height, width = frame.shape[:2]
    pad = max(10, int(max(w, h) * 1.4))
    min_x = max(0, x - pad)
    max_x = min(width, x + w + pad)
    min_y = max(0, y - pad)
    max_y = min(height, y + h + pad)
    patch = frame[min_y:max_y, min_x:max_x]
    if patch.size == 0:
        return 0.0

    hsv = cv2.cvtColor(patch, cv2.COLOR_BGR2HSV)
    green = cv2.inRange(hsv, np.array([35, 30, 30]), np.array([95, 255, 235]))
    center_min_x = x - min_x
    center_max_x = center_min_x + w
    center_min_y = y - min_y
    center_max_y = center_min_y + h
    green[center_min_y:center_max_y, center_min_x:center_max_x] = 0

    ring_area = green.size - max(0, w * h)
    if ring_area <= 0:
        return 0.0
    return float(np.count_nonzero(green)) / float(ring_area)


def clubhead_estimate(frame: np.ndarray, roi: tuple[int, int, int, int]) -> dict[str, Any] | None:
    min_x, min_y, max_x, max_y = roi
    height, width = frame.shape[:2]
    search_min_y = max(int(height * 0.36), min_y - int(height * 0.25))
    search = frame[search_min_y:max_y, min_x:max_x]
    gray = cv2.cvtColor(search, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 45, 130)
    lines = cv2.HoughLinesP(edges, 1, np.pi / 180, threshold=45, minLineLength=105, maxLineGap=18)
    if lines is None:
        return None

    best: dict[str, Any] | None = None
    best_score = -1.0
    for raw_line in lines[:, 0]:
        x1, y1, x2, y2 = [int(value) for value in raw_line]
        dx = x2 - x1
        dy = y2 - y1
        length = float(np.hypot(dx, dy))
        if length < 105:
            continue

        angle = abs(np.degrees(np.arctan2(dy, dx)))
        angle = min(angle, 180 - angle)
        if angle < 38 or angle > 82:
            continue

        local_lower = (x1, y1) if y1 >= y2 else (x2, y2)
        local_upper = (x2, y2) if y1 >= y2 else (x1, y1)
        lower = (min_x + local_lower[0], search_min_y + local_lower[1])
        upper = (min_x + local_upper[0], search_min_y + local_upper[1])
        if lower[1] < min_y - 35 or lower[1] > max_y + 35:
            continue
        if lower[0] < width * 0.18 or lower[0] > width * 0.84:
            continue
        if lower[1] > min_y + (max_y - min_y) * 0.74:
            continue

        mask = np.zeros(gray.shape, dtype=np.uint8)
        cv2.line(mask, (x1, y1), (x2, y2), 255, 3)
        line_pixels = gray[mask > 0]
        if line_pixels.size == 0:
            continue
        line_luma = float(line_pixels.mean())
        if line_luma > 150:
            continue

        lower_score = max(0.0, 1 - abs(lower[1] - ((min_y + max_y) / 2)) / max(1, max_y - min_y))
        darkness_score = max(0.0, 1 - line_luma / 160)
        score = length * 0.018 + lower_score * 2.2 + darkness_score * 2.4
        if score > best_score:
            best_score = score
            best = {
                "head": [float(lower[0]), float(lower[1])],
                "upper": [float(upper[0]), float(upper[1])],
                "length": round(length, 2),
                "angle": round(float(angle), 2),
                "line_luma": round(line_luma, 2),
                "score": round(score, 3),
            }

    return best


def shaft_lines(frame: np.ndarray, roi: tuple[int, int, int, int]) -> list[dict[str, Any]]:
    min_x, min_y, max_x, max_y = roi
    height = frame.shape[0]
    search_min_y = max(int(height * 0.34), min_y - int(height * 0.30))
    search = frame[search_min_y:max_y, min_x:max_x]
    gray = cv2.cvtColor(search, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 45, 130)
    lines = cv2.HoughLinesP(edges, 1, np.pi / 180, threshold=40, minLineLength=95, maxLineGap=18)
    if lines is None:
        return []

    result: list[dict[str, Any]] = []
    for raw_line in lines[:, 0]:
        x1, y1, x2, y2 = [int(value) for value in raw_line]
        dx = x2 - x1
        dy = y2 - y1
        length = float(np.hypot(dx, dy))
        if length < 95:
            continue

        angle = abs(np.degrees(np.arctan2(dy, dx)))
        angle = min(angle, 180 - angle)
        if angle < 36 or angle > 84:
            continue

        mask = np.zeros(gray.shape, dtype=np.uint8)
        cv2.line(mask, (x1, y1), (x2, y2), 255, 3)
        line_pixels = gray[mask > 0]
        if line_pixels.size == 0:
            continue
        line_luma = float(line_pixels.mean())
        if line_luma > 155:
            continue

        local_lower = (x1, y1) if y1 >= y2 else (x2, y2)
        local_upper = (x2, y2) if y1 >= y2 else (x1, y1)
        result.append(
            {
                "lower": [float(min_x + local_lower[0]), float(search_min_y + local_lower[1])],
                "upper": [float(min_x + local_upper[0]), float(search_min_y + local_upper[1])],
                "length": length,
                "angle": float(angle),
                "line_luma": line_luma,
            }
        )

    return result


def shaft_support_score(center_x: float, center_y: float, lines: list[dict[str, Any]]) -> float:
    best = 0.0
    for line in lines:
        lower_x, lower_y = line["lower"]
        upper_x, upper_y = line["upper"]
        if upper_y >= center_y:
            continue
        if lower_y < center_y - 190 or lower_y > center_y + 210:
            continue

        distance = float(np.hypot(center_x - lower_x, center_y - lower_y))
        if distance > 240:
            continue

        distance_score = max(0.0, 1 - distance / 240)
        length_score = min(1.0, float(line["length"]) / 620)
        darkness_score = max(0.0, 1 - float(line["line_luma"]) / 155)
        best = max(best, 0.58 * distance_score + 0.28 * length_score + 0.14 * darkness_score)

    return best


def patch_luma(frame: np.ndarray, x: int, y: int, w: int, h: int, pad: int) -> float:
    height, width = frame.shape[:2]
    min_x = max(0, x - pad)
    max_x = min(width, x + w + pad)
    min_y = max(0, y - pad)
    max_y = min(height, y + h + pad)
    patch = frame[min_y:max_y, min_x:max_x]
    if patch.size == 0:
        return 0.0
    return float(cv2.cvtColor(patch, cv2.COLOR_BGR2YUV)[:, :, 0].mean())


def contact_evidence(
    stable_frame: np.ndarray,
    pre_frame: np.ndarray,
    post_frame: np.ndarray,
    final_frame: np.ndarray,
    require_club_proximity: bool,
    club_radius: float,
    exclude_lower_body: bool,
    lower_body_radius: float,
    require_shaft_support: bool,
    shaft_support_threshold: float,
    require_pre_stability: bool,
    pre_stability_tolerance: float,
) -> dict[str, Any]:
    roi = mat_roi(pre_frame)
    club = clubhead_estimate(pre_frame, roi)
    lines = shaft_lines(pre_frame, roi)
    excluded_points = lower_body_exclusion_points(pre_frame) if exclude_lower_body else []
    blobs = bright_ball_blobs(
        pre_frame,
        roi,
        excluded_points=excluded_points,
        exclusion_radius=lower_body_radius,
    )
    evidence: list[BlobEvidence] = []

    for x, y, w, h, area in blobs:
        if club is not None:
            head_x, head_y = club["head"]
            center_x = x + w / 2
            center_y = y + h / 2
            if float(np.hypot(center_x - head_x, center_y - head_y)) > club_radius:
                continue
        elif require_club_proximity:
            continue

        pad = max(4, int(max(w, h) * 0.45))
        center_x = x + w / 2
        center_y = y + h / 2
        shaft_support = shaft_support_score(center_x, center_y, lines)
        if require_shaft_support and shaft_support < shaft_support_threshold:
            continue

        stable_luma = patch_luma(stable_frame, x, y, w, h, pad)
        pre_luma = patch_luma(pre_frame, x, y, w, h, pad)
        stable_delta = abs(pre_luma - stable_luma)
        if require_pre_stability and stable_delta > pre_stability_tolerance:
            continue

        post_luma = patch_luma(post_frame, x, y, w, h, pad)
        final_luma = patch_luma(final_frame, x, y, w, h, pad)
        transient_delta = pre_luma - post_luma
        persistent_delta = min(transient_delta, pre_luma - final_luma)
        evidence.append(
            BlobEvidence(
                center_x=x + w / 2,
                center_y=y + h / 2,
                area=area,
                width=w,
                height=h,
                stable_luma=stable_luma,
                pre_luma=pre_luma,
                post_luma=post_luma,
                final_luma=final_luma,
                stable_delta=stable_delta,
                transient_luma_delta=transient_delta,
                luma_delta=persistent_delta,
                shaft_support=shaft_support,
            )
        )

    evidence.sort(key=lambda item: item.luma_delta, reverse=True)
    best = evidence[0] if evidence else None
    return {
        "roi": list(roi),
        "club": club,
        "shaft_line_count": len(lines),
        "require_shaft_support": require_shaft_support,
        "shaft_support_threshold": shaft_support_threshold,
        "require_pre_stability": require_pre_stability,
        "pre_stability_tolerance": pre_stability_tolerance,
        "lower_body_exclusion_points": [[round(x, 1), round(y, 1)] for x, y in excluded_points],
        "lower_body_radius": lower_body_radius,
        "require_club_proximity": require_club_proximity,
        "club_radius": club_radius,
        "candidate_count": len(evidence),
        "best": best.to_dict() if best else None,
        "top_candidates": [item.to_dict() for item in evidence[:5]],
    }


def event_times(case: dict[str, Any], detection: dict[str, Any] | None) -> tuple[float, float, str]:
    clip = case["clip"]
    clip_start = float(clip["start"])
    clip_end = float(clip["end"])

    if case["kind"] == "positive" and case.get("label"):
        label = case["label"]
        event_start = float(label["start"])
        event_end = float(label["end"])
        return (
            max(clip_start + 0.2, event_start + 0.3),
            min(clip_end - 0.2, event_end + 1.0),
            "label",
        )

    if detection is not None:
        event_start = float(detection["start"])
        event_end = float(detection["end"])
        return (
            max(clip_start + 0.2, event_start - 1.0),
            min(clip_end - 0.2, event_end + 1.0),
            "detection",
        )

    raise ValueError("case has no label or detection to score")


def score_case(
    case: dict[str, Any],
    threshold: float,
    require_club_proximity: bool,
    club_radius: float,
    exclude_lower_body: bool,
    lower_body_radius: float,
    require_shaft_support: bool,
    shaft_support_threshold: float,
    require_pre_stability: bool,
    pre_stability_tolerance: float,
    stability_lookback: float,
) -> dict[str, Any]:
    clip_path = Path(case["clip"]["path"])
    detections = case.get("detections") or [None]
    scored_events = []

    for detection in detections:
        if case["kind"] == "negative" and detection is None:
            continue

        pre_abs, post_abs, source = event_times(case, detection)
        clip_start = float(case["clip"]["start"])
        clip_end = float(case["clip"]["end"])
        stable_abs = max(clip_start + 0.2, pre_abs - stability_lookback)
        final_abs = max(post_abs, clip_end - 0.5)
        stable_frame = read_frame(clip_path, stable_abs - clip_start)
        pre_frame = read_frame(clip_path, pre_abs - clip_start)
        post_frame = read_frame(clip_path, post_abs - clip_start)
        final_frame = read_frame(clip_path, final_abs - clip_start)
        evidence = contact_evidence(
            stable_frame,
            pre_frame,
            post_frame,
            final_frame,
            require_club_proximity=require_club_proximity,
            club_radius=club_radius,
            exclude_lower_body=exclude_lower_body,
            lower_body_radius=lower_body_radius,
            require_shaft_support=require_shaft_support,
            shaft_support_threshold=shaft_support_threshold,
            require_pre_stability=require_pre_stability,
            pre_stability_tolerance=pre_stability_tolerance,
        )
        best_delta = (evidence.get("best") or {}).get("luma_delta") or 0.0
        scored_events.append(
            {
                "source": source,
                "stable_time": round(stable_abs, 3),
                "pre_time": round(pre_abs, 3),
                "post_time": round(post_abs, 3),
                "final_time": round(final_abs, 3),
                "contact_confirmed": best_delta >= threshold,
                "best_luma_delta": round(float(best_delta), 2),
                "evidence": evidence,
                "detection": detection,
            }
        )

    confirmed = any(event["contact_confirmed"] for event in scored_events)
    return {
        "index": case["index"],
        "kind": case["kind"],
        "label": case.get("label"),
        "clip": case["clip"],
        "contact_confirmed": confirmed,
        "events": scored_events,
    }


def analyze(args: argparse.Namespace) -> dict[str, Any]:
    report = json.loads(args.report.read_text())
    positive_cases = [
        score_case(
            case,
            args.threshold,
            require_club_proximity=args.require_club_proximity,
            club_radius=args.club_radius,
            exclude_lower_body=not args.disable_lower_body_exclusion,
            lower_body_radius=args.lower_body_radius,
            require_shaft_support=args.require_shaft_support,
            shaft_support_threshold=args.shaft_support_threshold,
            require_pre_stability=not args.disable_pre_stability,
            pre_stability_tolerance=args.pre_stability_tolerance,
            stability_lookback=args.stability_lookback,
        )
        for case in report.get("cases", [])
    ]
    negative_cases = [
        score_case(
            case,
            args.threshold,
            require_club_proximity=args.require_club_proximity,
            club_radius=args.club_radius,
            exclude_lower_body=not args.disable_lower_body_exclusion,
            lower_body_radius=args.lower_body_radius,
            require_shaft_support=args.require_shaft_support,
            shaft_support_threshold=args.shaft_support_threshold,
            require_pre_stability=not args.disable_pre_stability,
            pre_stability_tolerance=args.pre_stability_tolerance,
            stability_lookback=args.stability_lookback,
        )
        for case in report.get("negative_cases", [])
    ]

    output = {
        "source_report": str(args.report),
        "threshold": args.threshold,
        "require_club_proximity": args.require_club_proximity,
        "club_radius": args.club_radius,
        "exclude_lower_body": not args.disable_lower_body_exclusion,
        "lower_body_radius": args.lower_body_radius,
        "require_shaft_support": args.require_shaft_support,
        "shaft_support_threshold": args.shaft_support_threshold,
        "require_pre_stability": not args.disable_pre_stability,
        "pre_stability_tolerance": args.pre_stability_tolerance,
        "stability_lookback": args.stability_lookback,
        "positive_case_count": len(positive_cases),
        "positive_contact_count": sum(1 for case in positive_cases if case["contact_confirmed"]),
        "negative_case_count": len(negative_cases),
        "negative_contact_count": sum(1 for case in negative_cases if case["contact_confirmed"]),
        "positive_cases": positive_cases,
        "negative_cases": negative_cases,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2))
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=Path(".videos/detector_eval/results/detector_fixture_report.json"))
    parser.add_argument("--output", type=Path, default=Path(".videos/detector_eval/results/contact_evidence_report.json"))
    parser.add_argument("--threshold", type=float, default=24.0)
    parser.add_argument("--require-club-proximity", action="store_true")
    parser.add_argument("--club-radius", type=float, default=170.0)
    parser.add_argument("--disable-lower-body-exclusion", action="store_true")
    parser.add_argument("--lower-body-radius", type=float, default=54.0)
    parser.add_argument("--require-shaft-support", action="store_true")
    parser.add_argument("--shaft-support-threshold", type=float, default=0.25)
    parser.add_argument("--disable-pre-stability", action="store_true")
    parser.add_argument("--pre-stability-tolerance", type=float, default=28.0)
    parser.add_argument("--stability-lookback", type=float, default=1.4)
    parser.add_argument("--summary-only", action="store_true")
    args = parser.parse_args()

    output = analyze(args)
    if args.summary_only:
        print(
            json.dumps(
                {
                    "source_report": output["source_report"],
                    "threshold": output["threshold"],
                    "require_club_proximity": output["require_club_proximity"],
                    "exclude_lower_body": output["exclude_lower_body"],
                    "require_shaft_support": output["require_shaft_support"],
                    "require_pre_stability": output["require_pre_stability"],
                    "positive_contact_count": output["positive_contact_count"],
                    "positive_case_count": output["positive_case_count"],
                    "negative_contact_count": output["negative_contact_count"],
                    "negative_case_count": output["negative_case_count"],
                    "missed_positive_indices": [
                        case["index"] for case in output["positive_cases"] if not case["contact_confirmed"]
                    ],
                    "negative_contact_indices": [
                        case["index"] for case in output["negative_cases"] if case["contact_confirmed"]
                    ],
                },
                indent=2,
            )
        )
    else:
        print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
