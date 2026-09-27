#!/usr/bin/env python3
"""Prepare timestamped source evidence and check the coaching library.

Run from any directory. Media stays in the ignored .videos workspace.
This tool does not infer coaching claims or mark visual evidence as reviewed.
"""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
LIBRARY = ROOT / "docs/coaching-knowledge"


def timestamp(seconds):
    minutes, seconds = divmod(int(seconds), 60)
    return f"{minutes:02d}:{seconds:02d}"


def normalize(args):
    source = Path(args.input)
    payload = json.loads(source.read_text())
    rows = []
    for event in payload["events"]:
        text = "".join(segment.get("utf8", "") for segment in event.get("segs", [])).strip()
        if text:
            rows.append({
                "start": event["tStartMs"] / 1000,
                "end": (event["tStartMs"] + event.get("dDurationMs", 0)) / 1000,
                "text": text,
            })
    if not rows:
        raise ValueError("No caption text found")
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    (output / "transcript.json").write_text(json.dumps(rows, indent=2) + "\n")
    lines = []
    for start in range(0, int(max(row["end"] for row in rows)) + 1, 30):
        text = " ".join(row["text"] for row in rows if start <= row["start"] < start + 30)
        if text:
            lines.append(f"{timestamp(start)} {text}")
    (output / "transcript.txt").write_text("\n".join(lines) + "\n")
    (output / "transcript-provenance.json").write_text(json.dumps({
        "source_file": source.name,
        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "format": "YouTube JSON3; caption display windows may overlap",
        "method": "Concatenate segments within each text event; omit empty display events; no paraphrase or word correction",
        "rows": len(rows),
    }, indent=2) + "\n")
    print(f"Normalized {len(rows)} caption events in {output}")


