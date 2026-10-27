---
name: verify-swingcoach
description: Prove a SwingCoach iOS change works before calling it done. Use after changing app code under SwingCoach/, when asked to test, reproduce, or show the app on Simulator or a connected iPhone, or when choosing which tests a change needs.
---

# Verify SwingCoach

A change is done when a check that can observe it has gone green. Pick the checks your change can reach, run them, and report the verdict. A check for an area your change cannot reach proves nothing and costs minutes, so skip it.

## 1. Pick the checks

List the files you changed, committed or not:

```bash
git diff --name-only $(git merge-base main HEAD); git ls-files --others --exclude-standard
```

Take every row whose paths or behavior you touched. A shared model (`SwingLibrary`, `SwingClip`, `ClipStorage`) reaches every row that reads it, so follow its callers. A row is a starting point, not a guarantee: if the checks you picked cannot observe the behavior you changed, also drive it yourself (step 3).

| You changed | Run |
| --- | --- |
| Pure logic in `SwingCoach/Models/` | The matching unit tests in `SwingCoachTests/` (step 2) |
| App launch, tab shell, navigation between tabs | `scripts/verify.sh smoke` |
| `LibraryView` sessions, selection, export | `scripts/verify.sh library` |
| Library filtering, starring, deletion | `scripts/verify.sh library` |
| Photos import | No committed check; drive it (step 3) |
| `SwingReviewPager`, `SwingDetailView`, playback, annotations | `scripts/verify.sh library review` (add `console` to scan playback for framework diagnostics) |
| Paging gestures | `scripts/verify.sh review` (`scripts/verify.sh stress` repeats the flicks over 171 clips) |
| Review lock | `scripts/verify.sh review --only ReviewLockUITests` |
| `CaptureView` controls, settings | `scripts/verify.sh capture` |
| Auto review annotations | `scripts/verify.sh capture --only AutoReviewAnnotationUITests` |
| Recording audio session | `scripts/verify.sh capture --only CaptureAudioUITests --only CaptureRecordingAudioSessionTests` |
| Manual record → Trim handoff | `scripts/verify.sh capture --only ManualTrimCancelUITests` |
| `TrimView/`, clip export | `scripts/verify.sh trim` |
| Context padding, rolling-buffer settings | `scripts/verify.sh trim --only TrimReviewUITests/testContextSettingsPersistAndTrimClockMatchesPlayback --only SwingClipContextTests --only AutoCaptureReviewSessionTests` |
| Partial Photos-save failure and retry | `scripts/verify.sh trim --only TrimReviewUITests/testPartialSaveKeepsFailedClipReachableForRetry` |
| Trim playback timing | `scripts/verify.sh trim-clock` |
| Save to Photos, local storage preference | `scripts/verify.sh storage` |
| `AnalyseView`, `SwingCoachAPI`, coaching display | `scripts/verify.sh coach` (local backend with seeded coaching; proves the app flow, not live AI quality) |
| `backend/` | The backend tests listed in AGENTS.md |
| Docs, comments, Git only | Nothing |

When no row covers the behavior, drive it yourself (step 3).

## 2. Run them

`scripts/verify.sh <area>...` builds once, creates a disposable Simulator, seeds synthetic media through DEBUG launch fixtures, runs the area's XCUITests and unit tests plus its file and Photos checks, and deletes the Simulator on exit. Pass several areas to one run: runs in one checkout share a build, and a second concurrent run reports BLOCKED. `scripts/verify.sh all` runs every default area; `--help` lists them. Exceptions: `trim-clock` runs a macOS probe with no Simulator; `coach` needs `SwingCoach/ReferenceSwings/DaBMIbhpel9_1.mp4` plus `backend/venv` and `backend/models/pose_landmarker_heavy.task`, and reports BLOCKED without them. Read the final `PASS`, `FAIL` or `BLOCKED <reason>` line and the exit status; evidence lands in `.verification-artifacts/verify/`. A run takes minutes, so run it in the background.

Unit tests, on a Simulator of your own because other agents may be running theirs:

```bash
(
  sim=$(xcrun simctl create "SwingCoach unit $$" com.apple.CoreSimulator.SimDeviceType.iPhone-17)
  trap 'xcrun simctl delete "$sim"' EXIT
  xcodebuild test -project SwingCoach.xcodeproj -scheme SwingCoach \
    -destination "platform=iOS Simulator,id=$sim" \
    -only-testing:SwingCoachTests CODE_SIGNING_ALLOWED=NO
)
```

The subshell exits with the test status and deletes its Simulator either way.

Narrow with `-only-testing:SwingCoachTests/<TestClass>` when one file covers your change.

In a git worktree, gitignored assets are missing. For the checks that need them, symlink `backend/venv`, `backend/models/pose_landmarker_heavy.task`, and `SwingCoach/ReferenceSwings/*.mp4` from the main checkout before running, and remove the links before committing.

Reuse a green result until code it covers changes again.

## 3. Drive it when no check exists

- Write a focused XCUITest that performs the new behavior and asserts the user-visible result. Keep it in `SwingCoachUITests/` when the behavior is worth protecting; otherwise delete it after the run.
- To let Ruari watch, open the Simulator in T3's Device panel (`device_list`, then `device_open`) and drive it with the returned CLI. Without T3 device tools, use the browser mirror in `docs/UI_PLAYGROUND.md`.
- Seed Photos with `xcrun simctl addmedia <udid> <video>`.

## 4. Know what the Simulator cannot prove

The Simulator has no camera, routes the Mac's microphone instead of the phone's, has no real capture frame timing, and failed Vision body-pose requests on the iOS 26.3 runtime ("Unable to setup request", October 2026). It can check UI orientation policy and audio-session control flow. Camera fps, real recording audio, device rotation, Auto detection timing, swing positions, thermal behavior, and any speed claim need the physical iPhone. Read [references/testing-ladder.md](references/testing-ladder.md) before touching the phone: it requires Ruari's readiness confirmation, holds the device IDs, and forbids uninstalling the app (that deletes Ruari's swings).

Per-area traps (Photos picker, Auto deletion, backend modes) are in [references/feature-notes.md](references/feature-notes.md).

## 5. Report

State one verdict per check:

- **Pass**: name the assertion that observed the change, plus the artifact path.
- **Fail**: the failing assertion and log line. Fix and rerun that check only.
- **Blocked**: the missing condition (fixture, phone readiness, backend), and what was verified instead.

List phone-only claims as unverified rather than inferring them from the Simulator.
