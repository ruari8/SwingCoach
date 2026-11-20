# Round 5 implementation brief

You are implementing one round of UI fixes for SwingCoach, an iPhone golf coaching app (SwiftUI, iOS 26). Work only in the worktree `/Users/ruari/Documents/Startups/SwingCoach-wt/ui-council` (branch `ui-council`). Do not push, do not touch `main`, do not merge. Read `AGENTS.md`, then `docs/FRONTEND.md` (its "Look" section describes the shared tokens and components in `SwingCoach/Theme.swift`).

## Ground rules

- Visual and interaction polish only. **No feature changes**: nothing added or removed that a user can do.
- Prefer shared tokens and shared components over per-screen tweaks or layout rewrites. Extend `Theme.swift` rather than adding one-off values.
- Keep meaningful colour: the red / amber / green level colours carry coaching meaning; the lime `Color.appAccent` is the brand accent. Never make the UI grey or sterile. Never let colour be the only signal.
- The player and Capture are dark by design; Library, Settings and Library sheets follow the system appearance.
- Current screenshots: `/Users/ruari/Documents/Startups/ui-council-media/shots/r04/` (`<NN-screen>-light.png` / `-dark.png`). Look before and after.
- Leave uncommitted files under `ui-council/` alone; they are the council's.
- **Originality:** SwingCoach's UI stays its own. Never make a screen resemble the reference apps (Sportsbox 3D Golf, Onform); if a fix would, skip it and say so.

## Fixes for this round, most important first

1. **Type ramp audit** (all screens). Typography slipped. Audit every `.font(...)` in the app UI: each screen should use at most four sizes from one shared ramp in `Theme.swift` (for example largeTitle-ish headline, title, body, caption), with semibold/bold used for one role each and tabular numbers wherever numbers sit in rows or badges. Replace ad hoc `.system(size:)` with ramp tokens except where a fixed size is genuinely needed (badges, the rail), and keep Dynamic Type working. Document the ramp in `docs/FRONTEND.md`'s "Look" section.
2. **Head-height drawing** (`05-player-open`). A thick red dashed ring, the grey address ring and the green zone stack on the head, and the red ring outshouts the red dot that marks the reading. Make the measured dot the strongest mark; draw the ring (if kept) as a thin outline.
3. **Auto: how to stop** (`14-auto-camera`). The armed capsule reads well but there is no visible cue for stopping Auto. If tapping the capsule (or another existing control) already stops Auto, show that with a stop glyph and "Tap to stop" inside the capsule. Do not add a new way to stop Auto; only make the existing one visible.
4. **Card clearance** (`13-auto-review`). The expanded finding card still starts against the golfer's shoes. Shorten it once more: the camera-dependence caveat for club readings can sit on one short line ("Depends on camera position") with the detail in All checks; keep 44 pt buttons.
5. **What "good" means** (`03-session-review`). "7 of 11 judged swings good" while a finding shows on all 11 with a halfway-back reading: add a one-line qualifier under the headline saying what counts as a good swing (as the coaching rules define it in `docs/COACHING.md`).
6. **All checks leads with the whole swing** (`07-all-checks`). The sheet's summary card leads with the impact finding. Lead with "11 of 16 checks in zone", then the finding labelled "Top finding".
7. **Steps out of what** (`05`, `06`). On the expanded card say "4 steps outside the good zone" (the P strip keeps the bare badge).
8. **Recap badge and example** (`11-auto-recap`). Label the headline badge "typical" and caption the example thumbnail "Swing 5 · 4 steps out".
9. **Folded card space** (`10-player-address-P1`). "Show findings" takes half the row; shorten it to "Findings" with the chevron so the title gets the width.
10. **Session photo captions** (`04-session-review-scrolled`). Captions mix steps with signed percentages whose reference is unstated; keep the swing number and zone result, drop the percentages there (they stay in All checks).
11. **"Select session" as an action** (`01-library`). It reads as grey metadata; style it as a secondary (bordered or tinted) button while "Review" stays primary.
12. **Swing Info confidence column** (`09-swing-info`). The percentages are smaller and dimmer than the times; use the same numeric style as Time and keep the "Low" tag as the emphasis.

Declined this round: a horizontally scrolling P strip with 44 pt-wide cells (Sol, third time). Left for Ruari to decide; do not change the strip's layout.
## Done means

- Builds for the Simulator with no new warnings: `xcodebuild build -project SwingCoach.xcodeproj -scheme SwingCoach -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- Tests pass: `scripts/verify.sh unit coaching library review capture` (run in the background and wait; only one Simulator at a time). If you change text a UI test asserts, update the test deliberately and say which; never weaken an assertion otherwise. If you touch thumbnails or anything Trim/storage reads, add `trim storage`.
- Update `docs/FRONTEND.md` / `docs/COACHING.md` where they describe something you changed.
- Commit on `ui-council` with a message listing the changes, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

Reply with: the commit hash, one line per numbered fix (done / partly / not done, and why), the test verdict line, and any test you changed.
