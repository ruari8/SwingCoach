# UI council ledger

Scores are 1–10 per metric (see [rubric.md](rubric.md)). Columns: typo = typography, hier = hierarchy, space = spacing, color, cons = consistency, clar = clarity, a11y = accessibility, subj = swing visibility, overl = drawing legibility, data, state, polish, overall. "min" is the lowest of the 13.

## Setup decisions

- **Base branch.** The "Next Ticket Priority Question" thread's UI pass is on `coaching-player-ux` (7 commits on `d75f001`), unpushed and with no PR. Its PR isn't merged, so this branch stacks on it; `ui-council` therefore carries those commits too. The commit before that pass is `d75f001`.
- **Seed.** 12 swings from the 15 Nov range session (`15:11_range_session`, clips 001–012), coached on the Mac with the app's own code (`detector_workbench/validation/coaching/run.sh`), copied into the Simulator's app container by `capture.sh`. Synthetic Auto shows them as its session (`-ui-testing-auto-library`).
- **Privacy.** The repo is public and the footage is Ruari's, so screenshots and the report stay out of git; the report is published as a private page.
- **References.** Sportsbox 3D Golf (AI swing analysis from one phone video, 4.9★, 3.8k ratings) and Onform (video analysis with drawing tools and AI auto-detect, 4.8★, 8.7k ratings), App Store screenshots of 20 Nov 2026.
- **Rubric.** Merged from Sol, Opus and Fable's proposals; Gemini's arrived after the freeze.
- **Originality (Ruari, 20 Nov, round 4).** The UI stays original: the references only calibrate scores. From round 5, member briefs forbid fixes that imitate a reference app, and implementers decline any that would.

## Summary

| Round | Commit | Member | Us min | Us overall | Sportsbox overall | Onform overall |
|---|---|---|---|---|---|---|
| 0 | `0ebe504` | sol | 5.6 | 7.0 | 7.4 | 7.7 |
| 0 | `0ebe504` | opus | 5.5 | 6.3 | 7.1 | 7.1 |
| 0 | `0ebe504` | fable | 5.0 | 6.1 | 6.6 | 7.4 |
| 0 | `0ebe504` | gemini | 4.8 | 5.8 | 7.4 | 7.9 |
| 1 | `907787c` | sol | 6.0 | 7.1 | 7.6 | 7.9 |
| 2 | `6436f63` | sol | 6.3 | 7.3 | 7.8 | 7.9 |
| 3 | `62b48ae` | sol | 6.8 | 7.7 | 7.5 | 8.0 |
| 4 | `eb33378` | sol | 6.7 | 7.6 | 7.5 | 7.9 |
| 5 | `e887fc4` | sol | 6.8 | 7.7 | 7.5 | 7.7 |
| 6 | `79a8e8b` | sol | 7.0 | 7.8 | 7.5 | 8.0 |
| 6 | `79a8e8b` | opus | 6.8 | 7.3 | 6.8 | 7.2 |
| 6 | `79a8e8b` | fable | 6.8 | 7.3 | 6.2 | 7.6 |

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

**gemini**

| App | typo | hier | space | color | cons | clar | a11y | subj | overl | data | state | polish | overall | min |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SwingCoach | 6.2 | 6.5 | 6.1 | 5.4 | 5.0 | 6.3 | 4.8 | 5.7 | 6.1 | 5.2 | 6.1 | 5.5 | 5.8 | 4.8 |
| Sportsbox | 6.8 | 7.3 | 7.2 | 7.8 | 6.8 | 7.3 | 7.5 | 7.8 | 7.6 | 8.5 | 7.5 | 6.8 | 7.4 | 6.8 |
| Onform | 7.6 | 7.9 | 7.8 | 8.0 | 7.9 | 7.5 | 7.9 | 8.5 | 8.1 | 7.4 | 7.8 | 7.7 | 7.9 | 7.4 |
| SwingCoach before the earlier pass (d75f001) | 5.5 | 5.2 | 5.6 | 4.7 | 4.4 | 5.3 | 4.4 | 7.1 | 4.8 | 4.3 | 4.8 | 4.6 | 4.9 | 4.3 |

Gemini's round 0 scores arrived during round 4's fixes and were folded in here. Known capture gap: on the pre-PR build (d75f001) the tour's recap path left a review player open, so that build's '14-auto-camera' shot is a player, not the camera; Sol and Fable noticed and scored around it.

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

## Round 3

Build: `62b48ae`

Changes this round:

