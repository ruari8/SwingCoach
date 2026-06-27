# Dom Caminiti Video Annotation Reference

## Scope

Research pass for SwingCoach's next video-annotation pipeline.

Target account: `https://www.instagram.com/domcaminitigolf/`

Collected on: 2026-06-21

Purpose: identify the visual annotation vocabulary and explanation pattern to use as reference material for SwingCoach's automated overlays. This is inspiration and product research only; SwingCoach should keep original visual styling, wording, and pedagogy.

## Collection Method

`yt-dlp` could not extract the Instagram reels profile directly, and `instaloader` returned a 403-style profile lookup failure. `gallery-dl` could enumerate public reel metadata and direct media URLs without authenticated cookies. I fetched 42 public reel metadata records, sorted by publish timestamp, and selected the latest 15 public videos.

Local research artifacts are intentionally under the ignored media workspace:

- Manifest: `.videos/domcaminiti_reference/latest15/manifest.json`
- Dense 1 FPS sheets: `.videos/domcaminiti_reference/latest15/sheets/`
- Compact overview sheets: `.videos/domcaminiti_reference/latest15/overview_sheets/`
- Combined overview index: `.videos/domcaminiti_reference/latest15/domcaminiti_latest15_overview_index.jpg`
- Machine transcript JSON: `.videos/domcaminiti_reference/latest15/transcripts/`

The dense sheets are timestamped at 1 FPS. They are intended for annotation review, not redistribution.

## Current SwingCoach State

The backend is currently in `annotation_reset` mode.

What the live pipeline does now:

- Reads video metadata.
- Extracts the full source timeline.
- Writes `base.mp4`.
- Writes `annotated.mp4` as the same clean video for compatibility.
- Writes `annotation_metadata.json` with no layers.
- Writes `annotation_tracks.json` with normalized per-frame timing records and empty `layers`.
- Returns a reset coaching summary.

What the live pipeline deliberately does not run:

- Pose estimation.
- Event/phase detection.
- SAM3 equipment prompting.
- Shaft/clubhead tracking.
- Body 3D recovery.
- Metric cards.
- GLTF replay export.

Important existing pieces:

- `SwingDetailView` already presents a carousel: original video, analyzed video, coach notes.
- `AnalysisResultView` already overlays client-rendered JSON tracks on clean video.
- `ManualAnnotationStore` already supports local line, arrow, freehand, rectangle, circle, label, eraser, undo, colors, and all-swing versus moment scope.
- `visualization_config.py` already names the likely future layer set: `club_plane`, `shaft_checkpoints`, `clubhead_path`, `setup_geometry`, `head_reference`, `hip_depth`, `hand_depth`, `lead_arm_plane`, `takeaway_checkpoint`, plus legacy `skeleton`, `reference_lines`, `ball_contact`, `phase_markers`, `confidence`, and `speed`.
- Commit `abc12c4` contains the previous experimental implementation. It generated normalized overlay tracks, guide shapes, phase markers, confidence evidence, a persistent club plane, clubhead path, head/hip references, hand-depth guides, lead-arm-plane guides, and ball-contact luma evidence, but it was rolled back so the annotation contract could be redesigned.

Guardrails still apply:

- Use `detect_shaft()` with prompt `"club shaft"` for shaft/plane work.
- Use context managers for heavy detectors.
- Confidence is a first-class output. Low confidence should withhold an overlay rather than draw a misleading one.

## Latest 15 Public Reels

