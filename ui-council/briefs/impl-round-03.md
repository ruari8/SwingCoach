# Round 3 implementation brief

You are implementing one round of UI fixes for SwingCoach, an iPhone golf coaching app (SwiftUI, iOS 26). Work only in the worktree `/Users/ruari/Documents/Startups/SwingCoach-wt/ui-council` (branch `ui-council`). Do not push, do not touch `main`, do not merge. Read `AGENTS.md`, then `docs/FRONTEND.md` (its "Look" section describes the shared tokens and components in `SwingCoach/Theme.swift`).

## Ground rules

- Visual and interaction polish only. **No feature changes**: nothing added or removed that a user can do.
- Prefer shared tokens and shared components over per-screen tweaks or layout rewrites. Extend `Theme.swift` rather than adding one-off values.
- Keep meaningful colour: the red / amber / green level colours carry coaching meaning; the lime `Color.appAccent` is the brand accent. Never make the UI grey or sterile. Never let colour be the only signal.
- The player and Capture are dark by design; Library, Settings and Library sheets follow the system appearance.
- Current screenshots: `/Users/ruari/Documents/Startups/ui-council-media/shots/r02/` (`<NN-screen>-light.png` / `-dark.png`). Look before and after.
- Leave uncommitted files under `ui-council/` alone; they are the council's.

## Fixes for this round, most important first

1. **Step card covers the shoe and ball** (`13-auto-review`, also `05`). Tighten the shared step card's vertical padding further and sit it lower, in the gap just above the scrubber, so the mat, near shoe and ball stay visible; check the stop lift still clears the club head and ball on the impact step in both Library and Auto review.
2. **Help text contrast** (`02-settings-light`, any light-mode footnote/help text). Small grey help text measures about 3.3:1 on the grouped background. Define one shared secondary-text token for help/footnote text that reaches 4.5:1 on both grouped backgrounds in light and dark, and use it everywhere such text appears (Settings, session review, sheets).
3. **Rail captions** (`05`, `06`). Three members have asked for labels on the tool rail. Add a short caption (10–11 pt semibold, e.g. "Info", "Speed", "Draw", "Layers", "Positions") under each icon inside the rail's own capsule, so the rail is self-explanatory without covering more of the video than a few points of width. Keep 44 pt targets.
4. **Recap from the tripod** (`11-auto-recap`). The severity row is small numbers with a tiny two-entry legend. Use the larger level badge size used in the session review, and replace "Shows it, a little" / "Shows it, far out" with one plain key: "Number = steps out of zone" (plus the dash for not judged).
5. **Unjudged guide reads as a pass** (`07-all-checks`, Address posture row). The zone track's marker sits inside the band, so it looks like a pass though it's Not judged. Put "Not judged" (and the reason when known) on the row's first line beside the name, and draw the guide track and marker in the neutral style with no in-zone wording.
6. **Badges belong to their pose** (`06`, `13`). Level badges, pose icons and P labels sit on adjacent rows and it takes a second look to pair them. Anchor each badge inside its own pose cell (top-trailing corner of the chip) and add a clear gap between the position strip and the scrubber.
7. **Head-height drawing** (`05`). Red, white and green head marks overlap at the point being explained. Keep the measured head marker and the zone outline prominent; draw the address reference thinner/dimmer so the three don't stack into one blob.
8. **Session review lead** (`03-session-review`). Lead the summary card with the headline count in large type ("7 of 11 judged swings in zone"), then the per-swing marks smaller beneath it; the recurring theme's badge must say what its number is ("5 steps out, typical" or similar) so it doesn't read as a count.
9. **Folded finding off its frame** (`10-player-address-P1`). With Address selected the card still leads "At impact: … 4". Label it as the swing's top finding and where it is ("Top finding · at impact") so it doesn't read as a verdict on the current frame.
10. **One severity wording** (`12-auto-compare`). Tile captions say "level 2" while the player says "2 steps out". Use "2 steps out" (and "In zone", "Not judged") everywhere a level is spelled out.
11. **Co-occurrence, not causation** (`04-session-review-scrolled`). The downward arrows between findings imply one causes the next while the text says "Both on 4 swings". Use a neutral connector (no arrowhead) and label each link "Seen together on N swings".

Declined this round: none.
## Done means

- Builds for the Simulator with no new warnings: `xcodebuild build -project SwingCoach.xcodeproj -scheme SwingCoach -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- Tests pass: `scripts/verify.sh unit coaching library review capture` (run in the background and wait; only one Simulator at a time). If you change text a UI test asserts, update the test deliberately and say which; never weaken an assertion otherwise. If you touch thumbnails or anything Trim/storage reads, add `trim storage`.
- Update `docs/FRONTEND.md` / `docs/COACHING.md` where they describe something you changed.
- Commit on `ui-council` with a message listing the changes, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

Reply with: the commit hash, one line per numbered fix (done / partly / not done, and why), the test verdict line, and any test you changed.
