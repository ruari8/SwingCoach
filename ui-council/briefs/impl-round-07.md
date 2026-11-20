# Round 7 implementation brief

You are implementing one round of UI fixes for SwingCoach, an iPhone golf coaching app (SwiftUI, iOS 26). Work only in the worktree `/Users/ruari/Documents/Startups/SwingCoach-wt/ui-council` (branch `ui-council`). Do not push, do not touch `main`, do not merge. Read `AGENTS.md`, then `docs/FRONTEND.md` (its "Look" section describes the shared tokens and components in `SwingCoach/Theme.swift`).

## Ground rules

- Visual and interaction polish only. **No feature changes**: nothing added or removed that a user can do.
- Prefer shared tokens and shared components over per-screen tweaks or layout rewrites. Extend `Theme.swift` rather than adding one-off values.
- Keep meaningful colour: the red / amber / green level colours carry coaching meaning; the lime `Color.appAccent` is the brand accent. Never make the UI grey or sterile. Never let colour be the only signal.
- The player and Capture are dark by design; Library, Settings and Library sheets follow the system appearance.
- Current screenshots: `/Users/ruari/Documents/Startups/ui-council-media/shots/r06/` (`<NN-screen>-light.png` / `-dark.png`). Look before and after.
- Leave uncommitted files under `ui-council/` alone; they are the council's.
- **Originality:** SwingCoach's UI stays its own. Never make a screen resemble the reference apps (Sportsbox 3D Golf, Onform); if a fix would, skip it and say so.

## Fixes for this round, most important first

This round's list comes from three council members (Sol, Opus, Fable) and is longer than usual. Items 1–15 are required; do 16–23 as well if they fit, and report any you skip.

1. **Head drawing, agreed by all three** (`05-player-open`). Address ring, this swing's ring and the green zone still stack on the head, and the legend shows Address as a line though it's drawn as a ring. Draw the address mark as one thin dashed light ring with the dark halo the shaft line uses, this swing as one solid ring, and make every legend swatch match the shape actually drawn (line, ring, dot, band). Shared drawing + legend code.
2. **One wording for "steps out" and the camera caveat** (`03`, `07`, `11`). The key reads "4 = steps out", "Number = steps out" and "A number is steps out…"; the caveat reads three ways too. Make one shared string for each (in one place in code) and use it everywhere, with one key dot size.
3. **Which number is a swing's dot** (`03`/`04-session-review`). Swing 8's dot says 4 while its theme caption says 6 steps out and the theme badge says 5 typical. Say what each number is: the key says the dot is that swing's worst check; the theme captions name their check. Don't change the numbers, only make their meaning explicit.
4. **Folded finding bar** (`10-player-address-P1`). Text touches the capsule edges and the title wraps beside a wide "Findings" control. 10 pt vertical padding; title one line (min scale ~0.85, then truncate); the right control a chevron only, with "Findings" kept as its accessibility label.
5. **Step card rhythm** (`05`, `06`). Row gaps are 13/7/11/4 pt and the legend sits 4 pt above the buttons. One even row gap (8–10 pt) throughout; legend in caption style inline with the steps-out pill where it fits; don't grow the card's height overall.
6. **Sheet top inset** (`07`, `08`, `03`). 44–150 pt of empty band under every sheet title. Reduce the shared sheet content top inset to 12–16 pt.
7. **Low badge colour** (`09-swing-info`). Cyan is a colour used nowhere else. Restyle "Low" in the neutral grey used for "not judged"; the low-confidence row uses regular weight, not bold.
8. **Light-mode amber text** (`04-session-review-scrolled-light`). "3 steps out, typical" is dark yellow on pale yellow (~2.5:1). In light mode use a dark amber ink token (≥ 4.5:1) for pill text; keep amber for the disc and stroke.
9. **Recap card, shorter and one family** (`11-auto-recap`). It covers the middle of the viewfinder. Keep the finding, its severity pill, the short camera caveat and "Compare them"; move the per-swing markers and the count line into the comparison (which already shows each swing). Give the recap card and the Auto status panel the same surface, radius and padding tokens.
10. **Recap caption** (`11`). "Swing 5 ·" dangles before "4 steps out". Two deliberate lines, no separator, labelled "Shows it most" like the session review; "On all 4 judged swings" where swing 1 wasn't judged.
11. **Library session header** (`01-library`). The meta wraps with a dangling dot; the two pills differ in height. Meta on its own full-width line under the title row; both pills one shared height; rename "Select session" to say its scope ("Select all 12").
12. **Zone edges on green** (`06`). Zone fill on green turf depends on a thin stroke: give zone strokes the same dark halo as the swing line and +0.5–1 pt weight.
13. **Lock and time** (`10`). The padlock is the only uncaptioned control: caption it ("Lock") in the rail caption style; show time as "7.8 s" (no leading zero).
14. **Not judged says why** (`12-auto-compare`, recap, session dots). "Not judged" repeats three times without a reason. Show the reason in the caption ("Not judged · short swing", "· camera moved", "· no reading") when known.
15. **Headline numerals** (`03`, `07`). "11" in display numerals reads as "1 1" because of monospaced digits. Use proportional digits for headline numerals; tabular only in columns and rows.
16. **"Your best here" drawing** (`04-session-review-scrolled-dark`). The in-zone clubhead marker sits outside the green rectangle, so it reads as a miss. Check how that check's zone is drawn; draw it as a band along the axis the check measures so an in-zone reading visibly sits inside it. Fix the drawing, not the measurement.
17. **P strip readability (non-layout)** (`05`). Raise P labels to 12 pt and replace the "?" suffix for low confidence with a dimmed glyph and dashed chip outline; show "Address · low confidence" by the time whenever a low-confidence position is selected, not only while scrubbing.
18. **Delete in the Auto review rail** (`13-auto-review`). Delete sits mid-rail styled like harmless tools; move it to the end after a divider and tint it red; keep the other tools in the same order as the Library player.
19. **Coach menu item** (`15-auto-coach-menu`). "Recap the last swings" wraps and is indented differently: "Recap last 5" (using the current window), aligned with the options above.
20. **Empty saved-count box** (`14-auto-camera`). When there is no thumbnail, the dark rounded square looks like a failed image. Show a neutral glyph in it (or the last swing's frame when available).
21. **Session summary card tighter** (`03`). Tighter vertical padding and marker spacing so the "Start here" theme starts higher.
22. **Camera caveat contrast** (`06`). The caveat is small grey beside a saturated badge: use the shared secondary style at higher contrast, own line when tight.
23. **All checks denominator** (`07`). "11 of 16 checks in zone" doesn't say which 16; say what counts (judged checks), and keep the guide label beside its value.

Declined this round: a horizontally scrolling P strip with 44 pt-wide cells (Sol, fifth time). Left for Ruari; item 17 improves the strip without changing its layout.
## Done means

- Builds for the Simulator with no new warnings: `xcodebuild build -project SwingCoach.xcodeproj -scheme SwingCoach -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- Tests pass: `scripts/verify.sh unit coaching library review capture` (run in the background and wait; only one Simulator at a time). If you change text a UI test asserts, update the test deliberately and say which; never weaken an assertion otherwise. If you touch thumbnails or anything Trim/storage reads, add `trim storage`.
- Update `docs/FRONTEND.md` / `docs/COACHING.md` where they describe something you changed.
- Commit on `ui-council` with a message listing the changes, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

Reply with: the commit hash, one line per numbered fix (done / partly / not done, and why), the test verdict line, and any test you changed.