| Rank | Date | Shortcode | Caption | Dense Sheet |
|---:|---|---|---|---|
| 1 | 2026-06-21 01:06 | `DZ1DCbAgYTk` | comment PICK ME for a free review of your swing | `.videos/domcaminiti_reference/latest15/sheets/01_202606210106_DZ1DCbAgYTk_1fps_sheet.jpg` |
| 2 | 2026-06-20 02:27 | `DZynZu9goX0` | If you cannot watch this for 2 mins, I cannot help you | `.videos/domcaminiti_reference/latest15/sheets/02_202606200227_DZynZu9goX0_1fps_sheet.jpg` |
| 3 | 2026-06-19 20:02 | `DZx7Wusj88R` | Hold on for just a second | `.videos/domcaminiti_reference/latest15/sheets/03_202606192002_DZx7Wusj88R_1fps_sheet.jpg` |
| 4 | 2026-06-19 13:01 | `DZxLS9LEcA9` | STOP FLIPPING THROUGH IMPACT | `.videos/domcaminiti_reference/latest15/sheets/04_202606191301_DZxLS9LEcA9_1fps_sheet.jpg` |
| 5 | 2026-06-18 20:09 | `DZvXVqNE5TR` | should we change it? | `.videos/domcaminiti_reference/latest15/sheets/05_202606182009_DZvXVqNE5TR_1fps_sheet.jpg` |
| 6 | 2026-06-18 12:03 | `DZufun0iQdS` | do not worry about your short game right now | `.videos/domcaminiti_reference/latest15/sheets/06_202606181203_DZufun0iQdS_1fps_sheet.jpg` |
| 7 | 2026-06-17 20:02 | `DZsxw2yCVhN` | Hudson, this is better than many touring pros | `.videos/domcaminiti_reference/latest15/sheets/07_202606172002_DZsxw2yCVhN_1fps_sheet.jpg` |
| 8 | 2026-06-17 12:01 | `DZr6wH_D7Pe` | fix your backswing to fix your downswing | `.videos/domcaminiti_reference/latest15/sheets/08_202606171201_DZr6wH_D7Pe_1fps_sheet.jpg` |
| 9 | 2026-06-16 16:26 | `DZp0M78ggdg` | I promise this will make shallowing the club easier | `.videos/domcaminiti_reference/latest15/sheets/09_202606161626_DZp0M78ggdg_1fps_sheet.jpg` |
| 10 | 2026-06-15 14:07 | `DZm_JhjxsJC` | @kevinhart4real - let us dial this in | `.videos/domcaminiti_reference/latest15/sheets/10_202606151407_DZm_JhjxsJC_1fps_sheet.jpg` |
| 11 | 2026-06-14 22:02 | `DZlQyy6xxUS` | Congrats @budcauley | `.videos/domcaminiti_reference/latest15/sheets/11_202606142202_DZlQyy6xxUS_1fps_sheet.jpg` |
| 12 | 2026-06-14 21:01 | `DZlKQRFnSdC` | You can play with high hands | `.videos/domcaminiti_reference/latest15/sheets/12_202606142101_DZlKQRFnSdC_1fps_sheet.jpg` |
| 13 | 2026-06-14 00:01 | `DZi6CodgVom` | comment TRAIN and send me a video of you doing the drill | `.videos/domcaminiti_reference/latest15/sheets/13_202606140001_DZi6CodgVom_1fps_sheet.jpg` |
| 14 | 2026-06-13 13:02 | `DZhuokwCali` | Fix the proper things in the proper order | `.videos/domcaminiti_reference/latest15/sheets/14_202606131302_DZhuokwCali_1fps_sheet.jpg` |
| 15 | 2026-06-12 21:02 | `DZgAsT-jl5V` | Laid off equals steepening downswing | `.videos/domcaminiti_reference/latest15/sheets/15_202606122102_DZgAsT-jl5V_1fps_sheet.jpg` |

## Per-Video Observations

### 1. `DZ1DCbAgYTk`

Visuals: persistent target/stance alignment lines, address shaft-plane line, takeaway shaft line, top-position laid-off comparison line, delivery plane comparison, and a physical stick constraint behind the golfer.

Transcript analysis: starts with positive setup facts, then traces one root issue: hands move out, clubhead sneaks inside, shaft gets shallow/laid off, transition drops under plane. The fix is a constraint drill, not a metric.

SwingCoach implication: V1 needs address alignment/shaft plane, takeaway hand/clubhead relation, top laid-off line, and delivery plane comparison.

### 2. `DZynZu9goX0`

Visuals: wall/door-frame constraint, clubhead outside-hands checkpoint, alignment stick down the shaft, lead-leg stick reference, and face-on wrist-hinge demonstration.

Transcript analysis: explains a universal pattern: good players keep clubhead up/outside hands; many amateurs get the clubhead behind the hands. The drill uses a physical boundary to force the shape.

SwingCoach implication: manual drill templates should include wall/door-frame, shaft-stick, and clubhead-outside-hands gates.

