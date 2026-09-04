# Duplicate Auto capture on September 4

The range recording reproduces [issue #2](https://github.com/ruari8/SwingCoach/issues/2).
Practice detection can publish a swing before contact confirmation finishes.
The contact path then publishes the same stroke with a second UUID. Auto exports
both IDs. Replay Debug and the standard fixture evaluator previously left
practice capture off, even when Capture had it enabled.

## Evidence

The user supplied `~/Downloads/ScreenRecording_09-04-2026 12-25-37_1.MP4`,
137.473 seconds, 1206 by 2622 pixels. Its SHA-256 is
`77af43cca9cbcbd285e4c3b3132bdd4cd84a27aa283c43b500eef75ac24df91b`.
The screen shows Auto, 240 fps, practice capture enabled, and saved counts
0 → 2 → 4 → 6 after three ball strikes. The recording does not show the saved
clips themselves or identify the installed build.

The local replay crops the camera area with
`crop=1206:2070:0:310,fps=30,scale=604:-2`. It uses source-time scale 1 because a
screen recording plays movement at real speed, regardless of the camera's
240 fps setting. The detector uses 8 fps low sampling, 16 fps burst sampling,
CPU inference, and practice capture enabled.

Before the fix, the first stroke produces these two events:

| Path | Impact | Declaration | Clip start | Clip end |
| --- | ---: | ---: | ---: | ---: |
| Practice | 31.733 | 32.000 | 30.133 | 32.533 |
| Contact | 31.733 | 32.067 | 30.133 | 32.533 |

The normal engine is still in `impactCandidate` at 32.000. The pose finish is
already sufficient for practice acceptance, but the contact engine needs one
more sampled frame. Practice checks existing detections, finds none, and emits.
Contact subsequently accepts without accounting for the earlier practice event.
The two IDs explain why Auto's per-ID export tracking does not help.

The full unfixed replay produces five events, duplicating strikes one and three.
The fixed replay produces three contact events at 31.733, 75.200, and 123.467
seconds. All contact times, declaration times, confidence values, and clip
boundaries are preserved. Both runs process 1,136 sampled frames. The phone's
six saves and replay's five unfixed events are distinct observations: a cropped,
re-encoded screen recording is not the original camera sample stream.

Local before/after JSON, the contact sheet, and the successful iOS build log are
in `.verification-artifacts/duplicate-capture-2026-09-04/`.

## Change and regression

Practice fallback now defers while contact confirmation is pending. It leaves
the pose dip unconsumed so a later frame can either recognize the accepted
contact or retain the swing as practice after contact expires. This preserves
contact evidence and does not extend the cooldown or add an export time filter.
The contact-only path retains its existing behavior.

Replay Debug now passes the same practice-capture preference as Capture when
starting or restarting. A preference change clears the active replay.
Both local evaluators accept `--practice-swings` and record the setting.

The committed observation fixture contains 53 sampled frames from source
seconds 27–33. It retains model boxes, pose confidence, wrist position, torso
height, hand height, and luma motion. The test bypasses inference but uses the
production decision path. It collects newly emitted IDs after each frame, as
Auto does, so filtering final output would not hide duplicate export events.

Run the regression from the repository root:

```bash
python3 detector_workbench/validation/test_swing_detector_v3_evidence.py --build
```

Before the fix, the single-stroke and successive-strokes checks fail. After the
fix, all 24 checks pass, including contact timing and confidence preservation,
practice capture without a ball, and practice fallback when target occlusion
causes contact confirmation to expire. The latter test adds a clubhead over the
known target before enough clear-absence samples arrive.

The iOS Simulator build passes. This verifies compilation of the Replay Debug
preference wiring. No physical-phone installation, live camera session, Photos
save check, or Replay Debug UI run was performed after the fix. Those remain
the device verification step; this report does not close issue #2.
