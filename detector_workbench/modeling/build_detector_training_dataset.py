#!/usr/bin/env python3
"""Build a filtered YOLO dataset from SAM3 pseudo-labels.

The raw SAM3 relabel output intentionally keeps many golf-ball candidates,
including far-field range balls. This builder creates a training-oriented
dataset for the on-device detector by keeping club labels and filtering ball
candidates down to foreground/useful balls.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import shutil
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

import cv2
import numpy as np


DEFAULT_CLASSES = ["club_shaft", "clubhead", "golf_ball_candidate"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--annotations",
        type=Path,
        default=Path("detector_model/mlx_sam3_labels/annotations.json"),
        help="Path to MLX SAM3 annotations.json.",
    )
    parser.add_argument(
        "--dataset-dir",
        type=Path,
        default=Path("detector_model/frame_dataset"),
        help="Frame dataset root containing frames/ and dataset_manifest.json.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("detector_model/yolo_swing_objects_v1"),
        help="Output YOLO dataset directory.",
    )
    parser.add_argument(
        "--classes",
        nargs="+",
        default=DEFAULT_CLASSES,
        help="Class names to include, in output class-id order.",
    )
    parser.add_argument(
        "--min-ball-area",
        type=int,
        default=100,
        help="Minimum pixel area for golf-ball candidates.",
    )
    parser.add_argument(
        "--min-ball-cy",
        type=float,
        default=0.50,
        help="Minimum normalized box center-y for ball candidates.",
    )
    parser.add_argument(
        "--max-balls-per-frame",
        type=int,
        default=5,
        help="Maximum filtered golf-ball candidates per frame.",
    )
    parser.add_argument(
        "--min-club-confidence",
        type=float,
        default=0.30,
        help="Minimum confidence for club shaft/head labels.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for video-level train/val/test split.",
    )
    parser.add_argument(
        "--val-ratio",
        type=float,
        default=0.15,
        help="Fraction of source videos assigned to validation.",
    )
    parser.add_argument(
        "--test-ratio",
        type=float,
        default=0.10,
        help="Fraction of source videos assigned to test.",
    )
    parser.add_argument(
        "--overlay-limit",
        type=int,
        default=120,
        help="Number of filtered-label QA overlays to write.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Delete output dir before writing.",
    )
    return parser.parse_args()


def yolo_line(class_id: int, bbox: list[int], width: int, height: int) -> str:
    x1, y1, x2, y2 = bbox
    x_center = ((x1 + x2) / 2) / width
    y_center = ((y1 + y2) / 2) / height
    box_width = (x2 - x1) / width
    box_height = (y2 - y1) / height
    return f"{class_id} {x_center:.6f} {y_center:.6f} {box_width:.6f} {box_height:.6f}"


def ball_score(detection: dict[str, Any], width: int, height: int) -> float:
    x1, y1, x2, y2 = detection["bbox_xyxy"]
    area = max(1, (x2 - x1) * (y2 - y1))
    cy = ((y1 + y2) / 2) / height
    cx = ((x1 + x2) / 2) / width
    centered_bonus = 1.0 - min(0.45, abs(cx - 0.5)) * 0.4
    foreground_bonus = 0.75 + cy
    return float(detection["confidence"]) * math.log1p(area) * foreground_bonus * centered_bonus


def filter_detections(
    frame: dict[str, Any],
    output_classes: list[str],
    min_ball_area: int,
    min_ball_cy: float,
    max_balls_per_frame: int,
    min_club_confidence: float,
) -> tuple[list[dict[str, Any]], Counter[str]]:
    width = int(frame["width"])
    height = int(frame["height"])
    class_to_id = {name: index for index, name in enumerate(output_classes)}
    kept: list[dict[str, Any]] = []
    dropped: Counter[str] = Counter()

    ball_candidates: list[dict[str, Any]] = []
    for detection in frame.get("detections", []):
        name = detection.get("class_name")
        if name not in class_to_id:
            dropped[f"{name or 'unknown'}:excluded_class"] += 1
            continue

        x1, y1, x2, y2 = detection["bbox_xyxy"]
        area = max(0, (x2 - x1) * (y2 - y1))
        cy = ((y1 + y2) / 2) / height

        if name == "golf_ball_candidate":
            if area < min_ball_area:
                dropped["golf_ball_candidate:small_area"] += 1
                continue
            if cy < min_ball_cy:
                dropped["golf_ball_candidate:far_field"] += 1
                continue
            ball_candidates.append(detection)
            continue

        if float(detection.get("confidence", 0.0)) < min_club_confidence:
            dropped[f"{name}:low_confidence"] += 1
            continue
        kept.append(detection)

    ball_candidates.sort(key=lambda item: ball_score(item, width, height), reverse=True)
    kept.extend(ball_candidates[:max_balls_per_frame])
    dropped["golf_ball_candidate:per_frame_cap"] += max(0, len(ball_candidates) - max_balls_per_frame)
    return kept, dropped


def split_sources(frames: list[dict[str, Any]], val_ratio: float, test_ratio: float, seed: int) -> dict[str, str]:
    source_names = sorted({frame["source_stem"] for frame in frames})
    rng = random.Random(seed)
    rng.shuffle(source_names)

    test_count = max(1, round(len(source_names) * test_ratio))
    val_count = max(1, round(len(source_names) * val_ratio))
    test_sources = set(source_names[:test_count])
    val_sources = set(source_names[test_count : test_count + val_count])
    return {
        source: "test" if source in test_sources else "val" if source in val_sources else "train"
        for source in source_names
    }


def draw_overlay(image_path: Path, detections: list[dict[str, Any]], classes: list[str], output_path: Path) -> None:
    image = cv2.imread(str(image_path))
    if image is None:
        return
    colors = {
        "club_shaft": (255, 180, 0),
        "clubhead": (0, 220, 255),
        "golf_ball_candidate": (255, 255, 255),
    }
    for detection in detections:
        name = detection["class_name"]
        x1, y1, x2, y2 = map(int, detection["bbox_xyxy"])
        color = colors.get(name, (0, 255, 0))
        cv2.rectangle(image, (x1, y1), (x2, y2), color, 3)
        label = f"{name} {float(detection.get('confidence', 0.0)):.2f}"
        cv2.putText(
            image,
            label,
            (x1, max(20, y1 - 8)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.7,
            color,
            2,
            cv2.LINE_AA,
        )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(output_path), image)


def main() -> None:
    args = parse_args()
    if args.output_dir.exists() and args.overwrite:
        shutil.rmtree(args.output_dir)
    args.output_dir.mkdir(parents=True, exist_ok=True)

    annotations = json.loads(args.annotations.read_text())
    frames = annotations["frames"]
    source_to_split = split_sources(frames, args.val_ratio, args.test_ratio, args.seed)

    for split in ("train", "val", "test"):
        (args.output_dir / "images" / split).mkdir(parents=True, exist_ok=True)
        (args.output_dir / "labels" / split).mkdir(parents=True, exist_ok=True)

    summary: dict[str, Any] = {
        "source_annotations": str(args.annotations),
        "source_dataset_dir": str(args.dataset_dir),
        "classes": args.classes,
        "filters": {
            "min_ball_area": args.min_ball_area,
            "min_ball_cy": args.min_ball_cy,
            "max_balls_per_frame": args.max_balls_per_frame,
            "min_club_confidence": args.min_club_confidence,
        },
        "splits": Counter(),
        "source_splits": source_to_split,
        "kept_by_class": Counter(),
        "dropped": Counter(),
        "frames_with_labels": 0,
        "frames_without_labels": 0,
    }

    overlay_written = 0
    class_to_id = {name: index for index, name in enumerate(args.classes)}
    per_split_sources: dict[str, set[str]] = defaultdict(set)

    for frame in frames:
        split = source_to_split[frame["source_stem"]]
        per_split_sources[split].add(frame["source_stem"])
        image_rel = Path(frame["image"])
        image_src = args.dataset_dir / image_rel
        image_name = image_rel.name
        image_dst = args.output_dir / "images" / split / image_name
        label_dst = args.output_dir / "labels" / split / image_name.replace(".jpg", ".txt")

        kept, dropped = filter_detections(
            frame,
            output_classes=args.classes,
            min_ball_area=args.min_ball_area,
            min_ball_cy=args.min_ball_cy,
            max_balls_per_frame=args.max_balls_per_frame,
            min_club_confidence=args.min_club_confidence,
        )
        summary["dropped"].update(dropped)
        summary["splits"][split] += 1

        if not image_dst.exists():
            shutil.copy2(image_src, image_dst)

        lines = []
        for detection in kept:
            class_name = detection["class_name"]
            summary["kept_by_class"][class_name] += 1
            lines.append(yolo_line(class_to_id[class_name], detection["bbox_xyxy"], frame["width"], frame["height"]))

        if lines:
            summary["frames_with_labels"] += 1
        else:
            summary["frames_without_labels"] += 1
        label_dst.write_text("\n".join(lines) + ("\n" if lines else ""))

        if overlay_written < args.overlay_limit and kept:
            draw_overlay(
                image_src,
                kept,
                args.classes,
                args.output_dir / "overlays" / image_name,
            )
            overlay_written += 1

    summary["split_sources"] = {split: len(sources) for split, sources in per_split_sources.items()}
    summary["kept_by_class"] = dict(summary["kept_by_class"])
    summary["dropped"] = dict(summary["dropped"])
    summary["splits"] = dict(summary["splits"])
    summary["overlay_count"] = overlay_written

    yaml_lines = [
        f"path: {args.output_dir.resolve()}",
        "train: images/train",
        "val: images/val",
        "test: images/test",
        "names:",
    ]
    yaml_lines.extend(f"  {index}: {name}" for index, name in enumerate(args.classes))
    (args.output_dir / "dataset.yaml").write_text("\n".join(yaml_lines) + "\n")
    (args.output_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")

    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
