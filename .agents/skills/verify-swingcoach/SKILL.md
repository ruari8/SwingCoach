---
name: verify-swingcoach
description: Verify SwingCoach's user-facing iOS behavior when asked to launch, drive, reproduce, test, or capture proof for Library, Capture, Trim, Coach, or DEBUG workflows on Simulator or a connected iPhone.
---

# Verify SwingCoach

Verify the real SwiftUI app through the smallest route capable of proving the claim. Read [features/README.md](features/README.md), then open the feature file for the requested behavior before driving it.

For camera, Photos, a connected iPhone, iPhone Mirroring, seeded media, or a manual reproduction, read [references/testing-ladder.md](references/testing-ladder.md) before choosing the route.

## Requirements

- Run from the SwingCoach repository on macOS with Xcode, `xcodebuild`, and `xcrun simctl` available.
- Use XCUITest as the baseline driver. An accessibility-capable device driver is also suitable when available.
- Use a physical iPhone for camera frame rate, audio, orientation, Photos interoperability, and detector performance claims. The Simulator can verify navigation, labels, local reference playback when its ignored fixtures are installed, and non-hardware UI states.
- Treat physical-iPhone and iPhone Mirroring readiness as user-provided session state. A device appearing in Xcode or `devicectl` proves discoverability, not that the phone is nearby, unlocked, mirrored, or ready for prompts. If the user has not confirmed the required route is ready in the current session, ask and pause before touching the phone. Simulator routes need no such handshake.

## Launch and prove the baseline

Run:

```bash
./.agents/skills/verify-swingcoach/scripts/verify-library-paging.sh
```

Pass an explicit artifact directory when a caller needs a stable location:

```bash
./.agents/skills/verify-swingcoach/scripts/verify-library-paging.sh \
  .verification-artifacts/library-paging/<run-id>
```

The helper first requires the three ignored local fixtures documented in `SwingCoach/ReferenceSwings/README.md`. It then copies the Xcode project and app sources to a scratch directory, adds a verification-only XCUITest there, creates a new iPhone 17 simulator, builds Debug, installs and launches `Pear.ai.SwingCoach`, runs the doctor, drives `Capture tab -> Library tab -> Reference swing 1 -> horizontal page swipe`, captures evidence, and cleans up. A missing fixture, failed build, or failed assertion makes the command fail.

Set `SWINGCOACH_VERIFY_DEVICE_TYPE` to another available simulator device type identifier when iPhone 17 is unavailable. Set `SWINGCOACH_VERIFY_RUNTIME` to an installed runtime identifier when the newest compatible runtime is not the intended target.

Readiness is reached only when the disposable simulator is `Booted`, `Pear.ai.SwingCoach` is installed, `simctl launch` returns a PID, and the doctor reports the running bundle from the Debug build.

## Doctor

The helper writes `doctor.txt` before UI driving. Require all of these:

- the owned simulator UUID is booted;
- the installed app reports bundle ID `Pear.ai.SwingCoach` and configuration `Debug`;
- the app process appears in the simulator's launch services;
- the source Git revision and dirty state are recorded;
- Photos authorization rows are recorded as raw TCC values, or as `notDetermined` when no row exists.

Treat a missing field or unexpected bundle ID as the wrong instance. Stop and clean up before retrying.

## Drive

Prefer accessibility labels and identifiers from the feature map. For the baseline, the scratch XCUITest launches the normal app entry point, handles any first-launch system prompt, taps the `Library` tab, opens `Reference swing 1`, reads `swing-position`, swipes `swing-review-page`, and requires `swing-position` to change.

Use the same disposable-simulator pattern for other mapped features. A path without a committed driver or required fixture remains unverified. Record that gap instead of substituting a nearby path.

## Evidence

Store each run under `.verification-artifacts/<feature>/<run-id>/`. Keep:

- `route.txt` with the device, OS, driver, build revision, readiness confirmation, and any human action;
- `doctor.txt` for instance, build, process, and authorization identity;
- `build.log` and `test.log` for commands, console output, and exit status;
- `test-summary.json` and the `.xcresult` bundle for XCTest assertions;
- `screenshots/` for the action and result attachments;
- `launch.png` for the launched app and `final-simulator.png` for the post-test simulator state;
- `cleanup.txt` for teardown confirmation.

The paging test reads the original accessibility value and asserts a different value after the swipe. This second read-only UI observation is the result proof. Screenshots support the assertion but do not replace it. For exploratory device sessions, pair the screen capture with the relevant log interval and mark any user-driven action in `route.txt`.

## Isolation and cleanup

Each helper run owns one uniquely named simulator, one `mktemp` scratch directory, one DerivedData directory inside that scratch directory, and one artifact directory. Xcode test cloning is disabled so every action stays on the owned simulator. Concurrent runs may use different artifact directories.

The exit trap terminates only `Pear.ai.SwingCoach` on the owned simulator, shuts down and deletes only that simulator UUID, and removes only the `mktemp` directory. It preserves the artifact directory. `cleanup.txt` must say that the simulator is absent after deletion.

If a manual run uses an existing simulator, require exclusive use and record its pre-run app and permission state. Restore that state rather than erasing or deleting the simulator.

## Helper

`scripts/verify-library-paging.sh [artifact-directory]` runs the full isolated baseline. It has no partial lifecycle modes. Read its final `PASS` or `FAIL` line and the artifact path. The bundled XCTest source in `assets/SwingCoachVerificationUITests.swift` is copied only into the scratch project and never changes product code. The required reference MP4s remain ignored local inputs and are never verification artifacts to commit.
