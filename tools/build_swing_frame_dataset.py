#!/usr/bin/env python3
"""Build a frame dataset from exported SwingCoach videos.

The extractor is intentionally phase-aware rather than interval-only. It samples
stable setup/address frames, rough backswing/downswing/follow-through anchors,
and a motion-derived impact candidate per clip. Outputs are stored under the
ignored detector_model workspace.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import cv2
import numpy as np


VIDEO_EXTENSIONS = {".mov", ".mp4", ".m4v"}


@dataclass
class VideoInfo:
    path: Path
    stem: str
    duration: float
    fps: float
    frame_count: int
    width: int
    height: int
    metadata: dict[str, Any] | None


def load_manifest(video_dir: Path) -> dict[str, dict[str, Any]]:
    manifest_path = video_dir / "metadata.json"
    if not manifest_path.exists():
        return {}
    payload = json.loads(manifest_path.read_text())
    return {
        item["filename"]: item
        for item in payload.get("swings", [])
        if isinstance(item, dict) and item.get("filename")
    }


def video_info(path: Path, metadata: dict[str, Any] | None) -> VideoInfo:
    capture = cv2.VideoCapture(str(path))
    if not capture.isOpened():
        raise RuntimeError(f"Could not open video: {path}")
    fps = float(capture.get(cv2.CAP_PROP_FPS)) or 30.0
    frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
    width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
    capture.release()

    duration = float(metadata.get("duration", 0)) if metadata else 0.0
    if duration <= 0 and fps > 0 and frame_count > 0:
        duration = frame_count / fps
    return VideoInfo(
        path=path,
        stem=path.stem,
        duration=duration,
        fps=fps,
        frame_count=frame_count,
        width=width,
        height=height,
        metadata=metadata,
    )


def read_frame(capture: cv2.VideoCapture, frame_index: int) -> np.ndarray | None:
    capture.set(cv2.CAP_PROP_POS_FRAMES, max(0, frame_index))
    ok, frame = capture.read()
    if not ok:
        return None
    return frame


def motion_profile(info: VideoInfo, sample_count: int) -> tuple[np.ndarray, np.ndarray]:
    capture = cv2.VideoCapture(str(info.path))
    if not capture.isOpened() or info.frame_count <= 1:
        return np.array([], dtype=np.int32), np.array([], dtype=np.float32)

    indices = np.linspace(0, info.frame_count - 1, sample_count, dtype=np.int32)
    previous: np.ndarray | None = None
    scores: list[float] = []
    valid_indices: list[int] = []

    for frame_index in indices:
        frame = read_frame(capture, int(frame_index))
        if frame is None:
            continue
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = cv2.resize(gray, (160, 90), interpolation=cv2.INTER_AREA)
        if previous is None:
            score = 0.0
        else:
            diff = cv2.absdiff(gray, previous)
            score = float(np.mean(diff))
        scores.append(score)
        valid_indices.append(int(frame_index))
        previous = gray

    capture.release()
    if not scores:
        return np.array([], dtype=np.int32), np.array([], dtype=np.float32)
    return np.array(valid_indices, dtype=np.int32), np.array(scores, dtype=np.float32)


def nearest_profile_index(profile_indices: np.ndarray, frame_index: int) -> int:
    if len(profile_indices) == 0:
        return 0
    return int(np.argmin(np.abs(profile_indices - frame_index)))


def choose_motion_frame(
    info: VideoInfo,
    profile_indices: np.ndarray,
    scores: np.ndarray,
    start_fraction: float,
    end_fraction: float,
    fallback_fraction: float,
) -> int:
    if len(profile_indices) == 0 or len(scores) == 0:
        return fraction_frame(info, fallback_fraction)
    start = fraction_frame(info, start_fraction)
    end = fraction_frame(info, end_fraction)
    mask = (profile_indices >= start) & (profile_indices <= end)
    if not np.any(mask):
        return fraction_frame(info, fallback_fraction)
    candidates = np.where(mask)[0]
    best = candidates[int(np.argmax(scores[candidates]))]
    return int(profile_indices[best])


def choose_low_motion_frame(
    info: VideoInfo,
    profile_indices: np.ndarray,
    scores: np.ndarray,
    start_fraction: float,
    end_fraction: float,
    fallback_fraction: float,
) -> int:
    if len(profile_indices) == 0 or len(scores) == 0:
        return fraction_frame(info, fallback_fraction)
    start = fraction_frame(info, start_fraction)
    end = fraction_frame(info, end_fraction)
    mask = (profile_indices >= start) & (profile_indices <= end)
    if not np.any(mask):
        return fraction_frame(info, fallback_fraction)
    candidates = np.where(mask)[0]
    best = candidates[int(np.argmin(scores[candidates]))]
    return int(profile_indices[best])


def fraction_frame(info: VideoInfo, fraction: float) -> int:
    fraction = max(0.0, min(1.0, fraction))
    return int(round((info.frame_count - 1) * fraction))


def clamp_frame(info: VideoInfo, frame_index: int) -> int:
    return max(0, min(info.frame_count - 1, int(frame_index)))


def frame_time(info: VideoInfo, frame_index: int) -> float:
    if info.fps <= 0:
        return 0.0
    return frame_index / info.fps


def select_frames(info: VideoInfo, profile_indices: np.ndarray, scores: np.ndarray) -> list[dict[str, Any]]:
    impact = choose_motion_frame(info, profile_indices, scores, 0.48, 0.86, 0.68)
    address_stable = choose_low_motion_frame(info, profile_indices, scores, 0.04, 0.24, 0.12)

    requested = [
        ("address_stable", address_stable),
        ("address_early", fraction_frame(info, 0.10)),
        ("address_late", fraction_frame(info, 0.18)),
        ("takeaway", fraction_frame(info, 0.28)),
        ("backswing_mid", fraction_frame(info, 0.38)),
        ("top_or_transition", fraction_frame(info, 0.50)),
        ("downswing", max(0, impact - int(round(info.fps * 1.0)))),
        ("pre_impact", max(0, impact - int(round(info.fps * 0.25)))),
        ("impact_candidate", impact),
        ("post_impact", min(info.frame_count - 1, impact + int(round(info.fps * 0.35)))),
        ("followthrough_mid", fraction_frame(info, 0.82)),
        ("finish", fraction_frame(info, 0.93)),
    ]

    selected: list[dict[str, Any]] = []
    used: set[int] = set()
    for phase, frame_index in requested:
        frame_index = clamp_frame(info, frame_index)
        if frame_index in used:
            # Nudge duplicates in very short clips so every phase can still have
            # an image where possible.
            for delta in range(1, max(2, int(info.fps // 2))):
                for candidate in (frame_index + delta, frame_index - delta):
                    candidate = clamp_frame(info, candidate)
                    if candidate not in used:
                        frame_index = candidate
                        break
                if frame_index not in used:
                    break
        used.add(frame_index)
        profile_idx = nearest_profile_index(profile_indices, frame_index)
        selected.append(
            {
                "phase": phase,
                "frame_index": frame_index,
                "time_seconds": round(frame_time(info, frame_index), 4),
                "source_fraction": round(frame_index / max(info.frame_count - 1, 1), 4),
                "motion_score": float(scores[profile_idx]) if len(scores) else None,
            }
        )
    return selected


def write_contact_sheet(images: list[tuple[str, np.ndarray]], output_path: Path) -> None:
    if not images:
        return
    thumb_w, thumb_h = 240, 135
    label_h = 28
    cols = 4
    rows = int(math.ceil(len(images) / cols))
    sheet = np.full((rows * (thumb_h + label_h), cols * thumb_w, 3), 245, dtype=np.uint8)

    for idx, (label, image) in enumerate(images):
        row = idx // cols
        col = idx % cols
        thumb = cv2.resize(image, (thumb_w, thumb_h), interpolation=cv2.INTER_AREA)
        y = row * (thumb_h + label_h)
        x = col * thumb_w
        sheet[y : y + thumb_h, x : x + thumb_w] = thumb
        cv2.putText(
            sheet,
            label[:34],
            (x + 8, y + thumb_h + 19),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.42,
            (35, 35, 35),
            1,
            cv2.LINE_AA,
        )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(output_path), sheet)


def extract_video_frames(info: VideoInfo, output_root: Path, profile_samples: int) -> dict[str, Any]:
    profile_indices, scores = motion_profile(info, sample_count=profile_samples)
    selections = select_frames(info, profile_indices, scores)
    frames_dir = output_root / "frames"
    sheets_dir = output_root / "contact_sheets"
    frames_dir.mkdir(parents=True, exist_ok=True)
    sheets_dir.mkdir(parents=True, exist_ok=True)

    capture = cv2.VideoCapture(str(info.path))
    frame_records: list[dict[str, Any]] = []
    contact_images: list[tuple[str, np.ndarray]] = []

    for selection in selections:
        frame = read_frame(capture, selection["frame_index"])
        if frame is None:
            continue
        filename = f"{info.stem}__{selection['phase']}__f{selection['frame_index']:06d}.jpg"
        output_path = frames_dir / filename
        cv2.imwrite(str(output_path), frame, [int(cv2.IMWRITE_JPEG_QUALITY), 92])
        record = {
            "image": str(output_path.relative_to(output_root)),
            "source_video": str(info.path),
            "source_filename": info.path.name,
            "source_stem": info.stem,
            "phase": selection["phase"],
            "frame_index": selection["frame_index"],
            "time_seconds": selection["time_seconds"],
            "source_fraction": selection["source_fraction"],
            "motion_score": selection["motion_score"],
            "width": info.width,
            "height": info.height,
            "fps": info.fps,
            "duration": info.duration,
            "metadata": info.metadata,
        }
        frame_records.append(record)
        contact_images.append((selection["phase"], frame))

    capture.release()
    write_contact_sheet(contact_images, sheets_dir / f"{info.stem}.jpg")
    return {
        "source_video": str(info.path),
        "source_filename": info.path.name,
        "frame_count": len(frame_records),
        "frames": frame_records,
    }


def ffprobe_summary(video_dir: Path, output_path: Path) -> None:
    videos = sorted(path for path in video_dir.iterdir() if path.suffix.lower() in VIDEO_EXTENSIONS)
    rows = []
    for path in videos:
        try:
            result = subprocess.run(
                [
                    "ffprobe",
                    "-v",
                    "error",
                    "-show_entries",
                    "format=duration,size:stream=codec_type,width,height,r_frame_rate,avg_frame_rate",
                    "-of",
                    "json",
                    str(path),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            rows.append({"file": path.name, "probe": json.loads(result.stdout)})
        except Exception as exc:  # noqa: BLE001 - diagnostic summary should continue
            rows.append({"file": path.name, "error": str(exc)})
    output_path.write_text(json.dumps(rows, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video-dir", type=Path, default=Path("detector_model/video_data"))
    parser.add_argument("--output-dir", type=Path, default=Path("detector_model/frame_dataset"))
    parser.add_argument("--profile-samples", type=int, default=90)
    parser.add_argument("--limit", type=int, default=None)
    args = parser.parse_args()

    manifest = load_manifest(args.video_dir)
    videos = sorted(path for path in args.video_dir.iterdir() if path.suffix.lower() in VIDEO_EXTENSIONS)
    if args.limit:
        videos = videos[: args.limit]

    args.output_dir.mkdir(parents=True, exist_ok=True)
    ffprobe_summary(args.video_dir, args.output_dir / "video_probe_summary.json")

    dataset_records: list[dict[str, Any]] = []
    video_records: list[dict[str, Any]] = []
    for index, path in enumerate(videos, start=1):
        metadata = manifest.get(path.name)
        info = video_info(path, metadata)
        print(f"[{index}/{len(videos)}] extracting {path.name} ({info.duration:.2f}s)")
        video_record = extract_video_frames(info, args.output_dir, args.profile_samples)
        video_records.append({k: v for k, v in video_record.items() if k != "frames"})
        dataset_records.extend(video_record["frames"])

    dataset = {
        "schema_version": 1,
        "source_video_dir": str(args.video_dir),
        "video_count": len(videos),
        "frame_count": len(dataset_records),
        "frames_per_video_target": 12,
        "selection_strategy": [
            "address/setup low-motion candidate",
            "phase percent anchors across the swing clip",
            "motion-derived impact candidate from the middle/late clip region",
        ],
        "videos_without_manifest_metadata": [
            path.name for path in videos if path.name not in manifest
        ],
        "videos": video_records,
        "frames": dataset_records,
    }
    (args.output_dir / "dataset_manifest.json").write_text(json.dumps(dataset, indent=2))
    print(f"Wrote {len(dataset_records)} frames from {len(videos)} videos to {args.output_dir}")
    if dataset["videos_without_manifest_metadata"]:
        print("Videos without metadata:", dataset["videos_without_manifest_metadata"])


if __name__ == "__main__":
    main()
