# Evidence index

Dated investigations, newest first. Read this table before reconstructing status from git history, worktrees, or issues. When an investigation changes state, update its `Status` line and this table in the same change.

Auto-capture cadence work is tracked in [issue #28](https://github.com/ruari8/SwingCoach/issues/28). [AUTO_CAPTURE_CADENCE.md](../AUTO_CAPTURE_CADENCE.md) explains how to collect and analyze the diagnostics. Raw logs and clips live under the ignored `.verification-artifacts/issue-28/`.

| Date | Investigation | Status | Next step |
| --- | --- | --- | --- |
| 2026-10-04 | [Auto writer handoff stall](./2026-10-04-handoff-stall.md) | Cause identified; fix in `836039d` (standby writer opened ahead of time); not yet device-tested | Two-minute Auto session at 240 fps, then `scripts/diagnostics/check_auto_handoffs.py` |
| 2026-09-14 | [Range session: remaining gaps and practice-swing false positive](./2026-09-14-range-session-investigation.md) | Gaps led to the Oct 4 investigation; the false positive is reproduced but unfixed | Fix the gate that falsely passes (see doc) |
| 2026-09-11 | [Consecutive-recording candidate](./2026-09-11-auto-cadence-fix.md) | Committed in `4465823` on Oct 4; not accepted as a complete jitter fix | Superseded by Oct 4 |
| 2026-09-10 | [Auto jitter: overlapping chunks](./2026-09-10-auto-cadence-investigation.md) | Diagnosis implemented by the Sep 11 candidate | None |
| 2026-09-06 | [Cadence measurements (JSON)](./2026-09-06-auto-cadence.json) | Raw data for [AUTO_CAPTURE_CADENCE.md](../AUTO_CAPTURE_CADENCE.md) | None |
