# Coaching: metrics and drawings (on the phone)

The app measures each down-the-line swing on the phone and draws what it measured on the video. No backend and no AI model call: Vision and the club detector find the body, club and ball, and plain geometry scores them against what tour pros do.

It gives four things:
- **Per swing:** up to 21 measurements, each with a level and a drawing on the frame it was measured at.
- **One line per swing:** "Good swing", "That's better", the one fault worth a thought, or "not judged" with the reason.
- **Every few swings in Auto:** a recap of what the last 5 or 10 had in common, with the swings side by side.
- **Per session:** the faults that kept repeating, pictured and charted swing by swing.

Voice and drills are not built. The earlier server-side coaching (a backend, the Coach tab, "Analyze Swing") was removed in November 2026.

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
| Background queue, live readings and saved results | `SwingCoachingStore.swift`, `CoachingLiveJoin.swift` |
| The walkthrough's order (verdict first, then the other faults in swing order) and the club-head trail | `CoachingWalkthrough.swift` |
| In the player: step card, drawings, club path, marks on the pose strip, the Layers tool, every check | `SwingCoach/CoachingPlayerViews.swift` |
| Session review | `SwingCoach/SwingCoachingViews.swift` |
| On the Auto camera screen: coach chip, latest verdict, recap, comparison | `SwingCoach/AutoCoachingViews.swift` |

Coaching starts from the swing's P1–P10 ([SWING_POSITIONS.md](./SWING_POSITIONS.md)). It needs the app's own copy of the clip.

### When a swing is measured

- **Every Auto swing is queued** as soon as it has positions, so a session's swings all have coaching in the Library without being opened. Opening a swing or a session review queues what it needs too, and the swing being looked at goes first.
- **Clips are read only while Auto is not recording**: paused for review, or stopped. A clip being read when Auto resumes is stopped and goes back to the front of the queue. Reading clips beside the camera has not been checked on a phone.
- **With "Measure swings while Auto records" on** (Settings › Coaching, off by default), a swing also gets a **first reading** as it is saved, from the copies of its frames Auto already holds in memory. See [The first reading during Auto](#the-first-reading-during-auto). The clip's reading replaces it later.

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
- **Shaded green**: where good players end up (the zone): a strip for a position, a fan for an angle, a box for the head or hands. Its edge has the measured line's dark outline at a lighter weight, so it holds on grass and mat.
- **The swing now**: green in zone, amber at levels 1–3, red at 4 and over.

A guide, and every check on a swing that isn't judged, is drawn in the neutral guide style instead: the swing's line grey and a guide's zone white, never green, so it never reads as in zone. Their thumbnails in All checks are drawn the same way.

Head height and head depth share one picture, as do hands height and hands out, so either can lead a fault and still be drawn.

## What the golfer is told

A golfer already overthinks, so the rules lean toward saying less (`CoachingFeedback`). A finding's title (each metric's `below` / `above` words) says what the swing did, in the past tense and a few words: "Head didn't drop into impact", "Shaft steepened coming down", "Trail knee moved out toward the ball". It never reads as something to do, so the words carry the meaning without the red badge. The session tables below quote the wording of their day.

1. Out-of-zone metrics that describe the same fault are folded together (hip depth, posture, head height, hands height and trail knee at impact are all "standing up through impact"). Each fault is mentioned once, by the metric that shows it best.
2. A fault has a **score**: level × the metric's weight × confidence, raised by a quarter for each other metric of the fault that agrees.
3. A swing whose worst fault scores under 3.5 is a **good swing**. No pointers. That takes about a level 4, or two agreeing metrics; a level 3 on its own is not enough.
4. Otherwise the swing gets **one** fault: its worst.
5. A fault becomes a session **theme** once at least 4 swings, and half of the swings where it could have been seen, show it at level 2 or more. Opposite directions are counted apart: clubhead inside the hands and clubhead outside the hands are different themes, each counted on its own metric. Steep coming down, under the plane coming down and standing up through impact are each one fault whichever of their metrics shows it: a swing counts when any of them is at level 2 or more, against every swing where any of them was measured. Themes are ordered by share × median level × weight; an earlier-in-the-swing theme within a quarter of the strongest leads instead, because a backswing fault often causes the downswing one. The session summary shows the first three.
6. Once there is a theme, per-swing feedback stays on it: the theme is the pointer whenever the swing shows it at a score of 2.5 or more. Another fault replaces it only at level 6 or more and twice the theme's score.
7. A swing where the theme's metric is back in zone, no other metric of that fault is out, and nothing else is worth a pointer, is **"That's better"**. Out on the other side of the zone doesn't count.
8. When half the swings go one way on a metric and half the other (clubhead inside on four, outside on four), neither is a theme: that is inconsistency, not a fault.
9. A swing's verdict uses the session's themes only once every earlier swing of the session has been coached. Until then it is judged on its own, so the pill doesn't depend on which swings happen to have been opened. Opening a swing queues the ones before it.

