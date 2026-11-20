# Round 4 implementation brief

You are implementing one round of UI fixes for SwingCoach, an iPhone golf coaching app (SwiftUI, iOS 26). Work only in the worktree `/Users/ruari/Documents/Startups/SwingCoach-wt/ui-council` (branch `ui-council`). Do not push, do not touch `main`, do not merge. Read `AGENTS.md`, then `docs/FRONTEND.md` (its "Look" section describes the shared tokens and components in `SwingCoach/Theme.swift`).

## Ground rules

- Visual and interaction polish only. **No feature changes**: nothing added or removed that a user can do.
- Prefer shared tokens and shared components over per-screen tweaks or layout rewrites. Extend `Theme.swift` rather than adding one-off values.
- Keep meaningful colour: the red / amber / green level colours carry coaching meaning; the lime `Color.appAccent` is the brand accent. Never make the UI grey or sterile. Never let colour be the only signal.
- The player and Capture are dark by design; Library, Settings and Library sheets follow the system appearance.
- Current screenshots: `/Users/ruari/Documents/Startups/ui-council-media/shots/r03/` (`<NN-screen>-light.png` / `-dark.png`). Look before and after.
- Leave uncommitted files under `ui-council/` alone; they are the council's.

## Fixes for this round, most important first

1. **Only the finding's own drawing on a walkthrough stop** (`05-player-open`). The torso wedge and other supporting strokes still compete with the head rings, sending the eye to two body areas. On a walkthrough stop draw only the step's finding; supporting drawings appear only with "Every check on the frame".
2. **Finding titles read as observations** (`05`). "Head stays up through impact" can read as an instruction to keep the head up, so the red badge must carry the meaning. Review every finding title in the coaching words (`CoachingWords` / metric definitions) and make each read as what the swing did, plainly ("Head rose at impact" or similar), never like a cue. Keep them short. Update `docs/COACHING.md` and any test that asserts a title.
3. **Auto armed state, again** (`14-auto-camera`). Still little visual weight from a tripod. Make it unmistakable: "Auto is on" at title size (28 pt bold), a 24 pt indicator, on a solid high-contrast capsule; it may grow to the full width above the bottom controls. The saved-count control stays secondary.
4. **Step card clearance** (`13-auto-review`, halfway back). The card's top still meets the front shoe. Tighten its vertical gaps and padding again so its top edge sits lower; keep button heights at 44 pt.
5. **Comparison previews** (`12-auto-compare`). The tall previews spend space on sky and foreground; only two swings' labels show on the first view, one of them the unjudged tile. Cap the shared preview height and crop toward the golfer and club so more swings fit.
6. **One word for progress** (`05`, `06`). "Step 2 of 4" and "3 steps out" overload "step". Use "Finding 2 of 4" for walkthrough progress; keep "N steps out" for severity.
7. **Section headings in light** (`03-session-review-light`). "What kept happening" is pale grey; define one shared section-heading colour that reads clearly (≥ 4.5:1) in light and dark and use it for every section heading.
8. **Recap frequency line** (`11-auto-recap`). "4 of 4 swings with a halfway back reading" leaves the reader to infer what happened. Say it: "On all 4 swings with a halfway-back reading" under the finding title, or equivalent.
9. **"Start here" placement** (`03-session-review`). Put "Start here" above the finding title in the secondary label style, not amber after the camera note, so it doesn't look like a severity.
10. **Two "Select"s** (`01-library`). The session's Select reads the same as the toolbar's. Label it for what it selects ("Select session").
11. **Drawings vs Layers** (`08-drawings-tool`). The rail says "Layers" and opens a sheet titled "Drawings", next to "Draw". Title the sheet "Drawing layers" so it follows its control.

Declined this round: a horizontally scrolling P strip with 44 pt-wide cells (Sol, second time): ten positions in 402 pt can't each be 44 pt wide without hiding some, and seeing all ten at once is the strip's job; the cells are full-height 56 pt targets.
## Done means

- Builds for the Simulator with no new warnings: `xcodebuild build -project SwingCoach.xcodeproj -scheme SwingCoach -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- Tests pass: `scripts/verify.sh unit coaching library review capture` (run in the background and wait; only one Simulator at a time). If you change text a UI test asserts, update the test deliberately and say which; never weaken an assertion otherwise. If you touch thumbnails or anything Trim/storage reads, add `trim storage`.
- Update `docs/FRONTEND.md` / `docs/COACHING.md` where they describe something you changed.
- Commit on `ui-council` with a message listing the changes, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

Reply with: the commit hash, one line per numbered fix (done / partly / not done, and why), the test verdict line, and any test you changed.
