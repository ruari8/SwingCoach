# SwingCoach testing ladder

Choose the lowest-cost route that can observe the behavior under test. A higher route does not replace a lower one: keep repeatable UI coverage in Simulator and reserve the phone for claims that depend on phone hardware or system integration.

## Phone readiness handshake

Treat phone access as unavailable until the user confirms the needed route is ready for the current testing session. Tool discovery is only a capability check. A phone can appear as paired or as an Xcode destination while it is upstairs, locked, disconnected, or waiting for a prompt the user cannot approve.

The user can establish readiness by saying either `phone ready for Xcode` or `mirroring ready`. A more detailed statement with the same meaning is fine. Reuse that confirmation during the current session until the device disconnects, locks, restarts, Mirroring closes, or the test finishes.

When the user has not supplied readiness and the claim requires a phone, explain why and ask for the matching setup:

- For Xcode device testing: ask the user to bring the phone nearby, connect it or enable its known wireless development connection, unlock it, and remain available for trust, Developer Mode, permission, or passcode prompts. Continue when the user says `phone ready for Xcode`.
- For iPhone Mirroring: ask the user to bring the phone into a state where Mirroring can connect, open iPhone Mirroring on the Mac, confirm the intended phone is visible and controllable, and remain available for phone-only prompts. Continue when the user says `mirroring ready`.

Ask only when the phone route is needed. Continue Simulator work without interrupting the user. If Simulator can prove part of the request, run that part and report the phone-only checks as deferred. Never treat a Simulator result as proof of the deferred hardware behavior.

If readiness fails during a run, stop device interaction, preserve the evidence collected so far, and tell the user the exact state needed to continue. Do not keep retrying connections or prompts in the background.

## Route 1: seeded Simulator

Use Simulator for navigation, accessibility, layout, playback, selection, Trim UI, error states, and Photos-picker flows that start from an existing video.

For exploratory work, use one dedicated `SwingCoach QA` simulator so the same fixtures remain available. For final proof, create a disposable simulator and artifact directory so app state and permissions are known.

Seed one or more videos into the Simulator Photos library before opening the picker:

```bash
xcrun simctl addmedia <simulator-udid> \
  /absolute/path/to/test-swing.mp4
```

`simctl addmedia` accepts photos and videos. Record the fixture path and verify that the intended asset is visible in the picker; a successful command alone does not prove the app selected it. When locally installed, the ignored files under `SwingCoach/ReferenceSwings/` are suitable disposable video inputs, but they are not substitutes for deliberately varied trim and orientation fixtures.

Use XCUITest or an available accessibility driver for repeatable actions and assertions. A Simulator mirror in the Codex browser is useful when the user wants to watch the run, but the driver and assertions remain the source of proof.

Simulator cannot establish real camera input, supported capture frame rates, microphone behavior, device rotation behavior, rolling-buffer timing, thermal performance, or on-device detector performance.

## Route 2: Xcode-driven physical iPhone

Use a connected iPhone for Capture, 30/60/120/240 fps selection and output, audio, camera orientation, Auto detection timing, real Photos interoperability, local-network backend access, and performance claims.

Before changing the phone:

1. Complete the phone readiness handshake.
2. Discover it with `xcrun devicectl list devices` and confirm it is an available destination with `xcodebuild -project SwingCoach.xcodeproj -scheme SwingCoach -showdestinations`.
3. Record the device model, OS, app build revision, permission state, and the disposable media that the run may create.
4. Build and launch through Xcode, then prefer an XCUITest that targets the physical-device destination. Capture device logs for the same interval as the UI evidence.

Keep the test data bounded: use named test clips or a dedicated QA album, and remove only assets created by the run. Never erase or reset the user's phone as cleanup.

Physical-device automation can drive the app through XCTest. Hardware permission prompts and some system-owned surfaces may still need one user action; record that action instead of presenting the run as unattended.

## Route 3: iPhone Mirroring observation

Use iPhone Mirroring with Computer Use for exploratory reproduction, visual inspection, and UI paths that do not yet expose stable accessibility identifiers. It is especially useful as the interaction surface while Xcode installs the build and captures logs from the phone.

Complete the Mirroring readiness handshake before opening, focusing, or controlling the mirrored phone. If the user confirmed Xcode device readiness only, ask separately before using Mirroring because the two routes have different setup requirements.

Treat Mirroring as an observation and interaction layer, not the proof oracle. Window position, animation, focus, and the accessibility exposed by the mirrored surface can make coordinate-driven steps fragile. When the behavior is repeatable, encode the smallest stable path as XCUITest and keep Mirroring for watching it.

The simplest live device session is:

1. The agent confirms the destination, build, and permissions, launches the Debug app, and starts log capture.
2. The agent drives the mirrored phone, or asks the user for one bounded action such as reproducing a system prompt.
3. As soon as the behavior occurs, capture the visible state and the matching log interval.
4. Re-read the result through UI state, stored data, or a relaunch when possible.

## Manual feedback packet

When live control is unavailable, ask for the smallest packet that preserves the bug:

```text
Feature: <capture / import / trim / coach / library>
Expected: <one sentence>
Observed: <one sentence>
Action: <last tap or gesture before it happened>
Evidence: <10-20 second screen recording or one screenshot>
Device/build: <iPhone model + iOS; build or approximate time>
```

The user should not have to reconstruct logs or write a full narrative. Correlate the supplied time with app/device logs, reproduce the same path on the cheapest capable route, and return a precise result: reproduced, not reproduced, or blocked by a named missing condition.

## Evidence contract

For every route, write `route.txt` beside the other artifacts with:

- route and driver;
- readiness state and the time of user confirmation, or `not-needed` for Simulator;
- simulator UUID or physical-device model and OS;
- source revision and dirty state;
- fixture identity and permission state;
- automated and human-driven actions;
- timestamps that align screenshots or recordings with logs.

A passing run names the user-visible assertion it observed after the action. A screenshot without a before/after assertion is supporting evidence, and a user-driven step is valid exploratory evidence when it is disclosed.
