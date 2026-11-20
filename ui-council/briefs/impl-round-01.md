# Round 1 implementation brief

You are implementing one round of UI fixes for SwingCoach, an iPhone golf coaching app (SwiftUI, iOS 26). Work only in the worktree `/Users/ruari/Documents/Startups/SwingCoach-wt/ui-council` (branch `ui-council`). Do not push, do not touch `main`, do not merge. Read `AGENTS.md` first.

## Ground rules

- Visual and interaction polish only. **No feature changes**: nothing added or removed that a user can do.
- Prefer shared tokens and shared components (type scale, weights, radius, spacing, colour, icon size, labels) over per-screen tweaks or layout rewrites. Where the same thing is styled in several files, make one definition and use it everywhere.
- Keep meaningful colour: the red / amber / green level colours (`Color.coachingLevel`) carry coaching meaning; never make the UI grey or sterile.
- The player and Capture screens are dark by design. The Library, Settings and Library sheets follow the system appearance.
- Screenshots of the current build are in `/Users/ruari/Documents/Startups/ui-council-media/shots/r00/` (`<NN-screen>-light.png` / `-dark.png`). Look at the screens you change before and after.
- One uncommitted change is already in the worktree: `SwingCoachingOverlay.tagCentres` in `SwingCoach/CoachingPlayerViews.swift` stacks drawing name tags so they no longer print over each other. Keep it.

## Fixes for this round, most important first

1. **Top row clipped** (`05-player-open`, `10-player-address-P1`). On a walkthrough stop the video lifts (`stopLift` in `LibraryView.swift`) and a black band at the top cuts off the Done button and the star of `ReviewTopBar` (`SwingReviewPager.swift`). The top row must sit fully visible at the same y in every player state (Library player and Auto review). Pin it to the safe area, not the video frame.
2. **Step card covers the feet, club head and ball** at impact (`05-player-open`). Make the card (`SwingCoachingPanel`, `CoachingLegend` in `CoachingPlayerViews.swift`) more compact: tighter vertical padding and row gaps, legend on fewer lines, buttons at 44 pt minimum. Then check `stopLift` lifts the frame enough that the ball and club head clear the card's top on the impact step; it is capped by `room` (the space under the top row), so lift as far as the top row allows.
3. **One accent colour.** The Library and tab bar use system blue, the player uses lime (`Color.swingPositionAccent`, also `colour` at `CoachingPlayerViews.swift:299`), Settings toggles use system green. Define one adaptive accent token: the existing lime on dark surfaces, and a darker ink of the same lime hue on light surfaces that passes WCAG AA (4.5:1) on white for text. Apply it as the app's tint (tab selection, Select, Done, toggles, links) and use it in the player and Capture. The red / amber / green level colours stay status-only.
4. **Player sheets** (`07-all-checks`, `08-drawings-tool`, `09-swing-info`). They are translucent, so the step card, Next button and P strip ghost through and lower text contrast, and Swing Info turns light grey glass in light mode while the others stay dark. Give every sheet over the player one shared style: dark scheme, an opaque (or near-opaque, 90%+) dark background, a Done button, and a bottom content inset so the last row is never clipped by the corner. Swing Info: rename the "Metadata" header to "Details", and label the positions table's columns ("Time", "Confidence").
5. **Same words everywhere.** The "All checks" button opens a sheet titled "Every check": title it "All checks". The comparison says "Not measured" on a tile and "not judged" in its caption: one phrase per state. Use the same position names everywhere: plain name with the P number in brackets ("Halfway back (P3)"), not "P3 lead arm parallel" in one place and "Halfway back (P3)" in another. Settings sheet title: "Settings", not "Experiments".
6. **Capture: Auto state from the tripod** (`14-auto-camera`, `11-auto-recap`). "Auto is on" is a 6 pt red dot and body text bottom-left, unreadable from 2–3 m, and red reads as "recording". Make the armed state a larger, high-contrast status: a bigger label (title3 or larger, semibold) with a larger indicator on a dark backing capsule, using a non-recording colour for armed (accent), keeping red for actual recording. Keep "N saved" secondary.
7. **Recap legend must match the bars** (`11-auto-recap`, `AutoCoachingViews.swift`). Bars 2–4 are solid amber, the legend's amber key is an outline labelled "Other way", and red is "Shows it". Each legend swatch must look exactly like the bar it explains; keep "this swing"'s colour the same on the card, its thumbnail and the comparison.
8. **Session review dots** (`03-session-review`, `SwingCoachingViews.swift`). Status is hue alone and the dots are about 14 pt. Put a shape in each (tick in zone, the level number out of zone, dash not judged — reuse `CoachingLevelBadge`), each in a 44 pt hit area, wrapping in order. Shorten "Not judged (chips, moved camera, unclear)" to "Not judged" so its value stays on the row; move the reasons into the footnote. Make "Start here" a darker, readable amber/ink. Caveat text 13 pt secondary, not tiny low-contrast grey.
9. **One level badge.** The player uses a filled circle (`CoachingLevelBadge`); the session review uses a tinted rounded square (`LevelMeter`) and the same square holds the P2/P3 tags. Use `CoachingLevelBadge` for levels everywhere and give P-position tags a distinct, neutral capsule.
10. **Library** (`01-library`). In dark mode the swing cards lose their surface, so captions float on black: give cards a secondary-background fill in both modes with the same radius. The session review entry is a bare golfer glyph next to Select: make it a labelled "Review" button (same action). Keep the section's Select but style it as a secondary text button so the screen does not have two equal "Select"s.
11. **Folded finding off the walkthrough** (`10-player-address-P1`): prefix it with where it is ("At impact: Head stays up through impact") and keep the selected-position ring only on the current P chip in the strip.
12. **Session review nav bar on scroll** (`04-session-review-scrolled`): "Session coaching" and Done sit straight on top of the scrolled photos. Give the bar a scroll-edge background so it never overlaps content.
13. **Rail**: the lime-filled button on the rail reads as permanently on. Keep a filled accent only for a tool that is actually active.

Not this round (declined or deferred, do not do): moving rail tools into a menu (hides tools, a layout rewrite); removing the section Select (a feature); refitting the whole video above the card (layout rewrite; item 2 covers it).

## Done means

- The app builds for the Simulator with no new warnings: `xcodebuild build -project SwingCoach.xcodeproj -scheme SwingCoach -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
- Tests pass: run `scripts/verify.sh unit coaching library review capture` in the worktree (minutes; run in the background and wait). Update any UI test that asserted text you deliberately changed (for example "Every check"), and say which. Do not weaken an assertion to make it pass otherwise.
- Only one Simulator at a time: do not start a second `verify.sh` while one runs.
- Update `docs/FRONTEND.md` / `docs/COACHING.md` where they describe something you changed (labels, the accent, sheet style).
- Commit on `ui-council` with a message that lists the changes, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

Reply with: the commit hash, one line per numbered fix (done / partly / not done, and why), the test verdict line, and any test you changed.