- Step card 9 pt padding, 5 pt rows, 2 pt above the scrubber; impact step clears shoes and ball (Sol). Partly: one Auto review frame still has the trail shoe under the card.
- Shared Color.helpText: 5.0:1 on grouped grey, 5.5:1 on white, 6.2:1+ in dark; used for all help and footnote text (Sol).
- Captioned tool rail: one 56 pt capsule, 10 pt semibold captions (Info, Speed, Draw, Layers, Delete, Positions, Expand), 46 pt targets (Sol, Opus, Fable).
- Recap badges at 26 pt with one key, 'Number = steps out of zone' (Sol).
- Unjudged guide rows say 'Not judged · a guide' up front and draw a dashed neutral track (Sol).
- Level badges pinned inside their own P chip; 8 pt gap to the scrubber (Sol).
- Address reference drawn thinner and dimmer so head marks don't stack (Sol).
- Session review leads with '7 of 11 judged swings good' in large type; themes say '5 steps out, typical' (Sol).
- Folded finding labelled 'Top finding · at impact' (Sol).
- One severity wording: 'N steps out', 'In zone', 'Not judged' everywhere (Sol).
- Session links are neutral connectors: 'Seen together on N swings' (Sol).

**sol**

| App | typo | hier | space | color | cons | clar | a11y | subj | overl | data | state | polish | overall | min |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SwingCoach | 7.8 | 7.6 | 7.0 | 7.7 | 7.3 | 7.4 | 6.8 | 8.0 | 8.2 | 7.4 | 7.8 | 7.8 | 7.7 | 6.8 |
| Sportsbox | 7.0 | 7.5 | 7.1 | 7.4 | 7.3 | 6.8 | 7.1 | 8.1 | 7.5 | 8.2 | 7.0 | 7.4 | 7.5 | 6.8 |
| Onform | 7.5 | 8.0 | 8.1 | 7.5 | 8.1 | 7.0 | 7.2 | 8.9 | 8.0 | 7.0 | 7.4 | 8.0 | 8.0 | 7.0 |

## Round 4

Build: `eb33378`

Changes this round:

- A walkthrough stop draws only its own finding; supporting drawings only with 'Every check on the frame' (Sol).
- Finding titles describe what the swing did, past tense: 'Head didn't drop into impact', 'Shaft steepened coming down' (Sol).
- Auto armed state: full-width solid capsule, 28 pt bold, 24 pt indicator with a matching 2 pt edge; saved count beneath (Sol, Gemini).
- Step card about 18 pt shorter (3 pt rows, 7 pt padding); All checks capsule drawn at 28 pt with a 44 pt tap (Sol).
- Comparison tiles share one 4:5 preview cropped to the golfer and club; four swings show on the first view (Sol).
- 'Finding 1 of 2' for progress, 'N steps out' for severity; 'Show findings' (Sol).
- Shared Color.sectionHeading (about 9.5:1) for every list section heading (Sol).
- Recap line: 'On all 4 swings with a halfway-back (P3) reading' (Sol).
- 'Start here' above the first theme's title in grey secondary style (Sol).
- Session header button reads 'Select session' (Sol, Gemini).
- The Layers rail tool opens 'Drawing layers' (Sol).

Declined:

- Horizontally scrolling P strip with 44 pt-wide cells (Sol, second time): ten positions in 402 pt cannot each be 44 pt wide without hiding some; the strip's job is to show all ten. Cells are full-height 56 pt targets.

**sol**

| App | typo | hier | space | color | cons | clar | a11y | subj | overl | data | state | polish | overall | min |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SwingCoach | 7.3 | 7.6 | 7.0 | 7.6 | 7.6 | 7.2 | 6.7 | 8.0 | 7.5 | 7.3 | 7.5 | 7.9 | 7.6 | 6.7 |
| Sportsbox | 7.0 | 7.3 | 6.8 | 7.2 | 7.4 | 6.8 | 6.2 | 7.9 | 7.2 | 8.2 | 6.8 | 7.3 | 7.5 | 6.2 |
| Onform | 7.6 | 7.8 | 7.5 | 7.3 | 7.8 | 6.9 | 6.7 | 8.7 | 8.0 | 6.9 | 6.8 | 8.0 | 7.9 | 6.7 |

## Round 5

Build: `e887fc4`

Changes this round:

- One type ramp in Theme.swift: four Dynamic Type sizes (large title, title 3, subheadline, caption); bold for headings, semibold for labels, tabular digits in rows and badges; fixed sizes named where cells can't grow.
- Head rings are thin solid outlines; the reading's dot is the strongest mark (Sol).
- Auto capsule says how to stop: 'Switch to Manual to stop' (Sol). Partly: tapping the capsule doesn't stop Auto, so no stop glyph was added.
- Club caveat on the step card shortened to 'Depends on camera position', full text in All checks (Sol). Partly: the card is only a few points shorter.
- Session headline gets a qualifier: what counts as 'good' (Sol).
- All checks leads with 'N of M checks in zone', then 'Top finding' (Sol).
- Expanded card: 'N steps outside the good zone' (Sol).
- Recap headline badge '4 steps out, typical'; example caption 'Swing 5 · 4 steps out' (Sol).
- Folded card action shortened to 'Findings' (Sol).
- Session photo captions keep the swing and zone result, no unexplained percentages (Sol).
- 'Select session' is a bordered secondary capsule (shared SecondaryCapsuleButtonStyle); 'Review' is the filled accent button (Sol).
- Swing Info confidence numbers in the same tabular style as Time (Sol).

