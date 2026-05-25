#!/usr/bin/env python3
"""Diagnostic audio-impact scorer for long golf videos.

This is an offline experiment, not production detector behavior. It extracts the
first audio track from a video, finds sharp high-frequency transients, and scores
them against rough swing-window labels.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
from scipy.io import wavfile
from scipy.ndimage import median_filter
from scipy.signal import find_peaks


@dataclass
class Peak:
    time: float
    score: float
    energy_db: float
    onset: float


def load_labels(path: Path) -> list[tuple[float, float]]:
    payload = json.loads(path.read_text())
    windows = payload.get("positive_swing_windows", [])
    return [(float(window["start"]), float(window["end"])) for window in windows]


def extract_audio(video: Path, wav_path: Path, sample_rate: int, force: bool) -> None:
    if wav_path.exists() and not force:
        return

    wav_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg",
        "-y",
        "-v",
        "error",
        "-i",
        str(video),
        "-map",
        "0:a:0",
        "-vn",
        "-ac",
        "1",
        "-ar",
        str(sample_rate),
        str(wav_path),
    ]
    subprocess.run(cmd, check=True)


def high_frequency_envelope(
    samples: np.ndarray,
    sample_rate: int,
    highpass_hz: float,
    frame_ms: float,
    hop_ms: float,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    if samples.ndim > 1:
        samples = samples.mean(axis=1)

    if samples.dtype.kind in "iu":
        input_scale = float(np.iinfo(samples.dtype).max)
    else:
        input_scale = 1.0

    # Use a first-difference energy envelope as a lightweight high-frequency
    # transient proxy. This is intentionally simple because the production
    # question is whether impact-like audio is useful at all.
    frame = max(2, int(round(sample_rate * frame_ms / 1000)))
    hop = frame
    if len(samples) <= frame:
        raise ValueError("Audio track is too short for configured frame size")

    all_times: list[np.ndarray] = []
    all_energy: list[np.ndarray] = []
    chunk_size = sample_rate * 60
    for chunk_start in range(0, len(samples) - frame, chunk_size):
        chunk_end = min(len(samples), chunk_start + chunk_size)
        chunk = samples[chunk_start:chunk_end].astype(np.float32)
        chunk = np.nan_to_num(chunk, copy=False)
        chunk -= float(np.mean(chunk))

        frame_count = len(chunk) // frame
        if frame_count == 0:
            continue
        framed = chunk[: frame_count * frame].reshape(frame_count, frame)
        diff = np.diff(framed, axis=1)
        energy = np.mean(diff * diff, axis=1, dtype=np.float64) / max(input_scale * input_scale, 1.0)
        centers = chunk_start + np.arange(frame_count, dtype=np.float64) * frame + frame / 2
        all_times.append(centers / sample_rate)
        all_energy.append(energy)

    times = np.concatenate(all_times)
    energy = np.concatenate(all_energy)

    # Decibels are easier to inspect, while the robust local score is better for
    # peak picking in a long outdoor clip with changing background noise.
    energy_db = np.array(10 * np.log10(np.maximum(energy, 1e-12)), dtype=np.float64, copy=True)
    local_median = median_filter(energy_db, size=max(5, int(round(3.0 / (frame_ms / 1000)))))
    local_excess = energy_db - local_median
    onset = np.maximum(np.diff(energy_db, prepend=energy_db[0]), 0)

    def robust_z(values: np.ndarray) -> np.ndarray:
        med = float(np.median(values))
        mad = float(np.median(np.abs(values - med)))
        return (values - med) / max(1.4826 * mad, 1e-6)

    score = robust_z(local_excess) + 0.65 * robust_z(onset)
    return times, score, energy_db


def pick_peaks(
    times: np.ndarray,
    score: np.ndarray,
    energy_db: np.ndarray,
    min_gap_s: float,
    max_peaks: int,
) -> list[Peak]:
    if len(times) < 2:
        return []

    hop_s = float(np.median(np.diff(times)))
    distance = max(1, int(round(min_gap_s / hop_s)))
    peak_indices, _ = find_peaks(score, distance=distance, prominence=0.25)
    peaks = [
        Peak(
            time=float(times[index]),
            score=float(score[index]),
            energy_db=float(energy_db[index]),
            onset=float(max(score[index] - score[index - 1], 0)) if index > 0 else 0.0,
        )
        for index in peak_indices
        if math.isfinite(float(score[index]))
    ]
    peaks.sort(key=lambda peak: peak.score, reverse=True)
    return peaks[:max_peaks]


def contains_time(windows: list[tuple[float, float]], time: float, padding: float = 0.0) -> bool:
    return any(start - padding <= time <= end + padding for start, end in windows)


def score_peaks(
    peaks: list[Peak],
    windows: list[tuple[float, float]],
    top_counts: list[int],
    padding: float,
) -> dict[str, Any]:
    window_results = []
    for index, (start, end) in enumerate(windows, start=1):
        inside = [peak for peak in peaks if start - padding <= peak.time <= end + padding]
        best = max(inside, key=lambda peak: peak.score, default=None)
        window_results.append(
            {
                "index": index,
                "start": start,
                "end": end,
                "best_peak": None
                if best is None
                else {
                    "time": round(best.time, 3),
                    "score": round(best.score, 3),
                    "energy_db": round(best.energy_db, 3),
                    "offset_from_start": round(best.time - start, 3),
                    "offset_from_end": round(best.time - end, 3),
                },
            }
        )

    top_summaries = []
    for count in top_counts:
        selected = peaks[:count]
        matched_windows = {
            index
            for index, (start, end) in enumerate(windows, start=1)
            if any(start - padding <= peak.time <= end + padding for peak in selected)
        }
        false_peaks = [
            peak
            for peak in selected
            if not contains_time(windows, peak.time, padding=padding)
        ]
        top_summaries.append(
            {
                "top_count": count,
                "matched_windows": len(matched_windows),
                "missed_windows": [
                    index
                    for index in range(1, len(windows) + 1)
                    if index not in matched_windows
                ],
                "false_peak_count": len(false_peaks),
                "false_peaks": [
                    {"time": round(peak.time, 3), "score": round(peak.score, 3)}
                    for peak in false_peaks[:25]
                ],
            }
        )

    return {
        "window_results": window_results,
        "top_summaries": top_summaries,
        "top_peaks": [
            {
                "rank": rank,
                "time": round(peak.time, 3),
                "score": round(peak.score, 3),
                "energy_db": round(peak.energy_db, 3),
                "inside_label": contains_time(windows, peak.time, padding=padding),
            }
            for rank, peak in enumerate(peaks[:100], start=1)
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video", type=Path, default=Path(".videos/IMG_2592.mov"))
    parser.add_argument("--labels", type=Path, default=Path(".videos/IMG_2592.labels.json"))
    parser.add_argument(
        "--wav",
        type=Path,
        default=Path(".videos/audio_eval/IMG_2592_mono_16k.wav"),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(".videos/audio_eval/audio_impact_report.json"),
    )
    parser.add_argument("--sample-rate", type=int, default=16_000)
    parser.add_argument("--highpass-hz", type=float, default=1_500)
    parser.add_argument("--frame-ms", type=float, default=12)
    parser.add_argument("--hop-ms", type=float, default=5)
    parser.add_argument("--min-gap-s", type=float, default=2.5)
    parser.add_argument("--max-peaks", type=int, default=600)
    parser.add_argument("--label-padding-s", type=float, default=0.0)
    parser.add_argument("--force-audio", action="store_true")
    args = parser.parse_args()

    labels = load_labels(args.labels)
    extract_audio(args.video, args.wav, args.sample_rate, args.force_audio)

    sample_rate, samples = wavfile.read(args.wav)
    times, score, energy_db = high_frequency_envelope(
        samples=samples,
        sample_rate=sample_rate,
        highpass_hz=args.highpass_hz,
        frame_ms=args.frame_ms,
        hop_ms=args.hop_ms,
    )
    peaks = pick_peaks(
        times=times,
        score=score,
        energy_db=energy_db,
        min_gap_s=args.min_gap_s,
        max_peaks=args.max_peaks,
    )
    report = {
        "video": str(args.video),
        "labels": str(args.labels),
        "audio": {
            "wav": str(args.wav),
            "sample_rate": sample_rate,
            "duration_s": round(len(samples) / sample_rate, 3),
            "highpass_hz": args.highpass_hz,
            "frame_ms": args.frame_ms,
            "hop_ms": args.hop_ms,
            "min_gap_s": args.min_gap_s,
        },
        "label_count": len(labels),
        **score_peaks(
            peaks=peaks,
            windows=labels,
            top_counts=[18, 36, 54, 72, 108, 144, 216],
            padding=args.label_padding_s,
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2))

    best_summary = max(
        report["top_summaries"],
        key=lambda item: (item["matched_windows"], -item["false_peak_count"]),
        default=None,
    )
    print(f"Audio duration: {report['audio']['duration_s']}s")
    print(f"Peaks analyzed: {len(peaks)}")
    if best_summary:
        print(
            "Best checked top-N: "
            f"top {best_summary['top_count']} matched "
            f"{best_summary['matched_windows']}/{len(labels)} labels with "
            f"{best_summary['false_peak_count']} outside-label peaks"
        )
        print(f"Missed windows: {best_summary['missed_windows']}")
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
