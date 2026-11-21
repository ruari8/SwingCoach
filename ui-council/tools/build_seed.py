#!/usr/bin/env python3
"""Builds the UI council's seed library from a coached range session.

Usage: build_seed.py <session-folder> <coached-folder> <seed-out>

<session-folder> is a range session exported from the phone (metadata.json and
the clips). <coached-folder> is the coaching harness output for those clips
(detector_workbench/validation/coaching/run.sh). <seed-out> receives the app
container layout that capture.sh copies into the Simulator:

  Documents/swing_library.json
  Library/Application Support/SwingVideos/<id>.mp4      (720 px, silent)
  Library/Application Support/SwingCoaching/<id>.report.json, .evidence.json

The seed is deterministic: fixed ids and dates (the session's own), the same
clips in the same order. Re-running with the same inputs rewrites the same
files, and existing transcodes are reused.
"""
import datetime as dt
import json
import pathlib
import subprocess
import sys

REFERENCE_DATE = dt.datetime(2001, 1, 1, tzinfo=dt.timezone.utc)


def seconds_since_2001(iso):
    return (dt.datetime.fromisoformat(iso.replace("Z", "+00:00")) - REFERENCE_DATE).total_seconds()


def main():
    session, coached, out = (pathlib.Path(p).expanduser() for p in sys.argv[1:4])
    metadata = {s["filename"]: s for s in json.loads((session / "metadata.json").read_text())["swings"]}
    documents = out / "Documents"
    support = out / "Library" / "Application Support"
    videos, coaching = support / "SwingVideos", support / "SwingCoaching"
    for folder in (documents, videos, coaching):
        folder.mkdir(parents=True, exist_ok=True)

    swings = []
    for clip_dir in sorted(p for p in coached.iterdir() if p.is_dir()):
        name = clip_dir.name + ".mp4"
        meta = metadata.get(name)
        record_file, report_file = clip_dir / "evidence.json", clip_dir / "report.json"
        if meta is None or not record_file.exists():
            continue
        record = json.loads(record_file.read_text())
        swing_id = meta["swingID"]
        target = videos / f"{swing_id}.mp4"
        if not target.exists():
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(session / name), "-an",
                            "-vf", "scale=-2:1280", "-c:v", "libx264", "-crf", "22", "-preset", "medium",
                            "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(target)], check=True)
        (coaching / f"{swing_id}.evidence.json").write_text(json.dumps(record["evidence"]))
        if report_file.exists():
            (coaching / f"{swing_id}.report.json").write_text(report_file.read_text())
        swings.append({
            "id": swing_id,
            "photoAssetID": "",
            "vantage": "DTL",
            "duration": meta["duration"],
            "createdAt": seconds_since_2001(meta["createdAt"]),
            "isFavorite": False,
            "isReference": False,
            "localVideoFilename": f"{swing_id}.mp4",
            "sourceTimeScale": float(record["evidence"].get("timeScale", 8)),
            "swingPositions": record["positions"],
        })

    swings.sort(key=lambda s: s["createdAt"], reverse=True)
    (documents / "swing_library.json").write_text(json.dumps(swings, indent=1))
    print(f"{len(swings)} swings -> {out}")


if __name__ == "__main__":
    main()
