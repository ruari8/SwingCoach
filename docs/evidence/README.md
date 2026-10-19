# Evidence index

Dated investigations, newest first. Read this table before reconstructing status from git history, worktrees, or issues. When an investigation changes state, update its `Status` line and this table in the same change.

Auto-capture cadence work is tracked in [issue #28](https://github.com/ruari8/SwingCoach/issues/28). [AUTO_CAPTURE_CADENCE.md](../AUTO_CAPTURE_CADENCE.md) explains how to collect and analyze the diagnostics. Raw logs and clips live under the ignored `.verification-artifacts/issue-28/`.

| Date | Investigation | Status | Next step |
| --- | --- | --- | --- |
| 2026-10-12 | [Range session: standby writer on the phone](./2026-10-12-range-session-standby-writer.md) | Standby writer works and cut drops per file switch by about two thirds; 8 of 44 clips still have gaps (rollover drops plus unexplained bursts) | Range session with `quiet-rollover-v1` and detector timing (Oct 19), including part at 120 fps; then remove encoder handoffs if gaps remain |
| 2026-10-04 | [Auto writer handoff stall](./2026-10-04-handoff-stall.md) | Fix in `836039d` device-tested on Oct 12: queue stall gone, smaller rollover drops remain | Superseded by Oct 12 |
| 2026-09-14 | [Range session: remaining gaps and practice-swing false positive](./2026-09-14-range-session-investigation.md) | Gaps led to the Oct 4 investigation; the false positive is reproduced but unfixed | Fix the gate that falsely passes (see doc) |
| 2026-09-11 | [Consecutive-recording candidate](./2026-09-11-auto-cadence-fix.md) | Committed in `4465823` on Oct 4; not accepted as a complete jitter fix | Superseded by Oct 4 |
| 2026-09-10 | [Auto jitter: overlapping chunks](./2026-09-10-auto-cadence-investigation.md) | Diagnosis implemented by the Sep 11 candidate | None |
| 2026-09-06 | [Cadence measurements (JSON)](./2026-09-06-auto-cadence.json) | Raw data for [AUTO_CAPTURE_CADENCE.md](../AUTO_CAPTURE_CADENCE.md) | None |
