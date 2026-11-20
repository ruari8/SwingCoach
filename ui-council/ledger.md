# UI council ledger

Scores are 1–10 per metric (see [rubric.md](rubric.md)). Columns: typo = typography, hier = hierarchy, space = spacing, color, cons = consistency, clar = clarity, a11y = accessibility, subj = swing visibility, overl = drawing legibility, data, state, polish, overall. "min" is the lowest of the 13.

## Setup decisions

- **Base branch.** The "Next Ticket Priority Question" thread's UI pass is on `coaching-player-ux` (7 commits on `d75f001`), unpushed and with no PR. Its PR isn't merged, so this branch stacks on it; `ui-council` therefore carries those commits too. The commit before that pass is `d75f001`.
- **Seed.** 12 swings from the 15 Nov range session (`15:11_range_session`, clips 001–012), coached on the Mac with the app's own code (`detector_workbench/validation/coaching/run.sh`), copied into the Simulator's app container by `capture.sh`. Synthetic Auto shows them as its session (`-ui-testing-auto-library`).
- **Privacy.** The repo is public and the footage is Ruari's, so screenshots and the report stay out of git; the report is published as a private page.
- **References.** Sportsbox 3D Golf (AI swing analysis from one phone video, 4.9★, 3.8k ratings) and Onform (video analysis with drawing tools and AI auto-detect, 4.8★, 8.7k ratings), App Store screenshots of 20 Nov 2026.
- **Rubric.** Merged from Sol, Opus and Fable's proposals; Gemini's arrived after the freeze.

## Summary

| Round | Commit | Member | Us min | Us overall | Sportsbox overall | Onform overall |
|---|---|---|---|---|---|---|
| 0 | `0ebe504` | sol | 5.6 | 7.0 | 7.4 | 7.7 |
| 0 | `0ebe504` | opus | 5.5 | 6.3 | 7.1 | 7.1 |
| 0 | `0ebe504` | fable | 5.0 | 6.1 | 6.6 | 7.4 |
| 1 | `907787c` | sol | 6.0 | 7.1 | 7.6 | 7.9 |
| 2 | `6436f63` | sol | 6.3 | 7.3 | 7.8 | 7.9 |

## Round 0

Build: `0ebe504 (coaching-player-ux) + tour fixture`

Changes this round:

- Baseline: the coaching walkthrough pass from coaching-player-ux (0ebe504), plus the tour's fixture flag.

**sol**

| App | typo | hier | space | color | cons | clar | a11y | subj | overl | data | state | polish | overall | min |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SwingCoach | 7.3 | 7.1 | 6.6 | 6.5 | 6.8 | 7.3 | 5.6 | 6.8 | 7.2 | 6.7 | 6.8 | 7.2 | 7.0 | 5.6 |
| Sportsbox | 7.1 | 7.5 | 6.8 | 7.4 | 7.4 | 6.5 | 6.4 | 7.8 | 7.0 | 8.2 | 6.9 | 7.3 | 7.4 | 6.4 |
| Onform | 7.6 | 7.8 | 7.4 | 7.5 | 7.8 | 6.8 | 6.6 | 8.5 | 7.5 | 6.8 | 7.1 | 7.9 | 7.7 | 6.6 |
| SwingCoach before the earlier pass (d75f001) | 6.8 | 6.0 | 6.9 | 6.2 | 6.1 | 5.9 | 5.4 | 8.0 | 6.3 | 5.9 | 5.8 | 6.7 | 6.3 | 5.4 |

**opus**

| App | typo | hier | space | color | cons | clar | a11y | subj | overl | data | state | polish | overall | min |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SwingCoach | 6.8 | 6.9 | 6.4 | 5.8 | 5.6 | 6.6 | 5.5 | 6.4 | 6.0 | 6.2 | 6.6 | 6.4 | 6.3 | 5.5 |
| Sportsbox | 6.8 | 7.2 | 6.8 | 6.8 | 7.0 | 6.5 | 5.8 | 6.5 | 6.8 | 8.0 | 6.5 | 7.3 | 7.1 | 5.8 |
| Onform | 7.0 | 6.6 | 6.8 | 6.8 | 7.2 | 6.3 | 6.2 | 7.8 | 7.2 | 6.0 | 6.3 | 7.4 | 7.1 | 6.0 |
| SwingCoach before the earlier pass (d75f001) | 6.6 | 6.0 | 6.5 | 6.0 | 5.8 | 5.6 | 5.4 | 7.4 | 5.0 | 5.6 | 5.8 | 6.2 | 5.8 | 5.0 |

**fable**

| App | typo | hier | space | color | cons | clar | a11y | subj | overl | data | state | polish | overall | min |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SwingCoach | 6.3 | 7.0 | 6.0 | 5.8 | 5.5 | 6.6 | 5.0 | 5.5 | 6.5 | 5.6 | 7.0 | 5.5 | 6.1 | 5.0 |
| Sportsbox | 6.0 | 6.5 | 5.8 | 6.2 | 5.5 | 6.0 | 5.6 | 6.5 | 6.0 | 8.0 | 6.0 | 6.0 | 6.6 | 5.5 |
| Onform | 7.2 | 7.0 | 7.3 | 7.2 | 7.5 | 6.3 | 6.3 | 8.3 | 7.0 | 6.0 | 6.5 | 7.8 | 7.4 | 6.0 |
| SwingCoach before the earlier pass (d75f001) | 5.8 | 5.8 | 6.0 | 5.5 | 5.3 | 5.3 | 4.8 | 7.2 | 5.5 | 4.8 | 6.3 | 5.2 | 5.4 | 4.8 |

