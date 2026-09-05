# iOS console diagnostics

Xcode displays messages from SwingCoach and from Apple frameworks running inside
its process. An internal message labelled `Error` is not, by itself, proof that
a recording, image, or playback operation failed. Check the observable operation
and public API error together.

## Reproduced Library messages

On September 5, 2026, `LibraryPagingUITests.testPagingSettlesOnOneWholeVideo`
reproduced the reported messages on an iPhone 17 simulator running iOS 26.3.1.
The test repeatedly paged among the three local reference videos and asserted
that each swipe settled on the intended whole video. Playback navigation passed
even while the console emitted these errors.

| Message/event | Original SwiftUI player | Native controller, analysis enabled | Same controller, analysis disabled |
| --- | ---: | ---: | ---: |
| VisionKit processing requests | 40 | 40 | 0 |
| Cancelled MAD request errors | 11 | 8 | 0 |
| `Visual isTranslatable ... noObservations` | 29 | 32 | 0 |
| `verify_image_parameters: invalid image bits/pixel or bytes/row` | 21 | 25 | 0 |

The second and third runs changed only `allowsVideoFrameAnalysis`. Every run
passed the same paging test. Counts vary with cancellation timing; their absence
after disabling analysis is the regression criterion. Evidence is stored locally
under `.verification-artifacts/console-diagnosis/`, including the three result
bundles and system logs.

Apple's native video player analyses paused frames for text and objects by
default. Disabling touch interaction or hiding playback controls does not stop
that work. SwingCoach already owns playback controls and drawing gestures, so
`SwingVideoPlayer` disables the unused analysis through the public
[`allowsVideoFrameAnalysis` property](https://developer.apple.com/documentation/avkit/avplayerviewcontroller/allowsvideoframeanalysis).
Review, full-screen review, and Trim use this player. SwingCoach's golf detector
and coaching analysis are separate and remain enabled according to their existing
settings.

The cancellation messages describe abandoned analysis requests, not deleted or
corrupted videos. The image-parameter error was also removed by this experiment;
that does not establish that every message with that text has the same cause.
`includesStylesSubmenu` was not reproduced in the simulator capture, so its
relationship to the native context-menu machinery remains unverified.

Run the repeatable check from the repository root:

```bash
./scripts/verify-media-playback.sh
```

The script requires the three ignored reference fixtures, owns a disposable
simulator, captures targeted framework logs, and verifies paging, transport and
drawing gestures, advancing review playback, and returning to Library. It rejects missing/skipped
tests, a missing log stream, the reproduced frame-analysis diagnostics, and the
Trim compiler warning. It preserves logs, screenshots, and XCTest results and
removes its simulator and scratch build directory. This is simulator playback
proof, not physical-camera or Photos interoperability proof.

## Startup messages and limits

| Message | Interpretation and action |
| --- | --- |
| `Reading from public effective user settings` | A settings-read diagnostic. The text does not report a failed operation. |
| Selected/configured `1920×1080 @ 240 fps` | SwingCoach's camera-format message. It describes configured settings, not measured delivered frame rate. |
| `FigXPCUtilities` / `FigCaptureSourceRemote`, `-17281` | Apple-internal capture diagnostics. Apple's developer-support response calls these likely benign when preview and sample-buffer delivery continue normally. A failed or frozen camera still needs investigation. |
| `FigAudioSession`, `-19224` | Apple-internal audio diagnostic. A fuller report on Apple's forums names an unsupported internal operation, but this number alone does not prove microphone failure or establish the cause on this iPhone. Check thrown audio-session errors and actual recorded audio. |
| `numANECores: Unknown aneSubType` | Neural Engine identification diagnostic. It does not establish whether Core ML inference succeeded, failed, or used another compute device. Physical-device inference remains a separate check. |
| `FigApplicationStateMonitor`, `-19431` | Private application-state diagnostic; no verified public meaning or app-side failure established here. |
| `AppleProResHW_CheckPlatform ... IOServiceGetMatchingService failed` | A failed lookup in Apple's ProRes hardware component. This line alone does not show that SwingCoach requested ProRes or that the video's actual codec cannot play. Verify the recording/playback result. |
| `Async` / `PlayerRemoteXPC`, `-12785` | Private media/player diagnostics. No verified public mapping or reproduction established in this investigation. Check playback status and observable behavior instead of guessing a meaning from the number. |

The physical-iPhone startup logs have not been reproduced in this investigation.
The simulator comparison removed the identified frame-analysis messages but
still emitted other CoreMedia diagnostics. It would be incorrect to describe the
entire console as fixed or all remaining messages as harmless.

For real app-level capture failures, filter Xcode's console to subsystem
`Pear.ai.SwingCoach`, category `Capture`. Audio setup failures now log the thrown
error instead of discarding it with `try?`. Capture runtime-error notifications
log the reported domain, code, and description. These logs preserve the existing
capture behavior; they do not implement retries or hide framework output.

The `TrimView` compiler warning was separate: `addSwing` returns a saved swing,
which made `MainActor.run` return that value too. This caller only needs the save
side effect, so it explicitly discards the returned value inside the closure.

Sources: [Apple response on the exact capture diagnostics](https://developer.apple.com/forums/thread/810894),
[reported audio diagnostic with its internal name](https://developer.apple.com/forums/tags/replaykit).