### 3. `DZx7Wusj88R`

Visuals: camera-position critique, toe-line/camera-height alignment, target/body alignment sticks, top-position high-hands/laid-off line, and trail-shoulder stick constraint.

Transcript analysis: makes camera setup a prerequisite to swing diagnosis. He explicitly sequences camera angle, alignment, then swing change.

SwingCoach implication: add a capture-quality/view gate before publishing geometry claims: DTL camera should be around hand height and near toe line.

### 4. `DZxLS9LEcA9`

Visuals: before/after comparison, impact hand/clubhead relationship, clubhead passing hands, alignment stick down the shaft to stop flipping, and clubface/spine match through impact.

Transcript analysis: uses a slow-speed feedback drill to teach impact control. The key point is not an abstract "release" metric; it is visible clubhead/hands order and face control.

SwingCoach implication: impact/release overlays are valuable but should begin as visual checkpoints: clubhead relative to hands, shaft lean/stick collision risk, and face/spine proxy.

### 5. `DZvXVqNE5TR`

Visuals: high hands/arms, very long backswing, wall constraint, trail-arm/wrist/shaft close to wall, hand-depth reference, and lead-foot-to-wall length limiter.

Transcript analysis: he first decides whether a nonstandard swing actually needs changing. When suggesting changes, he ties them to depth, width, length control, and physical feedback.

SwingCoach implication: the coaching voice should sometimes say "this is playable" and only annotate the change if it supports consistency. Automated overlays need a "do not overcorrect" mode.

### 6. `DZufun0iQdS`

Visuals: takeaway shaft too shallow, transition shaft steep through shoulder, hips moving toward ball, original plane return, and alignment-stick down-shaft drill.

Transcript analysis: rejects the user's stated priority, short game, and identifies swing structure as the root cause. The logic chain is takeaway shallow -> transition steep -> posture loss -> flip.

SwingCoach implication: V1 should support cause/effect sequencing across checkpoints, not isolated labels.

### 7. `DZsxw2yCVhN`

Visuals: mostly positive checkpoint lines: club up plane, halfway-back shaft to ball, lead arm matching shoulder plane, hand depth over heels, delivery through trail forearm, clubhead outside hands at impact.

Transcript analysis: praise-heavy review. The voice shifts from swing mechanics to performance system: short game, putting, routine, course management.

SwingCoach implication: annotations should support positive validation, not only faults. Add "strengths" overlays and avoid inventing a fix when the visible swing is solid.

### 8. `DZr6wH_D7Pe`

Visuals: top-position hand-depth line, open clubface/lead-wrist marker, lead-arm/clubface comparison, steep shaft through ear/shoulder, trail-shoulder pane/stick constraint.

Transcript analysis: backswing and top position explain the over-the-top downswing. Grip and face are treated as prerequisites before transition work.

SwingCoach implication: clubface/wrist match is high-value but should remain gated until evidence is reliable. The future layer should be separate from generic shaft plane.

### 9. `DZp0M78ggdg`

Visuals: setup checklist, target line and parallel body line, address shaft-to-belt-buckle reference, hands-under-shoulders posture, face-on spine tilt, stance width, ball position, grip V directions.

Transcript analysis: a setup masterclass. The explanation shows how alignment mistakes force compensatory swing shapes.

SwingCoach implication: build a `setup_geometry` family with DTL and face-on sublayers. Do not mix FO ball-position claims into DTL plane overlays.

### 10. `DZm_JhjxsJC`

Visuals: indoor net alignment, clubface/net target line, feet/body parallel line, posture/hands setup, halfway-back shaft, hands through bicep, stick two feet behind hands, under-stick delivery gate.

Transcript analysis: alignment is prioritized over swing mechanics because the brain is reacting to the intended start line.

SwingCoach implication: for indoor/net videos, detect or allow manual target/net line before making swing-path claims.

### 11. `DZlQyy6xxUS`

Visuals: clubhead covering hands at takeaway, halfway-back shaft pointing near ball, hands through bicep, top-position shaft zone between ball-hands line and hands-heels line, delivery through trail forearm, hip-to-hip impact control.

Transcript analysis: pro-model review. The coaching pattern is an ideal checkpoint sequence from takeaway through delivery.

