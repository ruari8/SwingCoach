#!/usr/bin/env python3
"""Builds ui-council/report.html and ui-council/report-assets/ from the
scores, the round notes, callouts.json and the screenshot folders.

Usage: report.py <media-root> <final-round> [<shots-round>]   (media-root holds shots/rNN, shots/pre-pr)

The images show private range footage, so report.html and report-assets/ are
gitignored; the page is published privately instead.
"""
import html, json, pathlib, sys
from PIL import Image, ImageDraw, ImageFont

root = pathlib.Path(__file__).resolve().parents[1]
media = pathlib.Path(sys.argv[1]).expanduser()
final = int(sys.argv[2])
shots = int(sys.argv[3]) if len(sys.argv) > 3 else final  # screenshots may be newer than the last scored round
assets = root / "report-assets"
assets.mkdir(exist_ok=True)

K = ["typography", "hierarchy", "spacing", "color", "consistency", "clarity", "accessibility",
     "subject", "overlays", "data", "state", "polish", "overall"]
NAMES = {"typography": "Typography", "hierarchy": "Hierarchy", "spacing": "Spacing and density",
         "color": "Color and contrast", "consistency": "Consistency", "clarity": "Clarity",
         "accessibility": "Accessibility", "subject": "Swing visibility", "overlays": "Drawing legibility",
         "data": "Data readability", "state": "State and confidence", "polish": "Appearance and polish",
         "overall": "Overall"}
MEMBERS = {"sol": "GPT Sol 6.2", "opus": "Opus 5.5", "fable": "Fable 5.2", "gemini": "Gemini Neon 4"}
rounds = {int(f.stem[1:]): json.loads(f.read_text()) for f in sorted((root / "scores").glob("r*.json"))}
notes = json.loads((root / "rounds.json").read_text())
callouts = json.loads((root / "callouts.json").read_text()) if (root / "callouts.json").exists() else {}
summary = json.loads((root / "summary.json").read_text()) if (root / "summary.json").exists() else {}
esc = html.escape


def mean(values):
    values = list(values)
    return sum(values) / len(values) if values else None


def thumb(src, name, width=360):
    out = assets / name
    if src.exists():
        im = Image.open(src).convert("RGB")
        im = im.resize((width, int(im.height * width / im.width)), Image.LANCZOS)
        im.save(out, quality=80)
        return f"report-assets/{name}"
    return None


def annotated(src, name, marks, width=360):
    """The after image with numbered circles at each callout's (x, y) fraction."""
    if not src.exists():
        return None
    im = Image.open(src).convert("RGB")
    im = im.resize((width, int(im.height * width / im.width)), Image.LANCZOS)
    draw = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 15)
    except OSError:
        font = ImageFont.load_default()
    for n, mark in enumerate(marks, 1):
        x, y = mark["x"] * im.width, mark["y"] * im.height
        r = 13
        draw.ellipse((x - r - 2, y - r - 2, x + r + 2, y + r + 2), fill="white")
        draw.ellipse((x - r, y - r, x + r, y + r), fill="#e5484d")
        draw.text((x, y), str(n), fill="white", font=font, anchor="mm")
    im.save(assets / name, quality=82)
    return f"report-assets/{name}"


# ---- Score tables ---------------------------------------------------------

def score_table():
    rows = []
    for n, r in sorted(rounds.items()):
        for member, apps in r["members"].items():
            us = apps["swingcoach"]
            rows.append(f"<tr><td>{n}</td><td><code>{esc(r['build'].split()[0])}</code></td><td>{esc(MEMBERS.get(member, member))}</td>"
                        f"<td class=num>{min(us[k] for k in K):.1f}</td><td class=num>{us['overall']:.1f}</td>"
                        f"<td class=num>{apps['sportsbox']['overall']:.1f}</td><td class=num>{apps['onform']['overall']:.1f}</td></tr>")
    return ("<table><thead><tr><th>Round</th><th>Commit</th><th>Member</th><th>Our lowest metric</th><th>Our overall</th>"
            "<th>Sportsbox overall</th><th>Onform overall</th></tr></thead><tbody>" + "".join(rows) + "</tbody></table>")


