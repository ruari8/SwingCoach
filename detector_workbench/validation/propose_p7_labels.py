#!/usr/bin/env python3
"""Propose P7 labels for continuous range footage with the existing TCN.

This is a labelling tool, not SwingDetectorV3. It reproduces the independent
test15 workflow with Apple Vision pose, the detectSwings club segmentation
model, and the `tcn_vision_club_v1` checkpoint. Outputs remain proposals until
their contact sheets are reviewed.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import torch
import cv2
from PIL import Image, ImageDraw
from scipy.signal import find_peaks


REPO = Path(__file__).resolve().parents[2]
DETECT_SWINGS = REPO.parent / "detectSwings"
EVENT_MODEL = DETECT_SWINGS / "event_model"
POSE_EXTRACTOR = EVENT_MODEL / "vision_pose_extract"
CLUB_EXTRACTOR = DETECT_SWINGS / "yolo_masks" / "extract_club_features.py"
CLUB_WEIGHTS = DETECT_SWINGS / "yolo_masks" / "runs" / "club_seg_v2_960" / "weights" / "best.pt"
CHECKPOINT = EVENT_MODEL / "runs" / "tcn_vision_club_v1" / "best.pt"

FPS = 30
WINDOW = 120
STRIDE = 15
THRESHOLD = 0.5
MIN_DISTANCE = 12
PROMINENCE = 0.1

sys.path.insert(0, str(EVENT_MODEL))
from dataset import EVENTS, build_features, resample_indices  # noqa: E402
from model import MODELS, decode_monotonic  # noqa: E402


def digest(path: Path) -> str:
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def timecode(seconds: float) -> str:
    return f"{int(seconds // 60):02d}:{seconds % 60:06.3f}"


def render_review_sheets(video: Path, labels: list[dict], source_time_scale: int, output: Path) -> None:
    """Render video-only context around proposals before V3 is evaluated."""
    review_dir = output / "review-sheets"
    review_dir.mkdir(parents=True, exist_ok=True)
    capture = cv2.VideoCapture(str(video))
    if not capture.isOpened():
        raise RuntimeError(f"cannot open {video} for P7 review sheets")
    offsets = [-1.0, -0.75, -0.50, -0.25, 0, 0.25, 0.50, 0.75, 1.0]
    try:
        for event in labels:
            panels = []
            for real_offset in offsets:
                source_seconds = max(0, event["time"] + real_offset * source_time_scale)
                capture.set(cv2.CAP_PROP_POS_MSEC, source_seconds * 1_000)
                ok, frame = capture.read()
                if not ok:
                    continue
                frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                panel = Image.fromarray(frame).resize((216, 384))
                draw = ImageDraw.Draw(panel)
                caption = f"{timecode(source_seconds)}  {real_offset:+.2f}s"
                draw.rectangle((0, 0, 216, 24), fill=(0, 0, 0))
                draw.text((5, 5), caption, fill=(255, 255, 255))
                if real_offset == 0:
                    draw.rectangle((1, 1, 214, 382), outline=(255, 220, 0), width=4)
                panels.append(panel)
            sheet = Image.new("RGB", (1_080, 768), color=(20, 20, 20))
            for index, panel in enumerate(panels):
                sheet.paste(panel, ((index % 5) * 216, (index // 5) * 384))
            sheet.save(review_dir / f"{event['id']}.jpg", quality=92)
    finally:
        capture.release()


def discover_videos(root: Path, requested: list[str] | None) -> list[tuple[str, Path]]:
    videos = []
    wanted = set(requested or [])
    for path in sorted([*root.glob("*.mov"), *root.glob("*.mp4")]):
        if wanted and path.stem not in wanted:
            continue
        videos.append((path.stem, path.resolve()))
    missing = wanted - {video_id for video_id, _ in videos}
    if missing:
        raise FileNotFoundError(f"fixtures not found under {root}: {sorted(missing)}")
    if not videos:
        raise FileNotFoundError(f"no MOV or MP4 fixtures under {root}")
    return videos


def frame_count(video: Path) -> int:
    output = subprocess.check_output(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=nb_frames", "-of", "json", str(video),
        ],
        text=True,
    )
    return int(json.loads(output)["streams"][0]["nb_frames"])


def extract_pose(videos: list[tuple[str, Path]], cache: Path) -> None:
    cache.mkdir(parents=True, exist_ok=True)
    for video_id, video in videos:
        target = cache / f"{video_id}.bin"
        expected_bytes = frame_count(video) * 19 * 3 * 4
        if target.exists() and target.stat().st_size == expected_bytes:
            print(f"[{video_id}] pose cache ready", flush=True)
            continue
        print(f"[{video_id}] extracting Apple Vision pose", flush=True)
        subprocess.run([str(POSE_EXTRACTOR), str(video), str(target)], check=True)
        if target.stat().st_size != expected_bytes:
            raise RuntimeError(
                f"{video_id} pose length mismatch: {target.stat().st_size} != {expected_bytes}"
            )


def extract_club(videos: list[tuple[str, Path]], cache: Path, python: Path) -> None:
    cache.mkdir(parents=True, exist_ok=True)
    pending = [(video_id, video) for video_id, video in videos if not (cache / f"{video_id}.npz").exists()]
    if not pending:
        print("club caches ready", flush=True)
        return
    print(f"extracting club features for {len(pending)} fixtures", flush=True)
    subprocess.run(
        [
            str(python), str(CLUB_EXTRACTOR),
            "--weights", str(CLUB_WEIGHTS),
            "--out-dir", str(cache),
            "--key", "stem",
            "--device", "mps",
            "--batch", "16",
            "--videos", *[str(video) for _, video in pending],
        ],
        check=True,
    )


def load_model():
    checkpoint = torch.load(CHECKPOINT, map_location="cpu", weights_only=False)
    model = MODELS[checkpoint["model"]](in_dim=checkpoint["in_dim"])
    model.load_state_dict(checkpoint["state"])
    model.eval()
    torch.set_num_threads(4)
    return checkpoint, model


def propose(
    video_id: str,
    video: Path,
    pose_path: Path,
    club_path: Path,
    source_time_scale: int,
    model,
    output: Path,
) -> dict:
    raw = np.fromfile(pose_path, dtype=np.float32).reshape(-1, 19, 3)
    landmarks = np.zeros((len(raw), 19, 4), dtype=np.float32)
    landmarks[:, :, :2] = raw[:, :, :2]
    landmarks[:, :, 3] = raw[:, :, 2]
    pose_ok = raw[:, :, 2].max(axis=1) > 0
    club = dict(np.load(club_path))
    if not all(len(values) == len(raw) for values in club.values()):
        raise RuntimeError(f"{video_id} pose/club lengths disagree")

    indices = resample_indices(len(raw), FPS, source_time_scale)
    sample_count = len(indices)
    if sample_count < WINDOW:
        raise RuntimeError(f"{video_id} is shorter than the four-second TCN window")
    starts = sorted(set(range(0, sample_count - WINDOW + 1, STRIDE)) | {sample_count - WINDOW})
    weights = np.zeros(sample_count, dtype=np.float64)
    accumulated = np.zeros((sample_count, 10), dtype=np.float64)
    windows = []

    for start in starts:
        first = int(indices[start])
        last = min(len(landmarks), int(indices[start + WINDOW - 1]) + source_time_scale)
        features = build_features(
            {"lm": landmarks[first:last], "ok": pose_ok[first:last]},
            {key: values[first:last] for key, values in club.items()},
            view="dtl",
        )
        features = features[indices[start : start + WINDOW] - first]
        if features.shape != (WINDOW, 107):
            raise RuntimeError(f"{video_id} feature shape is {features.shape}, expected (120, 107)")
        with torch.inference_mode():
            logits = model(torch.from_numpy(features[None]))[0].numpy()
        scores = 1 / (1 + np.exp(-np.clip(logits, -50, 50)))
        window_weights = np.hanning(WINDOW + 2)[1:-1]
        if start == 0:
            window_weights[: WINDOW // 2] = 1
        if start == starts[-1]:
            window_weights[WINDOW // 2 :] = 1
        accumulated[start : start + WINDOW] += scores * window_weights[:, None]
        weights[start : start + WINDOW] += window_weights
        decoded = decode_monotonic(logits)
        windows.append(
            {
                "start_real_seconds": start / FPS,
                "start_source_seconds": first / FPS,
                "ordered_events_source_frames": {
                    event: int(indices[start + int(position)])
                    for event, position in zip(EVENTS, decoded)
                },
            }
        )

    scores = accumulated / weights[:, None]
    p7 = scores[:, 6]
    all_peaks, properties = find_peaks(p7, prominence=0)
    selected, _ = find_peaks(
        p7,
        height=THRESHOLD,
        prominence=PROMINENCE,
        distance=MIN_DISTANCE,
    )
    endpoints = [
        index
        for index, neighbor in [(0, 1), (sample_count - 1, sample_count - 2)]
        if p7[index] >= THRESHOLD and p7[index] > p7[neighbor]
    ]
    selected = sorted(set(selected.tolist() + endpoints))

    output.mkdir(parents=True, exist_ok=True)
    peak_rows = []
    for position, peak in enumerate(all_peaks):
        peak_rows.append(
            {
                "source_seconds": float(indices[peak] / FPS),
                "real_seconds_assuming_slow_motion": float(indices[peak] / FPS / source_time_scale),
                "source_frame": int(indices[peak]),
                "p7_score": float(p7[peak]),
                "prominence": float(properties["prominences"][position]),
                "selected": int(peak) in selected,
            }
        )
    for peak in endpoints:
        peak_rows.append(
            {
                "source_seconds": float(indices[peak] / FPS),
                "real_seconds_assuming_slow_motion": float(indices[peak] / FPS / source_time_scale),
                "source_frame": int(indices[peak]),
                "p7_score": float(p7[peak]),
                "prominence": None,
                "selected": True,
            }
        )
    peak_rows.sort(key=lambda row: row["source_frame"])

    labels = []
    for number, peak in enumerate(selected, 1):
        frame = int(indices[peak])
        source_seconds = frame / FPS
        labels.append(
            {
                "id": f"{video_id}-p7-{number:02d}",
                "event": "p7",
                "frame": frame,
                "time": source_seconds,
                "source_timecode": timecode(source_seconds),
                "real_time_seconds_assuming_slow_motion": source_seconds / source_time_scale,
                "p7_score": float(p7[peak]),
                "quality": "estimated",
                "review_status": "needs_visual_review",
                "boundary_candidate": peak in endpoints,
            }
        )

    np.savez_compressed(output / "model-output.npz", scores=scores, source_frames=indices)
    (output / "windows.json").write_text(json.dumps(windows, indent=2) + "\n")
    with (output / "all-p7-peaks.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(peak_rows[0]))
        writer.writeheader()
        writer.writerows(peak_rows)

    result = {
        "video_id": video_id,
        "path": str(video),
        "source_time_scale": source_time_scale,
        "frame_count": len(raw),
        "duration": len(raw) / FPS,
        "pose_coverage": float(pose_ok.mean()),
        "club_coverage": float((club["club_conf"] > 0).mean()),
        "proposed_impact_count": len(labels),
        "events": labels,
    }
    (output / "proposed-labels.json").write_text(json.dumps(result, indent=2) + "\n")
    render_review_sheets(video, labels, source_time_scale, output)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture-root", type=Path, required=True)
    parser.add_argument("--only", nargs="*")
    parser.add_argument("--source-time-scale", type=int, default=8)
    parser.add_argument("--artifacts-dir", type=Path, required=True)
    parser.add_argument("--labels-out", type=Path, required=True)
    parser.add_argument("--skip-extraction", action="store_true")
    args = parser.parse_args()

    videos = discover_videos(args.fixture_root, args.only)
    pose_cache = args.artifacts_dir / "pose"
    club_cache = args.artifacts_dir / "club"
    if not args.skip_extraction:
        extract_pose(videos, pose_cache)
        extract_club(videos, club_cache, Path(sys.executable))

    checkpoint, model = load_model()
    proposals = []
    for video_id, video in videos:
        print(f"[{video_id}] proposing P7 peaks", flush=True)
        proposals.append(
            propose(
                video_id,
                video,
                pose_cache / f"{video_id}.bin",
                club_cache / f"{video_id}.npz",
                args.source_time_scale,
                model,
                args.artifacts_dir / video_id,
            )
        )

    created_at = datetime.now(timezone.utc).isoformat()
    args.labels_out.parent.mkdir(parents=True, exist_ok=True)
    manifest = {
        "version": 1,
        "timebase": "source video timeline seconds",
        "review_status": "needs_user_review",
        "label_method": "event_model_sliding_window_p7_peaks",
        "created_at": created_at,
        "model": {
            "run": "tcn_vision_club_v1",
            "epoch": int(checkpoint["epoch"]),
            "in_dim": int(checkpoint["in_dim"]),
            "checkpoint_sha256": digest(CHECKPOINT),
        },
        "method": {
            "window_real_seconds": WINDOW / FPS,
            "stride_real_seconds": STRIDE / FPS,
            "threshold": THRESHOLD,
            "minimum_peak_prominence": PROMINENCE,
            "minimum_separation_real_seconds": MIN_DISTANCE / FPS,
            "pose_extraction": "Apple Vision on every encoded frame",
            "club_extraction": "club_seg_v2_960 on every encoded frame",
            "source_time_scale_assumption": args.source_time_scale,
        },
        "notes": [
            "These are independent TCN proposals, not reviewed ground truth.",
            "The supplied source_time_scale is applied to the whole input; this tool does not detect mixed-speed boundaries.",
            "A P7 motion proposal does not establish ball contact. Review contact and timing separately before scoring a detector.",
            "The generator does not read SwingDetectorV3 outputs. Human review provenance must be recorded separately.",
        ],
        "videos": [
            {
                "id": proposal["video_id"],
                "filename": next(path.name for video_id, path in videos if video_id == proposal["video_id"]),
                "source_time_scale": args.source_time_scale,
                "expected_swing_count": proposal["proposed_impact_count"],
                "review_status": "needs_user_review",
                "label_method": "event_model_sliding_window_p7_peaks",
                "impact_time_labels": [
                    {"start": event["time"], "end": event["time"]}
                    for event in proposal["events"]
                ],
                "proposal_artifact": str(args.artifacts_dir / proposal["video_id"] / "proposed-labels.json"),
            }
            for proposal in proposals
        ],
    }
    args.labels_out.write_text(json.dumps(manifest, indent=2) + "\n")
    print(
        json.dumps(
            {
                "labels": str(args.labels_out),
                "videos": {
                    proposal["video_id"]: proposal["proposed_impact_count"]
                    for proposal in proposals
                },
                "total_proposals": sum(proposal["proposed_impact_count"] for proposal in proposals),
            },
            indent=2,
        ),
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
