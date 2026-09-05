# UI playground and browser Simulator

Foundation task: [Capture UI and persistent playground #20](https://github.com/ruari8/SwingCoach/issues/20).

Ruari prefers reviewing native iOS UI through the browser Simulator mirror. Use
this route for future iOS design iterations and when showing Simulator work.
The playground is a maintained development tool, checked into main so it can be
reopened and extended across tasks. Its simulated state resets on relaunch.

## Open the native playground

On macOS with Xcode, an iOS 26+ Simulator runtime, Node/npm, Python 3 and ffmpeg:

```bash
./playgrounds/ui/run.sh
```

This builds the standalone SwiftUI study, creates a dedicated iPhone 17
Simulator, installs `dev.swingcoach.capturestudy`, and starts `serve-sim`.
Open the exact URL printed by the mirror in the Codex in-app browser. Keep the
terminal running while reviewing. Ctrl-C stops the mirror and removes only the
Simulator created by this launcher. Source, local media and build caches remain.
Set `SWINGCOACH_PLAYGROUND_DEVICE_TYPE` to an installed device type if needed.

The Debug tab switches between native layouts 1 and 5 and between Auto, Manual
idle and Manual recording. Saved samples open the app's shared video player,
including playback, paging and deletion from the simulated session. Recording
and swing detection are simulated. Library, Coach and Trim are placeholders.

For an explicitly selected, exclusively used Simulator:

```bash
./playgrounds/ui/run.sh native <simulator-UDID>
```

The launcher preserves an explicitly supplied Simulator on exit. Re-run the
command after editing a study to rebuild and reinstall it. This standalone host
does not hot reload. Build without launching with `./playgrounds/ui/run.sh build`.

Native variants also accept links, useful for repeatable comparisons:

```bash
xcrun simctl openurl <simulator-UDID> 'capturestudy://design/1'
xcrun simctl openurl <simulator-UDID> 'capturestudy://design/1?mode=manual'
xcrun simctl openurl <simulator-UDID> 'capturestudy://design/5'
```

## Mirror the real app or another SwiftUI study

Build and launch the intended app using the project verification workflow, then
pass that exact Simulator UUID:

```bash
./scripts/mirror-ios-simulator.sh <simulator-UDID>
```

The wrapper pins `serve-sim` to the verified version, binds to localhost through
its default configuration, and uses a separate npm cache. It clears stale helpers
only for the chosen UUID and cleans them up on exit. Select a Simulator owned by
the current task or confirmed to be exclusively available. Keep other tasks'
mirrors running. Open the printed URL and verify a real frame renders and a
control responds before reporting the preview ready.

The `build-ios-apps:ios-simulator-browser` skill also supports hot reload for
previews in importable Swift packages. Use its package launcher when a future
study already lives in that shape. The current app does not need a package or
Xcode project conversion to use the browser mirror.

For assertions against the production app, use
[the project verification skill](../.agents/skills/verify-swingcoach/SKILL.md)
and `./scripts/verify-capture-controls.sh`. Simulator UI evidence does not prove
camera frame rate, live detector accuracy or Photos interoperability on a phone.
For landscape XCTest evidence, capture `XCUIScreen.main.screenshot()`;
`app.screenshot()` cropped the rotated application during this task.

## Original web concepts

```bash
./playgrounds/ui/run.sh web 8768
```

Open `http://127.0.0.1:8768/web/?variant=all` to compare the original five concepts.
Pass a different port if 8768 is occupied. This is the historical HTML study;
the native playground is the reference for Apple's actual controls and materials.

## Source and local media

- `playgrounds/ui/native/CaptureStudy.swift`: native camera layouts and state controls.
- `playgrounds/ui/native/StudyReview.swift`: sample model and review presentation.
- `playgrounds/ui/native/sync-player.py`: extracts current production playback
  controls and copies the shared pager/player into ignored build output on every
  build. Changes to the source extraction markers fail the build for repair.
- `playgrounds/ui/web/index.html`: original five-concept comparison.
- `playgrounds/ui/media/`: ignored, optional local media. `camera.jpg` supplies
  the camera background; `sample-001.mp4` through `sample-003.mp4` supply playback.
- `playgrounds/ui/.build/`: generated app, shared-player copies and module cache.

The local media from the original study was copied into this durable location.
Keep private screenshots and reference footage out of Git. A clean checkout
runs with a neutral camera background and ffmpeg-generated playback patterns.
Use `SWINGCOACH_PLAYGROUND_MEDIA=/path/to/owned/media` to select another media set.

## Accepted Capture direction, September 2026

Native layout 1 was selected after comparing five web concepts and native layouts
1 and 5. Keep most of the screen available for the camera and retain Apple's
native tab bar, including Debug. Auto precedes Manual and is the default. Manual
recording replaces the top settings with a system-font timer; detection status
sits bottom left. Auto uses a red active dot and a saved-swing shortcut bottom
right. Saved swings use the shared player with Done and delete controls.

Production Capture also has an off-by-default `Show model stats` setting under
Library > Experiments > Capture diagnostics. It exposes measured detector FPS
and average processing milliseconds beneath the status in Auto and Manual.
The native study preserves the approved visual comparison; use production
Capture and its verification driver to inspect real settings and status handling.

Continue future studies here, keeping their simulated state explicit. Record
accepted decisions in the implementation ticket and canonical frontend docs.