The 3.5 was set against the pros: 79 of the 94 judged pro swings (84%) come out "good swing", and treated as sessions the pros produce no theme. On the four range sessions 101 of 151 judged swings (67%) are good on their own. Judged in order with the session's themes applied, as the pills read, 71 are good or "that's better" and 80 get a pointer, nearly all of them the session's theme again. That is a lot of repeats for a golfer who wants to hear less, so on the camera screen the default is a recap every five swings, not a verdict after each one. The pill on an opened swing still gives that swing's verdict.

10. A **recap** covers a few swings in a row. Its theme is the strongest fault that at least three of them, and half of those where it could be seen, show at level 2 or more; with none, nothing kept repeating.

## In the app

### In the player (Library and Auto review)

Library and Auto review use the same player, the same top row (Done, "Swing 3 of 5" counted in the order hit, the star) and the same coaching.

- **Opens on the coach's first step.** Every way into a swing (Library card, Auto thumbnail, the verdict on the camera screen, a session dot) opens it paused on the frame of its first step, with that step's drawing up. No tap is needed.
- **The step card** under the video is kept compact and low (7-point vertical padding, 3-point rows, 44-point buttons, a 28-point All checks capsule that still takes a 44-point tap, the legend wrapping onto as few lines as it needs, 2 points above the scrubber) and says where in the swing and which finding it is ("Halfway down, finding 1 of 2"; "step" is kept for the level, "4 steps out"), the one sentence, its level as the badge with a word (`CoachingLevelPill`: "4 steps out", "✓ In zone", "– Not judged"; "N steps out" is the one phrase for a distance outside the zone everywhere) so the number never reads as a count, for a club check "Depends on camera position" beside it on one short line (the detail is in All checks), and which colour is which (Address, Good players, This swing). The numbers stay in All checks. Colour is never the only cue.
- **Steps:** first the verdict: the one pointer, "Good swing" (its main check in zone at impact, or where most are, drawn green), "That's better", or "not judged" with the reason and nothing drawn. Then every other fault on the swing, one step each, in swing order (`CoachingWalkthrough`). Supporting checks of the same fault on the same frame belong to the step, drawn with it only under "Every check on the frame". Next and Back move between steps; the last step's main button is Play swing.
- **On a step** the drawing builds up: address in white (thinner and dimmer than the swing's own line, so where they meet they don't stack into one blob), then the green zone, then the swing in its level's colour. The dot that marks the reading is the strongest mark; a ring (the head, now and at address) is a thin solid outline, so the rings and the zone never outshout it, and the reading inside the head's ring is a small hollow marker with the dark outline, so the face shows through. Only the step's own finding gets a name tag, placed beside the drawing at the height of its line (right of it, else left, above or below; clear of the tool rail and the top row), not on the golfer's head; a head check's tag goes above first, a further ring's height up, so it sits in clear space over the hat. Only the step's own finding is drawn, so the eye goes to one place on the body; the checks supporting it, and the other checks in zone on a "Good swing" step, are drawn only with "Every check on the frame" on, where every drawing keeps its tag. The legend keys the finding's drawing, and the video lifts for it alone. With Reduce Motion it fades in at once. If the drawing, or the club head on that frame (at the ball around impact), would sit under the card, the video lifts so it clears it, as far as the top row allows.
- **Playing:** each step's drawing appears at its own frame and holds, faded, until the next step's frame, so it can be read at speed. The club head's path draws as the swing plays.
- **Paused anywhere else** nothing is drawn, so a drawing only ever sits on the frame it was measured on. The card folds to one line with the first step and where it is ("Swing's top finding · at impact" over "Head didn't drop into impact", with a short "Findings" and a chevron, so the title gets the width; "Back in zone · …" for that's better), so it never reads as a verdict on the frame on screen; tapping it always goes back to the first step.
- **The pose strip** marks each position with a judged check: the furthest level out there in its colour, a tick when all are in zone, the badge pinned to its own chip's top-trailing corner inside the strip, with a clear gap to the scrubber above. VoiceOver says the level the same way ("up to 5 steps out"). The current position's chip is always filled white; on a walkthrough stop that is the step's position, even where the coaching timed it a frame or two off the position model (`PlayerWalkthroughStop`). VoiceOver says where the coach starts. Tapping a marked position shows its step.
- **All checks** (on the card; the sheet has the same title) leads with the whole swing ("11 of 16 checks in zone"), then the coach's verdict, labelled "Top finding" when it is one, then what the numbers mean ("A number is steps out. 1 step = a set distance past good players' zone, per check."). It lists every measurement by position ("Halfway back (P3)"), each with a picture of its frame and drawing, its reading against good players on a `CoachingZoneTrack` (the zone as a green band, the swing as a marker in its level's colour, and under it "You" and "Good players", each beside a small swatch of its mark (the dot, the band), with their values in the label size, and "Above zone" / "Below zone" / "In zone", in columns that line up row to row) and how many steps out it is; a club check says there that it depends on where the camera stands and to check it with the camera on the hand line. A guide, or any check on a swing that isn't judged, says "Not judged" and why ("a guide", "a chip or pitch") beside its name, with no in-zone wording, and its track is neutral: the zone a dashed outline with no fill, the swing a hollow ring. Picking one pauses on its frame and shows it on the card, with "Back to the coach".
- **The Layers tool** in the player's rail turns the coaching overlays, the club path, and every check on the paused frame on or off, in golf words; its sheet is titled "Layers" after the control, and its first toggle is "Coaching overlays". Draw, for adding your own marks, is a separate tool. The choice lasts for the review and covers every swing in it. While it differs from the coach's, the video says "Your layers" with Reset.
- **Reading:** a swing without a reading says "Reading this swing", about 10 seconds on a phone, and how many swings are ahead of it; while Auto records it says it starts when Auto pauses. A failed read says why with Try again. A first reading from Auto says "Body checks only" and that the club checks are coming; when the clip's reading replaces it the card says "Club checks added" and, if the verdict changed, what the body checks alone said. If the golfer hasn't moved through the steps, the player moves to the new first step.

### Club-head trail

The clip's reading follows the club from P1 to P9 (60 samples a real second, every frame through the downswing; see [Club timing](#club-timing)) and stores up to three club-head detections per sample in `evidence.track`. That is enough for a trail. `CoachingClubTrail` keeps one detection per sample, the one nearest the last kept point, drops a detection that sits still in most samples (a bag, a spare club) or jumps further than a club head can move, and fills gaps up to 0.12 real seconds in a straight line, drawn dashed. A first reading from Auto's copies has no track, so it has no trail until the clip is read. The trail is the accent lime, the club colour of the pose strip, never a level's colour: club readings depend on where the camera stands.

### Elsewhere

- **Auto camera screen:** a chip under the top bar sets when the coach speaks: every swing, every 5 swings (the default), every 10, or only when asked. Swings are measured either way.
  - *Every swing:* the latest swing's verdict sits above the saved-swings button as a card big enough to read from the tee ("Swing 5", the sentence, its level, Look); it opens that swing on its first step.
  - *Every 5 or 10:* when that many more swings of the session have been measured, a recap card comes up: the fault at least three of them (and half of those where it could be seen) shared, with its typical level as a pill ("5 steps out, typical"), a slot per swing (the shared `CoachingLevelBadge` at the session review's size and "Swing 3" under it, so severity reads by shape and number as well as colour), a picture of the swing that shows it most, captioned with the swing and its level ("Swing 5 ·" over "4 steps out"), and "Compare them". The theme's line says where it happened and names its denominator ("On 4 of 5 swings with a halfway-down (P5) reading", "On all 4 swings with …"). One plain key sits under the slots: "Number = steps out", with the tick ("In zone"), the dash ("Not judged") and an outlined badge ("Other way") keyed only when a slot has one. A badge is outlined, not filled, where the check was out the other way (a different fault, not the theme). The thumbnail's caption and each comparison tile carry the same badge as that swing. With nothing repeating it says so and how many needed no pointer. Swings already measured when the camera opened, or when the setting changed, are passed over, and deleting a swing doesn't bring an old recap back.
  - *Only when asked:* nothing comes up. "Recap the last swings" in the chip's menu shows the recap of the last five measured at any time, in every setting.
  - "Compare them" pauses Auto and shows the recap's swings side by side at the theme's position, each tile one capped height (4:5, `CoachingPreview.compareAspect`) with the frame cut toward the golfer and club (everything drawn on that frame) rather than sky and foreground, so more swings fit on the first view, each with the theme's drawing and its level spelled out ("2 steps out", "In zone", "Not judged"); a swing that wasn't judged has a tile of the same rounded bounds on a neutral fill, with the dash badge and "Not judged", and the legend's "This swing" shows every colour the tiles use. Tapping one opens it in the player on the check in the picture; Back returns to the comparison.
- **Library:** the Review button on a session header opens the session review:
  - the headline count in large type ("7 of 11 judged swings good"), with one line under it saying what good means: no fault far enough out for a pointer (rule 3 above), so smaller misses still count in the themes below; then a level badge a swing in the order hit, the player's `CoachingLevelBadge` (tick, level number, or dash for not judged), each a 44-point target that opens its swing, with a one-line key straight under them (tick good · number = steps out · dash not judged) and what a step is ("1 step = a set distance past good players' zone, per check": each check has its own step, see Metrics)
  - compact counts that name their denominators: "12 of 12 swings" measured and how many swings weren't judged; the good count in the headline is counted the way the swings' own pills read, "That's better" included
  - the three strongest things that kept happening, each with its typical level as a pill that says what the number is ("5 steps out, typical") and its share ("On 4 of 8 swings with a takeaway (P2) reading"), "Start here" above the first one's title in the secondary label style (never amber, so it doesn't read as a level), with two pictures of it: the swing that shows it most and the best one that doesn't, each captioned with the swing and where it sits against the zone ("Swing 8 · 6 steps out"; the signed numbers are in All checks); a footer says each count is out of the swings with a reading for that check
  - how the themes sit together in swing order, each with a neutral position tag, joined by a plain connector with no arrowhead and "Seen together on 4 swings": co-occurrence, not a claim that one causes the other
  - each theme's metric swing by swing against its green band

  Opening it queues the session's swings.
- **Settings › Coaching:** when the coach speaks in Auto, and "Measure swings while Auto records". Layers are chosen in the player.

Coaching runs in the background, one swing at a time. A swing deleted while it is being read saves nothing. Without measuring while Auto records, nothing is measured until Auto pauses or stops, so on the camera screen the verdict and the recaps only catch up then.

Results are saved under Application Support/`SwingCoaching`: `<swing id>.report.json` (small, what the UI reads) and `<swing id>.evidence.json` (about 100 KB). A report with an older `version` is re-scored from stored evidence without touching the clip; evidence with an older version is rebuilt from the clip. A first reading saves its report only (`fromLiveCopies`), and counts as not yet read from the clip.

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

### The first reading during Auto

In Auto the positions are ready 0.8 s after impact, found on small copies of the camera's frames held in memory: 30 a second, 480 × 270 as the sensor sees them, so 270 across once upright ([SWING_POSITIONS.md](./SWING_POSITIONS.md)). When the setting is on, `LiveSwingPoses` hands the swing's copies over with its positions and `CoachingEvidenceExtractor.extract(copies:positions:)` reads the ten position frames from them: pose, outline and club detector on each, 30 model calls a swing. The club is not followed between them.

That reading has the **body checks only**. The six club checks (`CoachingMetricDefinition.needsClip`: takeaway, shaft halfway back, transition, shaft halfway down, and the two address-plane guides) wait for the clip. A first reading is judged on the same rules, so it needs 8 of its 13 judged checks. It is joined to the swing once the swing is saved (`CoachingLiveJoin`), its times mapped from the recording onto the clip, and saved as the swing's report until the clip's reading replaces it. If swings are hit faster than they can be read, only the two newest wait; older ones are left for their clips.

How this was arrived at, on a Mac. `Configuration.liveCopies` reads a saved clip the way the copies are read and the harness runs it with `COACH_MODE=live`. Against the full clip on three range sessions (135 swings):

| | 23 Oct | 7 Nov | 15 Nov |
| --- | --- | --- | --- |
| Body metrics: median difference | 0 to 2.2 | 0 to 1.8 | 0 to 1.6 |
| Body metrics: levels within one | 86–100% | 94–100% | 90–100% |
| Body theme, clip | Trail knee out, 38 of 43 | Trail knee out, 28 of 31 | Head stays up, 36 of 48 |
| Body theme, first reading | Trail knee out, 34 of 40 | Trail knee out, 29 of 31 | Head stays up, 37 of 49 |
| Verdict of the same kind | 35 of 48 | 21 of 35 | 42 of 52 |

- The widest body differences are the hands at impact (they move fast, and the frame is up to half a slot off). Everything else is within a step.
- **The club readings did not hold**, which is why they are left out. With them in, on 15 November takeaway moved by a step (53% of levels within one) and became a theme the clip didn't have, and on 7 November transition read 2° steeper and did the same.
- Following the club at 30 samples a second changed none of the body readings, so it was dropped: that is 10 detector calls a swing instead of about 70.
- A swing's own verdict changes between the first reading and the clip on a fifth to two fifths of swings, mostly because the clip adds the club faults. The session's body themes don't move.

**This is a Mac simulation of the reading.** It reads the saved clip to imitate the copies. The hand-over from the camera and the join to the saved swing are built but **have not run on a phone**, and the Simulator cannot run them (no Vision body pose, no camera).

**Not checked:** anything on a phone. How long a first reading or a clip takes there, and whether the first reading costs frames or heat while Auto records, need a device run; `swing-coaching-live` and `swing-coaching` in the capture diagnostics carry the timings. The Simulator checks the UI against stored reports only.

## Checking a change

```bash
scripts/verify.sh coaching
```

runs `SwingCoachingUITests` (the `coaching` launch fixture: five swings with stored reports and a synthetic club track; with the synthetic camera they are the Auto session; `-ui-testing-coaching-reads <seconds>|fail` stands in for a clip read so the first-reading, reading and failed states can be checked), `CoachingWalkthroughTests` (step order, good and not-judged steps, the trail) and `SwingCoachingTests` (levels, measurements on synthetic evidence, club timing, the not-judged checks, the feedback rules, recaps and their schedule, the join of a first reading to its swing, the session review's examples).

No test covers the store's queue (pausing for Auto, a swing deleted mid-run, a first reading end to end) or checks a drawing's shapes against its number; both were reviewed by reading and by the review sheets.

To see the numbers and drawings on real swings:

```bash
detector_workbench/validation/coaching/run.sh ~/Downloads/15:11_range_session /tmp/coaching-1511 --limit 10
open /tmp/coaching-1511/review/index.html
```

The harness compiles the app's coaching sources on macOS, writes `evidence.json`, `report.json` and the ten position frames per clip, and `session.json` with the themes and per-swing verdicts (`alone` is the verdict with no session behind it). `review.py` draws each metric on its frame and lists the session's numbers. Evidence is reused between runs, so a change to metrics or zones re-scores in seconds; delete a clip's folder to rebuild its evidence.

Interaction mock-ups of coaching in Auto and at home, on real swings: [UI playground](./UI_PLAYGROUND.md#coaching-flows).

## Next

- A phone run of the first reading for speed, dropped frames and heat; then turn "Measure swings while Auto records" on by default.
- A camera-placement check at setup (hand line, hand height), so club readings mean the same thing every session.
- A better club source for the level-shaft and top-of-swing frames, a real club and swing-type reading, and zones per club. The dataset for one model that sees all of this is being curated in `../detectSwings`.
- The club-head trail on real range footage: it is built and drawn, but has only been seen on the fixture's synthetic track.
- Face-on metrics, then voice and drills on top of the verdicts.
