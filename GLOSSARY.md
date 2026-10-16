# SwingCoach

SwingCoach is a golf-coaching product that turns recorded golf swings into reviewable clips and evidence-backed coaching.

## Language

**SwingCoach**:
The golfer-facing product and the integration boundary for capture, swing collection, review, and coaching.
_Avoid_: training ground, model research repo

**detectSwings**:
The sister experimentation workspace where golf models are developed, trained, benchmarked, and validated before product integration.
_Avoid_: app repo, production app

**Practice session**:
A bounded period of rolling capture that groups a golfer's detected swings for review and coaching selection.
_Avoid_: analysis run, recording

**Swing detection**:
The decision that a golf swing occurred within continuous capture, together with the time window to retain as a swing clip. Swing events may contribute evidence, but a full event timeline is not required.
_Avoid_: event timing, coaching analysis

**Swing event detection**:
The estimation of the P1 through P10 positions within a swing. A validated event detector may also contribute evidence that a swing occurred.
_Avoid_: metric calculation, coaching diagnosis

**Capture frame rate**:
The number of frames recorded per second of real movement. In our range-footage discussions, "240 fps video" and "120 fps video" refer to capture frame rate, even when the exported video plays at 30 fps.
_Avoid_: playback frame rate, video duration

**Playback frame rate**:
The number of frames shown per second on the exported video's timeline. Our iPhone slow-motion exports usually play at 30 fps and already contain the stretched duration.
_Avoid_: capture frame rate

**Source video time**:
A position or duration on the supplied video's playback timeline, including any slow-motion stretching. Labels and player timecodes refer to this timeline.
_Avoid_: real swing time

**Real swing time**:
Elapsed time during the original movement. One minute of real movement recorded at 240 fps becomes eight minutes of source video time when exported entirely at 30 fps.
_Avoid_: playback duration

**Slow-motion factor**:
The ratio of source video time to real swing time. A 240 fps recording exported at 30 fps has an 8× factor; a 120 fps recording exported at 30 fps has a 4× factor.
_Avoid_: capture frame rate, extra frames

**Swing checkpoint**:
A frame or short window around any P1 through P10 position used to inspect or compare visible swing evidence. Its coaching value depends on the finding and evidence quality, not on whether it belongs to the backswing or downswing.
_Avoid_: event, metric, keyframe

**Coaching focus**:
The single swing behavior a golfer chooses to work on during a practice session, such as early extension.
_Avoid_: goal, issue, metric

**Coaching**:
The process of turning swing evidence into a prioritized explanation and a practice action. It combines visual annotations, metrics, coaching voice, drills or feels, and later comparison.
_Avoid_: analysis result, metric, live cue

**Visual annotation**:
Phase-anchored markup on a swing video that shows the golfer the visible evidence behind a coaching finding.
_Avoid_: metric, decoration, drawing

**Metric**:
A named quantitative measurement derived from swing evidence, with an explicit reference, confidence, and interpretation.
_Avoid_: score, finding, detector confidence

**Coaching finding**:
A prioritized conclusion about what the golfer should work on, supported by trustworthy visual evidence, measured evidence, or both, together with confidence.
_Avoid_: raw detection, metric, summary

**Coaching voice**:
The spoken or written explanation that connects a coaching finding to its evidence, effect on the swing, and next practice action.
_Avoid_: generic summary, annotation, metric

**Drill**:
A practice exercise or physical constraint chosen to change a coaching finding and make progress observable in later swings.
_Avoid_: tip, explanation

**Feel**:
A golfer-facing movement intention or sensation used to produce a change without claiming to describe the body's literal motion.
_Avoid_: metric, fact, drill

**Feedback loop**:
The repeated cycle of observing swing evidence, choosing a coaching finding, applying a drill or feel, and checking later swings for change.
_Avoid_: analysis run, practice session

**Live cue**:
A short spoken observation about the active coaching focus, delivered after a detected swing and before the golfer's next attempt.
_Avoid_: live analysis, notification, full coaching result

**Capture tone**:
An optional sound confirming that SwingCoach detected and retained a swing clip. It confirms capture rather than coaching quality.
_Avoid_: live cue, score
