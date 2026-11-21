# Round 8 implementation brief

You are implementing one round of UI fixes for SwingCoach, an iPhone golf coaching app (SwiftUI, iOS 26). Work only in the worktree `/Users/ruari/Documents/Startups/SwingCoach-wt/ui-council` (branch `ui-council`). Do not push, do not touch `main`, do not merge. Read `AGENTS.md`, then `docs/FRONTEND.md` (its "Look" section describes the shared tokens and components in `SwingCoach/Theme.swift`).

## Ground rules

- Visual and interaction polish only. **No feature changes**: nothing added or removed that a user can do.
- Prefer shared tokens and shared components over per-screen tweaks or layout rewrites. Extend `Theme.swift` rather than adding one-off values.
- Keep meaningful colour: the red / amber / green level colours carry coaching meaning; the lime `Color.appAccent` is the brand accent. Never make the UI grey or sterile. Never let colour be the only signal.
- The player and Capture are dark by design; Library, Settings and Library sheets follow the system appearance.
- Current screenshots: `/Users/ruari/Documents/Startups/ui-council-media/shots/r07/` (`<NN-screen>-light.png` / `-dark.png`). Look before and after.
- Leave uncommitted files under `ui-council/` alone; they are the council's.
- **Originality:** SwingCoach's UI stays its own. Never make a screen resemble the reference apps (Sportsbox 3D Golf, Onform); if a fix would, skip it and say so.

## Fixes for this round, most important first

1. **Auto: how to stop, larger** (`14-auto-camera`). "Switch to Manual to stop" is small and points to a compact control across the screen. Set the hint as "Tap Manual to stop" in a larger semibold style, and make the Auto/Manual segmented control's targets at least 44 pt tall (shared Capture control token).
2. **Recap example shorter** (`11-auto-recap`). The example thumbnail and its three caption lines push the card into the viewfinder. Shorten the thumbnail and set "Shows it most · Swing 5" and the severity badge on one caption line; keep the full-width Compare button.
3. **Say what each number covers** (`03-session-review`). The dot key and the theme badge share a style but different scopes. Key: "Top finding per swing". Theme badge: "Typically 5 steps out" with the check named in its caption (as now).
4. **Head rings untangled** (`05-player-open`). Solid ring, dashed address ring and green box still meet over the face. Draw the green zone behind both rings, thin the address ring's stroke and halo further, so the direction of the miss reads at a glance.
5. **Comparison caption** (`12-auto-compare`). "Tap one to walk through it" sits over a grid whose first tile is not judged. Say "Tap a judged swing to walk through it"; the unjudged tile keeps "Not judged · Short swing" inside it and its footer just "Swing 1" (no repeat).
6. **Low-confidence glyph** (`10-player-address-P1`). The dashed chip's meaning shows only in the transient time label. Add a small shared low-confidence glyph on dashed chips and the same glyph beside "Low confidence" in the label and in Swing Info's "Low" tag.
7. **Guide rows aren't zones** (`07-all-checks`). A guide's marker inside a band labelled "Good players" reads as in zone. For guide rows label the band "Reference range" and draw it dashed and neutral.
8. **Settings footer lead** (`02-settings`). The extra-footage footer still packs range, step, timing, modes and early stop into two paragraphs. Lead with one line: "Adds 0–30 s to new clips, in half-second steps." Then two short sentences for export timing and Auto's early stop.

Declined this round: a horizontally scrolling P strip with 44 pt-wide cells (Sol, sixth time): left for Ruari. "Session swing 2 of 12" for the Auto review counter (Sol, second time): the counter reads the same as the Library player's; renaming one would break consistency, and renaming both lengthens every player header.
## Done means

- Builds for the Simulator with no new warnings: `xcodebuild build -project SwingCoach.xcodeproj -scheme SwingCoach -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- Tests pass: `scripts/verify.sh unit coaching library review capture` (run in the background and wait; only one Simulator at a time). If you change text a UI test asserts, update the test deliberately and say which; never weaken an assertion otherwise. If you touch thumbnails or anything Trim/storage reads, add `trim storage`.
- Update `docs/FRONTEND.md` / `docs/COACHING.md` where they describe something you changed.
- Commit on `ui-council` with a message listing the changes, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

Reply with: the commit hash, one line per numbered fix (done / partly / not done, and why), the test verdict line, and any test you changed.
