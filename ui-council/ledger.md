# UI council ledger

Scores are 1–10 per metric (see [rubric.md](rubric.md)). Columns: typo = typography, hier = hierarchy, space = spacing, color, cons = consistency, clar = clarity, a11y = accessibility, subj = swing visibility, overl = drawing legibility, data, state, polish, overall. "min" is the lowest of the 13.

## Setup decisions

- **Base branch.** The "Next Ticket Priority Question" thread's UI pass is on `coaching-player-ux` (7 commits on `d75f001`), unpushed and with no PR. Its PR isn't merged, so this branch stacks on it; `ui-council` therefore carries those commits too. The commit before that pass is `d75f001`.
- **Seed.** 12 swings from the 15 Nov range session (`15:11_range_session`, clips 001–012), coached on the Mac with the app's own code (`detector_workbench/validation/coaching/run.sh`), copied into the Simulator's app container by `capture.sh`. Synthetic Auto shows them as its session (`-ui-testing-auto-library`).
- **Privacy.** The repo is public and the footage is Ruari's, so screenshots and the report stay out of git; the report is published as a private page.
- **References.** Sportsbox 3D Golf (AI swing analysis from one phone video, 4.9★, 3.8k ratings) and Onform (video analysis with drawing tools and AI auto-detect, 4.8★, 8.7k ratings), App Store screenshots of 20 Nov 2026.
- **Rubric.** Merged from Sol, Opus and Fable's proposals; Gemini's arrived after the freeze.
