# Round 9 implementation brief

You are implementing one round of UI fixes for SwingCoach, an iPhone golf coaching app (SwiftUI, iOS 26). Work only in the worktree `/Users/ruari/Documents/Startups/SwingCoach-wt/ui-council` (branch `ui-council`). Do not push, do not touch `main`, do not merge. Read `AGENTS.md`, then `docs/FRONTEND.md` (its "Look" section describes the shared tokens and components in `SwingCoach/Theme.swift`).

## This round is the product owner's direction

Ruari (the product owner) looked at the screenshots and gave direction that overrides earlier council asks:

- The golfer barely looks at the phone: it sits on a tripod recording them, and they walk back to it between shots to review. Screens are read at a glance.
- Many users are beginners (high handicappers): lots of text and words isn't useful. A drawing, a badge and one short finding are.
- On Capture, the live camera view comes first. The big "Auto is on" panel from rounds 2–8 is, in his words, "disgusting" and makes the UI cramped: "there is literally a toggle, it's pretty obvious".
- The Library should show more at a glance, like the iPhone Photos app: pinch to zoom in and out to see more or fewer thumbnails.

## Ground rules

- Visual and interaction polish only. **No feature changes**, except the Library pinch-to-zoom grid below, which the product owner asked for explicitly.
- Prefer shared tokens and shared components over per-screen tweaks or layout rewrites. Extend `Theme.swift` rather than adding one-off values.
- Keep meaningful colour: the red / amber / green level colours carry coaching meaning; the lime `Color.appAccent` is the brand accent. Never make the UI grey or sterile. Never let colour be the only signal.
- The player and Capture are dark by design; Library, Settings and Library sheets follow the system appearance.
- Current screenshots: `/Users/ruari/Documents/Startups/ui-council-media/shots/r08/` (`<NN-screen>-light.png` / `-dark.png`). Look before and after.
- Leave uncommitted files under `ui-council/` alone; they are the council's.
- **Originality:** SwingCoach's UI stays its own. Never make a screen resemble the reference apps (Sportsbox 3D Golf, Onform); if a fix would, skip it and say so.

## Fixes for this round, most important first

1. **Give the camera its view back** (`14-auto-camera`, `11-auto-recap`, `15`, `16`). Remove the full-width "Auto is on" status panel and the "Tap Manual to stop" hint. The Auto/Manual toggle carries the mode; at most add a small, quiet indicator (a dot in or beside the toggle) while Auto is armed. Keep the saved-count control compact and low. Nothing else grows over the viewfinder; overall the camera screen should show more live picture than round 0's (`shots/r00/14-auto-camera-dark.png`) did, not less. Keep the Auto/Manual control's 44 pt targets. Remove tokens that become unused.
2. **Recap card: a glance, not a read** (`11-auto-recap`). Cut it to: the finding title, its severity badge (number in its level colour, no long pill text), the "Shows it most" picture, and the Compare action. Drop the camera caveat line, the swing-count sentence and any key/legend from the card (they stay in the comparison and All checks). Make it as short as it can be and keep it low over the viewfinder.
3. **Step card: less text** (`05`, `06`, `13`). For a beginner glancing from the tripod: keep the finding title, the severity badge, Back / Play / Next and "All checks". Remove the camera caveat line and the Address / Good players / This swing legend from the card (the legend stays in All checks; the drawing's own colours already distinguish the swing). Shorten the "Halfway back, finding 3 of 8" eyebrow to the position and a small "3/8" counter. The card should end clearly shorter, which also clears more of the golfer.
4. **Library like Photos** (`01-library`). A denser grid of square thumbnails with tight 2 pt gutters (Photos-like), defaulting to 3 columns, with pinch to zoom between 2, 3 and 5 columns (animated, remembered in user defaults). Tiles lose their caption row: put the duration small over the thumbnail's bottom corner, drop the "DTL" badge when a session is all DTL, keep the star overlay for starred swings. Keep session headers (date, time span, count, Review / Select all) but compact. Thumbnails must stay sharp at the 2-column size (generate at the largest tile size × screen scale) and crop toward the golfer. Keep all existing library actions (select, delete, filter, review) working; update any UI test that relies on the old card layout, without weakening what it checks. Add a UI test that pinching changes the column count.
5. **Session review and All checks: fewer words where they're glanced at** (`03`, `07`). Keep the content, but trim explainer sentences that repeat what a badge or drawing already shows; keep at most one short line of explanation under any headline. Don't remove information a golfer can't get elsewhere.

Not this round: anything else from the council. Do not reintroduce large status banners over the camera.
## Done means

- Builds for the Simulator with no new warnings: `xcodebuild build -project SwingCoach.xcodeproj -scheme SwingCoach -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- Tests pass: `scripts/verify.sh unit coaching library review capture trim storage` (run in the background and wait; only one Simulator at a time). If you change text a UI test asserts, update the test deliberately and say which; never weaken an assertion otherwise. If you touch thumbnails or anything Trim/storage reads, add `trim storage`.
- Update `docs/FRONTEND.md` / `docs/COACHING.md` where they describe something you changed.
- Commit on `ui-council` with a message listing the changes, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

Reply with: the commit hash, one line per numbered fix (done / partly / not done, and why), the test verdict line, and any test you changed.