Gemini's round 0 scores were still running when round 1 started; they are added when they arrive.

## Round 1

Build: `907787c`

Changes this round:

- Drawing name tags stack instead of printing over each other (all three members).
- Top row (Done, counter, star) pinned to the safe area with a lighter fill and edge, so it shows over the black band and video (Opus, Fable).
- Step card compacted (12 pt padding, 6 pt gaps, legend wraps); the impact lift counts the club head so feet, ball and club head clear the card (all three).
- One accent token, Color.appAccent: the lime on dark, a darker lime ink (5.6:1) on light; app tint, toggles, tabs, Select, Done, timeline, Lock (Opus, Fable).
- One sheet style over the player: dark, 97% opaque, Done, bottom inset; Swing Info header 'Details', labelled Time and Confidence columns (all three).
- Same words everywhere: 'All checks' sheet, 'Not judged', 'Halfway back (P3)' position names, 'Settings' title (Opus, Fable, Sol).
- Auto armed state: title3 semibold label, 14 pt lime indicator on a dark capsule; red kept for recording only (all three).
- Recap legend keys drawn by the same view as the bars; this swing's colour matches across card, thumbnail and comparison (all three).
- Session review: a level badge per swing in a 44 pt target; 'Not judged' row shortened; darker 'Start here'; 13 pt caveats (all three).
- One level badge (the player's circle) everywhere; P tags are neutral capsules (Fable).
- Library: card surfaces in both modes; labelled 'Review' button; section Select as secondary text (Sol, Opus, Fable).
- Folded finding says where: 'At impact: …'; only the current P chip has a ring (Sol).
- Session review nav bar gets a background on scroll (Opus).
- Rail fill only for an active tool (Fable).

Declined:

- Move rail tools into one menu (Opus): hides tools and is a layout rewrite.
- Remove the section-level Select (Opus, Fable): removes a feature; restyled as secondary instead.
- Refit the whole video above the step card (Fable): layout rewrite; the lift plus a compact card covers the case.

**sol**

| App | typo | hier | space | color | cons | clar | a11y | subj | overl | data | state | polish | overall | min |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SwingCoach | 7.0 | 7.0 | 6.8 | 7.3 | 6.6 | 7.4 | 6.0 | 7.6 | 7.1 | 6.3 | 6.6 | 7.3 | 7.1 | 6.0 |
| Sportsbox | 7.1 | 7.5 | 7.0 | 7.3 | 7.3 | 7.0 | 6.8 | 7.5 | 7.4 | 8.6 | 6.6 | 7.6 | 7.6 | 6.6 |
| Onform | 7.5 | 7.8 | 7.6 | 7.6 | 8.0 | 7.1 | 6.9 | 8.7 | 8.0 | 6.4 | 7.2 | 8.1 | 7.9 | 6.4 |

## Round 2

Build: `6436f63`

Changes this round:

- One name tag per walkthrough stop, placed beside the drawing; supporting drawings thinner, half opacity, untagged (Sol).
- New CoachingZoneTrack: the good-players zone as a green band, the swing as a marker in its level colour, aligned tabular You / Good players / Above-Below-In zone (Sol, Fable).
- Auto armed state on a solid dark capsule, title2 semibold, 20 pt indicator, apart from the saved count (Sol).
- Recap slots carry the level badge and 'Swing N' under each bar (Sol).
- Current P position always selected (opening step fixed); 56 pt chip cells, 11 pt semibold labels (Sol, Fable).
- Not-judged comparison tile: rounded neutral tile with the dash badge (Sol).
- Guides and unjudged checks drawn neutral grey everywhere (Sol).
- Session review: one-line symbol key under the marks, compact counts that name their denominators (Sol).
- Rail glyphs: Draw pencil.line, Drawings square.3.layers.3d, Positions figure.golf (Sol, Fable).
- Low-confidence positions get a 'Low' tag (Sol).
- Library thumbnails at card size × screen scale, cropped to keep the golfer's head (Sol).
- Step card level badge carries a word: '4 steps out', 'In zone' (Opus).

Declined:

- Horizontally scrolling P strip (Sol): hides positions.
- Rename the Auto review counter to 'Session swing 2 of 12' (Sol): the counter already reads in the session's context.

**sol**

| App | typo | hier | space | color | cons | clar | a11y | subj | overl | data | state | polish | overall | min |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SwingCoach | 7.3 | 7.2 | 6.8 | 7.4 | 6.8 | 7.0 | 6.3 | 7.2 | 8.1 | 6.9 | 6.8 | 7.6 | 7.3 | 6.3 |
| Sportsbox | 7.2 | 7.6 | 7.1 | 7.4 | 7.5 | 7.1 | 6.7 | 8.1 | 7.4 | 8.6 | 6.9 | 7.7 | 7.8 | 6.7 |
| Onform | 7.5 | 8.1 | 7.7 | 7.5 | 8.0 | 7.0 | 7.0 | 8.6 | 7.9 | 7.0 | 7.3 | 8.1 | 7.9 | 7.0 |

Side effect logged: stored thumbnails are now card-shaped, so the Auto saved-count button and the player's loading poster show that crop.