def metric_table(n):
    r = rounds[n]
    head = "<tr><th>Member</th><th>App</th>" + "".join(f"<th>{esc(NAMES[k])}</th>" for k in K) + "</tr>"
    rows = []
    for member, apps in r["members"].items():
        for app, label in (("swingcoach", "SwingCoach"), ("sportsbox", "Sportsbox"), ("onform", "Onform")):
            s = apps[app]
            cells = "".join(f"<td class='num{' low' if app == 'swingcoach' and s[k] < 9.5 else ''}'>{s[k]:.1f}</td>" for k in K)
            rows.append(f"<tr class='{app}'><td>{esc(MEMBERS.get(member, member))}</td><td>{label}</td>{cells}</tr>")
    return f"<div class=scroll><table class=wide><thead>{head}</thead><tbody>{''.join(rows)}</tbody></table></div>"


# ---- Per-metric small multiples (inline SVG, three series) ----------------

def series(app, metric):
    """Sol's scores: the one member who scored every round."""
    return [(n, r["members"]["sol"][app][metric]) for n, r in sorted(rounds.items())
            if "sol" in r["members"] and app in r["members"]["sol"]]


def chart(metric):
    w, h, pad_l, pad_b, pad_t = 260, 150, 28, 22, 10
    xs = sorted(rounds)
    x0, x1 = xs[0], max(xs[-1], xs[0] + 1)
    lo, hi = 4.0, 10.0

    def X(n):
        return pad_l + (n - x0) / (x1 - x0) * (w - pad_l - 8)

    def Y(v):
        return pad_t + (hi - v) / (hi - lo) * (h - pad_t - pad_b)

    parts = [f"<svg viewBox='0 0 {w} {h}' role='img' aria-label='{esc(NAMES[metric])} by round'>"]
    for g in (5, 7, 9.5):
        parts.append(f"<line x1='{pad_l}' x2='{w - 8}' y1='{Y(g):.1f}' y2='{Y(g):.1f}' class='grid{' bar' if g == 9.5 else ''}'/>"
                     f"<text x='{pad_l - 4}' y='{Y(g) + 3:.1f}' class='tick' text-anchor='end'>{g:g}</text>")
    for n in xs:
        parts.append(f"<text x='{X(n):.1f}' y='{h - 6}' class='tick' text-anchor='middle'>{n}</text>")
    for app, cls in (("onform", "s3"), ("sportsbox", "s2"), ("swingcoach", "s1")):
        pts = series(app, metric)
        if not pts:
            continue
        d = " ".join(f"{X(n):.1f},{Y(v):.1f}" for n, v in pts)
        parts.append(f"<polyline points='{d}' class='line {cls}'/>")
        for n, v in pts:
            parts.append(f"<circle cx='{X(n):.1f}' cy='{Y(v):.1f}' r='4' class='dot {cls}'><title>{app} round {n}: {v:.2f}</title></circle>")
    parts.append("</svg>")
    return f"<figure class=chart><figcaption>{esc(NAMES[metric])}</figcaption>{''.join(parts)}</figure>"


# ---- Screens --------------------------------------------------------------

SCREENS = [("01-library", "Library"), ("02-settings", "Settings"), ("03-session-review", "Session review"),
           ("05-player-open", "Player, as it opens"), ("06-player-next-step", "Player, next step"),
           ("07-all-checks", "All checks"), ("09-swing-info", "Swing Info"), ("10-player-address-P1", "Player off the walkthrough"),
           ("11-auto-recap", "Auto recap"), ("12-auto-compare", "Recap comparison"), ("14-auto-camera", "Auto camera")]


def screen_section(before_dir, after_dir, tag, notes_key):
    out = []
    for key, title in SCREENS:
        marks = callouts.get(notes_key, {}).get(key, [])
        cells = []
        for look in ("light", "dark"):
            b = thumb(media / before_dir / f"{key}-{look}.png", f"{tag}-{key}-{look}-before.jpg")
            a = annotated(media / after_dir / f"{key}-{look}.png", f"{tag}-{key}-{look}-after.jpg",
                          marks if look == (marks[0].get("look", "dark") if marks else "dark") else [])
            cells.append(f"<div class=pair><figure><img loading=lazy src='{b}' alt='{esc(title)} before, {look}'><figcaption>Before · {look}</figcaption></figure>"
                         f"<figure><img loading=lazy src='{a}' alt='{esc(title)} after, {look}'><figcaption>After · {look}</figcaption></figure></div>" if b and a else "")
        caps = "".join(f"<li><b>{esc(m['what'])}</b> {esc(m['why'])} <span class=who>Flagged by {esc(m['who'])}.</span></li>" for m in marks)
        out.append(f"<section class=screen><h3>{esc(title)}</h3><div class=pairs>{''.join(cells)}</div>"
                   + (f"<ol class=callouts>{caps}</ol>" if caps else "") + "</section>")
    return "".join(out)


