# UI council

An overnight design review loop for the app's UI (20 Nov 2026). Four models score the app and two reference apps on a frozen rubric, the app is fixed round by round, and every round is recorded in the ledger.

| File | What it is |
| --- | --- |
| [rubric.md](rubric.md) | The 13 metrics, frozen at round 0 |
| [ledger.md](ledger.md) | Every round: commit, each member's scores for us and the references, changes, declined asks |
| [capture.sh](capture.sh) | The deterministic screenshot run: one iPhone 17 Simulator, pinned status bar, the seeded range session, `UICouncilTourUITests` in light and dark |
| [briefs/](briefs/) | The exact brief each member received |
| [references/](references/) | App Store screenshots of Sportsbox 3D Golf and Onform |
| `tools/` | Seed builder, brief writer, contact sheets, report builder |

The screenshots and `report.html` show Ruari's own range footage, so they are not committed (this repository is public). They live in `~/Documents/Startups/ui-council-media/`, and the report is published as a private claude.ai page linked from the PR.

Rerun a capture:

```bash
ui-council/capture.sh ~/Documents/Startups/ui-council-media/shots/rNN            # this checkout
ui-council/capture.sh ~/Documents/Startups/ui-council-media/shots/pre-pr --ref d75f001   # an older commit
```
