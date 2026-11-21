# Round 10 implementation brief

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
- Current screenshots: `/Users/ruari/Documents/Startups/ui-council-media/shots/r09/` (`<NN-screen>-light.png` / `-dark.png`). Look before and after.
- Leave uncommitted files under `ui-council/` alone; they are the council's.
- **Originality:** SwingCoach's UI stays its own. Never make a screen resemble the reference apps (Sportsbox 3D Golf, Onform); if a fix would, skip it and say so.

## Fixes for this round, most important first

1. **Auto's state inside the toggle, no banner** (`14-auto-camera`). An 8 pt colour-only dot is easy to miss. While Auto is armed, fill the selected "Auto" segment with the accent (dark text on lime); make the dot ~12 pt with a shape per state (filled = listening, hollow ring = paused, warning glyph = problem). Nothing new over the viewfinder.
2. **Simplify the bottom stack off the walkthrough** (`10-player-address-P1`). Five layers fill the bottom third and the time shows twice. Remove the floating status pill; show the position name (and the low-confidence glyph when it applies, in neutral secondary colour, not lime) in the transport row's left slot where "7.8 s" sits; drop the total duration. One 8 pt spacing token between the remaining bands.
3. **One name per finding on screen** (`05`). The on-video tag ("Head height at impact"), the card's position and its title name the same thing three ways. Hide the on-video tag while the step card is showing (keep it for "Every check" mode and when the card is folded).
4. **Finding title for the head** (`05`). "Head didn't drop into impact" can read as an instruction. Use "Head stayed high at impact". Check other titles for the same instruction-like reading.
5. **Severity in a word** (`05`, `06`, recap). Beside the badge on the finding card and the recap, add one short plain word for beginners: "A little out" (1–2), "Well out" (3–4), "Far out" (5+) — follow the coaching levels in `docs/COACHING.md`; the P strip keeps the bare badge. Keep "N steps out" in All checks.
6. **One legend component** (`07`, `12`, session review). "Address" is a dashed ring in one place and a grey dot in another; "This swing" a ring in one and dashes in another. Make one shared legend with fixed glyphs (you / good zone / address) and use it everywhere a legend appears.
7. **Recap picture** (`11-auto-recap`). The thumbnail's red line sits beside an amber "typical 3" badge, and at ~64 pt wide it's too small to read from the tripod. Let the picture fill the card's height, and put that swing's own badge on the picture's corner so the line's colour matches a badge.
8. **Head drawing** (`05`). The zone is hidden behind the rings. Draw the zone wider than the head ring so it shows on both sides; address ring ~50% opacity, 1.5 pt.
9. **Lighter shaft zone** (`06`). The green wedge tints the leg and mat; reduce its fill and edge weight, keeping the dark stroke on the measured shaft.
10. **All checks top** (`07`). Merge the two legend rows and the step definition into one caption line ("Number = steps out of the good zone"), so the first check is in view.
11. **Comparison header** (`12-auto-compare`). Title and "On all 4 judged swings" only; drop the instruction sentence; legend and camera note on one caption line.
12. **Session summary** (`03`). Cut the "Good = …" line and the Measured row; show "1 not judged · short swing" as one caption under the marks. Put "Shows it most" / "Your best here" above their pictures (`04`).
13. **Library select** (`01-library`). Two select controls with near-identical words. Make the toolbar's select an icon (checkmark.circle, accessibility label "Select swings") beside the gear and +; keep the session header's "Select".
14. **Hit areas** (`05`, `11`). "All checks" capsule (~26 pt) and the recap close button (~28 pt) are small; give the shared capsule and close-button styles a 44 pt minimum hit area (visual size can stay).
15. **Player Done/Back** (`05`, `13`). A rounded rectangle beside a circular star: make it a capsule at the star's height using the shared button style.
16. **Rail labels** (`06`). "Positions" touches the rail edges; 11 pt labels with 6 pt side padding (widen the rail slightly), and an outline-weight glyph for Positions to match the others.
17. **Swing Info bottom** (`09`). The last row is still cut by the sheet's corner: add a bottom inset of at least the corner radius and use the same inset card style as the other sheets.
18. **P strip badges** (`05`, `10`). Badges still perch on cell edges; inset each fully inside its own cell, ~18 pt with 12 pt digits.
19. **Layers toggle wording** (`08`). "Every check on the frame" → "All checks at this position", helper "Includes checks in zone when paused."

Declined this round: moving Delete into a menu (Opus; it's already last, after a divider, in red); renaming tools "My lines"/"Coach lines" (Opus; 'Draw' and 'Layers' were settled last round); shifting the in-zone green away from the lime accent (Opus; the hues differ and the status set is fixed); a scrolling P strip (Sol; left for Ruari); "Session swing N of 12" (Sol, third time; consistency with the Library player).
## Done means

- Builds for the Simulator with no new warnings: `xcodebuild build -project SwingCoach.xcodeproj -scheme SwingCoach -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- Tests pass: `scripts/verify.sh unit coaching library review capture` (run in the background and wait; only one Simulator at a time). If you change text a UI test asserts, update the test deliberately and say which; never weaken an assertion otherwise. If you touch thumbnails or anything Trim/storage reads, add `trim storage`.
- Update `docs/FRONTEND.md` / `docs/COACHING.md` where they describe something you changed.
- Commit on `ui-council` with a message listing the changes, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

Reply with: the commit hash, one line per numbered fix (done / partly / not done, and why), the test verdict line, and any test you changed.
