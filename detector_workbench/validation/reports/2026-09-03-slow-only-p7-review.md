# Slow-only P7 label review: test16–test21

Generated 2026-09-03. **The user subsequently approved all 19 proposed ball hits without count or timestamp edits** and requested V3 evaluation. The [approved manifest](../labels/unseen_range_slow_only_labels.json) records that approval. The original proposal remains unchanged. The label-generation work below did not run SwingDetectorV3.

The fresh TCN run produced 22 P7 motion proposals. Agent inspection of the ball before and after each proposal retained 19 apparent ball hits and excluded three practice swings. This count is a proposed label set, not a detector performance result.

Times below are **minutes:seconds on the trimmed MP4 playback timeline**. Do not divide these times by eight when seeking in a player. All six clips use a constant `source_time_scale=8` for model processing.

| Fixture | Original | Proposed ball hits | Trimmed playback times |
|---|---|---:|---|
| test16 | IMG_4484.mov | 3 | 3:45.3, 9:33.9, 17:27.5 |
| test17 | IMG_4485.mov | 3 | 2:44.8, 11:37.3, 17:19.7 |
| test18 | IMG_4486.mov | 1 | 1:52.8 |
| test19 | IMG_4487.mov | 7 | 0:49.9, 18:30.9, 26:02.1, 33:21.3, 41:48.3, 48:53.3, 55:34.4 |
| test20 | IMG_4488.mov | 2 | 1:22.1, 6:46.4 |
| test21 | IMG_4489.mov | 3 | 4:59.5, 11:02.1, 21:28.0 |

**Total: 19 proposed ball hits.** Exact model times and scores are retained in the [review manifest](../labels/proposed/unseen_range_slow_only_labels.json).

## Excluded motion proposals

| Fixture | Trimmed playback time | Visual observation |
|---|---|---|
| test20 | 8:58.1 | The club passes beside the balls; both visible balls remain in the same positions through follow-through. |
| test20 | 9:39.2 | The club passes beside the balls; both visible balls remain in the same positions through follow-through. |
| test21 | 8:54.9 | The club passes beside the balls; both visible balls remain in the same positions through follow-through. |

Two additional unselected peaks with scores at least 0.2 and prominence at least 0.1 were checked: test17 at 8:00.0 (short rehearsal motions, ball stays put), and test21 at 7:13.9 (reaching toward the basket). Neither was added.

## What was run

Inputs are `.detectorTestV3/unseen-2026-08-31/slow-only/test16.mp4` through `test21.mp4`. The [preparation manifest](../fixtures/2026-08-31-slow-only.json) records their hashes and original offsets. Normal-speed sections were removed previously; test21 retains its already-slow ending.

The event model is the existing `detectSwings` checkpoint `tcn_vision_club_v1`, epoch 125. Inference used four-real-second windows, 0.5-second stride, P7 threshold 0.5, prominence 0.1, and minimum peak separation 0.4 real seconds. The checkpoint hash and settings are in the label manifest.

To avoid repeating expensive feature extraction, raw Apple Vision pose and `club_seg_v2_960` observations were selected for the exact retained frames. The preparation script verified original/output file hashes, equality of every retained encoded video packet, and alignment of every TCN sample timestamp. It did not reuse earlier labels, TCN scores, candidate peaks, or SwingDetectorV3 results. TCN inference was run again on the trimmed sequences.

Local reproducibility artifacts live under `.verification-artifacts/unseen-range-slow-only-tcn/`:

- `prepare_feature_cache.py` and `feature-cache-provenance.json`: frame mapping, assertions, feature hashes.
- `raw-tcn-proposals.json` and per-video scores/peaks: fresh model output before contact review.
- `render_contact_review.py` and per-video `contact-review/`: source-frame evidence with enlarged strike areas.

Recorded TCN command, after preparing the verified feature cache:

```bash
backend/venv/bin/python detector_workbench/validation/propose_p7_labels.py \
  --fixture-root .detectorTestV3/unseen-2026-08-31/slow-only \
  --source-time-scale 8 \
  --artifacts-dir .verification-artifacts/unseen-range-slow-only-tcn \
  --labels-out .verification-artifacts/unseen-range-slow-only-tcn/raw-tcn-proposals.json \
  --skip-extraction
```

## Review limits

Visual checks used frames at −6, −2, 0, +2, +6, and +10 playback seconds around each proposal, equivalent to −0.75 through +1.25 real seconds. Retained events show the addressed ball before the stroke and its absence afterward; spare balls remain visible where applicable. Driver events show an occupied tee before and an empty tee afterward.

The timestamps remain TCN peak estimates, not manually refined impact frames. This was candidate-based review, not an exhaustive manual annotation of every frame. The user accepted the 19 retained ball-hit labels; the excluded practice proposals remain agent visual assessments. The old full-video counts and withdrawn manifests were not used as targets.

## Per-event visual evidence

- **test16**
  - [3:45.3: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test16/contact-review/test16-p7-01.jpg)
  - [9:33.9: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test16/contact-review/test16-p7-02.jpg)
  - [17:27.5: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test16/contact-review/test16-p7-03.jpg)
- **test17**
  - [2:44.8: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test17/contact-review/test17-p7-01.jpg)
  - [11:37.3: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test17/contact-review/test17-p7-02.jpg)
  - [17:19.7: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test17/contact-review/test17-p7-03.jpg)
- **test18**
  - [1:52.8: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test18/contact-review/test18-p7-01.jpg)
- **test19**
  - [0:49.9: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test19/contact-review/test19-p7-01.jpg)
  - [18:30.9: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test19/contact-review/test19-p7-02.jpg)
  - [26:02.1: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test19/contact-review/test19-p7-03.jpg)
  - [33:21.3: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test19/contact-review/test19-p7-04.jpg)
  - [41:48.3: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test19/contact-review/test19-p7-05.jpg)
  - [48:53.3: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test19/contact-review/test19-p7-06.jpg)
  - [55:34.4: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test19/contact-review/test19-p7-07.jpg)
- **test20**
  - [1:22.1: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test20/contact-review/test20-p7-01.jpg)
  - [6:46.4: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test20/contact-review/test20-p7-02.jpg)
  - [8:58.1: excluded practice swing](../../../.verification-artifacts/unseen-range-slow-only-tcn/test20/contact-review/test20-p7-03.jpg)
  - [9:39.2: excluded practice swing](../../../.verification-artifacts/unseen-range-slow-only-tcn/test20/contact-review/test20-p7-04.jpg)
- **test21**
  - [4:59.5: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test21/contact-review/test21-p7-01.jpg)
  - [11:02.1: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test21/contact-review/test21-p7-03.jpg)
  - [21:28.0: proposed ball hit](../../../.verification-artifacts/unseen-range-slow-only-tcn/test21/contact-review/test21-p7-04.jpg)
  - [8:54.9: excluded practice swing](../../../.verification-artifacts/unseen-range-slow-only-tcn/test21/contact-review/test21-p7-02.jpg)
