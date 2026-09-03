# Request and review coaching

Coach lets a golfer choose saved swings, submit analysis, watch progress, retry failures, and reopen completed coaching results.

## Sub-features

- `coach-open` opens Coach from the tab bar or an analyze action in Library, Trim, or swing detail.
- `coach-select` chooses saved swings in the picker.
- `coach-progress` shows queued and active analysis state.
- `coach-retry` retries a failed analysis.
- `coach-result` reopens completed video and notes from Recent Analyses.

## How to get to it (user POV)

- Tap `Coach` in the app tab bar, then `Select Swings` or the top-right add button.
- Select swings in Library and tap the analyze toolbar action.
- Tap the analyze action after Trim exports clips.
- Tap the analyze action in an unanalyzed swing detail view.

## Driving it with XCUITest

Preconditions:

- Seed at least one disposable personal swing. Local references alone do not exercise upload and analysis safely.
- Choose and record one backend mode in `Library -> Experimental settings`: local, deployed, custom, or mock.
- For local real analysis, run the backend and require its health check before UI driving. Real storage-backed runs also need valid R2 configuration.

- **Tab entry.** Tap `Coach`. Require `Swing Coach`, `AI Swing Coach`, `Select Swings`, and `Go to Library` when no saved analysis exists.
- **Picker.** Tap `Select Swings`, select the disposable swing, and require `Analyze (1)` to become enabled. `Cancel` must dismiss without starting work.
- **Library entry.** Enter Library selection mode, select a personal swing, and tap the analyze toolbar action. Require the Coach tab and an `Analysis Queue` row.
- **Detail entry.** Open an unanalyzed personal swing and tap its analyze action. Require the same queue state.
- **Progress.** Require `Waiting...` followed by `Analyzing swing...` or a completed result. Capture the exact failure text if it moves to `Analysis failed`.
- **Retry.** On a failed row, tap `Retry` once and require a new active state. Keep repeated remote retries behind explicit user approval.
- **Result.** Open the completed item under `Recent Analyses`. Require `Original video`, and when present, `Annotated video` and `Coach notes`. Reopen after app relaunch to prove local persistence.

## Gotchas

- A healthy FastAPI process does not prove R2-backed upload and artifact access. Follow the full selected mode.
- DEBUG `Mock analysis` still calls `/mock/analyze`; it is not an offline client stub.
- The local backend URL works from Simulator at `127.0.0.1`. A physical iPhone needs the Mac's LAN URL and local-network permission.
- Analysis runs and uploads can create remote state. Use a disposable clip and record run IDs before cleanup.
- The current project has no committed end-to-end Coach XCUITest, so all analysis entry points remain unverified until their chosen backend path succeeds.
