"""Review sheets for the coaching harness output.

For every clip folder under <out-dir> (evidence.json, report.json, pNN.jpg),
draws each metric's drawing on the frame of its swing position and writes
<out-dir>/review/<clip>.jpg plus <out-dir>/review/index.html with the
session's numbers.

Usage: tools/venv/bin/python detector_workbench/validation/coaching/review.py <out-dir> [--limit N]
"""
import html
import json
import statistics
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

POSITIONS = [1, 2, 3, 4, 5, 6, 7]
NAMES = {1: "P1 Address", 2: "P2 Takeaway", 3: "P3 Halfway back", 4: "P4 Top",
         5: "P5 Halfway down", 6: "P6 Delivery", 7: "P7 Impact"}
TILE_H = 900
REFERENCE = (255, 255, 255)
ZONE = (70, 220, 120)
GOOD = (60, 220, 110)
WARN = (255, 190, 40)
BAD = (255, 70, 60)


def font(size):
    return ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", size)


def colour(level):
    return GOOD if level == 0 else WARN if abs(level) <= 3 else BAD


def crop_box(evidence):
    """One crop for the whole swing: the golfer, club and ball with a margin."""
    xs, ys = [], []
    for frame in evidence["frames"]:
        if frame["position"] > 7:
            continue
        for p in frame["joints"].values():
            xs.append(p["x"]); ys.append(p["y"])
        for key in ("shafts", "clubheads"):
            for b in frame[key][:1]:
                xs += [b["x"], b["x"] + b["width"]]; ys += [b["y"], b["y"] + b["height"]]
    x0, x1, y0, y1 = min(xs) - 0.12, max(xs) + 0.12, min(ys) - 0.05, max(ys) + 0.05
    return max(0, x0), max(0, y0), min(1, x1), min(1, y1)


def draw_tile(clip_dir, evidence, report, position, box):
    image = Image.open(clip_dir / f"p{position:02d}.jpg").convert("RGB")
    W, H = image.size
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    width = max(3, H // 320)

    def px(p):
        return (p["x"] * W, p["y"] * H)

    def dashed(a, b, fill):
        (ax, ay), (bx, by) = a, b
        length = ((bx - ax) ** 2 + (by - ay) ** 2) ** 0.5
        steps = max(1, int(length / (width * 5)))
        for i in range(0, steps, 2):
            t0, t1 = i / steps, min(1, (i + 1) / steps)
            d.line([ax + (bx - ax) * t0, ay + (by - ay) * t0, ax + (bx - ax) * t1, ay + (by - ay) * t1], fill=fill, width=width)

    lines = []
    for metric in report["metrics"]:
        if metric["position"] != position:
            continue
        # A club check held for the camera is drawn grey, like a guide.
        held = metric.get("cameraHold") is True
        subject = (190, 190, 190) if held else colour(metric["level"])
        lines.append((metric, subject))
        for shape in metric["drawings"]:
            fill = {"reference": REFERENCE, "zone": ZONE, "subject": subject}[shape["role"]]
            pts = [px(p) for p in shape["points"]]
            size = (shape.get("size") or 0) * H
            if shape["kind"] == "line":
                if shape.get("dashed"):
                    dashed(pts[0], pts[1], fill + (255,))
                else:
                    d.line(pts, fill=fill + (255,), width=width)
            elif shape["kind"] == "area":
                d.polygon(pts, fill=fill + (60,))
            elif shape["kind"] == "band":
                (ax, ay), (bx, by) = pts
                length = max(1e-6, ((bx - ax) ** 2 + (by - ay) ** 2) ** 0.5)
                nx, ny = -(by - ay) / length * size, (bx - ax) / length * size
                d.polygon([(ax + nx, ay + ny), (bx + nx, by + ny), (bx - nx, by - ny), (ax - nx, ay - ny)], fill=fill + (70,))
            elif shape["kind"] == "circle":
                (cx, cy) = pts[0]
                d.ellipse([cx - size, cy - size, cx + size, cy + size], outline=fill + (255,), width=width)
            elif shape["kind"] == "dot":
                (cx, cy) = pts[0]
                r = width * 2.2
                d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill + (255,), outline=(0, 0, 0, 255), width=2)
    image = Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB")
    x0, y0, x1, y1 = box
    image = image.crop((int(x0 * W), int(y0 * H), int(x1 * W), int(y1 * H)))
    scale = TILE_H / image.size[1]
    image = image.resize((int(image.size[0] * scale), TILE_H))

    caption_h = 34 + 30 * max(1, len(lines))
    tile = Image.new("RGB", (image.size[0], TILE_H + caption_h), (18, 18, 20))
    tile.paste(image, (0, 0))
    t = ImageDraw.Draw(tile)
    t.text((10, TILE_H + 4), NAMES[position], fill=(255, 255, 255), font=font(24))
    for i, (metric, col) in enumerate(lines):
        unit = "°" if metric["unit"] == "degrees" else "%"
        state = ("held: camera" if metric.get("cameraHold") is True else f"L{metric['level']:+d}" if metric["level"]
                 else "in zone" if metric.get("scored", True) else "guide")
        text = f"{metric['title']}: {metric['value']:+.0f}{unit}  {state}"
        t.text((10, TILE_H + 34 + 30 * i), text, fill=col if metric.get("scored", True) else (190, 190, 190), font=font(21))
    return tile


