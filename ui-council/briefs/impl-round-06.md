# Round 6 implementation brief

You are implementing one round of UI fixes for SwingCoach, an iPhone golf coaching app (SwiftUI, iOS 26). Work only in the worktree `/Users/ruari/Documents/Startups/SwingCoach-wt/ui-council` (branch `ui-council`). Do not push, do not touch `main`, do not merge. Read `AGENTS.md`, then `docs/FRONTEND.md` (its "Look" section describes the shared tokens and components in `SwingCoach/Theme.swift`).

## Ground rules

- Visual and interaction polish only. **No feature changes**: nothing added or removed that a user can do.
- Prefer shared tokens and shared components over per-screen tweaks or layout rewrites. Extend `Theme.swift` rather than adding one-off values.
- Keep meaningful colour: the red / amber / green level colours carry coaching meaning; the lime `Color.appAccent` is the brand accent. Never make the UI grey or sterile. Never let colour be the only signal.
- The player and Capture are dark by design; Library, Settings and Library sheets follow the system appearance.
- Current screenshots: `/Users/ruari/Documents/Startups/ui-council-media/shots/r05/` (`<NN-screen>-light.png` / `-dark.png`). Look before and after.
- Leave uncommitted files under `ui-council/` alone; they are the council's.
- **Originality:** SwingCoach's UI stays its own. Never make a screen resemble the reference apps (Sportsbox 3D Golf, Onform); if a fix would, skip it and say so.

## Fixes for this round, most important first

1. **Head marker** (`05-player-open`). The solid red marker hides part of the golfer's head and the tag touches the hat. Use a smaller hollow centre marker with the dark outline, and place the tag in clear space above the head (sky), not touching it.
2. **Target edges** (`06-player-next-step`). The amber shaft line is crisp but the green wedge's thin edges fade into grass and mat. Give zone edges the same dark outline treatment as the measured line, at a lighter weight, keeping the translucent fill. Do it in the shared drawing code so every zone gets it.
3. **Auto status as a panel** (`14-auto-camera`). The outlined capsule looks like a button, and the stop hint is small. Make it a solid dark status panel (no button-like outline), prominent text, lime indicator, and the "Switch to Manual to stop" hint in readable contrast; if it isn't tappable, it must not look tappable.
4. **Recap card height** (`11-auto-recap`). The coloured bars repeat what the numbered badges already say. Remove the bars; keep the badges, swing labels and the one-line key.
5. **Zone track captions** (`07-all-checks`). "You" / "Good players" labels and values are small and detached from the marks. Make them larger and brighter (tabular), and put a tiny swatch of the dot and the band beside each label.
6. **Steps out, defined once** (`03-session-review`). Use one phrase for distance outside the zone everywhere ("N steps out"), add a one-line definition of a step where the key is ("1 step = one zone-width outside good players"), and say the theme count uses swings with a reading for that check. Follow `docs/COACHING.md` for what a level is; do not invent a new definition.
7. **Low-confidence position named** (`10-player-address-P1`). "P1?" signals doubt without naming it. Where the selected position shows its name, say "Address · Low confidence"; prefix the folded card "Swing's top finding · at impact".
8. **Rail toggle labelled** (`05`). The lone chevron above the rail is the only unlabelled control; caption it "Hide" / "Show" (tools) in the rail's caption style.
9. **Layers naming** (`08-drawings-tool`). Title the sheet "Layers" to match its control; name the first toggle "Coaching overlays". Keep "Draw" for adding marks.
10. **Toolbar Select** (`01-library`). Label the toolbar action "Select swings" (the session button stays "Select session").
11. **Settings help copy** (`02-settings`). The extra-footage paragraph is a dense six-line block. Split it: one short instruction line by the steppers, then a second short paragraph for export timing and early-stop behaviour. Same for any other help paragraph over three lines.

Declined this round: a horizontally scrolling P strip with 44 pt-wide cells (Sol, fourth time). Left for Ruari; do not change the strip's layout.
## Done means

- Builds for the Simulator with no new warnings: `xcodebuild build -project SwingCoach.xcodeproj -scheme SwingCoach -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- Tests pass: `scripts/verify.sh unit coaching library review capture` (run in the background and wait; only one Simulator at a time). If you change text a UI test asserts, update the test deliberately and say which; never weaken an assertion otherwise. If you touch thumbnails or anything Trim/storage reads, add `trim storage`.
- Update `docs/FRONTEND.md` / `docs/COACHING.md` where they describe something you changed.
- Commit on `ui-council` with a message listing the changes, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

Reply with: the commit hash, one line per numbered fix (done / partly / not done, and why), the test verdict line, and any test you changed.
