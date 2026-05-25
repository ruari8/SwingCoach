#!/usr/bin/env python3
"""Create SAM3 pseudo-labels for the swing frame dataset.

This produces object-detection labels from text-prompted SAM3 masks. The output
is intended for review/bootstrapping, not as blindly trusted ground truth.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND_ROOT = REPO_ROOT / "backend"
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from analysis.equipment_tracker import EquipmentTracker  # noqa: E402


LOG = logging.getLogger("sam3_label_frame_dataset")


@dataclass(frozen=True)
class LabelClass:
    id: int
    name: str
    prompts: tuple[str, ...]


LABEL_CLASSES = [
    LabelClass(0, "golf_club", ("golf club",)),
    LabelClass(1, "club_shaft", ("club shaft",)),
    LabelClass(2, "clubhead", ("golf club head", "clubhead", "driver head")),
    LabelClass(3, "golf_ball", ("golf ball",)),
]


def load_existing(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {
            "schema_version": 1,
            "label_source": "sam3_text_prompt_pseudo_labels",
            "classes": [
                {"id": item.id, "name": item.name, "prompts": list(item.prompts)}
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


def mask_to_bbox(mask: Any, scale_back: float, width: int, height: int) -> tuple[int, int, int, int] | None:
    if hasattr(mask, "cpu"):
        mask = mask.cpu().numpy()
    mask = np.asarray(mask)
    if mask.ndim > 2:
        mask = mask.squeeze()
    binary = mask > 0
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


def choose_detection(output: dict[str, Any], scale_back: float, width: int, height: int) -> dict[str, Any] | None:
    masks = output.get("masks", [])
    scores = output.get("scores", [])
    if len(masks) == 0:
        return None
    if hasattr(scores, "detach"):
        scores = scores.detach().cpu().numpy()
    scores_np = np.asarray(scores, dtype=np.float32) if len(scores) else np.zeros(len(masks), dtype=np.float32)

    candidates: list[dict[str, Any]] = []
    for index, mask in enumerate(masks):
        bbox = mask_to_bbox(mask, scale_back=scale_back, width=width, height=height)
        if bbox is None:
            continue
        area = bbox_area(bbox)
        if area == 0:
            continue
        candidates.append(
            {
                "bbox": list(bbox),
                "confidence": float(scores_np[index]) if index < len(scores_np) else 0.0,
                "area": area,
            }
        )
    if not candidates:
        return None
    candidates.sort(key=lambda item: item["confidence"], reverse=True)
    return candidates[0]


def detect_frame(
    tracker: EquipmentTracker,
    image_path: Path,
    dataset_root: Path,
    max_side: int,
    source_frame: dict[str, Any],
) -> dict[str, Any]:
    image = Image.open(image_path).convert("RGB")
    width, height = image.size
    sam_image, scale = resize_for_sam(image, max_side=max_side)
    scale_back = 1.0 / scale
    inference_state = tracker.processor.set_image(sam_image)

    detections = []
    for label_class in LABEL_CLASSES:
        best: dict[str, Any] | None = None
        for prompt in label_class.prompts:
            output = tracker.processor.set_text_prompt(state=inference_state, prompt=prompt)
            candidate = choose_detection(output, scale_back=scale_back, width=width, height=height)
            if candidate is None:
                continue
            candidate["prompt"] = prompt
            if best is None or candidate["confidence"] > best["confidence"]:
                best = candidate
        if best is None:
            continue
        detections.append(
            {
                "class_id": label_class.id,
                "class_name": label_class.name,
                "prompt": best["prompt"],
                "bbox_xyxy": best["bbox"],
                "confidence": round(float(best["confidence"]), 5),
                "area_pixels": int(best["area"]),
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
        "golf_ball": (255, 255, 255),
    }
    for detection in frame_label["detections"]:
        x1, y1, x2, y2 = detection["bbox_xyxy"]
        class_name = detection["class_name"]
        color = colors.get(class_name, (255, 0, 255))
        cv2.rectangle(image, (x1, y1), (x2, y2), color, 2)
        label = f"{class_name} {detection['confidence']:.2f}"
        cv2.putText(
            image,
            label,
            (x1, max(20, y1 - 8)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            color,
            2,
            cv2.LINE_AA,
        )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(output_path), image, [int(cv2.IMWRITE_JPEG_QUALITY), 90])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset-dir", type=Path, default=Path("detector_model/frame_dataset"))
    parser.add_argument("--output-dir", type=Path, default=Path("detector_model/sam3_labels"))
    parser.add_argument("--max-side", type=int, default=960)
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--phase", action="append", help="Limit to one or more phases")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--overlay-limit", type=int, default=120)
    parser.add_argument("--device", default=None)
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

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

    with EquipmentTracker(device=args.device, confidence_threshold=0.0) as tracker:
        for index, frame in enumerate(frames, start=1):
            image_rel = frame["image"]
            if args.resume and image_rel in done:
                continue
            image_path = args.dataset_dir / image_rel
            LOG.info("[%s/%s] %s", index, len(frames), image_rel)
            frame_label = detect_frame(
                tracker=tracker,
                image_path=image_path,
                dataset_root=args.dataset_dir,
                max_side=args.max_side,
                source_frame=frame,
            )
            annotations["frames"].append(frame_label)
            write_yolo_label(frame_label, labels_dir)
            if len(list(overlays_dir.glob("*.jpg"))) < args.overlay_limit:
                draw_overlay(image_path, frame_label, overlays_dir / Path(image_rel).name)
            annotations_path.write_text(json.dumps(annotations, indent=2))

    summary = {
        "frame_count": len(annotations["frames"]),
        "detections_by_class": {},
        "frames_by_phase": {},
        "empty_frame_count": 0,
    }
    for frame in annotations["frames"]:
        phase = frame.get("phase") or frame.get("source", {}).get("phase")
        if phase:
            summary["frames_by_phase"][phase] = summary["frames_by_phase"].get(phase, 0) + 1
        if not frame["detections"]:
            summary["empty_frame_count"] += 1
        for detection in frame["detections"]:
            name = detection["class_name"]
            summary["detections_by_class"][name] = summary["detections_by_class"].get(name, 0) + 1
    (args.output_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
