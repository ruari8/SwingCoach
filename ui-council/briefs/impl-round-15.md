# Round 15 implementation brief

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
- Current screenshots: `/Users/ruari/Documents/Startups/ui-council-media/shots/r14/` (`<NN-screen>-light.png` / `-dark.png`). Look before and after.
- Leave uncommitted files under `ui-council/` alone; they are the council's.
- **Originality:** SwingCoach's UI stays its own. Never make a screen resemble the reference apps (Sportsbox 3D Golf, Onform); if a fix would, skip it and say so.

## Fixes for this round, most important first

The council has stalled on two metrics: consistency (the level shown three ways) and accessibility. This round goes after both.

1. **One verdict badge, glyphs not numbers** (`05`, `06`, `10`, `12`, `13`, recap, session review). The player, P strip and comparison show numbered badges (1–4) while the session review uses tick / "!" / "!!". A bare number reads as a count. Use the shared glyph badge (tick in zone, amber "!", red "!!", dash not judged) everywhere a verdict badge appears. "N steps out" remains only as text in All checks rows. Make the step card's severity word one step larger and semibold, since it now carries the meaning beside the glyph.
2. **One name for the range** (`03`, `04`, `07`). The same range is "good zone", "in zone", "green band" and "reference range". Use "Good zone" everywhere a range is named (guides keep "Reference only"); on the Swing by swing chart say "Good: +4% to +26%" and label the better side in words.
3. **Session pictures cropped to the golfer** (`03`, `04`). The tall frames are mostly sky and turf; crop both pictures to the same golfer-centred 4:5 region (body, club, ball) so the drawing is larger and the second theme rises.
4. **Zone strokes on turf** (`06`). Zone strokes ~3 pt with the same dark halo as the shaft line, with a 15–20% fill, in the shared drawing style.
5. **Recap setting off the viewfinder centre** (`14`, `11`, `15`). The "Recap: every 5 swings" chip takes its own centred row over the viewfinder. Move it into the top row beside "240 fps" as a compact pill ("Recap: 5"), same pill style; nothing centred over the frame.
6. **Transport label and lock** (`10`). "Address / Low / confidence" wraps to three ragged lines; keep two lines max (position, then glyph + "Low confidence") in a tighter caption style. Label the lock by its action ("Lock" / "Unlock"), since it keeps the controls on screen.
7. **Video doesn't jump** (`10` vs `05`). The video sits ~16 pt lower off the walkthrough than on it; anchor it to the same top inset in both states (the stop lift may still raise it).
8. **All checks summary** (`07`). Drop the "Top finding" lines (they repeat the card behind) and put the key on one caption line, so two check rows show at the first detent.
9. **Session review copy** (`03`). Headline "7 of 11 swings good" (the caption already says why one wasn't judged); remove the unlabelled camera glyph from theme rows (keep it with words in All checks); write theme counts as "N of M measured".
10. **Light caption contrast** (`03-light`). Light-mode secondary caption grey is ~3.5:1; darken the shared light caption colour to reach 4.5:1.
11. **Library header** (`01`). Drop the duplicated count from the session row (the header line already has it).
12. **Next as the accent primary** (`05`). The solid white Next slab out-shouts the finding. Give Next the accent fill with a dark label, like Review and Auto ready; Play swing stays grey.
13. **Spelling and case** (`08`, `02`). "Clubhead" everywhere; sentence case for every section header.

Declined this round: removing the toolbar select icon (Opus, Fable): library-wide selection is a feature. A compact end-of-list row for the not-judged comparison tile (Opus): round 14 restored one tile size at Sol's request so the grid reads in swing order.
## Done means

- Builds for the Simulator with no new warnings: `xcodebuild build -project SwingCoach.xcodeproj -scheme SwingCoach -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- Tests pass: `scripts/verify.sh unit coaching library review capture` (run in the background and wait; only one Simulator at a time). If you change text a UI test asserts, update the test deliberately and say which; never weaken an assertion otherwise. If you touch thumbnails or anything Trim/storage reads, add `trim storage`.
- Update `docs/FRONTEND.md` / `docs/COACHING.md` where they describe something you changed.
- Commit on `ui-council` with a message listing the changes, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

Reply with: the commit hash, one line per numbered fix (done / partly / not done, and why), the test verdict line, and any test you changed.
