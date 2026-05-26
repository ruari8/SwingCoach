#!/usr/bin/env python3
"""Create MLX SAM3 pseudo-labels for the swing frame dataset.

This is the preferred Mac-side relabeling path for SwingCoach frame data. It
keeps multiple visible golf-ball candidates, merges duplicate prompt hits, and
preserves confidence so labels can be reviewed before model training.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image


LOG = logging.getLogger("mlx_sam3_relabel")


@dataclass(frozen=True)
class LabelClass:
    id: int
    name: str
    prompts: tuple[str, ...]
    max_detections: int
    nms_iou: float = 0.45
    min_area_pixels: int = 20
    max_area_ratio: float | None = None


LABEL_CLASSES = [
    LabelClass(0, "golf_club", ("golf club",), max_detections=1, nms_iou=0.5),
    LabelClass(1, "club_shaft", ("club shaft",), max_detections=1, nms_iou=0.5),
    LabelClass(
        2,
        "clubhead",
        ("golf club head", "clubhead", "driver head"),
        max_detections=1,
        nms_iou=0.45,
    ),
    LabelClass(
        3,
        "golf_ball_candidate",
        ("golf ball", "golfball", "white golf ball", "small white golf ball"),
        max_detections=12,
        nms_iou=0.35,
        min_area_pixels=20,
        max_area_ratio=0.02,
    ),
]


def install_mlx_sam3_import(mlx_repo: Path) -> None:
    if not mlx_repo.exists():
        raise FileNotFoundError(
            f"MLX SAM3 repo not found at {mlx_repo}. "
            "Clone https://github.com/Deekshith-Dade/mlx_sam3.git into this path."
        )
    sys.path.insert(0, str(mlx_repo.resolve()))


def load_existing(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {
            "schema_version": 2,
            "label_source": "mlx_sam3_image_text_prompt_pseudo_labels",
            "classes": [
                {
                    "id": item.id,
                    "name": item.name,
                    "prompts": list(item.prompts),
                    "max_detections": item.max_detections,
                    "nms_iou": item.nms_iou,
                }
                for item in LABEL_CLASSES
            ],
            "frames": [],
        }
    return json.loads(path.read_text())


def resize_for_sam(image: Image.Image, max_side: int) -> tuple[Image.Image, float]:
    width, height = image.size
    longest = max(width, height)
    if longest <= max_side:
        return image, 1.0
    scale = max_side / longest
    resized = image.resize((int(round(width * scale)), int(round(height * scale))), Image.BILINEAR)
    return resized, scale


def to_numpy(value: Any) -> np.ndarray:
    if hasattr(value, "detach"):
        value = value.detach()
    if hasattr(value, "cpu"):
        value = value.cpu()
    return np.asarray(value)


def mask_to_bbox(mask: Any, scale_back: float, width: int, height: int) -> tuple[int, int, int, int] | None:
    mask_np = to_numpy(mask)
    if mask_np.ndim > 2:
        mask_np = mask_np.squeeze()
    binary = mask_np > 0
    if not np.any(binary):
        return None

    rows = np.any(binary, axis=1)
    cols = np.any(binary, axis=0)
    y1, y2 = np.where(rows)[0][[0, -1]]
    x1, x2 = np.where(cols)[0][[0, -1]]
    x1 = int(round(x1 * scale_back))
    x2 = int(round(x2 * scale_back))
    y1 = int(round(y1 * scale_back))
    y2 = int(round(y2 * scale_back))
    x1 = max(0, min(width - 1, x1))
    x2 = max(0, min(width - 1, x2))
    y1 = max(0, min(height - 1, y1))
    y2 = max(0, min(height - 1, y2))
    if x2 <= x1 or y2 <= y1:
        return None
    return x1, y1, x2, y2


def bbox_area(bbox: tuple[int, int, int, int]) -> int:
    x1, y1, x2, y2 = bbox
    return max(0, x2 - x1) * max(0, y2 - y1)


def bbox_iou(a: list[int], b: list[int]) -> float:
    ax1, ay1, ax2, ay2 = a
    bx1, by1, bx2, by2 = b
    ix1 = max(ax1, bx1)
    iy1 = max(ay1, by1)
    ix2 = min(ax2, bx2)
    iy2 = min(ay2, by2)
    iw = max(0, ix2 - ix1)
    ih = max(0, iy2 - iy1)
    inter = iw * ih
    if inter == 0:
        return 0.0
    area_a = bbox_area((ax1, ay1, ax2, ay2))
    area_b = bbox_area((bx1, by1, bx2, by2))
    return inter / max(1, area_a + area_b - inter)


def nms(candidates: list[dict[str, Any]], iou_threshold: float, max_detections: int) -> list[dict[str, Any]]:
    kept: list[dict[str, Any]] = []
    for candidate in sorted(candidates, key=lambda item: item["confidence"], reverse=True):
        if all(bbox_iou(candidate["bbox"], item["bbox"]) < iou_threshold for item in kept):
            kept.append(candidate)
        if len(kept) >= max_detections:
            break
    return kept


def candidates_from_output(
    output: dict[str, Any],
    label_class: LabelClass,
    prompt: str,
    scale_back: float,
    width: int,
    height: int,
) -> list[dict[str, Any]]:
    masks = output.get("masks", [])
    scores = output.get("scores", [])
    if len(masks) == 0:
        return []

    scores_np = to_numpy(scores).astype(np.float32) if len(scores) else np.zeros(len(masks), dtype=np.float32)
    max_area = int(width * height * label_class.max_area_ratio) if label_class.max_area_ratio else None

    candidates: list[dict[str, Any]] = []
    for index, mask in enumerate(masks):
        bbox = mask_to_bbox(mask, scale_back=scale_back, width=width, height=height)
        if bbox is None:
            continue
        area = bbox_area(bbox)
        if area < label_class.min_area_pixels:
            continue
        if max_area is not None and area > max_area:
            continue
        candidates.append(
            {
                "bbox": list(bbox),
                "confidence": float(scores_np[index]) if index < len(scores_np) else 0.0,
                "area": area,
                "prompt": prompt,
            }
        )
    return candidates


def detect_frame(
    processor: Any,
    image_path: Path,
    dataset_root: Path,
    max_side: int,
    source_frame: dict[str, Any],
) -> dict[str, Any]:
    image = Image.open(image_path).convert("RGB")
    width, height = image.size
    sam_image, scale = resize_for_sam(image, max_side=max_side)
    scale_back = 1.0 / scale

    t0 = time.perf_counter()
    inference_state = processor.set_image(sam_image)
    image_seconds = time.perf_counter() - t0

    detections: list[dict[str, Any]] = []
    prompt_seconds = 0.0
    prompt_stats: dict[str, int] = {}

    for label_class in LABEL_CLASSES:
        class_candidates: list[dict[str, Any]] = []
        for prompt in label_class.prompts:
            t_prompt = time.perf_counter()
            output = processor.set_text_prompt(prompt, inference_state)
            prompt_seconds += time.perf_counter() - t_prompt
            candidates = candidates_from_output(
                output=output,
                label_class=label_class,
                prompt=prompt,
                scale_back=scale_back,
                width=width,
                height=height,
            )
            prompt_stats[prompt] = len(candidates)
            class_candidates.extend(candidates)

        for candidate in nms(
            class_candidates,
            iou_threshold=label_class.nms_iou,
            max_detections=label_class.max_detections,
        ):
            detections.append(
                {
                    "class_id": label_class.id,
                    "class_name": label_class.name,
                    "prompt": candidate["prompt"],
                    "bbox_xyxy": candidate["bbox"],
                    "confidence": round(float(candidate["confidence"]), 5),
                    "area_pixels": int(candidate["area"]),
                }
            )

    return {
        "image": str(image_path.relative_to(dataset_root)),
        "source_stem": source_frame.get("source_stem"),
        "source_filename": source_frame.get("source_filename"),
        "phase": source_frame.get("phase"),
        "frame_index": source_frame.get("frame_index"),
        "time_seconds": source_frame.get("time_seconds"),
        "width": width,
        "height": height,
        "detections": detections,
        "source": source_frame,
        "timing": {
            "set_image_seconds": round(image_seconds, 4),
            "prompt_seconds": round(prompt_seconds, 4),
        },
        "prompt_candidate_counts": prompt_stats,
    }


def write_yolo_label(frame_label: dict[str, Any], labels_dir: Path) -> None:
    image_rel = Path(frame_label["image"])
    label_path = labels_dir / image_rel.with_suffix(".txt").name
    width = frame_label["width"]
    height = frame_label["height"]
    lines = []
    for detection in frame_label["detections"]:
        x1, y1, x2, y2 = detection["bbox_xyxy"]
        x_center = ((x1 + x2) / 2) / width
        y_center = ((y1 + y2) / 2) / height
        box_width = (x2 - x1) / width
        box_height = (y2 - y1) / height
        lines.append(
            f"{detection['class_id']} {x_center:.6f} {y_center:.6f} {box_width:.6f} {box_height:.6f}"
        )
    labels_dir.mkdir(parents=True, exist_ok=True)
    label_path.write_text("\n".join(lines) + ("\n" if lines else ""))


def draw_overlay(image_path: Path, frame_label: dict[str, Any], output_path: Path) -> None:
    image = cv2.imread(str(image_path))
    if image is None:
        return
    colors = {
        "golf_club": (60, 170, 255),
        "club_shaft": (255, 180, 40),
        "clubhead": (70, 220, 90),
        "golf_ball_candidate": (255, 255, 255),
    }
    for detection in frame_label["detections"]:
        x1, y1, x2, y2 = detection["bbox_xyxy"]
        class_name = detection["class_name"]
        color = colors.get(class_name, (255, 0, 255))
        thickness = 3 if class_name == "golf_ball_candidate" else 2
        cv2.rectangle(image, (x1, y1), (x2, y2), color, thickness)
        label = f"{class_name} {detection['confidence']:.2f}"
        cv2.putText(
            image,
            label,
            (x1, max(20, y1 - 8)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.52,
            color,
            2,
            cv2.LINE_AA,
        )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(output_path), image, [int(cv2.IMWRITE_JPEG_QUALITY), 90])


def summarize(annotations: dict[str, Any]) -> dict[str, Any]:
    summary: dict[str, Any] = {
        "frame_count": len(annotations["frames"]),
        "detections_by_class": {},
        "frames_with_class": {},
        "frames_by_phase": {},
        "empty_frame_count": 0,
        "avg_set_image_seconds": 0.0,
        "avg_prompt_seconds": 0.0,
    }

    set_times: list[float] = []
    prompt_times: list[float] = []
    for frame in annotations["frames"]:
        phase = frame.get("phase") or frame.get("source", {}).get("phase")
        if phase:
            summary["frames_by_phase"][phase] = summary["frames_by_phase"].get(phase, 0) + 1
        detections = frame.get("detections", [])
        if not detections:
            summary["empty_frame_count"] += 1
        present_classes = set()
        for detection in detections:
            name = detection["class_name"]
            present_classes.add(name)
            summary["detections_by_class"][name] = summary["detections_by_class"].get(name, 0) + 1
        for name in present_classes:
            summary["frames_with_class"][name] = summary["frames_with_class"].get(name, 0) + 1
        timing = frame.get("timing", {})
        if "set_image_seconds" in timing:
            set_times.append(float(timing["set_image_seconds"]))
        if "prompt_seconds" in timing:
            prompt_times.append(float(timing["prompt_seconds"]))

    if set_times:
        summary["avg_set_image_seconds"] = round(float(np.mean(set_times)), 4)
    if prompt_times:
        summary["avg_prompt_seconds"] = round(float(np.mean(prompt_times)), 4)
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset-dir", type=Path, default=Path("detector_model/frame_dataset"))
    parser.add_argument("--output-dir", type=Path, default=Path("detector_model/mlx_sam3_labels"))
    parser.add_argument("--mlx-repo", type=Path, default=Path("detector_model/mlx_sam3"))
    parser.add_argument("--max-side", type=int, default=960)
    parser.add_argument("--threshold", type=float, default=0.3)
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--phase", action="append", help="Limit to one or more phases")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--overlay-limit", type=int, default=180)
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    install_mlx_sam3_import(args.mlx_repo)

    from sam3 import build_sam3_image_model  # noqa: PLC0415
    from sam3.model.sam3_image_processor import Sam3Processor  # noqa: PLC0415

    manifest = json.loads((args.dataset_dir / "dataset_manifest.json").read_text())
    frames = manifest["frames"]
    if args.phase:
        wanted = set(args.phase)
        frames = [frame for frame in frames if frame["phase"] in wanted]
    if args.limit:
        frames = frames[: args.limit]

    args.output_dir.mkdir(parents=True, exist_ok=True)
    annotations_path = args.output_dir / "annotations.json"
    annotations = load_existing(annotations_path) if args.resume else load_existing(Path("__missing__"))
    done = {frame["image"] for frame in annotations.get("frames", [])}

    labels_dir = args.output_dir / "yolo_labels"
    overlays_dir = args.output_dir / "overlays"

    LOG.info("Loading MLX SAM3 image model from %s", args.mlx_repo)
    load_started = time.perf_counter()
    model = build_sam3_image_model()
    processor = Sam3Processor(model, confidence_threshold=args.threshold)
    annotations["model_runtime"] = {
        "runtime": "mlx",
        "repo": str(args.mlx_repo),
        "threshold": args.threshold,
        "max_side": args.max_side,
        "model_load_seconds": round(time.perf_counter() - load_started, 4),
    }

    overlay_count = len(list(overlays_dir.glob("*.jpg")))
    for index, frame in enumerate(frames, start=1):
        image_rel = frame["image"]
        if args.resume and image_rel in done:
            continue
        image_path = args.dataset_dir / image_rel
        LOG.info("[%s/%s] %s", index, len(frames), image_rel)
        frame_label = detect_frame(
            processor=processor,
            image_path=image_path,
            dataset_root=args.dataset_dir,
            max_side=args.max_side,
            source_frame=frame,
        )
        annotations["frames"].append(frame_label)
        write_yolo_label(frame_label, labels_dir)
        if overlay_count < args.overlay_limit:
            draw_overlay(image_path, frame_label, overlays_dir / Path(image_rel).name)
            overlay_count += 1
        annotations_path.write_text(json.dumps(annotations, indent=2))

    summary = summarize(annotations)
    (args.output_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
