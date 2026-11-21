# Round 12 implementation brief

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
- Current screenshots: `/Users/ruari/Documents/Startups/ui-council-media/shots/r11/` (`<NN-screen>-light.png` / `-dark.png`). Look before and after.
- Leave uncommitted files under `ui-council/` alone; they are the council's.
- **Originality:** SwingCoach's UI stays its own. Never make a screen resemble the reference apps (Sportsbox 3D Golf, Onform); if a fix would, skip it and say so.

## Fixes for this round, most important first

1. **More video on the first finding** (`05`). Five equally weighted rail tools sit on the footage during the walkthrough. Open the walkthrough with the rail collapsed (tools one tap away), and caption the reveal control "Tools" instead of "Hide"/"Show". Off the walkthrough, keep the rail's current behaviour.
2. **Recap: one verdict** (`11-auto-recap`). The thumbnail's red 4 competes with the headline's amber 3. Remove the badge from the thumbnail; keep the small "Swing 5" label. The per-swing levels stay in Compare.
3. **Session tally smaller** (`03`). The tally is the strongest thing on the sheet. Set it at section-heading size and tighten the inset around the marks so "Start here" and its pictures come into view sooner.
4. **Dashed reference ring lighter still** (`05`). It competes with the measured ring at phone size; reduce it further (opacity/weight) while the measured ring and zone edge stay crisp.
5. **P strip badges in their own slot** (`06`, `10`). Badges overlap the pose silhouettes; reserve a shallow slot above each silhouette inside the cell for the badge (and the low-confidence glyph). Whole cell stays tappable.
6. **Low confidence said once** (`10`). The "?" beside Address can read as help. Show "Address · Low confidence" in the transport row's label (second line if needed) with the shared glyph.
7. **All checks summary key** (`07`). Keep only the severity and judged/not-judged key in the summary; rows already label "You" and the zone.
8. **Layers toggle name** (`08`). "All checks at this position" echoes the All checks button. Rename it "Show all drawings here"; keep the note about paused playback.
9. **Capture top row backing** (`14`, `16`). "240 fps ⌄" is bare text while the toggle and coach chip have capsules. Give it the same dark capsule as the coach chip so it holds up over bright sky.
10. **Library filter icon** (`01`). The top-left three-line circle is ambiguous; use the standard filter glyph (`line.3.horizontal.decrease.circle`) with its accessibility label unchanged.

Declined this round: a status word beside the Auto toggle (Sol, again): the product owner says the toggle is enough. Rewording the "How they sit together" footer to drop "the earliest often causes the later ones" (Sol): that's the coaching rule in `docs/COACHING.md`, not a UI claim.
## Done means

- Builds for the Simulator with no new warnings: `xcodebuild build -project SwingCoach.xcodeproj -scheme SwingCoach -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- Tests pass: `scripts/verify.sh unit coaching library review capture` (run in the background and wait; only one Simulator at a time). If you change text a UI test asserts, update the test deliberately and say which; never weaken an assertion otherwise. If you touch thumbnails or anything Trim/storage reads, add `trim storage`.
- Update `docs/FRONTEND.md` / `docs/COACHING.md` where they describe something you changed.
- Commit on `ui-council` with a message listing the changes, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

Reply with: the commit hash, one line per numbered fix (done / partly / not done, and why), the test verdict line, and any test you changed.
