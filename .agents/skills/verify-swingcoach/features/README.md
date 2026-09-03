# SwingCoach verification map

This directory maps SwingCoach's user-facing iOS workflows to observable Simulator or device behavior. Read this index before driving the app, then use the matching feature file.

When a feature involves a camera, Photos fixture, connected iPhone, iPhone Mirroring, or manual reproduction, choose the route from [../references/testing-ladder.md](../references/testing-ladder.md).

## Baseline preconditions

- Build the `SwingCoach` scheme in Debug from `SwingCoach.xcodeproj`.
- Use bundle ID `Pear.ai.SwingCoach`.
- Give each run its own simulator UUID, DerivedData directory, result bundle, and artifact directory.
- Start from a newly created simulator unless the feature requires physical-device state.
- Run the doctor before the first UI action.

## Driving conventions

- Prefer XCUITest element labels and accessibility identifiers over coordinates.
- Start normal user-entry checks without `-ui-testing-library`. That launch argument is useful for the repo's focused test, but it bypasses the production Capture-to-Library entry path.
- Wait for named UI state. Avoid fixed sleeps except when the app exposes no stable completion handle.
- Keep camera, Photos, and backend requirements explicit. Simulator success cannot prove physical-camera behavior.

## Proof and skip reporting

- Capture the action and result as separate screenshots or XCTest attachments.
- Preserve the test log, `.xcresult`, summary JSON, doctor report, and cleanup report.
- Confirm mutations through a second user-facing read when possible, such as reopening a saved item.
- Name the feature ID and entry point in the artifact directory or test name.
- Report every skipped entry point with its unmet permission, fixture, hardware, or backend condition.

## Features

- [Browse and review swings](library-review.md) covers the Library tab, optional local references, detail paging, playback controls, starring, and metadata.
- [Capture swings](capture.md) covers Auto and Manual capture, frame-rate selection, recording, review, and hardware limits.
- [Import and trim video](import-trim.md) covers Photos import, trim ranges, detected clips, export, and cancellation.
- [Request and review coaching](coach-analysis.md) covers Coach entry points, swing selection, analysis progress, retries, and completed results.