def bullet_list(items):
    return "<ul>" + "".join(f"<li>{esc(i)}</li>" for i in items) + "</ul>" if items else "<p>None.</p>"


# ---- Why the score rose, and what is still short of 10 --------------------

def last_scored(member):
    scored = [n for n, r in sorted(rounds.items()) if member in r["members"]]
    return scored[-1] if scored else None


def why_up_table():
    why = summary.get("why_up", {})
    start = rounds[min(rounds)]["members"]
    ends = {m: rounds[last_scored(m)]["members"][m]["swingcoach"] for m in MEMBERS if last_scored(m) is not None}
    order = sorted((k for k in K if k != "overall"), key=lambda k: -(ends["sol"][k] - start["sol"]["swingcoach"][k])) + ["overall"]
    head = "<tr><th>Metric</th>" + "".join(
        f"<th class=num>{esc(MEMBERS[m].split()[0])}<br><span class=sub>r0 → r{last_scored(m)}</span></th>" for m in ends) + "<th>What drove it</th></tr>"
    rows = []
    for k in order:
        cells = ""
        for m, e in ends.items():
            a, b = start[m]["swingcoach"][k], e[k]
            cells += f"<td class=num>{a:.1f} → <b>{b:.1f}</b><br><span class=gain>+{b - a:.1f}</span></td>"
        rows.append(f"<tr><td><b>{esc(NAMES[k])}</b></td>{cells}<td class=why>{esc(why.get(k, ''))}</td></tr>")
    return f"<div class=scroll><table class=whyt><thead>{head}</thead><tbody>{''.join(rows)}</tbody></table></div>"


def gaps_list():
    path = root / "gaps.json"
    if not path.exists():
        return ""
    g = json.loads(path.read_text())
    items = "".join(
        f"<li><span class=tag>{esc(NAMES.get(i['metric'], i['metric']))}</span> <b>{esc(i['element'])}</b> "
        f"<span class=who>({esc(i['screen'].replace('.png', ''))})</span><br>{esc(i['problem'])}<br>"
        f"<span class=fix>Suggested fix: {esc(i['fix'])}</span></li>" for i in g["issues"])
    return f"<p class=lede>Every issue {esc(g['source'])} still listed, most important first.</p><ol class=gaps>{items}</ol>"


def reference_section():
    rows = []
    for n, r in sorted(rounds.items()):
        cells = "".join(
            (f"<td class=num>{r['members'][m]['sportsbox']['overall']:.1f} / {r['members'][m]['onform']['overall']:.1f}</td>"
             if m in r["members"] else "<td></td>") for m in MEMBERS)
        rows.append(f"<tr><td>{n}</td>{cells}</tr>")
    table = ("<div class=scroll><table><thead><tr><th>Round</th>" + "".join(f"<th class=num>{esc(MEMBERS[m])}</th>" for m in MEMBERS)
             + "</tr></thead><tbody>" + "".join(rows) + "</tbody></table></div>")
    shots = []
    for app in ("sportsbox", "onform"):
        for src in sorted((media / "references" / app).glob("*.jpg")):
            t = thumb(src, f"ref-{src.stem}.jpg", width=240)
            shots.append(f"<img loading=lazy src='{t}' alt='{esc(app)} App Store screenshot'>")
    return (f"<p class=lede>The reference apps, Sportsbox 3D Golf and Onform, were scored from App Store marketing screenshots "
            f"(below), the same images every round. Nobody used either app. The scores still moved from round to round, so "
            f"any gap under about half a point is noise. Sportsbox / Onform overall, by round:</p>{table}"
            f"<p class=lede>A sound setup would freeze each member's round 0 reference scores. Measured that way, only Sol's "
            f"latest 8.1 clears both apps (7.4 / 7.7), and that rests on one model reading marketing images.</p>"
            f"<div class=refs>{''.join(shots)}</div>")


first, last = rounds[min(rounds)], rounds[final]
declined = [d for n in sorted(notes, key=int) for d in notes[n].get("declined", [])]
start_end = ""
for m in MEMBERS:
    a = first["members"].get(m, {}).get("swingcoach")
    scored = [n for n, r in sorted(rounds.items()) if m in r["members"]]
    b = rounds[scored[-1]]["members"][m]["swingcoach"] if scored else None
    start_end += (f"<tr><td>{esc(MEMBERS[m])}</td>"
                  f"<td class=num>{'%.1f' % min(a[k] for k in K) if a else '–'}</td><td class=num>{'%.1f' % a['overall'] if a else '–'}</td>"
                  f"<td class=num>{'%.1f' % min(b[k] for k in K) if b else '–'}</td><td class=num>{'%.1f' % b['overall'] if b else '–'}</td></tr>")

