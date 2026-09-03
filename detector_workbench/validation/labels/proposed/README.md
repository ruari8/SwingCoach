# Proposed labels awaiting review

**2026-09-03: the user approved all 19 trimmed test16–test21 ball-hit labels.**
The approved copy is [../unseen_range_slow_only_labels.json](../unseen_range_slow_only_labels.json).
The proposal and its SHA-256 remain unchanged as the pre-review record.
`unseen_range_slow_only_labels.json` contains 19 proposed ball-hit labels from
a fresh TCN run on the uniformly slowed copies. Agent visual review excluded
three practice swings from 22 raw P7 proposals. Times use the **trimmed MP4
playback timeline**, not the original MOV timeline. See the
[counts, timestamps, and evidence](../../reports/2026-09-03-slow-only-p7-review.md).
The six-video set remains separate from the original 54-label regression set.

**test15 review completed on 2026-08-30.** The user accepted all three predictions as "pretty much perfect labelling" and requested swing-detector testing. The approved times are now in `../detector_test_v3_labels.json`. The proposed events, scores, and original `needs_review` status remain unchanged; its audit path was normalized to a repository-relative local-artifact path.

Files here contain model predictions, not human-reviewed ground truth. The detector baseline reads `../detector_test_v3_labels.json` explicitly and does not include these proposals.

`test15_p7_labels.json` contains P7 proposals for `.detectorTestV3/test15.mp4`. Times use the exported video's playback timeline. The capture rate is 240 fps, playback is 30 fps, and `source_time_scale` is 8.

The existing `detectSwings` checkpoint `tcn_vision_club_v1` generated the proposals. Its usual decoder assumes one swing per clip, so this run used an experimental sliding-window P7 peak rule over the whole recording. The JSON records the rule and model hash. Neither manual swing labels nor SwingDetectorV2 outputs selected the windows.

Local review frames, raw scores, all peaks, conversion verification, and scripts are in `.verification-artifacts/test15-event-labels/`. Open `review.md` there to review the proposed impacts. The source MOV remains unchanged beside the converted MP4.

For future proposals, record user review and any timing/count corrections before adding them to the baseline. A machine proposal must not silently become an expected result.

**The six 2026-08-31 recordings' 31-label and 33-label manifests were withdrawn.**
User review on 2026-09-03 contradicted the counts, and follow-up inspection
confirmed practice swings wrongly labelled as ball impacts. The invalid JSON,
SHA-256 files, and obsolete score report were removed before the branch history
was squashed. The manually chosen speed segments were also unverified
as Apple transition boundaries. See [the correction and input
audit](../../reports/2026-09-03-unseen-input-audit.md).
