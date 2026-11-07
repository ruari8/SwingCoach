# November 6 range session: missed swings under floodlights

**Status: cause found and fixed in [PR #64](https://github.com/ruari8/SwingCoach/pull/64). Saved clips had no jitter. A phone check at the range is pending.**

Ruari felt about 1 in 5 swings went unsaved, and could not see why from in front of the camera.

## Inputs

- `~/Downloads/6:11_range_Session`: 35 Auto exports, `metadata 2.json`, `capture-diagnostics.jsonl` (two runs, 17:29–18:14 UTC), a screenshot of Capture, and `IMG_5895.MOV`, a separate iPhone camera recording of the session. iPhone18,3, iOS 27.0.1, `quiet-rollover-v2`, 240 fps.
- `IMG_5895.MOV` is Apple slow motion: 1x for file time 0–91 s and from 3448 s to the end, 8x in between (boundaries from frame-difference motion). Run it as three segments; a uniform 8x scale plays the ends eight times too fast.
- Phone copies: `.verification-artifacts/2026-11-06-range/` (ignored).

## Findings

**Jitter: none.** `analyze_auto_cadence.py --pattern 'swingcoach_*'` found 0 gaps over 75 ms in all 35 clips; the longest interval was 40 ms.

**"Waiting for model…" was a display bug.** The screenshot shows Auto on, 2 saved, and `Waiting for model…`. Auto never published the detector snapshot (fixed in #59).

**The detector, not capture, dropped the shots.** In the Mac replay of `IMG_5895.MOV`, every dropped real shot failed only `no_swing_sequence`: ball departure 1.0, club sweep 0.89–0.99, arc 0.89–0.94, pose present, sequence 0. Under floodlights the clubhead blurs through the strike and YOLO loses it, so the near-away-near club path never forms. Frame strips confirmed each one as a real strike.

**Phone speed makes it worse.** While a swing was in progress the phone ran a median 13 inferences per second (Nov 6 log), not the 16 fps burst target. At a 12 fps burst the reviewed 54-impact gate fell to 47/54 on main, all seven misses on the sequence gate.

**Same failure on the phone.** A footage-camera run of `IMG_5895.MOV` on the phone with main saved 8 shots and logged `no_swing_sequence` rejections (via #63) at 100.7, 187.6 and 438.2 s.

## Fix and result

PR #64 holds a candidate that fails only the sequence gate for 2.6 s and accepts it when a pose full-swing dip lands within 0.5 s of its impact. See [SWING_DETECTOR_V3.md](../SWING_DETECTOR_V3.md) for the rule and tables.

| Set | main | PR #64 |
| --- | --- | --- |
| 54 reviewed impacts @12 fps | 47/54 | 54/54 |
| 54 reviewed impacts @16 fps | 54/54 | 54/54 |
| 19 unseen impacts @16 fps | 19/19 | 19/19 |
| `IMG_5895.MOV` @12 fps | 6 shots | 12 shots, all real |

## Other observations

- In the desk footage-camera run, two exports took 81 s and 50 s while the app had just come back from Photos; the status read `Saving 2 swings…` with 0 saved. At the range all 83 exports from Oct 23 and Nov 6 took 0.1–1.7 s. Not pursued.
- `Operation Interrupted` writer append failures appeared 2–3 times per run, as on Oct 23, outside saved clips.

## Next step

Count shots hit against shots saved at the range with the PR #64 build (installed Nov 7), and read any misses from the `detector-candidate` log.
