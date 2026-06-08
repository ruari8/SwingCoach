# Swing Annotation Research Notes

## Source And Method

Target account: `https://www.instagram.com/domcaminitigolf/`.

`yt-dlp` could not extract the Instagram profile directly; the current extractor reports the Instagram user path as broken. Dom's Linktree confirms the same public coaching presence on Instagram and TikTok, so I used the public TikTok mirror at `https://www.tiktok.com/@domcaminitigolf`.

Sample: 20 recent public TikTok videos from `@domcaminitigolf`, downloaded with `yt-dlp` on 2026-06-08. I generated contact sheets for visual inspection and rough transcripts with Whisper `tiny.en`. Transcripts are useful for theme detection but should not be treated as exact quotes.

Representative sampled titles:
- `STOP ROTATING FROM THE TOP`
- `Don’t fix the spin out YET`
- `Don’t swing it from the inside YET`
- `Be careful when shallowing the club`
- `Fix your swing in the proper order`
- `Before and after`
- `NELLY KORDA SWING REVIEW`
- `Jon Rahm Swing Review`
- `Force the swing you want with feedback`

## What Dom Does Well

Dom rarely annotates everything. He freezes the swing at a meaningful checkpoint, draws one or two bold references, and explains cause and effect in plain language. The useful part is not the drawing by itself; it is the pairing of a visible checkpoint with a specific coaching claim.

His common structure:

1. Name the golfer and give a direct hook.
2. Start with setup or takeaway, not impact.
3. Freeze at one checkpoint and draw one visual proof.
4. Explain what that checkpoint causes later in transition or impact.
5. Show a drill or constraint that forces the intended change.

The dominant language pattern is: "you can see X here, which causes Y later, so do Z first." He often rejects symptom-first fixes: do not fix over-the-top, spin-out, or inside-out path until grip, alignment, setup, or top position explains why that motion exists.

## Frequent Visual Annotations

### 1. Address Shaft Plane

Visual: a long line through the club shaft at address, often extended through the body/ball area.

Spoken purpose:
- Shows whether the club starts on a usable plane.
- Later compares transition shaft to the original plane.
- Often tied to posture: shaft pointing at belt buckle versus belly button.

Implementation:
- Keep `club_plane` as a primary default-on layer.
- It should persist across the full video or at least from address through impact.
- Use `"club shaft"` prompting for shaft work.

### 2. Shaft At Lead-Arm Parallel

Visual: line along shaft when lead arm is roughly parallel to the ground.

Spoken purpose:
- "Shaft points back at the golf ball" is treated as a good checkpoint.
- Too shallow means the shaft points outside the ball.
- Too steep means it points behind the heels or too upright.

Implementation:
- Add/keep a `shaft_checkpoints` layer with address, takeaway/lead-arm-parallel, top, transition, and delivery lines.
- This should not flash for one frame. Current renderer behavior should show each checkpoint for a short inspection window around the phase; a still-position review mode remains a good next UI step.

### 3. Clubhead Covering Hands

Visual: line or marker showing clubhead relative to hands from down-the-line.

Spoken purpose:
- Good takeaway often has the clubhead covering or slightly outside the hands.
- A clubhead too far inside/behind hands predicts a shallow/flat backswing and later steepening.

Implementation:
- Add a named guide under `takeaway_checkpoint`.
- This is more coachable than a generic skeleton.

### 4. Hands Through Bicep / Hand Depth

Visual: line or circle around the hands at takeaway/top, sometimes compared against torso landmarks.

Spoken purpose:
- Hands through bicep suggests the body has turned enough.
- Hands over heels at the top is better than hands over toes or middle of foot.
- High hands with low body turn often causes a loop/drop compensation.

Implementation:
- Keep `hand_depth`, but default it off unless confidence is high.
- Make this a position-review overlay rather than a constantly animated path.

### 5. Lead Arm Versus Shoulder Plane

Visual: shoulder-plane line and lead-arm line at the top.

Spoken purpose:
- "Lead arm matches shoulder plane" is a recurring good checkpoint.
- Lead arm above shoulder plane/high hands is called out as a source of transition compensation.

Implementation:
- Keep `lead_arm_plane` available, default off.
- It should appear at top-position review and be toggleable separately from generic body reference lines.

### 6. Clubface / Lead Wrist Match

Visual: line or box around lead wrist and clubface at the top.

Spoken purpose:
- Clubface matching lead arm is a key "square" checkpoint.
- Toe hanging down/open face explains stalling, flipping, and over-the-top compensations.
- Grip trainer recommendations are frequently tied to this visual.

Implementation:
- Add a future `clubface_wrist` layer once we have reliable clubface/wrist orientation.
- Until then, do not claim clubface angle from weak evidence.

### 7. Setup Alignment

