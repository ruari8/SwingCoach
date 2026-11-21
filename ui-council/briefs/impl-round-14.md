# Round 14 implementation brief

You are implementing one round of UI fixes for SwingCoach, an iPhone golf coaching app (SwiftUI, iOS 26). Work only in the worktree `/Users/ruari/Documents/Startups/SwingCoach-wt/ui-council` (branch `ui-council`). Do not push, do not touch `main`, do not merge. Read `AGENTS.md`, then `docs/FRONTEND.md` (its "Look" section describes the shared tokens and components in `SwingCoach/Theme.swift`).

## Product principles (from the product owner; they override council asks)

- The golfer barely looks at the phone: it sits on a tripod recording them, and they walk back to it between shots. Screens are read at a glance.
- Many users are beginners: a drawing, a badge and one short finding help; extra words, caveats and legends mostly don't. Detail belongs one tap deeper.
- On Capture the live camera view comes first. Never add banners or panels over the viewfinder; the Auto/Manual toggle shows the mode.
- The Library is a dense Photos-style grid (round 9). Keep it.

## Ground rules

- Visual and interaction polish only. **No feature changes**: nothing added or removed that a user can do.
- Prefer shared tokens and shared components over per-screen tweaks or layout rewrites. Extend `Theme.swift` rather than adding one-off values.
- Keep meaningful colour: the red / amber / green level colours carry coaching meaning; the lime `Color.appAccent` is the brand accent. Never make the UI grey or sterile. Never let colour be the only signal.
- The player and Capture are dark by design; Library, Settings and Library sheets follow the system appearance.
- Current screenshots: `/Users/ruari/Documents/Startups/ui-council-media/shots/r13/` (`<NN-screen>-light.png` / `-dark.png`). Look before and after.
- Leave uncommitted files under `ui-council/` alone; they are the council's.
- **Originality:** SwingCoach's UI stays its own. Never make a screen resemble the reference apps (Sportsbox 3D Golf, Onform); if a fix would, skip it and say so.

## Fixes for this round, most important first

1. **Auto's state in words, inside the toggle** (`14`). The glyph alone leaves "is it watching?" to inference. While detection is active, the Auto segment reads "Auto ready" (keep the glyph); paused reads "Auto" with the ring. No new footprint: it must fit the existing segmented control (shrink the label style one step if needed, keeping 44 pt targets).
2. **Recap names its scope** (`11`). Label the button "Compare last 5" (use the actual window size) so the card reads as a pattern over swings, not one shot.
3. **Amber and red dots differ by shape too** (`03`, and every verdict dot). Both use the same "!". Give amber and red distinct glyphs in the shared verdict-dot style (e.g. "!" vs "!!", or a different outline), used everywhere such dots appear.
4. **Folded card says it jumps** (`10`). The folded finding reads like a verdict on the current frame. Give it the action label "Jump to impact finding" (or "Jump to <position> finding"), keeping the position in the transport row.
5. **Comparison key** (`12`). Show only the keys for drawings visible in the tiles beside the grid; the full key and the camera qualifier live in All checks.
6. **Reference-only rows** (`07`). Use "Reference only" beside guide rows (Posture) and the same words in the summary key for the dashed bar style.
7. **Comparison grid order** (`12`). The half-height unjudged tile staggers the columns; give it the same frame size as other tiles (its contents stay neutral) so captions read in a clean grid. (This reverses round 13's half-height tile.)
8. **Co-occurrence footer** (`04`). Members read "the earliest often causes the later ones" as a causal claim the counts can't show. Use "Listed in swing order. Work on the earliest first." — the coaching advice stays, the claim goes.
9. **One name for the recap** (`02`, `14`). Settings "Coach speaks in Auto" suggests voice. Use "Show Auto recap" in Settings and "Recap: every 5 swings" on the Capture chip.

Declined this round: "4 steps out" instead of the severity word on the step card (Sol): the product owner wants words, not numbers, for beginners; the badge carries the number. Redrawing the shaft line from the grip (Sol): the line shows where the shaft points, extended to the ground, which is the check's meaning.
## Done means

- Builds for the Simulator with no new warnings: `xcodebuild build -project SwingCoach.xcodeproj -scheme SwingCoach -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- Tests pass: `scripts/verify.sh unit coaching library review capture` (run in the background and wait; only one Simulator at a time). If you change text a UI test asserts, update the test deliberately and say which; never weaken an assertion otherwise. If you touch thumbnails or anything Trim/storage reads, add `trim storage`.
- Update `docs/FRONTEND.md` / `docs/COACHING.md` where they describe something you changed.
- Commit on `ui-council` with a message listing the changes, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

Reply with: the commit hash, one line per numbered fix (done / partly / not done, and why), the test verdict line, and any test you changed.
