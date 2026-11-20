# Round 13 implementation brief

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
- Current screenshots: `/Users/ruari/Documents/Startups/ui-council-media/shots/r12/` (`<NN-screen>-light.png` / `-dark.png`). Look before and after.
- Leave uncommitted files under `ui-council/` alone; they are the council's.
- **Originality:** SwingCoach's UI stays its own. Never make a screen resemble the reference apps (Sportsbox 3D Golf, Onform); if a fix would, skip it and say so.

## Fixes for this round, most important first

The full council (Sol, Opus, Fable) agrees the biggest remaining problem is the severity system: words, colours and numbers disagree across screens. Fix that first.

1. **One severity system** (`05`, `06`, `13`, `11`, `03`, `07`). Tie the word to the colour, in one shared level style: amber (levels 1–3) always reads "A little out", red (4+) always "Well out", in-zone green "In zone"; the threshold lives in one place (`Color.coachingLevel`'s bands). Use only that word beside a badge everywhere a word appears. "N steps out" stays only in All checks rows.
2. **Session dots without numerals** (`03`). The dots (a swing's top finding) disagree with theme chips and captions. Show each swing as a coloured shape only: tick in zone, "!" out (amber or red), dash not judged; drop the numeral and the key line. Theme chips read the word tier ("Typically well out"); captions under pictures keep just "Swing 8".
3. **Recap: no contradiction** (`11`). The picture's red line and the amber "typically" badge disagree on one card. On the recap show the finding title and the picture only (the picture's own colour carries that swing's level); drop the level word and badge from the recap. Levels stay in Compare.
4. **Head drawing on a stop** (`05`). Hide the dashed address ring while paused on a walkthrough stop (keep it with "Show all drawings here"); draw the zone as an outlined band (~30% fill) above the ring in z-order so the gap reads.
5. **Bottom stack on a stop** (`05`, `06`, `13`). Hide the scrubber's tick-dot row while the step card shows. Where there is an unused black band above the video, let the stop lift use it so the feet and ball clear the card's top.
6. **Auto glyph inside the toggle** (`14`). Move the state mark inside the Auto segment at cap height: filled when armed, ring when paused, warning glyph on a problem. Remove the separate dot beside the toggle. No added footprint over the viewfinder.
7. **Theme meta, one line** (`03`, `04`). One caption per theme: "4 of 8 swings · takeaway", with the camera icon alone as a trailing mark for camera-dependent checks (its sentence moves to All checks).
8. **All checks rows** (`07`). Legend once in the header; each row leads with the word ("Above zone"); numbers in caption style with what the percentage is of (e.g. "% of body height" — use the metric definition's unit); row thumbnails 64 pt.
9. **Library header** (`01`). Demote the stats row to one caption line; spell out "Down the line" (and in Swing Info); hide a zero count. Use the impact (P7) frame as the thumbnail poster when positions exist, so tiles differ at a glance.
10. **Sheets** (`07`, `08`, `09` light). Dim the video behind player sheets the same in light and dark; size the Layers sheet to its content.
11. **Small text floor** (`10`). "Low confidence" is ~9 pt: set an 11 pt minimum in the shared ramp and use the 12 pt caption style there.
12. **Rail** (`10`). 16 pt trailing margin matching the Tools button; 8 pt padding around the longest label. Give Speed an SF Symbol with "1x" as its label.
13. **Copy trims** (`02`, `15`, `08`). Settings footers to one line each. Coach menu action "Show recap now" with a leading symbol so it reads as an action. In the Layers sheet use "drawings" consistently in row titles ("Coach's drawings").
14. **Compare: not-judged tile** (`12`). Keep swing order, but render a not-judged swing as a half-height tile.
15. **Lock label** (`10`). Name what it locks (check what the review lock does and label it, e.g. "Lock swing").

Declined this round: a dimmer Next button (Fable): it's the primary action from the tripod and should stay the brightest control. Removing the toolbar select icon (Fable): it's library-wide selection, a feature. "Session swing N of 12", a "Watching" word, a scrolling P strip and rewording the coaching rule footer (Sol): unchanged decisions.
## Done means

- Builds for the Simulator with no new warnings: `xcodebuild build -project SwingCoach.xcodeproj -scheme SwingCoach -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- Tests pass: `scripts/verify.sh unit coaching library review capture` (run in the background and wait; only one Simulator at a time). If you change text a UI test asserts, update the test deliberately and say which; never weaken an assertion otherwise. If you touch thumbnails or anything Trim/storage reads, add `trim storage`.
- Update `docs/FRONTEND.md` / `docs/COACHING.md` where they describe something you changed.
- Commit on `ui-council` with a message listing the changes, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

Reply with: the commit hash, one line per numbered fix (done / partly / not done, and why), the test verdict line, and any test you changed.