Visual: target line plus parallel body/alignment line, usually with alignment sticks.

Spoken purpose:
- Clubface aims at target; feet/knees/hips/shoulders/body parallel to target line.
- Bad alignment is framed as a root cause for over-rotation and pulls.

Implementation:
- Keep `setup_geometry`, but split into specific toggles later:
  - target line
  - body alignment
  - stance width
  - ball position
- Default off until we can detect target/ball line reliably.

### 8. Face-On Setup Lines

Visual: shoulder tilt line, stance width, ball-position marker, hand-position marker.

Spoken purpose:
- Driver ball position under lead armpit/lead foot instep.
- Upper body tilted back and away from target.
- Grip V's pointing toward trail shoulder.
- Lead hip bump and foot flare show up as setup recommendations.

Implementation:
- This needs face-on-specific overlays. Do not reuse DTL plane labels for FO video.
- Add stance/ball-position markers only when the ball and feet are detected confidently.

### 9. Transition Shaft Path

Visual: shaft line in transition, compared to shoulder/ear/trail forearm/original plane.

Spoken purpose:
- Shaft through trail forearm is frequently described as a good shallow delivery checkpoint.
- Shaft through shoulder/ear is used to show steep transition.
- He often explains whether a "shallow" look is good or just a compensation.

Implementation:
- This should be one of the highest-priority automated overlays.
- `shaft_checkpoints.delivery` should show a line at delivery and a label like "trail forearm" or "steep" only when confidence is high.

### 10. Drill / Constraint Objects

Visual: physical alignment stick, noodle, or obstacle behind the hands.

Spoken purpose:
- He uses feedback constraints to force a movement, especially "stick two feet behind you just above your hands."
- The drill is visually shown after the diagnosis, not mixed into the diagnosis frame.

Implementation:
- Manual drawing tools matter. Users/coaches should be able to draw a training-stick line, arrow, circle, and label on a still or full swing.
- Add saved manual templates later: alignment stick, shaft plane, hand-depth gate.

## What We Should Copy

- Full source-duration playback. Dom's explanations depend on context before and after the checkpoint.
- Few default overlays. Use the strongest two or three automatically, not everything.
- Position-specific overlays. Let users inspect address, takeaway, top, delivery, and impact as still checkpoints.
- Persistent references. Address plane/head/hip lines should remain long enough to compare against later positions.
- Inspection windows. Phase-specific shaft/top/takeaway annotations should stay on screen long enough to pause or scrub through them.
- Cause/effect labels. A useful overlay should answer "what does this prove?"
- Before/after comparison support. Several clips rely on visual contrast more than raw metrics.

## What We Should Avoid

- Generic skeleton as a default. Dom does not use full body skeletons as primary coaching proof.
- Confidence badges over the video by default. Confidence belongs in metadata or a details panel unless it directly affects a claim.
- One-frame flashes. If an annotation appears for 0.1 seconds, it is not coachable.
- Metric-heavy overlays while the measurement basis is weak. Dom's breakdowns are checkpoint-led, not number-led.
- Multiple unrelated lines at once. Each visual should support the current spoken/coaching point.

## Recommended Product Annotation Set

Default on:
- `club_plane`: address shaft plane, persistent.
- `shaft_checkpoints`: key shaft lines at takeaway/top/delivery when confident.
- `clubhead_path`: clubhead trace through analyzed swing window when available.
- `head_reference`: address head height/position reference.
- `takeaway_checkpoint`: clubhead relative to hands.

Available but default off:
- `skeleton`
- `reference_lines`
- `setup_geometry`
- `hip_depth`
- `hand_depth`
- `lead_arm_plane`
- `ball_contact`
- `phase_markers`
- `confidence`
- `speed`

Future layers worth adding:
- `clubface_wrist`: clubface matching lead arm, open/closed face evidence.
- `alignment_target`: target line and parallel body line.
- `ball_position`: FO ball position relative to lead foot/armpit/ear.
- `drill_constraints`: saved manual stick/noodle/gate templates.

## UI Implications

- Keep the vertical rail, but every server-backed layer must be reachable there, not just the first few.
- Show short labels with icons. Repeated slash-line icons make the rail hard to parse.
- Add a checkpoint/stills mode when the number of useful overlays exceeds live-video screen space.
- The layer toggle should affect client-rendered JSON tracks over clean video. Avoid burned-in overlays as the normal path.
- Manual drawing should feel like coach markup: line, arrow, freehand, rectangle, circle, label, eraser, undo, color swatches, and full-swing versus moment scope.

## Open Follow-Up

This pass used public TikTok mirrors because Instagram extraction was blocked. A better future research pass would use authenticated Instagram cookies or direct creator-approved exports, then run a stronger transcription model and timestamp visual annotations frame-by-frame.
