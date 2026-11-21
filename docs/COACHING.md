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
| The walkthrough's order (verdict first, then the other faults in swing order) and the clubhead trail | `CoachingWalkthrough.swift` |
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

Every metric is one number at one position, with a zone. Inside the zone the level is 0. Outside, the level counts steps from the zone, 1 to 10, signed by direction. There is no overall score. Where a finding is shown to the golfer, one plain word beside its badge says how far out it is, tied to the badge's colour by one threshold (`CoachingSeverity` in `Theme.swift`): "A little out" in amber at 1–3 steps, "Well out" in red at 4 or more, "In zone" in green. "N steps out" is said only in All checks' rows.

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
- **Shaded green**: where good players end up (the zone): a strip for a position, a fan for an angle, a box for the head or hands. Its edge is about 3 points on the player (`zoneEdgeWeight`, the shared drawing style) with the same dark halo as the shaft line, over a light 16% fill (20% for a head check's band), so it holds on green turf and mat. A zone is drawn along the axis its check measures: the takeaway's band runs from the grip down past the clubhead, so a head in zone sits inside it wherever the club hangs (report version 9 redraws stored readings from their evidence).
- **The swing now**: green in zone, amber at levels 1–3, red at 4 and over.

A guide, and every check on a swing that isn't judged, is drawn in the neutral guide style instead: the swing's line grey and a guide's zone white, never green, so it never reads as in zone. Their thumbnails in All checks are drawn the same way.

Head height and head depth share one picture, as do hands height and hands out, so either can lead a fault and still be drawn. The head is drawn as rings round the face's centre (the measured point): one solid ring for the head now, a thin dashed one, fainter still, for address. The rings are sized from the pose's head (face centre to neck, 0.85 of it, between 11% and 16% of body scale), so they take in the whole head of a golfer bent over the ball rather than sitting on the chin (report version 10 redraws stored readings from their evidence).

## What the golfer is told

A golfer already overthinks, so the rules lean toward saying less (`CoachingFeedback`). A finding's title (each metric's `below` / `above` words) says what the swing did, in the past tense and a few words: "Head stayed high at impact", "Shaft steepened coming down", "Shaft pointed outside the ball". It is one plain sentence, never a label and a sentence ("Shaft flat: …"). It never reads as something to do, so the words carry the meaning without the red badge. The session tables below quote the wording of their day.

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

