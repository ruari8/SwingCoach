# Feature notes

Traps by area that a check or a hand-driven run can hit. Accessibility labels live in the source and in the existing XCUITests; read those rather than a copy here.

## Library and review

- Local reference swings come from gitignored files in `SwingCoach/ReferenceSwings/` and are absent from a clean checkout. Checks that need them report Blocked without them; prefer synthetic clips.
- `-ui-testing-library` launches straight into the Library and skips the normal tab entry. Use a normal launch when the entry path is what you changed.
- Player controls auto-hide. Tap the video surface before querying them.
- For paging, compare the `swing-position` label before and after the swipe. A screenshot of a later swing is weaker proof.
- Local references start starred, so prove star persistence on a personal swing.

## Capture

- Auto is the default mode and starts on appearance. On a fresh install, permission prompts can cover the tab bar.
- Auto detection can take seconds after impact because it waits for finish evidence.
- Deleting from Auto review removes the clip from both SwingCoach and Photos. Use disposable media.

## Import and Trim

- The Photos picker runs outside the app process. Drive it through system accessibility, not app element queries, and wait for `Trim Swings` before assuming a selection.
- Limited and full Photos access take different file-handoff paths. One does not verify the other.
- Detection on imported video runs asynchronously. Wait for a named detected or unavailable state.
- Export mutates the app library and, depending on the path, Photos. Confirm both stores.
- No committed check drives the full Photos-picker import yet.

## Coach

- `scripts/verify-coaching.sh` runs a local backend with seeded coaching. It proves upload, progress, and result display; live AI quality needs the VPS backend described in AGENTS.md.
- DEBUG `Mock analysis` still calls `/mock/analyze` on the backend. It is not an offline stub.
- From Simulator the local backend is `127.0.0.1`. A physical iPhone needs the Mac's LAN URL and local-network permission.
- Analysis runs and uploads create remote state. Use a disposable clip and record run IDs.
