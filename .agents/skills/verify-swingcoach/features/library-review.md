# Browse and review swings

Library lets a golfer browse personal swings and optional local reference swings, open the video-first detail view, page between swings, control playback, star a swing, and inspect metadata.

## Sub-features

- `library-open` opens Library from each production entry point.
- `library-reference` shows three DTL reference swings when the ignored local fixtures are installed.
- `library-detail` opens a reference swing in the review workspace.
- `library-page` moves to the next swing with a horizontal swipe.
- `library-playback` exposes play, frame-step, speed, lock, and full-screen controls.
- `library-star` persists star state.
- `library-metadata` opens the swing metadata sheet.

## How to get to it (user POV)

- Tap `Library` in the app tab bar from Capture or Coach.
- Tap `Go to Library` from the empty Coach screen.
- In Library, tap a card under `Reference swings` or `Your swings`.

## Driving it with XCUITest

Preconditions:

- The app is installed on a fresh simulator and the doctor passes.
- Local files `DaBMIbhpel9_1.mp4`, `DaB3eJ3gAcv_1.mp4`, and `DaD04inv5-Z_1.mp4` are installed under `SwingCoach/ReferenceSwings/`. They are ignored and absent from a clean checkout.

- **Tab entry.** Launch normally and tap `app.tabBars.buttons["Library"]`. The navigation title is `My Swings` and the `Reference swings` section appears.
- **Coach entry.** Tap `Coach`, then `Go to Library`. `My Swings` appears. This entry point has no committed automated proof yet.
- **Open reference.** Tap `app.staticTexts["Reference swing 1"]`. `swing-review-page`, `swing-position`, and `Back to library` appear.
- **Page.** Read `app.staticTexts["swing-position"].label`, drag `swing-review-page` from normalized x `0.82` to `0.18`, and require the label to change within two seconds.
- **Playback.** Require `Play`, `Step back one frame`, `Step forward one frame`, `Keep controls on screen`, `Change playback speed`, and `Open full screen` before claiming those controls are reachable.
- **Star persistence.** Tap `Star swing`, return with `Back to library`, reopen the same card, and require `Remove star`. Restore the original star state after proof. Local references start starred, so use a personal swing fixture for this mutation.
- **Metadata.** Tap `Show swing metadata`, capture the sheet, dismiss it, and confirm the review page remains visible.
- **Automated proof.** With the local fixtures installed, run `./.agents/skills/verify-swingcoach/scripts/verify-library-paging.sh`. It proves tab entry, local reference installation, detail entry, and paging from a normal launch.

## Gotchas

- The repository's `LibraryPagingUITests` passes `-ui-testing-library`, which skips the production tab entry. The verification helper supplies a scratch-only test that taps the tab.
- A fresh simulator can show system permission prompts while Capture is the initial tab. The scratch test dismisses first-launch prompts before choosing Library.
- Reference swings are copied into app-owned storage from ignored local build inputs and do not prove Photos-library playback.
- Player controls may auto-hide. Tap the video surface before querying them.
- A screenshot of a later swing is weaker than the `swing-position` before-and-after assertion.
