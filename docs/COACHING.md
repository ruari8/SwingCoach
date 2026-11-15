# Coaching: metrics and drawings (on the phone)

The app measures each down-the-line swing on the phone and draws what it measured on the video. No backend and no AI model call: Vision and the club detector find the body, club and ball, and plain geometry scores them against what tour pros do.

It gives three things:
- **Per swing:** up to 21 measurements, each with a level and a drawing on the frame it was measured at.
- **One line per swing:** "Good swing", "That's better", the one fault worth a thought, or "not judged" with the reason.
- **Per session:** the faults that kept repeating.

Voice and drills are not built. The old backend coaching (`backend/`, the Coach tab, "Analyze Swing") is untouched and separate.

Down-the-line clips captured in the app only. Face-on, imports and reference swings are skipped.

## What runs

| Step | Code |
| --- | --- |
| Follow the club from address to follow-through, time P2, P6 and P7 off it, then record body joints, the golfer's outline, club and ball on the frame at each of P1–P10 | `SwingCoach/Models/Coaching/CoachingEvidenceExtractor.swift` |
| The stored evidence | `CoachingEvidence.swift` |
| Evidence to points: hands, shaft, clubhead, ball, backside, head; and the checks that a swing can be judged | `CoachingSwingGeometry.swift` |
| P2 and P6 where the shaft is level, P7 where the ball leaves | `CoachingCheckpointTiming.swift` |
| The metrics, their zones and levels | `CoachingMetrics.swift` |
| Evidence to a report: a value, level and drawing per metric | `CoachingAnalyzer.swift` |
| What to say: one fault per swing, session themes | `CoachingFeedback.swift` |
| Background queue and saved results | `SwingCoachingStore.swift` |
| Drawings on the video, verdict pill, measurement list, session summary | `SwingCoach/SwingCoachingViews.swift` |

Coaching starts from the swing's P1–P10 ([SWING_POSITIONS.md](./SWING_POSITIONS.md)). It needs the app's own copy of the clip.

### Evidence

