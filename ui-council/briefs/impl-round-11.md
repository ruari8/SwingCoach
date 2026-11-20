# Round 11 implementation brief

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
- Current screenshots: `/Users/ruari/Documents/Startups/ui-council-media/shots/r10/` (`<NN-screen>-light.png` / `-dark.png`). Look before and after.
- Leave uncommitted files under `ui-council/` alone; they are the council's.
- **Originality:** SwingCoach's UI stays its own. Never make a screen resemble the reference apps (Sportsbox 3D Golf, Onform); if a fix would, skip it and say so.

## Fixes for this round, most important first

1. **Head drawing reads as the head** (`05`). The measured ring is centred on the nose landmark, so on a bent-over golfer it looks like it sits on the chin. Keep the measurement and the ring's centre, but make the head ring's radius cover the whole head (scale it from the pose's head size if the evidence has it, else a larger fixed fraction), and give the dashed reference ring even less weight. Don't move any drawn point.
2. **Finding titles without shorthand** (`06`, `13`, recap). "Shaft flat: pointed outside the ball" leads with jargon and wraps. Use "Shaft pointed outside the ball". Check every title for a "Label: sentence" pattern and drop the label part.
3. **Recap: two badges** (`11-auto-recap`). The picture's red 4 and the headline's amber 3 read as two ratings of one swing. Put a tiny "Swing 5" under the picture's badge so it's clearly that swing's; the headline keeps "Typically well out" with its badge.
4. **Session review lead** (`03`). The tally and its legend take the first read; "Start here" is smaller. Raise the first finding's title to the next heading size; condense the tally key to one line under the marks.
5. **All checks key** (`07`). The key's "You" is a red dot but rows use outlined white and solid yellow dots. Use one marker shape for "You" everywhere, colour carrying the level.
6. **Rail over bright footage** (`05`). The translucent rail's contrast varies over cloud, grass and the bay divider; raise the shared rail material's minimum opacity and keep labels full white.
7. **Low confidence reads as one value** (`09`). "Low" is smaller than "50%"; set them at the same size and contrast as one reading ("Low · 50%").
8. **P strip** (`10`). Use the strip's full height as each cell's touch region, labels a step larger, badges aligned consistently in the same corner of every cell.
9. **Settings footer** (`02`). Condense the extra-footage footer to two short sentences (how time is counted; what happens when Auto stops early).

Declined this round: a "Watching" text label for Auto (Sol): the product owner says the toggle is enough, and round 10 fills the Auto segment while armed. Labelling the toolbar's select icon (Sol): Opus and Fable asked for icon-only last round; VoiceOver has the label.
## Done means

- Builds for the Simulator with no new warnings: `xcodebuild build -project SwingCoach.xcodeproj -scheme SwingCoach -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- Tests pass: `scripts/verify.sh unit coaching library review capture` (run in the background and wait; only one Simulator at a time). If you change text a UI test asserts, update the test deliberately and say which; never weaken an assertion otherwise. If you touch thumbnails or anything Trim/storage reads, add `trim storage`.
- Update `docs/FRONTEND.md` / `docs/COACHING.md` where they describe something you changed.
- Commit on `ui-council` with a message listing the changes, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

Reply with: the commit hash, one line per numbered fix (done / partly / not done, and why), the test verdict line, and any test you changed.