page = f"""<title>SwingCoach UI Council</title>
<meta name="claude:viewport-fit-sides" content="cover">
<style>
:root{{--bg:#fbfbf9;--surface:#ffffff;--ink:#141413;--ink2:#55544f;--line:#e4e2dc;--accent:#5b7f00;--low:#b3261e;
--s1:#2a78d6;--s2:#eb6834;--s3:#1baf7a;}}
@media (prefers-color-scheme:dark){{:root:not([data-theme="light"]){{--bg:#151514;--surface:#1d1d1b;--ink:#f0efec;--ink2:#b9b8ae;--line:#33332f;--accent:#d8f36a;--low:#ff8a80;--s1:#3987e5;--s2:#d95926;--s3:#199e70;}}}}
:root[data-theme="dark"]{{--bg:#151514;--surface:#1d1d1b;--ink:#f0efec;--ink2:#b9b8ae;--line:#33332f;--accent:#d8f36a;--low:#ff8a80;--s1:#3987e5;--s2:#d95926;--s3:#199e70;}}
*{{box-sizing:border-box}} body{{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}}
main{{max-width:1180px;margin:0 auto;padding-block:32px 80px;padding-left:max(16px, env(safe-area-inset-left, 0px));padding-right:max(16px, env(safe-area-inset-right, 0px))}} h1{{font-size:32px;margin:0 0 4px}} h2{{margin-top:48px;font-size:24px}} h3{{font-size:18px;margin:28px 0 8px}}
.lede{{color:var(--ink2);max-width:760px}} table{{border-collapse:collapse;margin:12px 0;font-size:14px}} th,td{{border-bottom:1px solid var(--line);padding:6px 10px;text-align:left;vertical-align:top}}
th{{color:var(--ink2);font-weight:600}} .num{{font-variant-numeric:tabular-nums;text-align:right}} .low{{color:var(--low);font-weight:600}}
.scroll{{overflow-x:auto}} table.wide{{font-size:12.5px}} tr.sportsbox td,tr.onform td{{color:var(--ink2)}}
.charts{{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:12px}} .chart{{margin:0;background:var(--surface);border:1px solid var(--line);border-radius:10px;padding:8px}}
.chart figcaption{{font-size:13px;font-weight:600;margin:0 0 2px 4px}} svg{{width:100%;height:auto;display:block}}
.grid{{stroke:var(--line);stroke-width:1}} .grid.bar{{stroke:var(--ink2);stroke-dasharray:3 3}} .tick{{fill:var(--ink2);font-size:10px}}
.line{{fill:none;stroke-width:2}} .dot{{stroke:var(--surface);stroke-width:2}} .s1{{stroke:var(--s1)}} circle.s1{{fill:var(--s1)}} .s2{{stroke:var(--s2)}} circle.s2{{fill:var(--s2)}} .s3{{stroke:var(--s3)}} circle.s3{{fill:var(--s3)}}
.legend{{display:flex;gap:18px;font-size:14px;color:var(--ink2);flex-wrap:wrap}} .legend i{{display:inline-block;width:14px;height:3px;vertical-align:middle;margin-right:6px}}
.pairs{{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:16px}} .pair{{display:grid;grid-template-columns:1fr 1fr;gap:8px}}
.pair figure{{margin:0}} .pair img{{width:100%;border-radius:10px;border:1px solid var(--line);display:block}} .pair figcaption{{font-size:12px;color:var(--ink2);margin-top:4px}}
.callouts{{max-width:820px}} .callouts li{{margin:6px 0}} .who{{color:var(--ink2)}} code{{font-size:13px}}
.verdict{{display:inline-block;padding:4px 10px;border-radius:999px;border:1px solid var(--line);font-weight:600}}
.toc{{display:flex;flex-wrap:wrap;gap:8px 16px;margin:16px 0 0;font-size:14px}} .toc a{{color:var(--accent);text-decoration:none;font-weight:600}}
.callout{{background:var(--surface);border:1px solid var(--line);border-left:4px solid var(--low);border-radius:10px;padding:4px 18px;max-width:880px}}
.callout li{{margin:8px 0}} .sub{{font-weight:400;font-size:11px}} .gain{{color:var(--accent);font-size:12px;font-weight:600}}
table.whyt td.why{{min-width:320px;max-width:520px;color:var(--ink)}} table.whyt td.num{{white-space:nowrap}}
.structural li,.gaps li{{margin:10px 0;max-width:880px}} .tag{{display:inline-block;font-size:12px;font-weight:600;padding:1px 8px;border-radius:999px;border:1px solid var(--line);color:var(--ink2)}}
.fix{{color:var(--ink2)}} .refs{{display:flex;gap:8px;overflow-x:auto;padding-bottom:8px}} .refs img{{height:300px;border-radius:8px;border:1px solid var(--line)}}
</style><main>
<h1>SwingCoach UI Council</h1>
<p class=lede>{esc(summary.get('lede', 'Four models scored the app and two reference apps on a frozen 13-metric rubric, round by round, while the UI was fixed between rounds.'))}</p>
<nav class=toc><a href="#read">How far to trust this</a><a href="#screens">Before and after</a><a href="#why">Why the score rose</a><a href="#gaps">Why not 10</a><a href="#refs">Reference apps</a><a href="#tables">Score tables</a></nav>
<h2>Summary</h2>
<p><span class=verdict>{esc(summary.get('verdict', 'In progress'))}</span></p>
<ul><li>Rounds: {final} after the baseline.</li><li>Stop reason: {esc(summary.get('stop', 'still running'))}</li></ul>
<table><thead><tr><th>Member</th><th>Start: lowest metric</th><th>Start: overall</th><th>Latest: lowest metric</th><th>Latest: overall</th></tr></thead><tbody>{start_end}</tbody></table>
<h2 id=read>How far to trust these scores</h2>
<div class=callout><ul>{''.join(f'<li>{esc(i)}</li>' for i in summary.get('honest', []))}</ul></div>
<h2 id=screens>Before and after, screen by screen</h2>
<p class=lede>Before is round 0, the start of this council. After is the build on the PR: round {final} plus Ruari's review amendments. {esc(summary.get('amend', ''))} The numbers on each after image match the notes under it: what changed, why, and who asked for it.</p>
{screen_section('shots/r00', f'shots/r{shots:02d}', 'council', 'council')}
<h2 id=why>Why the score rose from the start</h2>
<p class=lede>Each member's round 0 score next to their last one: round {final} for Sol, round 14 for the others. Every member scored every metric higher. Each row names the changes behind the gain; the screens above show them.</p>
{why_up_table()}
<h3>Each metric by round</h3>
<p class=legend><span><i style='background:var(--s1)'></i>SwingCoach</span><span><i style='background:var(--s2)'></i>Sportsbox</span><span><i style='background:var(--s3)'></i>Onform</span><span>Sol's scores, the one member who scored every round. The dashed line is the 9.5 bar.</span></p>
<div class=charts>{''.join(chart(k) for k in K)}</div>
<h2 id=gaps>Why we're still well short of 10</h2>
<ul class=structural>{''.join(f'<li>{i}</li>' for i in summary.get('gaps_structural', []))}</ul>
<h3>What a reviewer still flags</h3>
{gaps_list()}
<h3>What would close the gap</h3>
<ol>{''.join(f'<li>{esc(i)}</li>' for i in summary.get('next_steps', []))}</ol>
<h2 id=refs>The reference apps</h2>
{reference_section()}
<h2 id=tables>Scores, round by round</h2>{score_table()}
<h3>Round 14, the last full council, every metric</h3>{metric_table(14)}<h3>Round {final}, every metric</h3>{metric_table(final)}
<h2>What the earlier pass did</h2>
<p class=lede>{esc(summary.get('earlier', 'The coaching walkthrough pass on coaching-player-ux, from d75f001 to 0ebe504.'))}</p>
{screen_section('shots/pre-pr', 'shots/r00', 'earlier', 'earlier')}
<h2>Declined asks</h2>{bullet_list(declined)}
<h2>Where members disagreed</h2>{bullet_list(summary.get('disagreements', []))}
<h2>Council flubs</h2>{bullet_list(summary.get('flubs', []))}
</main>"""
(root / "report-artifact.html").write_text(page)
(root / "report.html").write_text("<!doctype html><html lang=en><head><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1,viewport-fit=cover'>" + page + "</html>")
print(root / "report.html")
