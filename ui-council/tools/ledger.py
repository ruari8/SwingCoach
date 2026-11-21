#!/usr/bin/env python3
"""Regenerates ledger.md from scores/rNN.json and rounds.json."""
import json, pathlib
root = pathlib.Path(__file__).resolve().parents[1]
K = ["typography","hierarchy","spacing","color","consistency","clarity","accessibility","subject","overlays","data","state","polish","overall"]
SHORT = ["typo","hier","space","color","cons","clar","a11y","subj","overl","data","state","polish","overall"]
APPS = [("swingcoach","SwingCoach"),("sportsbox","Sportsbox"),("onform","Onform"),("swingcoach_prior","SwingCoach before the earlier pass (d75f001)")]
notes = json.loads((root/"rounds.json").read_text())
out = [(root/"ledger-header.md").read_text().rstrip(), ""]
summary = ["## Summary", "", "| Round | Commit | Member | Us min | Us overall | Sportsbox overall | Onform overall |", "|---|---|---|---|---|---|---|"]
body = []
for f in sorted((root/"scores").glob("r*.json")):
    r = json.loads(f.read_text()); n = r["round"]; note = notes.get(str(n), {})
    body += [f"## Round {n}", "", f"Build: `{r['build']}`", ""]
    if note.get("changes"):
        body += ["Changes this round:", ""] + [f"- {c}" for c in note["changes"]] + [""]
    if note.get("declined"):
        body += ["Declined:", ""] + [f"- {c}" for c in note["declined"]] + [""]
    for member, apps in r["members"].items():
        body += [f"**{member}**", "", "| App | " + " | ".join(SHORT) + " | min |", "|---|" + "---|" * (len(K) + 1)]
        for key, label in APPS:
            if key in apps:
                s = apps[key]; body.append(f"| {label} | " + " | ".join(f"{s[k]:.1f}" for k in K) + f" | {min(s[k] for k in K):.1f} |")
        body.append("")
        us = apps["swingcoach"]
        summary.append(f"| {n} | `{r['build'].split()[0]}` | {member} | {min(us[k] for k in K):.1f} | {us['overall']:.1f} | {apps['sportsbox']['overall']:.1f} | {apps['onform']['overall']:.1f} |")
    if note.get("notes"):
        body += [note["notes"], ""]
(root/"ledger.md").write_text("\n".join(out + summary + [""] + body))
print("ledger.md written")