def sheet(args):
    from PIL import Image, ImageDraw, ImageFont

    video = Path(args.video).resolve()
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    times = [float(value) for value in args.times.split(",")]
    if not times or min(times) < 0:
        raise ValueError("Supply nonnegative timestamps")
    duration = float(json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", str(video)
    ]))["format"]["duration"])
    if max(times) >= duration:
        raise ValueError(f"Frame times must be less than video duration ({duration:g}s)")
    width, height = (270, 480) if args.portrait else (480, 270)
    label = 30
    columns = 3
    pages = []
    font = ImageFont.load_default(size=18)
    crop_filter = ""
    if args.crop:
        crop_values = [int(v) for v in args.crop.split(":")]
        if len(crop_values) != 4 or min(crop_values[:2]) <= 0 or min(crop_values[2:]) < 0:
            raise ValueError("Crop must be positive width:height and nonnegative x:y")
        crop_filter = "crop=" + ":".join(map(str, crop_values)) + ","
    for page_start in range(0, len(times), 12):
        batch = times[page_start:page_start + 12]
        canvas = Image.new("RGB", (columns * width, ((len(batch) + columns - 1) // columns) * (height + label)), "#161616")
        draw = ImageDraw.Draw(canvas)
        frames = []
        for index, seconds in enumerate(batch):
            name = f"frame-{seconds:09.3f}.jpg"
            frame = output / name
            subprocess.run([
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-ss", str(seconds),
                "-i", str(video), "-frames:v", "1", "-vf",
                crop_filter + f"scale={width}:{height}:force_original_aspect_ratio=decrease,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2",
                "-q:v", "2", str(frame),
            ], check=True)
            x, y = (index % columns) * width, (index // columns) * (height + label)
            with Image.open(frame) as image:
                canvas.paste(image, (x, y + label))
            draw.text((x + 8, y + 4), f"{timestamp(seconds)} / {seconds:g}s", font=font, fill="white")
            frames.append({"time_seconds": seconds, "file": name})
        page = f"sheet-{page_start // 12 + 1:02d}.jpg"
        canvas.save(output / page, quality=90)
        pages.append({"file": page, "frames": frames})
    (output / "index.json").write_text(json.dumps({
        "video": str(video.relative_to(ROOT)),
        "time_basis": "source playback seconds; frame nearest requested seek time",
        "crop_width_height_x_y": args.crop,
        "pages": pages,
    }, indent=2) + "\n")
    print(f"Prepared {len(times)} frames across {len(pages)} sheets in {output}")


def transcribe(args):
    import importlib.metadata
    import mlx_whisper

    video = Path(args.video).resolve()
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    result = mlx_whisper.transcribe(
        str(video), path_or_hf_repo=args.model,
        language=None if args.language == "auto" else args.language,
        word_timestamps=True, temperature=0, verbose=False,
    )
    raw = output / "asr-raw.json"
    raw.write_text(json.dumps(result, indent=2) + "\n")
    rows = [{"start": s["start"], "end": s["end"], "text": s["text"].strip()}
            for s in result["segments"] if s["text"].strip()]
    if not rows:
        raise ValueError("No speech segments found; inspect audio before treating the source as silent")
    (output / "transcript.json").write_text(json.dumps(rows, indent=2) + "\n")
    (output / "transcript.txt").write_text("\n".join(
        f'{timestamp(r["start"])}–{timestamp(r["end"])} {r["text"]}' for r in rows
    ) + "\n")
    (output / "transcript-provenance.json").write_text(json.dumps({
        "source_file": video.name,
        "source_sha256": hashlib.sha256(video.read_bytes()).hexdigest(),
        "raw_file": raw.name,
        "raw_sha256": hashlib.sha256(raw.read_bytes()).hexdigest(),
        "format": "Local MLX Whisper ASR; estimated speech timestamps",
        "model": args.model,
        "mlx_whisper_version": importlib.metadata.version("mlx-whisper"),
        "language_requested": args.language, "language_detected": result.get("language"),
        "temperature": 0, "word_timestamps": True,
        "method": "Full media audio transcribed locally; retain raw segments and words; no paraphrase or correction",
        "independently_human_verified": False, "rows": len(rows),
    }, indent=2) + "\n")
    print(f"Transcribed {len(rows)} speech segments in {output}")


def validate(args):
    manifest = json.loads((LIBRARY / "manifest.json").read_text())
    identifiers = [source["id"] for source in manifest["sources"]]
    assert len(identifiers) == len(set(identifiers)), "Duplicate source"
    completed = 0
    cases = 0
    for source in manifest["sources"]:
        if source["status"] != "analysed":
            continue
        record = json.loads((LIBRARY / "sources" / f"{source['id']}.json").read_text())
        assert record["source_id"] == source["id"]
        assert record["coverage"]["full_transcript_read"] is True
        assert record["coverage"]["visual_review_method"]
        assert record["cases"], f"No cases: {source['id']}"
        media = ROOT / record["assets"]["video"]
        assert media.is_file(), f"Missing video: {media}"
        probe = json.loads(subprocess.check_output([
            "ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", str(media)
        ]))
        assert abs(float(probe["format"]["duration"]) - record["duration_seconds"]) < 3
        transcript = ROOT / record["assets"]["transcript"]
        caption_rows = json.loads(transcript.read_text())
        assert caption_rows, f"Empty transcript: {transcript}"
        for key, expected in record.get("asset_sha256", {}).items():
            actual = hashlib.sha256((ROOT / record["assets"][key]).read_bytes()).hexdigest()
            assert actual == expected, f"Evidence changed: {key} in {source['id']}"
        evidence = {item["id"]: item for item in record["evidence"]}
        assert len(evidence) == len(record["evidence"])
        for item in evidence.values():
            start, end = item["span_seconds"]
            assert 0 <= start < end <= record["duration_seconds"], item["id"]
            assert item["attribution"] and item["summary"]
            assert any(row["start"] < end and row["end"] > start for row in caption_rows), item["id"]
            for frame in item.get("frames", []):
                assert start <= frame["time_seconds"] <= end, item["id"]
                assert (ROOT / frame["path"]).is_file(), frame["path"]
                assert frame["observation"], item["id"]
        case_ids = {case["id"] for case in record["cases"]}
        assert len(case_ids) == len(record["cases"])
        for case in record["cases"]:
            assert case["evidence_ids"] and case["applicability"] and case["unknowns"]
            assert case["review_status"] == "source_checked_not_expert_validated"
            assert all(ref in evidence for ref in case["evidence_ids"])
            assert any(evidence[ref].get("frames") for ref in case["evidence_ids"]), case["id"]
            assert all(ref in case_ids for ref in case.get("alternative_case_ids", [])), case["id"]
            assert 0 <= case["selection"]["max_simultaneous_cues"] <= 2, case["id"]
        for relation in record.get("cross_source_links", []):
            assert relation["current_case"] in case_ids
            related_id = relation["source_case"].rsplit("-C", 1)[0]
            related = json.loads((LIBRARY / "sources" / f"{related_id}.json").read_text())
            assert relation["source_case"] in {case["id"] for case in related["cases"]}
            assert relation["relation"] and relation["explanation"]
        for distinction in record.get("within_source_distinctions", []):
            assert all(ref in case_ids for ref in distinction["cases"])
            assert distinction["relationship"]
        completed += 1
        cases += len(record["cases"])
    sources_by_id = {source["id"]: source for source in manifest["sources"]}
    pending_creator_reviews = []
    for review in manifest["additional_creator_reviews"]:
        selected = review["selected_source_ids"]
        assert len(selected) == len(set(selected)), "Duplicate additional creator source"
        assert review["seed_id"] not in selected, "Seed counted as additional source"
        assert all(sid in sources_by_id for sid in selected), "Unregistered additional source"
        if review["status"] == "analysed":
            assert len(selected) == review["requested_count"], "Incomplete creator selection"
            assert all(sources_by_id[sid]["status"] == "analysed" for sid in selected), "Incomplete creator analysis"
        else:
            pending_creator_reviews.append(review)
    print(json.dumps({"sources_analysed": completed, "sources_registered": len(identifiers), "cases": cases,
                      "extra_creator_sources_pending": pending_creator_reviews,
                      "check_scope": "Files, timestamps, references, readable media. Does not certify coaching correctness or visual interpretation."}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(required=True)
    captions = commands.add_parser("normalize")
    captions.add_argument("input")
    captions.add_argument("output")
    captions.set_defaults(run=normalize)
    frames = commands.add_parser("sheet")
    frames.add_argument("video")
    frames.add_argument("output")
    frames.add_argument("--times", required=True, help="Comma-separated source playback seconds")
    frames.add_argument("--portrait", action="store_true", help="Use 270×480 cells for vertical video")
    frames.add_argument("--crop", help="Optional source-pixel crop width:height:x:y; retain uncropped evidence too")
    frames.set_defaults(run=sheet)
    speech = commands.add_parser("transcribe", help="Locally transcribe full audio with MLX Whisper")
    speech.add_argument("video")
    speech.add_argument("output")
    speech.add_argument("--model", required=True, help="Local model path or Hugging Face MLX Whisper repository")
    speech.add_argument("--language", default="auto", help="Whisper language code, or auto (default)")
    speech.set_defaults(run=transcribe)
    check = commands.add_parser("validate")
    check.set_defaults(run=validate)
    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
