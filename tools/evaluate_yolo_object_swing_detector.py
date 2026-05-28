#!/usr/bin/env python3
"""Evaluate a YOLO-backed swing detector on range-session clips.

This is an experiment harness for the SwingCoach detector pipeline. It uses the
current golf-object model to validate or propose swing windows from video
features:

- club/shaft motion proposes candidate windows;
- stable foreground ball candidates define a strike area when visible;
- disappearance of that strike-area ball/patch after motion confirms a hit.

The first target is the long range-session fixture set derived from
`.videos/IMG_2592.mov`.
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
import subprocess
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from ultralytics import YOLO


CLASS_NAMES = {
    0: "club_shaft",
    1: "clubhead",
    2: "golf_ball_candidate",
}


@dataclass
class Box:
    class_id: int
    class_name: str
    confidence: float
    x1: float
    y1: float
    x2: float
    y2: float

    @property
    def cx(self) -> float:
        return (self.x1 + self.x2) / 2

    @property
    def cy(self) -> float:
        return (self.y1 + self.y2) / 2

    @property
    def area(self) -> float:
        return max(0.0, self.x2 - self.x1) * max(0.0, self.y2 - self.y1)


@dataclass
class FrameFeature:
    index: int
    time: float
    width: int
    height: int
    boxes: list[Box]
    visual_motion: float
    club_motion: float

    @property
    def club_boxes(self) -> list[Box]:
        return [box for box in self.boxes if box.class_name in {"club_shaft", "clubhead"}]

    @property
    def ball_boxes(self) -> list[Box]:
        return [box for box in self.boxes if box.class_name == "golf_ball_candidate"]

    @property
    def club_score(self) -> float:
        return max((box.confidence for box in self.club_boxes), default=0.0)

    @property
    def foreground_balls(self) -> list[Box]:
        return [
            box
            for box in self.ball_boxes
            if box.confidence >= 0.35 and box.cy / max(1, self.height) >= 0.50
        ]


@dataclass
class CandidateWindow:
    start: float
    end: float
    source: str
    peak_motion: float


def run(command: list[str]) -> str:
    completed = subprocess.run(command, check=True, capture_output=True, text=True)
    return completed.stdout


def video_duration(path: Path) -> float:
    payload = json.loads(
        run(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "json",
                str(path),
            ]
        )
    )
    return float(payload["format"]["duration"])


def overlaps(a_start: float, a_end: float, b_start: float, b_end: float) -> bool:
    return a_start <= b_end and b_start <= a_end


def clip_name(kind: str, index: int, start: float, end: float) -> str:
    return f"{kind}_{index:03d}_{int(start)}_{int(end)}.mp4"


def build_clip(source: Path, output: Path, start: float, end: float, width: int, fps: int) -> None:
    if output.exists():
        return

    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-y",
            "-ss",
            f"{start:.3f}",
            "-i",
            str(source),
            "-t",
            f"{end - start:.3f}",
            "-map",
            "0:v:0",
            "-vf",
            f"fps={fps},scale={width}:-2",
            "-an",
            "-c:v",
            "libx264",
            "-preset",
            "ultrafast",
            "-crf",
            "28",
            "-movflags",
            "+faststart",
            str(output),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def load_labels(path: Path) -> list[dict[str, float]]:
    payload = json.loads(path.read_text())
    return [
        {"start": float(item["start"]), "end": float(item["end"])}
        for item in payload["positive_swing_windows"]
    ]


def negative_windows(
    positives: list[dict[str, float]],
    duration: float,
    clip_duration: float,
    margin: float,
    limit: int,
) -> list[dict[str, float]]:
    windows = sorted(positives, key=lambda item: item["start"])
    gaps: list[dict[str, float]] = []
    previous_end = 0.0

    for window in windows:
        gap_start = previous_end + margin
        gap_end = window["start"] - margin
        if gap_end - gap_start >= clip_duration:
            middle = (gap_start + gap_end) / 2
            start = max(gap_start, middle - clip_duration / 2)
            gaps.append({"start": start, "end": start + clip_duration})
        previous_end = max(previous_end, window["end"])

    tail_start = previous_end + margin
    if duration - tail_start >= clip_duration:
        middle = (tail_start + duration) / 2
        start = max(tail_start, middle - clip_duration / 2)
        gaps.append({"start": start, "end": start + clip_duration})

    return gaps[:limit]


def build_cases(args: argparse.Namespace) -> list[dict[str, Any]]:
    positives = load_labels(args.labels)
    cases: list[dict[str, Any]] = []
    fixtures_dir = args.output_dir / "fixtures"
    selected = positives[: args.limit] if args.limit else positives

    for index, label in enumerate(selected, start=1):
        start = max(0.0, label["start"] - args.pre_roll)
        end = label["end"] + args.post_roll
        path = fixtures_dir / clip_name("positive", index, start, end)
        build_clip(args.video, path, start, end, args.fixture_width, args.fixture_fps)
        cases.append(
            {
                "index": index,
                "kind": "positive",
                "label": label,
                "clip": {"path": str(path), "start": start, "end": end, "duration": end - start},
            }
        )

    if args.negative_limit:
        duration = video_duration(args.video)
        for index, label in enumerate(
            negative_windows(positives, duration, args.negative_duration, args.negative_margin, args.negative_limit),
            start=1,
        ):
            start = label["start"]
            end = label["end"]
            path = fixtures_dir / clip_name("negative", index, start, end)
            build_clip(args.video, path, start, end, args.fixture_width, args.fixture_fps)
            cases.append(
                {
                    "index": index,
                    "kind": "negative",
                    "label": None,
                    "clip": {"path": str(path), "start": start, "end": end, "duration": end - start},
                }
            )

    return cases


def frame_times(path: Path, sample_fps: float) -> tuple[cv2.VideoCapture, float, int, int]:
    cap = cv2.VideoCapture(str(path))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    stride = max(1, int(round(fps / sample_fps)))
    return cap, fps, frame_count, stride


def yolo_boxes(result: Any, width: int, height: int) -> list[Box]:
    boxes: list[Box] = []
    if result.boxes is None:
        return boxes

    xyxy = result.boxes.xyxy.detach().cpu().numpy()
    cls = result.boxes.cls.detach().cpu().numpy()
    conf = result.boxes.conf.detach().cpu().numpy()
    for coords, class_id_raw, confidence in zip(xyxy, cls, conf):
        class_id = int(class_id_raw)
        class_name = CLASS_NAMES.get(class_id, f"class_{class_id}")
        x1, y1, x2, y2 = coords.tolist()
        boxes.append(
            Box(
                class_id=class_id,
                class_name=class_name,
                confidence=float(confidence),
                x1=max(0, min(width, float(x1))),
                y1=max(0, min(height, float(y1))),
                x2=max(0, min(width, float(x2))),
                y2=max(0, min(height, float(y2))),
            )
        )
    return boxes


def box_from_payload(payload: dict[str, Any]) -> Box:
    return Box(
        class_id=int(payload["class_id"]),
        class_name=str(payload["class_name"]),
        confidence=float(payload["confidence"]),
        x1=float(payload["x1"]),
        y1=float(payload["y1"]),
        x2=float(payload["x2"]),
        y2=float(payload["y2"]),
    )


def box_payload(box: Box) -> dict[str, Any]:
    return {
        "class_id": box.class_id,
        "class_name": box.class_name,
        "confidence": round(box.confidence, 6),
        "x1": round(box.x1, 3),
        "y1": round(box.y1, 3),
        "x2": round(box.x2, 3),
        "y2": round(box.y2, 3),
    }


def feature_from_payload(payload: dict[str, Any]) -> FrameFeature:
    return FrameFeature(
        index=int(payload["index"]),
        time=float(payload["time"]),
        width=int(payload["width"]),
        height=int(payload["height"]),
        boxes=[box_from_payload(item) for item in payload["boxes"]],
        visual_motion=float(payload["visual_motion"]),
        club_motion=float(payload["club_motion"]),
    )


def feature_payload(feature: FrameFeature) -> dict[str, Any]:
    return {
        "index": feature.index,
        "time": round(feature.time, 6),
        "width": feature.width,
        "height": feature.height,
        "boxes": [box_payload(box) for box in feature.boxes],
        "visual_motion": round(feature.visual_motion, 8),
        "club_motion": round(feature.club_motion, 8),
    }


def downsample_gray(frame: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    return cv2.resize(gray, (120, 200), interpolation=cv2.INTER_AREA)


def best_club_point(feature: FrameFeature) -> tuple[float, float] | None:
    club_boxes = sorted(feature.club_boxes, key=lambda item: item.confidence, reverse=True)
    if not club_boxes:
        return None
    box = club_boxes[0]
    return box.cx / max(1, feature.width), box.cy / max(1, feature.height)


def extract_features(model: YOLO, path: Path, sample_fps: float, imgsz: int, conf: float, device: str) -> list[FrameFeature]:
    cap, fps, frame_count, stride = frame_times(path, sample_fps)
    batch_frames: list[np.ndarray] = []
    batch_meta: list[tuple[int, float, int, int, float]] = []
    features: list[FrameFeature] = []
    previous_gray: np.ndarray | None = None
    previous_club: tuple[float, float] | None = None
    frame_index = -1

    def flush() -> None:
        nonlocal previous_club
        if not batch_frames:
            return
        results = model.predict(batch_frames, imgsz=imgsz, conf=conf, iou=0.7, device=device, verbose=False)
        for result, (index, time, width, height, visual_motion) in zip(results, batch_meta):
            feature = FrameFeature(
                index=index,
                time=time,
                width=width,
                height=height,
                boxes=yolo_boxes(result, width, height),
                visual_motion=visual_motion,
                club_motion=0.0,
            )
            point = best_club_point(feature)
            if point is not None and previous_club is not None:
                feature.club_motion = math.dist(point, previous_club)
            if point is not None:
                previous_club = point
            features.append(feature)
        batch_frames.clear()
        batch_meta.clear()

    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame_index += 1
        if frame_index % stride != 0:
            continue

        time = frame_index / fps
        height, width = frame.shape[:2]
        gray = downsample_gray(frame)
        if previous_gray is None:
            visual_motion = 0.0
        else:
            visual_motion = float(np.mean(cv2.absdiff(gray, previous_gray)) / 255.0)
        previous_gray = gray
        batch_frames.append(frame)
        batch_meta.append((frame_index, time, width, height, visual_motion))
        if len(batch_frames) >= 24:
            flush()

    flush()
    cap.release()

    # OpenCV frame count can include rotation/metadata oddities. Keep the field
    # read so future debugging can compare sampled frame counts when needed.
    _ = frame_count
    return features


def load_features(path: Path) -> list[FrameFeature]:
    payload = json.loads(path.read_text())
    return [feature_from_payload(item) for item in payload["features"]]


def save_features(path: Path, features: list[FrameFeature]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"features": [feature_payload(feature) for feature in features]}) + "\n")


def extract_or_load_features(model: YOLO, path: Path, args: argparse.Namespace) -> list[FrameFeature]:
    if args.feature_cache and args.feature_cache.exists():
        return load_features(args.feature_cache)

    features = extract_features(
        model,
        path,
        sample_fps=args.sample_fps,
        imgsz=args.imgsz,
        conf=args.conf,
        device=args.device,
    )
    if args.feature_cache:
        save_features(args.feature_cache, features)
    return features


def smoothed_motion(features: list[FrameFeature]) -> list[float]:
    raw = [
        (feature.visual_motion * 8.0)
        + (feature.club_motion * 5.5)
        + (0.35 if feature.club_score >= 0.60 else 0.0)
        for feature in features
    ]
    smoothed = []
    for index in range(len(raw)):
        lower = max(0, index - 2)
        upper = min(len(raw), index + 3)
        smoothed.append(float(sum(raw[lower:upper]) / max(1, upper - lower)))
    return smoothed


def propose_windows(features: list[FrameFeature], threshold: float, min_duration: float, max_duration: float) -> list[CandidateWindow]:
    if not features:
        return []

    motion = smoothed_motion(features)
    candidates: list[CandidateWindow] = []
    active_start: int | None = None
    last_active_index: int | None = None
    gap_tolerance = 1.8

    for index, (feature, value) in enumerate(zip(features, motion)):
        is_active = value >= threshold and feature.club_score >= 0.35
        if is_active:
            if active_start is None:
                active_start = index
            last_active_index = index
            continue

        if active_start is not None and last_active_index is not None:
            if feature.time - features[last_active_index].time <= gap_tolerance:
                continue
            start_time = max(0.0, features[active_start].time - 2.2)
            end_time = features[last_active_index].time + 2.0
            duration = end_time - start_time
            if duration <= max_duration:
                candidates.append(
                    CandidateWindow(
                        start=start_time,
                        end=end_time,
                        source="object_motion",
                        peak_motion=max(motion[active_start : last_active_index + 1]),
                    )
                )
            active_start = None
            last_active_index = None

    if active_start is not None and last_active_index is not None:
        start_time = max(0.0, features[active_start].time - 2.2)
        end_time = features[last_active_index].time + 2.0
        duration = end_time - start_time
        if duration <= max_duration:
            candidates.append(
                CandidateWindow(
                    start=start_time,
                    end=end_time,
                    source="object_motion",
                    peak_motion=max(motion[active_start : last_active_index + 1]),
                )
            )

    return [
        window
        for window in merge_candidate_windows(candidates, max_gap=2.4)
        if window.end - window.start >= min_duration
    ]


def merge_candidate_windows(windows: list[CandidateWindow], max_gap: float) -> list[CandidateWindow]:
    if not windows:
        return []

    merged: list[CandidateWindow] = []
    for window in sorted(windows, key=lambda item: item.start):
        if not merged or window.start > merged[-1].end + max_gap:
            merged.append(window)
            continue

        previous = merged[-1]
        merged[-1] = CandidateWindow(
            start=previous.start,
            end=max(previous.end, window.end),
            source=f"{previous.source}+{window.source}",
            peak_motion=max(previous.peak_motion, window.peak_motion),
        )
    return merged


def ball_anchors(
    features: list[FrameFeature],
    start: float,
    end: float,
    min_y: float,
    limit: int = 5,
) -> list[tuple[float, float]]:
    points: list[tuple[float, float, float]] = []
    for feature in features:
        if not (start <= feature.time <= end):
            continue
        for ball in feature.foreground_balls:
            x = ball.cx / feature.width
            y = ball.cy / feature.height
            if y >= min_y:
                points.append((x, y, ball.confidence))

    if not points:
        return []

    # Cluster coarse locations first. Multiple balls can be visible on the mat,
    # and the addressed ball is not always the densest/most persistent one.
    buckets: Counter[tuple[int, int]] = Counter((round(x * 18), round(y * 18)) for x, y, _ in points)
    anchors: list[tuple[float, float]] = []
    for bucket, _ in buckets.most_common(limit):
        clustered = [(x, y, c) for x, y, c in points if (round(x * 18), round(y * 18)) == bucket]
        total_weight = sum(c for _, _, c in clustered)
        if total_weight <= 0:
            continue
        anchors.append(
            (
                sum(x * c for x, _, c in clustered) / total_weight,
                sum(y * c for _, y, c in clustered) / total_weight,
            )
        )
    return anchors


def anchor_presence_ratio(features: list[FrameFeature], start: float, end: float, anchor: tuple[float, float] | None) -> float:
    window = [feature for feature in features if start <= feature.time <= end]
    if not window:
        return 0.0

    present = 0
    for feature in window:
        if anchor is None:
            if feature.foreground_balls:
                present += 1
            continue
        if any(
            math.dist((ball.cx / feature.width, ball.cy / feature.height), anchor) <= 0.055
            for ball in feature.foreground_balls
        ):
            present += 1
    return present / len(window)


def anchor_present(feature: FrameFeature, anchor: tuple[float, float] | None) -> bool:
    if anchor is None:
        return bool(feature.foreground_balls)
    return any(
        math.dist((ball.cx / feature.width, ball.cy / feature.height), anchor) <= 0.055
        for ball in feature.foreground_balls
    )


def estimate_disappearance_time(
    features: list[FrameFeature],
    start: float,
    end: float,
    anchor: tuple[float, float] | None,
) -> float | None:
    timeline = [
        (feature.time, anchor_present(feature, anchor))
        for feature in features
        if start <= feature.time <= end
    ]
    if len(timeline) < 4:
        return None

    for index, (time, present) in enumerate(timeline):
        if present:
            continue
        previous = timeline[max(0, index - 6) : index]
        following = timeline[index : min(len(timeline), index + 4)]
        previous_present = sum(1 for _, value in previous if value)
        following_absent = sum(1 for _, value in following if not value)
        if previous_present >= 2 and following_absent >= 2:
            return time
    return None


def anchor_clubhead_evidence(
    features: list[FrameFeature],
    start: float,
    end: float,
    anchor: tuple[float, float] | None,
    near_distance: float,
) -> dict[str, Any]:
    if anchor is None:
        return {"min_distance": None, "near_ratio": 0.0, "frame_ratio": 0.0, "near": False}

    window = [feature for feature in features if start <= feature.time <= end]
    if not window:
        return {"min_distance": None, "near_ratio": 0.0, "frame_ratio": 0.0, "near": False}

    min_distance: float | None = None
    near_count = 0
    frames_with_clubhead = 0
    for feature in window:
        clubheads = [
            box
            for box in feature.boxes
            if box.class_name == "clubhead" and box.confidence >= 0.30
        ]
        if not clubheads:
            continue
        frames_with_clubhead += 1
        distances = [
            math.dist((box.cx / feature.width, box.cy / feature.height), anchor)
            for box in clubheads
        ]
        frame_min = min(distances)
        min_distance = frame_min if min_distance is None else min(min_distance, frame_min)
        if frame_min <= near_distance:
            near_count += 1

    frame_ratio = frames_with_clubhead / len(window)
    near_ratio = near_count / len(window)
    return {
        "min_distance": None if min_distance is None else round(min_distance, 4),
        "near_ratio": round(near_ratio, 4),
        "frame_ratio": round(frame_ratio, 4),
        "near": min_distance is not None and (min_distance <= near_distance or near_ratio >= 0.08),
    }


def validate_window(features: list[FrameFeature], window: CandidateWindow, args: argparse.Namespace) -> dict[str, Any]:
    pre_start = max(0.0, window.start - 4.5)
    pre_end = window.start + (window.end - window.start) * 0.45
    address_start = max(0.0, window.start - 2.5)
    address_end = window.start + 3.0
    post_start = window.start + (window.end - window.start) * 0.58
    post_end = window.end + 2.2
    anchors = ball_anchors(features, pre_start, pre_end, min_y=args.min_ball_anchor_y)
    anchor_evidence = []
    for anchor_candidate in anchors:
        pre_presence_candidate = anchor_presence_ratio(features, pre_start, pre_end, anchor_candidate)
        post_presence_candidate = anchor_presence_ratio(features, post_start, post_end, anchor_candidate)
        clubhead = anchor_clubhead_evidence(
            features,
            address_start,
            address_end,
            anchor_candidate,
            near_distance=args.address_clubhead_distance,
        )
        anchor_evidence.append(
            {
                "anchor": anchor_candidate,
                "pre": pre_presence_candidate,
                "post": post_presence_candidate,
                "drop": pre_presence_candidate - post_presence_candidate,
                "clubhead": clubhead,
            }
        )
    anchor_evidence.sort(
        key=lambda item: (
            item["clubhead"]["near"],
            item["drop"],
            item["pre"],
            -(99.0 if item["clubhead"]["min_distance"] is None else item["clubhead"]["min_distance"]),
        ),
        reverse=True,
    )
    best_anchor = anchor_evidence[0] if anchor_evidence else None
    anchor = None if best_anchor is None else best_anchor["anchor"]
    pre_presence = 0.0 if best_anchor is None else float(best_anchor["pre"])
    post_presence = 0.0 if best_anchor is None else float(best_anchor["post"])
    clubhead_evidence = (
        {"min_distance": None, "near_ratio": 0.0, "frame_ratio": 0.0, "near": False}
        if best_anchor is None
        else best_anchor["clubhead"]
    )

    in_window = [feature for feature in features if window.start <= feature.time <= window.end]
    peak_motion = max(smoothed_motion(in_window), default=0.0) if in_window else 0.0
    club_frame_ratio = (
        sum(1 for feature in in_window if feature.club_score >= 0.45) / len(in_window)
        if in_window
        else 0.0
    )
    ball_disappearance = pre_presence >= 0.18 and post_presence <= max(0.12, pre_presence * 0.45)
    impact_anchor = anchor
    impact_time: float | None = None
    clubhead_ranked = sorted(
        anchor_evidence,
        key=lambda item: (
            item["clubhead"]["near_ratio"],
            -(99.0 if item["clubhead"]["min_distance"] is None else item["clubhead"]["min_distance"]),
            item["drop"],
        ),
        reverse=True,
    )
    for item in clubhead_ranked:
        clubhead = item["clubhead"]
        if clubhead["near_ratio"] < 0.35 and (clubhead["min_distance"] is None or clubhead["min_distance"] > 0.08):
            continue
        candidate_time = estimate_disappearance_time(features, window.start, post_end, item["anchor"])
        if candidate_time is None:
            continue
        impact_anchor = item["anchor"]
        impact_time = candidate_time
        break
    if impact_time is None and ball_disappearance:
        impact_time = estimate_disappearance_time(features, window.start, post_end, anchor)
    no_ball_but_strong_motion = anchor is None and peak_motion >= 0.78 and club_frame_ratio >= 0.45
    accepted = (
        ball_disappearance
        and peak_motion >= args.acceptance_min_peak_motion
    )

    confidence = min(
        0.96,
        0.22
        + min(0.32, peak_motion * 0.22)
        + min(0.22, club_frame_ratio * 0.22)
        + (0.28 if ball_disappearance else 0.0)
        + (0.08 if clubhead_evidence["near"] else 0.0)
        + (0.05 if no_ball_but_strong_motion else 0.0),
    )

    return {
        "accepted": accepted,
        "confidence": round(confidence, 4),
        "anchor": None if anchor is None else {"x": round(anchor[0], 4), "y": round(anchor[1], 4)},
        "impact_anchor": None if impact_anchor is None else {"x": round(impact_anchor[0], 4), "y": round(impact_anchor[1], 4)},
        "anchor_candidates": [
            {
                "x": round(item["anchor"][0], 4),
                "y": round(item["anchor"][1], 4),
                "pre": round(float(item["pre"]), 4),
                "post": round(float(item["post"]), 4),
                "drop": round(float(item["drop"]), 4),
                "clubhead": item["clubhead"],
            }
            for item in anchor_evidence[:5]
        ],
        "pre_ball_presence": round(pre_presence, 4),
        "post_ball_presence": round(post_presence, 4),
        "ball_disappearance": ball_disappearance,
        "impact_time": None if impact_time is None else round(impact_time, 3),
        "address_clubhead": clubhead_evidence,
        "peak_motion": round(peak_motion, 4),
        "club_frame_ratio": round(club_frame_ratio, 4),
    }


def detections_from_features(features: list[FrameFeature], args: argparse.Namespace) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    proposals = propose_windows(
        features,
        threshold=args.motion_threshold,
        min_duration=args.min_window_duration,
        max_duration=args.max_window_duration,
    )
    detections = []
    rejected = []
    for proposal in proposals:
        evidence = validate_window(features, proposal, args)
        if not evidence["accepted"]:
            rejected.append(
                {
                    "start": round(proposal.start, 3),
                    "end": round(proposal.end, 3),
                    "source": proposal.source,
                    "evidence": evidence,
                }
            )
            continue
        start = proposal.start
        end = proposal.end
        if evidence["impact_time"] is not None:
            impact_time = float(evidence["impact_time"])
            start = max(0.0, min(start, impact_time - args.impact_pre_roll))
            end = max(start, min(end, impact_time + args.impact_post_roll))
        detections.append(
            {
                "start": round(start, 3),
                "end": round(end, 3),
                "proposal_start": round(proposal.start, 3),
                "proposal_end": round(proposal.end, 3),
                "confidence": evidence["confidence"],
                "source": proposal.source,
                "evidence": evidence,
            }
        )
    return detections, rejected


def summarize_features(features: list[FrameFeature]) -> dict[str, Any]:
    counts = Counter()
    for feature in features:
        for box in feature.boxes:
            counts[box.class_name] += 1
    motions = smoothed_motion(features)
    return {
        "sampled_frames": len(features),
        "detections_by_class": dict(counts),
        "motion_mean": round(statistics.mean(motions), 4) if motions else 0.0,
        "motion_max": round(max(motions), 4) if motions else 0.0,
    }


def evaluate_case(model: YOLO, case: dict[str, Any], args: argparse.Namespace) -> dict[str, Any]:
    clip = case["clip"]
    features = extract_features(
        model,
        Path(clip["path"]),
        sample_fps=args.sample_fps,
        imgsz=args.imgsz,
        conf=args.conf,
        device=args.device,
    )
    detections, rejected = detections_from_features(features, args)
    absolute_detections = []
    matched = case["kind"] == "negative" and not detections
    false_positive_count = 0

    for detection in detections:
        absolute = {
            **detection,
            "start": round(clip["start"] + detection["start"], 3),
            "end": round(clip["start"] + detection["end"], 3),
        }
        if case["label"] is not None:
            absolute["overlaps_label"] = overlaps(
                absolute["start"],
                absolute["end"],
                case["label"]["start"],
                case["label"]["end"],
            )
            matched = matched or absolute["overlaps_label"]
            false_positive_count += 0 if absolute["overlaps_label"] else 1
        else:
            false_positive_count += 1
        absolute_detections.append(absolute)

    return {
        **case,
        "matched": matched,
        "false_positive_count": false_positive_count,
        "detections": absolute_detections,
        "rejected_proposals": rejected,
        "feature_summary": summarize_features(features),
    }


def evaluate(args: argparse.Namespace) -> dict[str, Any]:
    args.output_dir.mkdir(parents=True, exist_ok=True)
    cases = build_cases(args)
    model = YOLO(str(args.model))
    evaluated = [evaluate_case(model, case, args) for case in cases]
    positives = [case for case in evaluated if case["kind"] == "positive"]
    negatives = [case for case in evaluated if case["kind"] == "negative"]

    report = {
        "video": str(args.video),
        "labels": str(args.labels),
        "model": str(args.model),
        "parameters": {
            "sample_fps": args.sample_fps,
            "imgsz": args.imgsz,
            "conf": args.conf,
            "motion_threshold": args.motion_threshold,
            "min_window_duration": args.min_window_duration,
            "max_window_duration": args.max_window_duration,
            "acceptance_min_peak_motion": args.acceptance_min_peak_motion,
            "min_ball_anchor_y": args.min_ball_anchor_y,
            "address_clubhead_distance": args.address_clubhead_distance,
            "impact_pre_roll": args.impact_pre_roll,
            "impact_post_roll": args.impact_post_roll,
        },
        "positive_case_count": len(positives),
        "matched_count": sum(1 for case in positives if case["matched"]),
        "missed_count": sum(1 for case in positives if not case["matched"]),
        "false_positive_count": sum(case["false_positive_count"] for case in positives),
        "negative_case_count": len(negatives),
        "negative_false_positive_count": sum(case["false_positive_count"] for case in negatives),
        "cases": positives,
        "negative_cases": negatives,
    }
    report_path = args.output_dir / "results" / "yolo_object_detector_report.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    return report


def evaluate_full_video(args: argparse.Namespace) -> dict[str, Any]:
    args.output_dir.mkdir(parents=True, exist_ok=True)
    labels = load_labels(args.labels)
    model = YOLO(str(args.model))
    features = extract_or_load_features(model, args.video, args)
    detections, rejected = detections_from_features(features, args)

    scored_detections = []
    for detection in detections:
        matched_labels = [
            index
            for index, label in enumerate(labels, start=1)
            if overlaps(detection["start"], detection["end"], label["start"], label["end"])
        ]
        scored_detections.append({**detection, "matched_label_indices": matched_labels})

    cases = []
    for index, label in enumerate(labels, start=1):
        overlapping = [
            detection
            for detection in scored_detections
            if index in detection["matched_label_indices"]
        ]
        cases.append(
            {
                "index": index,
                "label": label,
                "matched": bool(overlapping),
                "detections": overlapping,
            }
        )

    false_positives = [
        detection for detection in scored_detections if not detection["matched_label_indices"]
    ]
    report = {
        "video": str(args.video),
        "labels": str(args.labels),
        "model": str(args.model),
        "mode": "full_video_live_style",
        "parameters": {
            "sample_fps": args.sample_fps,
            "imgsz": args.imgsz,
            "conf": args.conf,
            "motion_threshold": args.motion_threshold,
            "min_window_duration": args.min_window_duration,
            "max_window_duration": args.max_window_duration,
            "acceptance_min_peak_motion": args.acceptance_min_peak_motion,
            "min_ball_anchor_y": args.min_ball_anchor_y,
            "address_clubhead_distance": args.address_clubhead_distance,
            "impact_pre_roll": args.impact_pre_roll,
            "impact_post_roll": args.impact_post_roll,
            "feature_cache": None if args.feature_cache is None else str(args.feature_cache),
        },
        "feature_summary": summarize_features(features),
        "positive_case_count": len(cases),
        "matched_count": sum(1 for case in cases if case["matched"]),
        "missed_count": sum(1 for case in cases if not case["matched"]),
        "false_positive_count": len(false_positives),
        "detections": scored_detections,
        "false_positives": false_positives,
        "cases": cases,
        "rejected_proposal_count": len(rejected),
    }
    report_path = args.output_dir / "results" / "yolo_object_detector_full_report.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["clips", "full"], default="clips")
    parser.add_argument("--video", type=Path, default=Path(".videos/IMG_2592.mov"))
    parser.add_argument("--labels", type=Path, default=Path(".videos/IMG_2592.labels.json"))
    parser.add_argument("--model", type=Path, default=Path("detector_model/yolo_runs/swing_objects_yolo11n_v1_960/weights/best.pt"))
    parser.add_argument("--output-dir", type=Path, default=Path(".videos/yolo_object_detector_eval"))
    parser.add_argument("--sample-fps", type=float, default=2.0)
    parser.add_argument("--imgsz", type=int, default=960)
    parser.add_argument("--conf", type=float, default=0.25)
    parser.add_argument("--device", default="mps")
    parser.add_argument("--motion-threshold", type=float, default=0.55)
    parser.add_argument("--min-window-duration", type=float, default=10.0)
    parser.add_argument("--max-window-duration", type=float, default=24.0)
    parser.add_argument("--acceptance-min-peak-motion", type=float, default=1.10)
    parser.add_argument("--min-ball-anchor-y", type=float, default=0.66)
    parser.add_argument("--address-clubhead-distance", type=float, default=0.18)
    parser.add_argument("--impact-pre-roll", type=float, default=13.0)
    parser.add_argument("--impact-post-roll", type=float, default=4.5)
    parser.add_argument("--feature-cache", type=Path, default=None)
    parser.add_argument("--pre-roll", type=float, default=10.0)
    parser.add_argument("--post-roll", type=float, default=10.0)
    parser.add_argument("--fixture-width", type=int, default=960)
    parser.add_argument("--fixture-fps", type=int, default=30)
    parser.add_argument("--negative-limit", type=int, default=8)
    parser.add_argument("--negative-duration", type=float, default=40.0)
    parser.add_argument("--negative-margin", type=float, default=20.0)
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()

    report = evaluate_full_video(args) if args.mode == "full" else evaluate(args)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
