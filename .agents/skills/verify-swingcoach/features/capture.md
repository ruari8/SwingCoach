# Capture swings

Capture lets a golfer choose Auto or Manual workflow, choose a capture frame rate, record or detect swings, and review saved clips.

## Sub-features

- `capture-open` opens Capture from the tab bar or Library's empty-state action.
- `capture-mode` switches between Auto and Manual.
- `capture-fps` selects 30, 60, 120, or 240 fps HD.
- `capture-manual` starts and stops a recording, then opens Trim.
- `capture-auto` arms detection and reports saved swings.
- `capture-review` opens the captured-swing carousel.

## How to get to it (user POV)

- Tap `Capture` in the app tab bar.
- Tap `Record` from Library when no personal or reference swings are present.

## Driving it with XCUITest

Preconditions:

- Use a physical iPhone for recording, camera orientation, frame-rate, audio, rolling-buffer, and detector claims.
- Camera, microphone, and add-only Photos authorization state is recorded by the doctor.
- Clear test clips from SwingCoach and Photos before and after a mutating run.

- **Tab entry.** Tap `Capture` in the tab bar. A segmented control named `Capture` and the current FPS menu appear.
- **Library entry.** On a fixture build with an empty library, tap `Record`. Capture appears. Installed local references make this entry unreachable, so report it unverified unless the fixture removes them.
- **Mode.** Tap `Manual`, then `Auto`, in the `Capture` segmented control. The Manual record control appears only in Manual. Auto shows its guide card.
- **FPS.** Open the FPS menu and choose one of `30fps HD`, `60fps HD`, `120fps HD`, or `240fps HD`. Read the menu value after selection.
- **Manual recording.** On a physical device, choose Manual, activate the record control, capture a short clip, stop, and require the `Trim Swings` screen.
- **Auto review.** On a physical device with a detected swing, require `<count> swing captured`, tap `Review`, and require `Close swing review` plus `Delete this swing`.

## Gotchas

- Simulator navigation proves only UI state. It has no real camera stream and cannot prove requested FPS, AVAssetWriter output, audio, orientation, or detector timing.
- Auto is the default and starts on appearance. Permission prompts can cover the tab bar on a fresh install.
- The record control has no explicit accessibility label in the current source. Add one before treating coordinate-based recording automation as stable.
- Auto detection can take seconds after impact because it waits for finish evidence.
- Deleting from Auto review removes the clip from both SwingCoach and Photos. Use disposable media.