SwingCoach implication: this is the clearest V1 template: checkpoint bundle with address/takeaway/halfway/top/delivery/impact, each attached to one visible criterion.

### 12. `DZlKQRFnSdC`

Visuals: high-hands warning, lead arm above shoulder plane, hands over toes, laid-off shaft line, trail-shoulder pane/stick drill, hands/arms/club under-stick gate.

Transcript analysis: explains that high hands can work but usually require compensation. The drill forces lower/deeper hands and better arm/shoulder relationship.

SwingCoach implication: `lead_arm_plane`, `hand_depth`, and `shaft_top_zone` should be separate toggles so a coach can show the top-position cause before transition effects.

### 13. `DZi6CodgVom`

Visuals: wall limiter for backswing length and a bag/pillow target for impact/release sequencing.

Transcript analysis: pure drill video. It teaches when to start downswing and where to release energy using tactile feedback.

SwingCoach implication: manual drawing/drill mode needs reusable constraint templates even when no automated metric is involved.

### 14. `DZhuokwCali`

Visuals: halfway-back shaft line to ball, standing-too-close setup marker, hands moving out/away, shallow shaft, transition shaft through bicep versus trail forearm, posture/space issue, cone or object hand-path gate.

Transcript analysis: again uses "proper things in order": setup distance first, then takeaway path, then transition shallowing.

SwingCoach implication: setup distance and hand-path gate should be part of V1 because they directly explain shaft-plane errors.

### 15. `DZgAsT-jl5V`

Visuals: ball-through-hands top-position line, shaft left/right of that line, steepening frame-by-frame in transition, clubhead outside hands, flip through impact, stand-farther setup, trail-shoulder stick with shaft-hooking constraint.

Transcript analysis: laid-off top causes steepening. The fix changes setup distance, arm/shoulder plane, hand depth, and shaft position at the top.

SwingCoach implication: add a top-position `shaft_zone` annotation with clear "laid off / across / on plane" labels only when shaft confidence and phase confidence are high.

## Visual Annotation Feature List

### V1 Default-On Candidates

1. Address shaft plane

Persistent line through the address shaft, derived from `detect_shaft()` using prompt `"club shaft"`. It should stay visible through takeaway/delivery comparisons.

2. Takeaway hand/clubhead checkpoint

Down-the-line checkpoint showing whether the clubhead is covering or outside the hands, plus whether the shaft points near the ball line.

3. Shaft checkpoint bundle

Windowed lines at address, takeaway/lead-arm-parallel, top, transition, delivery, and impact when phase confidence is high. Labels should be sparse and checkpoint-specific.

4. Clubhead path

Trace through the analyzed swing window, but only when clubhead tracking is temporally stable.

5. Head reference

Dashed address head-height line plus top/impact markers. Useful for posture/sway but should not become a body-skeleton default.

6. Setup distance/posture

Hands under shoulders, butt-of-club distance to belt buckle, and DTL posture reference. This appears repeatedly as a root cause.

### V1 Available But Default-Off

1. Setup alignment

Target line plus parallel body/feet line. Valuable, but target-line inference is hard and should often be manual-assisted.

2. Hip depth

Address posterior hip line and top/impact hip markers. Useful for early extension but camera/view-sensitive.

3. Hand depth

Hand path and top-position vertical gate. Useful for "hands over heels/toes" explanations.

4. Lead arm plane

Top-position shoulder-plane versus lead-arm line.

5. Ball/contact evidence

Only when ball/contact confidence is strong. Use as evidence, not a loud default overlay.

6. Phase markers

Good for debug and still review, but not a default video overlay.

7. Confidence badges

Keep in details/debug by default. The video should show withheld/available state through layer visibility.

### Future/Research Layers

1. Clubface and wrist match

Top-position clubface-to-lead-arm relationship and lead-wrist cup/bow proxy. High value, high risk.

2. Release/impact control

Clubhead relative to hands, shaft lean/stick-contact proxy, and face/spine relationship. Needs careful validation.

3. FO setup geometry

Spine tilt, ball position, stance width, hand position, foot flare, weight distribution proxy. Should be explicitly face-on gated.

4. Drill constraints