Three sources, all on-device:
- **Vision body pose** (19 joints). Wrists are usually hidden at address and impact from down the line, so the hands there come from the top of the shaft instead.
- **Vision person segmentation**, reduced to the golfer's left and right edge on 160 rows. The back edge at hip height is the backside for hip depth. Only the region connected to the golfer's hips is kept, so other people on the range are left out.
- **`SwingObjectsYOLO11n`** (the Auto detector's model): shaft box, clubhead and ball. The shaft box's corner nearest the hands is the grip; a clubhead detection near the far corner is the head. A "clubhead" seen in the same place in most frames (a bag, a spare club) is ignored. The ball is the candidate that stays put through the backswing nearest the soled club.

### Club timing

The position model reads body pose, so P2, P6 and P7 land a frame or two off at 30 fps. That is a long way for a clubhead. The extractor reads the clip once from P1 to P9, sampling the club 60 times per real second and at every frame through the downswing (about 120 samples), then:
- **P2** is the first time the clubhead climbs through hand height going back.
- **P6** is the last time it drops through hand height coming down.
- **P7** is the first frame the ball is gone from its spot for good: after it was seen at least three times, and with at least four samples and no sighting after. Any later sighting means an earlier gap was the club passing in front of it.

 A club time more than 4 slots (P2) or 2.5 slots (P6, P7) from the model's is dropped as a tracking slip, and so is one that would put the positions out of order. On the 15 November session P2 moved 11–20 frames later (240 fps), P6 2–10 earlier and P7 up to 8 either way.

The re-timed positions are saved back on the swing, so the player's position strip jumps to the frames the drawings were measured on. `SwingPositions.modelClipTimes` keeps the model's own times so coaching can start again from them.

At a position the club comes from the frame itself when the detector sees the shaft there, and otherwise from the track samples either side, joined by a straight line at lower confidence. At P2 and P6 the shaft points at the camera, the detector often misses it, and the reading leans on the track. These are the least reliable readings.

## When a swing isn't judged

A swing is measured but gets no verdict and counts toward no theme when:

| Reason | How it is told | Why |
| --- | --- | --- |
| **Short swing** (chip or pitch) | The hands stay under the trail shoulder at the top | The zones come from full swings |
| **Camera moved** | Either ankle appears to shift more than 10% of body scale between address and the top. Both feet are planted until then, and a tripod clip's ankle joints wander about 5% | Nothing can be compared with address |
| **Positions unclear** | At P1 the club isn't hanging down from the hands, or at P7 the hands (the top of the shaft, or the wrists when blur hides it) are more than a quarter of body scale from where they started or can't be found, or the top wasn't seen, or fewer than 8 of the 17 judged measurements could be made | The clip opens on a rehearsal, impact landed on the follow-through, or too little was seen for "good swing" to mean anything |

On the four range sessions below that was 11 short swings, 3 moved cameras and 5 unclear of 170. On the pro Instagram clips it was 74 of 168, mostly clips that open on a waggle.

A single reading more than ten steps outside its zone is dropped as a measurement slip (a wrong shaft end, another person joined to the outline) and listed as not measured.

## Metrics

Every metric is one number at one position, with a zone. Inside the zone the level is 0. Outside, the level counts steps from the zone, 1 to 10, signed by direction. There is no overall score.

Distances are a share of the golfer's **body scale**: trail shoulder to hip plus hip to ankle at address. That makes them independent of how far the camera is. "Toward the ball" is positive. Handedness comes from which way the golfer faces at address.

| Metric | At | Measures | Zone | Step |
| --- | --- | --- | --- | --- |
| Posture *(guide)* | P1 | Forward bend, hips to neck, from vertical | 29 to 39° | |
| Hands at address *(guide)* | P1 | Hands against a line down from the trail shoulder | 5 to 13% | |
| Takeaway | P2 | Clubhead against the hands, shaft level | 4 to 26% | 5% |
| Address plane going back *(guide)* | P2 | Clubhead against the address plane line | | |
| Shaft halfway back | P3 | Where the butt of the club points on the ground, against the ball | −29 to 3% | 6% |
| Lead arm at the top | P4 | Lead arm angle against the shoulder line | 8 to 20° | 4° |
| Hand depth at the top | P4 | Hands against a line up from the trail heel | 0 to 10% | 3% |
| Hip depth at the top | P4 | Backside against its address line | −3 to 1.5% | 1.5% |
| Head height at the top | P4 | Head against address, up-down | −6 to 0% | 1.5% |
| Head at the top | P4 | Head against address, toward-away | −1.5 to 3% | 1.5% |
| Posture at the top | P4 | Forward bend against address | −7 to 2° | 3° |
| Transition | P5 | Shaft angle against the same point going back (P3) | −16 to 6° | 3° |
| Shaft halfway down | P5 | Where the butt points on the ground, against the ball | −25 to 26% | 8% |
| Address plane coming down *(guide)* | P6 | Clubhead against the address plane line | | |
| Hip depth at impact | P7 | Backside against its address line | −3.5 to 3% | 1.5% |
| Head height at impact | P7 | Head against address, up-down | −12 to −3% | 2% |
| Head at impact | P7 | Head against address, toward-away | −5.5 to 2% | 2% |
| Posture at impact | P7 | Forward bend against address | −6 to 6° | 3° |
| Hands height at impact | P7 | Hands against address, up-down | 2.5 to 10.5% | 2% |
| Hands at impact | P7 | Hands against address, toward-away | 0.5 to 7% | 2% |
| Trail knee at impact | P7 | Trail knee against address, toward-away | −1 to 8% | 1.5% |

A **guide** is drawn but never judged: its level is always 0.
- The two setup metrics depend on the club, and the pro swings behind the zones are mostly drivers.
- The address plane (from the soled clubhead through a point just up the trail forearm, as Swing Coach draws it) is not something good players stay close to: their clubheads sit anywhere within a third of body scale of it.

A metric is left out of a swing's report when its evidence is missing or its confidence is under 0.3, and listed as not measured.

Not measured, and not claimed: clubface, shaft at the top (the club is hidden behind the head from down the line), impact quality, ball flight, anything in 3D.

### Where the zones come from

Each zone is the middle 70% (15th to 85th percentile, rounded) of **96 tour-pro down-the-line swings** (94 since the last checks were added; the zones were not refitted for two swings). They are the slow-motion `purego1f` Instagram clips in `../detectSwings` (right-handed, 720 × 1280, 59 at 8× and 109 at 4×) that pass the same checks a swing here has to pass to be judged; 74 of the 168 do not. Run on 15 November 2026 with the harness below. So a level counts steps outside what good players do.

What the pros showed:
- They lower the head into impact (median −6%) and going back (−3%). A head that stays level reads as "stays up".
- The lead arm sits about 14° above the shoulder line at the top, not on it.
- Halfway back the butt of the club points inside the ball (median −12%), and the shaft is 6° flatter coming down than going back.
- At impact their hands are higher (+6%) and further from the body (+4%) than at address, and the trail knee has moved 4% toward the ball. Those are normal, not faults.

Limits of that set:
- Takeaway rests on 29 swings, and the address plane coming down on 9.
- **One zone per metric covers every club.** Among the pros, long clubs against short clubs differ by a fifth to a third of a zone on the club metrics (hands at address +6%, shaft halfway back +6%, transition +5°) and by 1–3 units on the body metrics. The split is by the club's length on screen, which is rough; a real club reading is needed before zones go per club.
- The clips are still noisier than a tripod range clip.

### Drawings

Each drawing has up to three parts, the same in every metric:
- **White**: where the golfer was at address, or a fixed guide.
- **Shaded green**: where good players end up (the zone): a strip for a position, a fan for an angle, a box for the head or hands.
- **The swing now**: green in zone, amber at levels 1–3, red at 4 and over.

Head height and head depth share one picture, as do hands height and hands out, so either can lead a fault and still be drawn.

## What the golfer is told

A golfer already overthinks, so the rules lean toward saying less (`CoachingFeedback`):

1. Out-of-zone metrics that describe the same fault are folded together (hip depth, posture, head height, hands height and trail knee at impact are all "standing up through impact"). Each fault is mentioned once, by the metric that shows it best.
2. A fault has a **score**: level × the metric's weight × confidence, raised by a quarter for each other metric of the fault that agrees.
3. A swing whose worst fault scores under 3.5 is a **good swing**. No pointers. That takes about a level 4, or two agreeing metrics; a level 3 on its own is not enough.
4. Otherwise the swing gets **one** fault: its worst.
5. A fault becomes a session **theme** once at least 4 swings, and half of the swings where it could have been seen, show it at level 2 or more. Opposite directions are counted apart: clubhead inside the hands and clubhead outside the hands are different themes, each counted on its own metric. Steep coming down, under the plane coming down and standing up through impact are each one fault whichever of their metrics shows it, counted against every swing where any of those metrics was measured. Themes are ordered by share × median level × weight; an earlier-in-the-swing theme within a quarter of the strongest leads instead, because a backswing fault often causes the downswing one. The session summary shows the first three.
6. Once there is a theme, per-swing feedback stays on it: the theme is the pointer whenever the swing shows it at a score of 2.5 or more. Another fault replaces it only at level 6 or more and twice the theme's score.
7. A swing where the theme's metric is back in zone, no other metric of that fault is out, and nothing else is worth a pointer, is **"That's better"**. Out on the other side of the zone doesn't count.
8. When half the swings go one way on a metric and half the other (clubhead inside on four, outside on four), neither is a theme: that is inconsistency, not a fault.
9. A swing's verdict uses the session's themes only once every earlier swing of the session has been coached. Until then it is judged on its own, so the pill doesn't depend on which swings happen to have been opened. Opening a swing queues the ones before it.

The 3.5 was set against the pros: 79 of the 94 judged pro swings (84%) come out "good swing", and treated as sessions the pros produce no theme. On the four range sessions 101 of 151 judged swings (67%) are good on their own. Judged in order with the session's themes applied, as the pills read, 71 are good or "that's better" and 80 get a pointer, nearly all of them the session's theme again. That is a lot of repeats for a golfer who wants to hear less; the recap-every-few-swings flow in the playground is the quieter alternative, and which is the default is still open.

## In the app

- **Swing detail and Auto review:** a pill under the top bar shows the verdict. The first tap pauses on the position the fault was measured at and draws it; the next tap opens every measurement grouped by position. Tapping a measurement jumps to it.
- **Drawings** show while the playhead is within one position slot of the frame they were measured on, so they hold when paused there and pass by when playing.
- **What is drawn:** the coach decides by default. It draws the one fault the verdict names, by every metric that shows it (standing up through impact can draw the hip line, the trail knee and the head box together), and **nothing on a good swing**, however many measurements sit a little outside their zones. In the measurement list, the eye on a check always draws it or never draws it, "Draw every check" draws them all, and "Let the coach decide" clears both. Choices apply to every swing.
- **Library:** the golfer icon on a session header opens Session coaching: swings measured, good swings (counted the way the swings' own pills read, "That's better" included), swings not judged, and the three strongest things that kept happening with "Start here" on the first. Opening it coaches the session's swings.
- **Settings › Coaching:** drawings on or off, and "Coach swings during Auto".

Coaching runs in the background, one swing at a time, when a swing is opened or a session summary asks. It is **off during Auto by default**: reading each saved clip beside the camera has not been checked on a phone for dropped frames or heat. While Auto is recording nothing runs: a swing being coached when Auto resumes from review is stopped and goes back to the front of the queue. A swing deleted while it is being coached saves nothing.

Results are saved under Application Support/`SwingCoaching`: `<swing id>.report.json` (small, what the UI reads) and `<swing id>.evidence.json` (about 100 KB). A report with an older `version` is re-scored from stored evidence without touching the clip; evidence with an older version is rebuilt from the clip.

## Checked so far

On a Mac, with the app's own code, on real range sessions exported from the phone:

| Session | Swings | What kept happening (swings, median level) |
| --- | --- | --- |
| 23 Oct 2026 | 48 | Trail knee moves out toward the ball (38 of 43, level 3) |
| 6 Nov 2026 | 35 | Clubhead inside the hands at takeaway (10 of 18, level 7); trail knee moves out (24 of 29, level 3) |
| 7 Nov 2026 | 35 | Clubhead inside the hands (23 of 23, level 5); trail knee moves out (28 of 31, level 3); shaft flat halfway back (25 of 31, level 2) |
| 15 Nov 2026 | 52 | Shaft flat halfway back (28 of 47, level 3); head stays up through impact (36 of 48, level 3) |

"Trail knee moves out" and "head stays up" are both "standing up through impact", led by whichever of its metrics showed it most often that day.

The golfer's median against the pros' middle 70%, across the judged swings:

| | Range sessions | Pros |
| --- | --- | --- |
| Trail knee at impact | +10% toward the ball | −1 to 8% |
| Head height at impact | −1% | −12 to −3% |
| Hip depth at impact | +2.7% toward the ball | −3.5 to 3% |
| Posture at impact | −5° | −6 to 6° |
| Shaft halfway back | +8% outside the ball | −29 to 3% |
| Transition | +4° steeper | −16 to 6° |
| Takeaway | +4% | 4 to 26% |
| Hands at impact | +3.6% out, +4.3% up | 0.5 to 7%, 2.5 to 10.5% |

### Club readings move with the camera; body readings don't

Splitting the judged swings by session and by club setup (address posture under 26° is the long club) shows which readings can be trusted:

| | 23 Oct | 6 Nov | 7 Nov | 15 Nov | Pros' middle 70% |
| --- | --- | --- | --- | --- | --- |
| Trail knee at impact | +9 to +11% | +10 to +11% | +9 to +11% | +7 to +10% | −1 to 8% |
| Hip depth at impact | +2 to +3% | +1 to +2% | +3 to +5% | +1 to +3% | −3.5 to 3% |
| Head height at impact, short club | +1% | +1% | +2% | +2% | −12 to −3% |
| Posture at impact, short club | −9° | −9° | −10° | −8 to −12° | −6 to 6° |
| Shaft halfway back | −14 to +1% | +7% | +11 to +14% | −3 to +19% | −29 to 3% |
| Transition | −3 to +1° | +2° | +7 to +11° | −1 to +12° | −16 to 6° |
| Takeaway | +3 to +11% | −20 to −12% | −21 to −8% | −19 to +11% | 4 to 26% |

The four body rows hold across four sessions, both clubs and wherever the golfer stood in the frame. The three club rows change from session to session, and on 15 November they flip from in zone to well out partway through, at the point where the golfer's and the ball's place in the frame changes.

A club reading from down the line is a picture of a 3D direction, and it changes with where the camera stands relative to the target line. Nothing here checks that. So:
- The body findings (trail knee out, hips toward the ball, and with the short club standing up through impact) are solid.
- The club findings (takeaway, shaft halfway back, transition) are **provisional**. They are marked `dependsOnCamera` and say so in the measurement list and the session summary. They need the camera on the hand line at hand height every session, and ideally a check that it is.

The pro zones for the club metrics include that same camera variety, which makes them wider than they would be from one fixed camera.

Lessons from getting here:
- Without club timing, the 15 November session reported "clubhead well outside the hands" on 26 of 39 swings. That was the early P2 frame, not the swing.
- With guessed zones, "lead arm above the shoulder plane" was a theme in three sessions. The pros do the same.
- With zones taken from all 168 pro clips, 60% of pros got a pointer. The flagged ones were clips that open on a rehearsal or where impact landed on the follow-through; the checks above came from that.

Check a new theme against the review sheets before trusting it.

A swing takes about 3.5 s on an M-series Mac: 2.3 s following the club, 0.6 s reading the ten position frames, 0.3 s for the outlines.

### Straight after impact (simulated)

In Auto the positions are ready 0.8 s after impact, from 480-wide copies of the camera frames held in memory, 30 per second ([SWING_POSITIONS.md](./SWING_POSITIONS.md)). Coaching could run on the same copies instead of waiting for the saved clip. `CoachingEvidenceExtractor.Configuration.liveCopies` reads a clip that way (30 samples a second, 480 wide, positions from the nearest sample), and the harness runs it with `COACH_MODE=live`.

On the 52 swings of 15 November, against the full clip:
- Body metrics are the same: the median difference is 0 to 1.5, under a step, and 91–100% of levels are within one.
- Club metrics are close (median difference about 1.5, 93–100% within a level) except takeaway (5.5%, one step; 67% within a level).
- The session's themes are the same two.
- The per-swing verdict matches on 36 of 52. Verdicts sit near the 3.5 line, so a small change in a reading flips them; themes don't move.

Work per swing in that mode: about 50 detector calls and 10 outlines on small frames, with pose already done by the positions step. **This is a Mac simulation.** It reads the saved clip to imitate the copies; nothing is wired into Auto and nothing has run on a phone.

**Not checked:** anything on a phone. How long a swing takes there, and whether coaching during Auto costs frames or heat, need a device run. The Simulator can't run Vision body pose, so there the UI is checked against stored reports only.

## Checking a change

```bash
scripts/verify.sh coaching
```

runs `SwingCoachingUITests` (the `coaching` launch fixture: five swings with stored reports) and `SwingCoachingTests` (levels, measurements on synthetic evidence, club timing, the not-judged checks, the feedback rules).

No test covers the store's queue (pausing for Auto, a swing deleted mid-run) or checks a drawing's shapes against its number; both were reviewed by reading and by the review sheets.

To see the numbers and drawings on real swings:

```bash
detector_workbench/validation/coaching/run.sh ~/Downloads/15:11_range_session /tmp/coaching-1511 --limit 10
open /tmp/coaching-1511/review/index.html
```

The harness compiles the app's coaching sources on macOS, writes `evidence.json`, `report.json` and the ten position frames per clip, and `session.json` with the themes and per-swing verdicts (`alone` is the verdict with no session behind it). `review.py` draws each metric on its frame and lists the session's numbers. Evidence is reused between runs, so a change to metrics or zones re-scores in seconds; delete a clip's folder to rebuild its evidence.

Interaction mock-ups of coaching in Auto and at home, on real swings: [UI playground](./UI_PLAYGROUND.md#coaching-flows).

## Next

- A phone run for speed and heat, then wire coaching to Auto's live copies so the verdict is there when the swing's thumbnail appears.
- A camera-placement check at setup (hand line, hand height), so club readings mean the same thing every session.
- A better club source for the level-shaft and top-of-swing frames, a real club and swing-type reading, and zones per club. The dataset for one model that sees all of this is being curated in `../detectSwings`.
- The clubhead path as a drawing, face-on metrics, then voice and drills on top of the verdicts.