def main():
    root = Path(sys.argv[1])
    limit = int(sys.argv[sys.argv.index("--limit") + 1]) if "--limit" in sys.argv else None
    out = root / "review"
    out.mkdir(exist_ok=True)
    definitions = json.loads((root / "definitions.json").read_text())
    by_id = {d["id"]: d for d in definitions}
    clips = sorted(p.parent for p in root.glob("*/report.json"))
    rows = []
    values = {}
    for index, clip_dir in enumerate(clips):
        record = json.loads((clip_dir / "evidence.json").read_text())
        report = json.loads((clip_dir / "report.json").read_text())
        for metric in report["metrics"]:
            metric.update(title=by_id[metric["id"]]["title"], unit=by_id[metric["id"]]["unit"],
                          scored=by_id[metric["id"]].get("scored", True))
            values.setdefault(metric["id"], []).append(metric)
        rows.append((clip_dir.name, report, record.get("lens")))
        if limit is not None and index >= limit:
            continue
        box = crop_box(record["evidence"])
        tiles = [draw_tile(clip_dir, record["evidence"], report, p, box) for p in POSITIONS]
        height = max(t.size[1] for t in tiles)
        sheet = Image.new("RGB", (sum(t.size[0] for t in tiles) + 8 * (len(tiles) - 1), height), (18, 18, 20))
        x = 0
        for tile in tiles:
            sheet.paste(tile, (x, 0))
            x += tile.size[0] + 8
        sheet.save(out / f"{clip_dir.name}.jpg", quality=82)

    parts = ["<!doctype html><meta charset=utf-8><title>Coaching review</title>",
             "<style>body{background:#121214;color:#eee;font:15px -apple-system,Helvetica;margin:24px}"
             "table{border-collapse:collapse;margin:12px 0 32px}td,th{padding:4px 10px;border-bottom:1px solid #333;text-align:right}"
             "td:first-child,th:first-child{text-align:left}img{max-width:100%;display:block;margin:6px 0 28px}"
             ".lo{color:#ffbe28}.hi{color:#ff6a5a}.ok{color:#3cdc6e}h2{margin-top:36px}</style>",
             f"<h1>Coaching review: {html.escape(root.name)}</h1><p>{len(rows)} swings</p>",
             "<table><tr><th>Metric</th><th>Position</th><th>Zone</th><th>Measured</th><th>Median</th><th>In zone</th><th>Under</th><th>Over</th></tr>"]
    for definition in definitions:
        metrics = values.get(definition["id"], [])
        unit = "°" if definition["unit"] == "degrees" else "%"
        zone = f"{definition['zoneLow']:g} to {definition['zoneHigh']:g}{unit}"
        if not metrics:
            parts.append(f"<tr><td>{definition['title']}</td><td>P{definition['position']}</td><td>{zone}</td><td>0</td><td colspan=4></td></tr>")
            continue
        vals = [m["value"] for m in metrics]
        # In zone, under and over count the judged readings only.
        held = sum(m.get("cameraHold") is True for m in metrics)
        levels = [m["level"] for m in metrics if m.get("cameraHold") is not True]
        measured = f"{len(metrics)} ({held} held)" if held else f"{len(metrics)}"
        parts.append(
            f"<tr><td>{definition['title']}</td><td>P{definition['position']}</td><td>{zone}</td><td>{measured}</td>"
            f"<td>{statistics.median(vals):+.1f}{unit}</td><td class=ok>{sum(l == 0 for l in levels)}</td>"
            f"<td class=lo title=\"{html.escape(definition['below'])}\">{sum(l < 0 for l in levels)}</td>"
            f"<td class=hi title=\"{html.escape(definition['above'])}\">{sum(l > 0 for l in levels)}</td></tr>")
    parts.append("</table>")
    session_file = root / "session.json"
    headlines = {}
    if session_file.exists():
        session = json.loads(session_file.read_text())
        headlines = {v["clip"]: v for v in session["verdicts"]}
        kinds = [v["kind"] for v in session["verdicts"]]
        parts.append("<h2>Session</h2>")
        parts.append(f"<p>Per-swing verdicts as the app would give them, in the order hit: "
                     f"{kinds.count('shortSwing')} short swing, {kinds.count('cameraMoved')} moved camera and "
                     f"{kinds.count('positionsUnclear')} unclear positions (not judged), "
                     f"<span class=ok>{kinds.count('good')} good swing</span>, "
                     f"<span class=ok>{kinds.count('better')} that's better</span>, "
                     f"<span class=lo>{kinds.count('focus')} one pointer</span>.</p>")
        if session.get("tempo"):
            t = session["tempo"]
            direction = f" · {html.escape(t['direction'])}" if t.get("direction") else ""
            parts.append(f"<p>Tempo: median <b>{t['medianRatio']:.1f}:1</b> "
                         f"({t['medianBackswingMs']} / {t['medianDownswingMs']} ms) "
                         f"across {t['swings']} of {t['totalSwings']} swings{direction}.</p>")
        if session["themes"]:
            parts.append("<table><tr><th>What kept happening</th><th>Position</th><th>Swings</th><th>Median level</th></tr>")
            for theme in session["themes"]:
                parts.append(f"<tr><td>{html.escape(theme['text'])}</td><td>P{theme['position']}</td>"
                             f"<td>{theme['swings']} of {theme['measured']}</td><td>{theme['medianLevel']:+d}</td></tr>")
            parts.append("</table>")
        else:
            parts.append("<p>No fault showed up on half the swings.</p>")
        cameras = [v["camera"]["verdict"] for v in session["verdicts"] if "camera" in v]
        if cameras:
            counts = ", ".join(f"{cameras.count(word)} {html.escape(word)}" for word in sorted(set(cameras)))
            parts.append(f"<p>Camera placement, read off each address frame: {counts}. "
                         f"The club checks are judged only where it is good.</p>")
    for name, _, lens in rows[: (limit + 1) if limit is not None else None]:
        verdict = headlines.get(name)
        said = f" <span class={'ok' if verdict['kind'] in ('good', 'better') else 'lo' if verdict['kind'] == 'focus' else ''}>{html.escape(verdict['headline'])}</span>" if verdict else ""
        tempo = verdict.get("tempo") if verdict else None
        tempo_tag = f" <small style='color:#9aa'>tempo {tempo['ratio']:.1f}:1 ({tempo['backswingMs']}/{tempo['downswingMs']} ms{' low' if tempo.get('lowConfidence') else ''})</small>" if tempo else ""
        if lens:
            src = "intrinsic" if lens.get("focalLengthSource") == "intrinsicMatrix" else f"{lens.get('videoFieldOfView', 0):.1f}° FOV"
            lens_tag = f" <small style='color:#9aa'>f={lens['focalLengthPixels']:.0f} px ({html.escape(src)})</small>"
        else:
            lens_tag = " <small style='color:#777'>lens unknown</small>"
        camera = (verdict or {}).get("camera")
        camera_tag = ""
        if camera:
            readings = [f"{label} {camera[key]:+.0f}%" for key, label in
                        (("heightAboveHands", "height"), ("offHandLine", "line")) if camera.get(key) is not None]
            camera_tag = (f" <small style='color:#9aa'>camera {html.escape(camera['verdict'])}"
                          f"{' (' + ', '.join(readings) + ')' if readings else ''}</small>")
        parts.append(f"<h2>{html.escape(name)}{said}{tempo_tag}{lens_tag}{camera_tag}</h2><img loading=lazy src=\"{name}.jpg\">")
    (out / "index.html").write_text("\n".join(parts))
    print(out / "index.html")


if __name__ == "__main__":
    main()