Wall, door frame, cone, trail-shoulder pane, alignment-stick-under/over gates, shaft-stick down lead thigh, bag/pillow impact target.

5. Before/after comparison

Linked visual sheets or side-by-side/replay comparison for progress and model examples.

## Coaching Voice Pattern

Dom's strongest pattern is not the drawing itself; it is the explanatory chain attached to the drawing.

Common flow:

1. Establish one visible fact from setup or an early checkpoint.
2. Explain what that fact causes later.
3. Avoid fixing the symptom first.
4. Show a physical constraint that forces the intended motion.
5. Ask for feedback/video of the drill or frame the next practice step.

Common claim shape:

- Setup/alignment cause the brain to make compensatory motion.
- Takeaway shape determines transition options.
- Top position explains steepening, shallowing, stalling, or flipping.
- Face/grip/wrist issues must be solved before transition-path advice.
- A good swing review can validate strengths and move away from mechanics.

SwingCoach should generate explanation units like:

- `visible_fact`: the exact frame/window and overlay that proves the point.
- `downstream_effect`: what this usually causes later.
- `priority`: why this comes before another fix.
- `uncertainty`: what was withheld or needs better capture.
- `next_action`: drill/constraint or manual drawing suggestion.

## Proposed Backend Architecture

Add `backend/analysis/annotate/` and move annotation responsibilities out of `artifact_renderer.py`.

Suggested package shape:

```text
backend/analysis/annotate/
|-- __init__.py
|-- contract.py          # Track, frame, layer, guide shape, confidence, publish decision dataclasses
|-- evidence.py          # EvidenceBundle assembled from pose, club, shaft, ball, phases, view gate
|-- phases.py            # Phase windows and checkpoint selection helpers
|-- shaft.py             # Address plane, shaft checkpoints, top shaft zone, delivery compare
|-- setup.py             # Alignment, stance, hands-under-shoulders, setup distance, FO setup gates
|-- body_refs.py         # Head line, hip depth, hand depth, lead arm plane
|-- club_path.py         # Clubhead trace and takeaway clubhead-vs-hands relationship
|-- drills.py            # Generated/manual drill-constraint guide templates
|-- tracks.py            # Normalized JSON track assembly
`-- validation.py        # Fixture visual checks and withhold reasons
```

Pipeline shape:

1. `video_info`: read source metadata.
2. `view_gate`: determine DTL/FO, framing, camera stability, and whether target/ball are visible.
3. `phase_scan`: find address, takeaway, top, transition, delivery, impact windows.
4. `evidence_extract`: run pose and equipment detectors only for required windows.
5. `candidate_build`: each annotation module proposes candidates with geometry, source frames, confidence, and claim text.
6. `publish_decide`: withhold low-confidence or wrong-view candidates with explicit reasons.
7. `track_assemble`: write normalized client-rendered JSON over clean video.
8. `debug_artifacts`: optional contact sheets and per-layer visual tests.

Keep `ArtifactRenderer` focused on artifact writing: clean `base.mp4`, compatibility `annotated.mp4`, `annotation_metadata.json`, `annotation_tracks.json`, and optional baked export.

## Recommended V1 Order

1. Define the normalized track contract and publish/withhold shape.
2. Move old `abc12c4` track assembly ideas into `annotate/contract.py` and `annotate/tracks.py` without re-enabling detectors.
3. Implement address shaft plane from setup frames using `"club shaft"`.
4. Add takeaway checkpoint from pose wrists plus clubhead/shaft evidence.
5. Add delivery shaft compare against address plane and trail forearm proxy.
6. Add head reference and hand-depth/top gates.
7. Add fixture-level visual tests and generated contact sheets before app-enabling default layers.
8. Add manual drill-constraint templates in the iOS rail after generated layers are stable.

## Open Questions

- Should V1 be DTL-only until FO setup geometry is separately specified?
- Should the user choose target line manually before `setup_alignment` is publishable?
- Should generated coach notes be checkpoint cards linked to timecodes instead of free-form paragraphs?
- Should manual drawings be exportable back into the backend artifact bundle, or stay local-only for now?
- What fixture set proves each layer: down-the-line indoor, down-the-line range, face-on range, high-speed slow-motion, poor camera angle, bad lighting, and no-ball/no-club cases?