Declined:

- Horizontally scrolling P strip with 44 pt-wide cells (Sol, third time): left for Ruari to decide; the strip keeps all ten positions visible.

**sol**

| App | typo | hier | space | color | cons | clar | a11y | subj | overl | data | state | polish | overall | min |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SwingCoach | 7.6 | 7.8 | 7.1 | 7.8 | 7.4 | 7.3 | 6.8 | 8.1 | 8.2 | 7.1 | 7.5 | 7.9 | 7.7 | 6.8 |
| Sportsbox | 7.1 | 7.5 | 6.8 | 7.5 | 7.3 | 6.9 | 6.4 | 7.8 | 7.6 | 8.3 | 6.8 | 7.5 | 7.5 | 6.4 |
| Onform | 7.0 | 7.6 | 7.4 | 7.6 | 7.8 | 7.0 | 6.5 | 8.8 | 8.1 | 6.9 | 7.0 | 7.8 | 7.7 | 6.5 |

## Round 6

Build: `79a8e8b`

Changes this round:

- Head reading: small hollow marker with dark outline; head tags sit in the sky above the hat (Sol).
- Every zone edge gets the measured line's dark outline at a lighter weight, in the shared drawing code (Sol).
- Auto state is a solid dark status panel with no button-like outline; 'Switch to Manual to stop' near-white (Sol).
- Recap bars removed; badges carry status, outlined for 'other way'; same in recap caption and Compare tiles (Sol).
- Zone track captions larger, brighter, tabular, each with a swatch of its mark (Sol).
- 'N steps out' is the only severity wording; key defines a step as a set distance per check, matching COACHING.md (Sol). The implementer declined the brief's 'one zone-width' wording because each check has its own step size.
- Low-confidence position named 'Address · Low confidence'; folded card 'Swing's top finding · at impact' (Sol).
- Rail fold toggle captioned 'Hide' / 'Show' (Sol).
- 'Layers' sheet and tool; first toggle 'Coaching overlays' (Sol).
- Toolbar 'Select swings' (Sol).
- Settings footers: short first line, details after, none over three lines (Sol).

Declined:

- Horizontally scrolling P strip with 44 pt-wide cells (Sol, fourth time): left for Ruari.

**sol**

| App | typo | hier | space | color | cons | clar | a11y | subj | overl | data | state | polish | overall | min |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SwingCoach | 7.8 | 7.9 | 7.3 | 8.0 | 7.8 | 7.4 | 7.0 | 8.0 | 7.6 | 7.4 | 7.8 | 8.1 | 7.8 | 7.0 |
| Sportsbox | 6.9 | 7.6 | 7.1 | 7.4 | 7.5 | 7.1 | 6.7 | 7.7 | 7.5 | 8.1 | 7.1 | 7.4 | 7.5 | 6.7 |
| Onform | 7.6 | 7.8 | 7.9 | 7.5 | 8.1 | 7.2 | 7.1 | 8.8 | 8.0 | 7.0 | 7.4 | 8.2 | 8.0 | 7.0 |

**opus**

| App | typo | hier | space | color | cons | clar | a11y | subj | overl | data | state | polish | overall | min |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SwingCoach | 7.3 | 7.5 | 6.9 | 7.3 | 6.8 | 7.0 | 7.0 | 7.1 | 7.5 | 7.0 | 7.6 | 7.4 | 7.3 | 6.8 |
| Sportsbox | 6.4 | 6.8 | 6.3 | 6.4 | 6.5 | 6.2 | 5.8 | 7.0 | 6.8 | 7.5 | 6.0 | 6.6 | 6.8 | 5.8 |
| Onform | 7.4 | 7.0 | 7.3 | 6.9 | 7.3 | 6.4 | 6.8 | 7.8 | 7.0 | 6.2 | 6.6 | 7.6 | 7.2 | 6.2 |

**fable**

| App | typo | hier | space | color | cons | clar | a11y | subj | overl | data | state | polish | overall | min |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SwingCoach | 7.0 | 7.5 | 6.8 | 7.5 | 6.9 | 7.6 | 6.9 | 7.3 | 7.2 | 7.5 | 7.3 | 7.0 | 7.3 | 6.8 |
| Sportsbox | 6.0 | 6.5 | 6.0 | 6.0 | 5.5 | 5.5 | 6.0 | 6.5 | 6.0 | 7.0 | 6.0 | 6.0 | 6.2 | 5.5 |
| Onform | 7.5 | 7.3 | 7.5 | 7.5 | 7.8 | 6.3 | 6.8 | 8.5 | 7.5 | 6.5 | 7.0 | 8.0 | 7.6 | 6.3 |

Decision: Sol's lowest metric held at 6.8, 6.7, 6.8 over rounds 3–5, so round 6 is scored by the full council for a fresh read rather than waiting for Sol to clear 9.5 alone. Gemini's round 6 scores were still running when round 7 started.
