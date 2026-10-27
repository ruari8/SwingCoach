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
| `LibraryView` sessions, selection, export | `scripts/verify-library-sessions.sh` |
| Library filtering, starring, deletion | `scripts/verify-review.sh` |
| Photos import | No committed check; drive it (step 3) |
| `SwingReviewPager`, `SwingDetailView`, playback, annotations | `scripts/verify-review.sh` and `scripts/verify-media-playback.sh` |
| Paging gestures | `scripts/verify-fast-swipes.sh` |
| Review lock | `scripts/verify-review-lock.sh` |
| `CaptureView` controls, settings | `scripts/verify-capture-controls.sh` |
| Auto review annotations | `scripts/verify-capture-controls.sh <artifact-dir> annotations` |
| Recording audio session | `scripts/verify-capture-audio.sh` |
| Manual record → Trim handoff | `scripts/verify-manual-trim-cancel.sh` |
| `TrimView/`, clip export | `scripts/verify-trim-review.sh` |
| Context padding, rolling-buffer settings | `SWINGCOACH_TRIM_VERIFY_CONTEXT=1 scripts/verify-trim-review.sh <artifact-dir>` |
| Partial Photos-save failure and retry | `SWINGCOACH_TRIM_VERIFY_PARTIAL=1 scripts/verify-trim-review.sh` |
| Trim playback timing | `scripts/verify-trim-playback-clock.sh` |
| Save to Photos, local storage preference | `scripts/verify-save-photos.sh` |
| `AnalyseView`, `SwingCoachAPI`, coaching display | `scripts/verify-coaching.sh` (local backend with seeded coaching; proves the app flow, not live AI quality) |
| `backend/` | The backend tests listed in AGENTS.md |
| Docs, comments, Git only | Nothing |

When no row covers the behavior, drive it yourself (step 3).

## 2. Run them

Most `scripts/verify-*.sh` build their own disposable Simulator, seed synthetic media, run XCUITests, and delete the Simulator on exit. Exceptions: `verify-trim-playback-clock.sh` runs a macOS probe with no Simulator; `verify-media-playback.sh` needs the three private videos in `SwingCoach/ReferenceSwings/`; `verify-coaching.sh` needs one of those videos plus `backend/venv` and `backend/models/pose_landmarker_heavy.task`. Read the final lines and the exit status; evidence lands in `.verification-artifacts/`. A run takes several minutes, so run independent checks in the background.

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
