"""Copies coached swings into the playground's local media folder for web/coaching.html.

Takes harness output folders (detector_workbench/validation/coaching/run.sh) and
writes playgrounds/ui/media/coaching/: each swing's ten position frames, and
data.js with the reports, per-swing verdicts, session themes and metric table.
The media folder is ignored by git: the frames are Ruari's swings.

Usage: tools/venv/bin/python playgrounds/ui/coaching-media.py <label>=<harness-out-dir> ...
  e.g. range=/tmp/coaching-1511 pros=/tmp/coaching-pros
"""
import json
import shutil
import sys
from pathlib import Path

from PIL import Image

OUT = Path(__file__).parent / "media" / "coaching"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    data = {"sessions": []}
    for argument in sys.argv[1:]:
        label, root = argument.split("=", 1)
        root = Path(root)
        session = json.loads((root / "session.json").read_text())
        data["definitions"] = json.loads((root / "definitions.json").read_text())
        swings = []
        for verdict in session["verdicts"]:
            clip = root / verdict["clip"]
            record = json.loads((clip / "evidence.json").read_text())
            folder = OUT / label / verdict["clip"]
            folder.mkdir(parents=True, exist_ok=True)
            for frame in sorted(clip.glob("p*.jpg")):
                target = folder / frame.name
                if not target.exists():
                    # Phone-sized: the mock draws them about 400 px wide.
                    image = Image.open(frame)
                    image.thumbnail((720, 1280))
                    image.save(target, quality=82)
            swings.append({
                "id": verdict["clip"],
                "frames": f"{label}/{verdict['clip']}",
                "aspect": record["evidence"]["frameWidth"] / record["evidence"]["frameHeight"],
                "positions": [{"number": p["number"], "clipTime": f["clipTime"], "confidence": p["confidence"]}
                              for p, f in zip(record["positions"]["positions"], record["evidence"]["frames"])],
                "report": json.loads((clip / "report.json").read_text()),
                "verdict": {k: verdict[k] for k in ("kind", "headline", "fault", "metric", "level", "alone") if k in verdict},
            })
        data["sessions"].append({"label": label, "themes": session["themes"], "swings": swings})
    (OUT / "data.js").write_text("window.COACHING = " + json.dumps(data) + ";\n")
    print(OUT / "data.js", sum(len(s["swings"]) for s in data["sessions"]), "swings")


if __name__ == "__main__":
    main()
