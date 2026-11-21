# Round 2 implementation brief

You are implementing one round of UI fixes for SwingCoach, an iPhone golf coaching app (SwiftUI, iOS 26). Work only in the worktree `/Users/ruari/Documents/Startups/SwingCoach-wt/ui-council` (branch `ui-council`). Do not push, do not touch `main`, do not merge. Read `AGENTS.md`, then `docs/FRONTEND.md` (its "Look" section describes the shared tokens in `SwingCoach/Theme.swift` from round 1).

## Ground rules

- Visual and interaction polish only. **No feature changes**: nothing added or removed that a user can do.
- Prefer shared tokens and shared components over per-screen tweaks or layout rewrites. Extend `Theme.swift` rather than adding one-off values.
- Keep meaningful colour: the red / amber / green level colours carry coaching meaning; the lime `Color.appAccent` is the brand accent. Never make the UI grey or sterile. Never let colour be the only signal.
- The player and Capture are dark by design; Library, Settings and Library sheets follow the system appearance.
- Current screenshots: `/Users/ruari/Documents/Startups/ui-council-media/shots/r01/` (`<NN-screen>-light.png` / `-dark.png`). Look before and after.
- Leave uncommitted files under `ui-council/` alone; they are the council's.

## Fixes for this round, most important first

1. **One label on the opening frame** (`05-player-open`). Two coloured name tags ("Posture at impact", "Head height at impact") sit over the golfer's head, and the posture one competes with the step's finding. On a walkthrough stop, only the step's own finding gets a name tag, placed beside the golfer, not on the head; supporting drawings on that frame stay drawn but muted (thinner, lower opacity) with no tag. "Every check on the frame" mode keeps tags for all.
2. **Readings against their zone** (`07-all-checks`, and the session review's "-23%" / "+5%"). Rows say "You: +19%. Good players: −29% to +3%." as a sentence, so the golfer must compare numbers. Add one small shared component: a horizontal track with the good-players zone as a green band and the swing's value as a marker in its level colour, with the reading and the zone as aligned tabular numbers under it, and a word for the side ("Above zone", "Below zone", "In zone"). Use it in All checks rows. Where a reading appears elsewhere with no context (session review captions), say what it is ("6 steps out, −23%").
3. **Auto armed state** (`14-auto-camera`). Still reads like a caption next to "12 saved". Make "Auto is on" clearly the primary capture state: larger text (title2 semibold or bigger), a larger indicator, on a solid (not translucent) dark capsule, visually separated from the saved-count control which stays secondary.
4. **Recap strip, not hue alone** (`11-auto-recap`). The five bars differ only by colour. Put the shared `CoachingLevelBadge` (tick / level number / dash) on each swing's slot, with the swing number beneath, so severity reads by shape and number too; keep the bar colour.
5. **Position strip** (`05`, `06`, `10`). On the opening step P7 has no selected treatment, while later steps show P3 selected: the current position must always carry the selected treatment, with its level badge kept separate. Make every chip's whole cell the hit area at least 44 pt tall, and raise the P labels to 11 pt semibold. Keep all ten visible (no scrolling strip).
6. **Not-judged tile** (`12-auto-compare`). Swing 1 is a big black gap with faint text that reads like a failed thumbnail. Show it with the same rounded bounds as the other tiles, a neutral fill, the dash badge and "Not judged" in readable secondary text.
7. **Guides look neutral** (`07-all-checks`, Address row). An unjudged guide (posture at address) is drawn in green, which reads as "in zone". Draw guides and their thumbnails in the neutral guide style everywhere.
8. **Session review top** (`03-session-review`). The totals block and a four-line key delay the first theme. Put a compact symbol key directly under the markers (one line: tick in zone · number = steps out · dash not judged), tighten the summary rows, and name each denominator in its label ("7 of 11 judged swings"; the theme line "4 of 8 swings with a takeaway reading").
9. **Rail clarity** (`05`, `06`). Two adjacent icons (the coloured crossed-lines tool and the line-over-dots tool) can't be told apart. Use clearer, conventional SF Symbols for each rail tool and make sure each has a distinct glyph; if a tool opens a sheet of options, its glyph should say so. Do not add permanent text labels over the video.
10. **Swing Info confidence** (`09-swing-info`). A 50% address reading looks like the 80%+ rows. Mark low-confidence rows with a short "Low" label (and the existing "?" on the name) in a distinct colour/weight; use the same wording anywhere positions show low confidence.
11. **Library thumbnails** (`01-library`). Thumbnails are soft and the landscape crop cuts off the golfer's head. Generate thumbnails at the card's displayed size × screen scale (see `thumbnailTargetSize` in `SwingLibrary.swift`) and bias the crop toward the top of a portrait clip so the golfer's head and body show.
12. **Step card level badge** (`05`, `06`). The bare "4" or "3" in a coloured circle reads like a count. On the step card, give the badge a short word ("4 out" / "3 steps out", or "In zone"); the P strip keeps the bare badge.

Declined this round (do not do): a horizontally scrolling P strip (hides positions); renaming the Auto review counter to "Session swing 2 of 12" (the counter already reads in the session's context).

## Done means

- Builds for the Simulator with no new warnings: `xcodebuild build -project SwingCoach.xcodeproj -scheme SwingCoach -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- Tests pass: `scripts/verify.sh unit coaching library review capture` (run in the background and wait; only one Simulator at a time). If you change text a UI test asserts, update the test deliberately and say which; never weaken an assertion otherwise. If you touch thumbnails or anything Trim/storage reads, add `trim storage`.
- Update `docs/FRONTEND.md` / `docs/COACHING.md` where they describe something you changed.
- Commit on `ui-council` with a message listing the changes, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

Reply with: the commit hash, one line per numbered fix (done / partly / not done, and why), the test verdict line, and any test you changed.