Library and Auto review use the same player, the same top row (Done or Back as a capsule the star's height, "Swing 3 of 5" counted in the order hit, the star) and the same coaching.

- **Opens on the coach's first step.** Every way into a swing (Library card, Auto thumbnail, the verdict on the camera screen, a session dot) opens it paused on the frame of its first step, with that step's drawing up. No tap is needed. The player's tools start folded under "Tools" while the walkthrough shows, so the finding has more of the video; one tap opens them.
- **The step card** under the video is a glance from the tripod, kept compact and low (7-point vertical padding, one even gap of about 8 points between its rows' text, 44-point buttons, a 28-point All checks capsule that still takes a 44-point tap (`PanelCapsuleButtonStyle`), 8 points above the scrubber). It says where in the swing ("Halfway down") with a small counter of the findings ("1/2"; VoiceOver "Finding 1 of 2"; "step" is kept for the level, "4 steps out"), then the one sentence with its level badge before it (`CoachingLevelBadge` at 26 points, the one glyph badge: a tick, "!" amber, "!!" red, a dash, never a number; VoiceOver says "4 steps out", "In zone", "Not judged") and, out of zone, one plain word over the sentence in the level's ink saying how far, semibold at the body size since it carries the meaning beside the glyph (`CoachingWords.severity`: amber "A little out" for 1–3 steps, red "Well out" for 4 or more), then Back / Play swing / Next (`PanelButtonStyle`: Next is the card's primary action in the lime accent with a dark label, Play swing and Back stay grey; on the last step Play swing takes the accent). A swing that isn't judged adds the reason in one line. The card is the one place the finding is named while it shows: the drawing's tag gives way to it. The drawing's own colours tell the swing from the zone and address; the key to them (You, Good zone, Address), a club check's camera caveat and the numbers are in All checks. Colour is never the only cue: the badge carries a glyph and the title says what happened.
- **Steps:** first the verdict: the one pointer, "Good swing" (its main check in zone at impact, or where most are, drawn green), "That's better", or "not judged" with the reason and nothing drawn. Then every other fault on the swing, one step each, in swing order (`CoachingWalkthrough`). Supporting checks of the same fault on the same frame belong to the step, drawn with it only under "Show all drawings here". Next and Back move between steps; the last step's main button is Play swing.
- **On a step** the drawing builds up: address in white (thinner and dimmer than the swing's own line, so where they meet they don't stack into one blob), then the green zone, then the swing in its level's colour. The dot that marks the reading is the strongest mark. On the head, this swing is one solid ring in its level's colour with the shaft line's dark halo, and no dot inside. Paused on a walkthrough stop the address ring is left out, so the ring and its zone are the whole story; with "Show all drawings here", while playing and in pictures, address is one dashed light ring, 1 point at 25% opacity with a narrower halo, so it never competes with the measured ring or the zone's edge at phone size. The green zone is an outlined band (20% fill) drawn over the rings, a ring's radius wider on each side than the box the head's centre should be in (so the ring fits inside it when in zone, and the zone shows past both sides of the rings), cut away with a small gap under each ring, so the rings and the zone never meet over the face and the direction of the miss reads at a glance. Zones are filled light (16%) with an edge about 3 points wide carrying the shaft line's full dark halo, so the edge holds on turf while a wedge over the leg and the mat tints them less than the measured line. Only the step's own finding is drawn, so the eye goes to one place on the body. While the card shows, it names the finding and the drawing has no tag (VoiceOver still reads the drawing at its place); with the card folded or the controls hidden, the finding gets a name tag, placed beside the drawing at the height of its line (right of it, else left, above or below; clear of the tool rail and the top row), not on the golfer's head; a head check's tag goes above first, a further ring's height up, so it sits in clear space over the hat. The checks supporting it, and the other checks in zone on a "Good swing" step, are drawn only with "Show all drawings here" on, where every drawing keeps its tag. The legend keys the finding's drawing, and the video lifts for it alone. With Reduce Motion it fades in at once. The video's top sits at the same place on the walkthrough and off it (edge to edge, a portrait clip is anchored with its top at the safe area's top rather than centred), so it doesn't jump when the card comes and goes. If the drawing, or the clubhead on that frame (at the ball around impact), with room under it for the feet, would sit under the card, the video lifts so it clears it, as far as the top row allows or as far as the black band above a letterboxed clip goes, whichever is more (only sky moves into the band). While the card shows, the scrubber's position dots are hidden.
- **Playing:** each step's drawing appears at its own frame and holds, faded, until the next step's frame, so it can be read at speed. The clubhead's path draws as the swing plays.
- **Paused anywhere else** nothing is drawn, so a drawing only ever sits on the frame it was measured on. The card folds to one line with the first step as an action that says where it goes ("Jump to impact finding" over "Head stayed high at impact", the position's plain name lowercased; the transport row still names the frame on screen; on one line that shrinks a little, then truncates, with 10 points above and below and a chevron alone on the right ("Findings" to VoiceOver and Voice Control), so the title gets the width; "Jump to impact · back in zone" for that's better), so it never reads as a verdict on the frame on screen; tapping it always goes back to the first step.
- **The pose strip** marks each position with a judged check: the furthest level out there in its colour, a tick when all are in zone, the shared glyph badge (16 points: a tick, "!" or "!!", never a number) in a shallow slot at the top of its own cell, over the pose and never on it, with a clear gap to the scrubber above. VoiceOver says the level the same way ("up to 5 steps out"). Position names are 14 points; a low-confidence glyph sits in the same slot, before the badge. A position under 50% confidence has a dimmed pose in a dashed outline, and while it is the current position the transport row's left slot says so in words, a second line under its name with the low-confidence glyph ("Low confidence", condensed so the readout stays two lines), in the neutral grey. The current position's chip is always filled white; on a walkthrough stop that is the step's position, even where the coaching timed it a frame or two off the position model (`PlayerWalkthroughStop`). VoiceOver says where the coach starts. Tapping a marked position shows its step.
- **All checks** (on the card; the sheet has the same title) leads with the whole swing ("11 of 16 judged checks in zone", proportional digits; the top finding is the card behind, so it isn't repeated, and without one a line says nothing is far enough out to work on), then the sheet's one key (`CoachingLegend`) on one caption line: the rows' track, "You" and "Good zone" (`trackKey:`), and, when guides are listed, their dash badge and dashed range together as "Reference only" (`referenceKey:`), so no row repeats it and two check rows show at the first detent. The badges need no key: a tick, "!" and "!!", with the side and steps beside them. It lists every measurement by position ("Halfway back (P3)"), each with a 64-point picture of its frame cut toward its drawing, then, on a `CoachingZoneTrack`, the side and the steps in its level's ink ("Above zone · 3 steps out", "In zone"; the only place "N steps out" is shown), the zone as a green band with the swing as a marker in its level's colour, and the numbers in one caption with what they measure ("You +19% · Good zone −29% to +3% · % of body height"); its badge carries the level (VoiceOver reads it as the row's value); a club check has the shared caveat with what to do ("Depends on camera position. Check it with the camera on your hand line."). A guide says "Reference only" beside its name, the key's words for its dashed range; any check on a swing that isn't judged says "Not judged" and why ("short swing", "camera moved"); with no in-zone wording, and its track is neutral: the zone a dashed outline with no fill, the swing the same solid marker in grey. A range is named "Good zone" wherever it is named (`CoachingWords.zoneName`), a guide's too; the guide says "Reference only" and its range is dashed and grey, so a reading inside it doesn't read as in zone. Picking one pauses on its frame and shows it on the card, with "Back to the coach".
- **The Layers tool** in the player's rail turns the coach's drawings, the club path, and "Show all drawings here" ("Includes checks in zone when paused.") on or off, in golf words; its sheet is titled "Layers" after the control, is as tall as its rows, and its first toggle is "Coach's drawings". Draw, for adding your own marks, is a separate tool. The choice lasts for the review and covers every swing in it. While it differs from the coach's, the video says "Your layers" with Reset.
- **Reading:** a swing without a reading says "Reading this swing", about 10 seconds on a phone, and how many swings are ahead of it; while Auto records it says it starts when Auto pauses. A failed read says why with Try again. A first reading from Auto says "Body checks only" and that the club checks are coming; when the clip's reading replaces it the card says "Club checks added" and, if the verdict changed, what the body checks alone said. If the golfer hasn't moved through the steps, the player moves to the new first step.

### Club-head trail

The clip's reading follows the club from P1 to P9 (60 samples a real second, every frame through the downswing; see [Club timing](#club-timing)) and stores up to three clubhead detections per sample in `evidence.track`. That is enough for a trail. `CoachingClubTrail` keeps one detection per sample, the one nearest the last kept point, drops a detection that sits still in most samples (a bag, a spare club) or jumps further than a clubhead can move, and fills gaps up to 0.12 real seconds in a straight line, drawn dashed. A first reading from Auto's copies has no track, so it has no trail until the clip is read. The trail is the accent lime, the club colour of the pose strip, never a level's colour: club readings depend on where the camera stands.

### Elsewhere

- **Auto camera screen:** a compact chip in the top row beside the frame rate (`CoachingCadenceChip`, "Recap: 5"; "1", "10" or "ask" for the other choices; VoiceOver reads "Recap: Every 5 swings", and "Show Auto recap" in Settings is the same choice), never centred over the viewfinder, sets when the recap comes up: every swing, every 5 swings (the default), every 10, or only when asked. Swings are measured either way.
  - *Every swing:* the latest swing's verdict sits above the saved-swings button as a card big enough to read from the tee ("Swing 5", the sentence, its level, Look in the lime accent); it opens that swing on its first step.
  - *Every 5 or 10:* when that many more swings of the session have been measured, a recap card comes up, a glance kept low over the viewfinder: a picture of the swing that shows it most, as tall as the card and 96 points wide (`CoachingPreview.recapPictureWidth`), cut toward the golfer and club, with only that swing's number on its corner ("Swing 5"), its drawing's colour the card's one level (VoiceOver reads the picture with that swing's word); the fault at least three of them (and half of those where it could be seen) shared, as the title alone, with no badge or level word to disagree with the picture; a close button (`CloseButtonStyle`, drawn 28 points, 44 to tap), and "Compare last 5" (the recap's window, so the card reads as a pattern over swings, not one shot). It is on the same solid panel, radius and insets as the latest verdict (`solidPanelBackground()`). The count, each swing's level and the key are in the comparison; a club check's camera caveat is in All checks. With nothing repeating it says so with a tick (a dash when none could be judged), and the button reads "Look at them". Swings already measured when the camera opened, or when the setting changed, are passed over, and deleting a swing doesn't bring an old recap back.
  - *Only when asked:* nothing comes up. "Show recap now" in the chip's menu, with a leading symbol so it reads as an action apart from the options above it, shows the recap of the setting's window (5, or 10 at every 10) at any time, in every setting.
  - "Compare last 5" pauses Auto and shows the recap's swings side by side at the theme's position, under the count out of the judged swings ("On 4 of 5 judged swings", "On all 4 judged swings" when one wasn't judged; the reading count when the check couldn't be read on every judged swing), each tile one capped height (4:5, `CoachingPreview.compareAspect`) with the frame cut toward the golfer and club (everything drawn on that frame) rather than sky and foreground, so more swings fit on the first view, each with the theme's drawing and its badge with the severity word ("A little out", "Well out", "In zone", "Other way" for a swing out the other way); a swing with nothing to picture (not judged, or no reading) is a tile the same size on a neutral fill, with the dash badge and "Not judged" with its reason ("Short swing"), and a footer of just "Swing 1", never repeating it. The tiles keep swing order in a clean two-column grid, so the captions line up row by row; the header is the title and the count, with the key under them on one caption line, only for what the tiles draw (`picturedOnly:`: You, the zone, and Address only where it is the head's dashed ring); the legend's "You" shows every colour the tiles use. The full key and a club check's camera caveat are in All checks. Tapping one opens it in the player on the check in the picture; Back returns to the comparison.
- **Library:** the Review button on a session header opens the session review:
  - the headline count at a section heading's size ("7 of 11 swings good", `appTitle`, out of the swings judged; the caption under the marks says why any weren't), so "Start here" and its pictures come into view sooner; then a mark a swing in the order hit, a shape with no numeral (`CoachingLevelBadge`, the same glyph badge as everywhere: a tick for a good swing, the top finding's level as "!" in amber a little out or "!!" in red well out, so the two differ by shape too, a dash not judged), each a 44-point target that opens its swing (laid out 32 points tall, with a tight 6-point gap round the marks, so the rows sit close), with no key line, and one caption after them when some weren't judged ("1 not judged · short swing"); the good count in the headline is counted the way the swings' own pills read, "That's better" included
  - the three strongest things that kept happening, each with its typical level as a pill in the word tier ("!! Typically well out", the glyph badge) and one caption naming how many of the measured swings showed it and the check its level is read on ("4 of 8 measured · takeaway"; a club check's camera caveat is in All checks, with its words), "Start here" above the first one's title in the secondary label style (never amber, so it doesn't read as a level), that title a heading size up (`appTitle`) so it is read straight after the tally, with two pictures of it: the swing that shows it most and the best one that doesn't, both cut to the same golfer-centred 4:5 region (`CoachingFrameView.golferRegion`: the body checks' drawings at every position on both swings and the two pictured drawings, so body, club and ball, with a margin that reaches the feet, enlarged at most twice past filling the picture; club checks drawn elsewhere are left out, since their long lines run to the frame's edges) so the drawing is larger and the sky and turf are cut away, each named above the picture ("Shows it most", "Your best here") and captioned under it with the swing alone ("Swing 8"; the picture's colours carry its level, and the numbers are in All checks) (the share names its own denominator, so there is no footer)
  - how the themes sit together in swing order, each with a neutral position tag, joined by a plain connector with no arrowhead and "Seen together on 4 swings": co-occurrence, not a claim that one causes the other; one footer line, "Listed in swing order. Work on the earliest first.", gives the advice without a causal claim
  - each theme's metric swing by swing against its good zone: the range in words over the chart ("Good: +4% to +26%") and the band named "Good" in a gutter beside it, so the better place reads without a key

  Opening it queues the session's swings.
- **Settings › Coaching:** "Show Auto recap" (how often the recap comes up in Auto), and "Measure swings while Auto records". Layers are chosen in the player.

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
- The clubhead trail on real range footage: it is built and drawn, but has only been seen on the fixture's synthetic track.
- Face-on metrics, then voice and drills on top of the verdicts.
