# Import and trim video

Library import opens a Photos video in Trim, where a golfer can mark or review swing ranges and export clips to the local library.

## Sub-features

- `import-open` starts import from Library.
- `import-permission` handles full, limited, denied, and not-determined Photos access.
- `trim-open` opens `Trim Swings` for the chosen video.
- `trim-range` adjusts a manual or auto-detected swing range.
- `trim-export` exports one or more clips to the library.
- `trim-cancel` leaves without saving clips.

## How to get to it (user POV)

- Tap the Library toolbar import button.
- Tap `Import` in Library's empty state when that state is available.
- Choose a video from Photos and continue into `Trim Swings`.
- Stop a Manual recording in Capture to enter `Trim Swings` with the captured video.

## Driving it with XCUITest

Preconditions:

- Seed one disposable golf-swing video into the owned simulator or test device Photos library.
- Record Photos authorization state and the seeded asset identity.
- Use a new app container or remove imported clips after the run.

- **Toolbar entry.** In Library, tap the import toolbar button. Use the visible accessibility description from the UI snapshot because the source currently supplies only an image label.
- **Empty entry.** Tap `Import` in the empty state. Installed local references prevent that state, so use a verification-only empty-library fixture or report the path unverified.
- **Limited access.** When authorization is limited, require the `Photos Access` dialog and its `Continue Import`, `Choose Allowed Videos`, `Open Settings`, and `Cancel` actions.
- **Picker.** Choose the seeded video in the system Photos picker. Wait for the picker to dismiss and require `Trim Swings` rather than assuming selection completed.
- **Trim.** Require `Cancel`, `DTL`, the timeline, and either an `Auto-detected swing` or the manual range controls before editing.
- **Side-effect proof.** Export one clip, return to Library, reopen the new card, and verify playback. Then remove the test clip while preserving evidence.
- **Capture entry.** On a physical device, stop a short Manual recording and require the same `Trim Swings` title.

## Gotchas

- Photos picker content is outside the app process. Drive it through system accessibility, not app-only element queries.
- Limited access can take a different file-handoff path from full access. One mode does not verify the other.
- Imported video detection runs asynchronously. Wait for a named detected or unavailable state, not a fixed delay.
- Export mutates both the app library and, depending on the path, Photos. Confirm both stores before cleanup.
- The current project has no committed end-to-end import XCUITest, so this feature remains unverified until a seeded-media run succeeds.
