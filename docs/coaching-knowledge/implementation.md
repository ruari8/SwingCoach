# Coaching pipeline implementation

## Objective and sequence

Preserve the existing knowledge work in Git, build a local viewer, then connect
video observations, calculated metrics, visual annotations, a grounded AI coach
and actionable feedback to the existing iOS analysis flow.

The source corpus was committed as `18025f5`. Unrelated capture/cadence work in
the checkout is outside this change. Raw media remains local and ignored.

## Shared contract

An observation records what is visible, its video time, view, method and confidence.
An interpretation links those observations to a possible coaching finding.
A coaching decision retains the selected source case, supporting observations,
missing prerequisites, one current action and a reassessment plan.

Metrics describe quantities that can actually be calculated from the video.
Two-dimensional body movement is not pressure, calibrated distance, clubface
angle or three-dimensional rotation. No universal fault threshold may be inferred
from the library's prose or from a search score.

Annotations explain the observations used in the decision. Body reference lines
and hand paths can precede club-specific analysis. Shaft work must use a detected
shaft, not a wrist-to-clubhead guess. P4 means top and P7 means impact in new
coaching records; do not reuse the legacy event module's incompatible numbering.

The smart coach receives the measured evidence, golfer context and relevant
source cases. It must distinguish hypotheses from measurements, preserve useful
movements, select one focus, cite its case, and ask for missing evidence when
needed. API failure must return useful measured observations without invented
diagnoses. Persist the evidence and decision used by follow-up chat.

## Completion evidence

- Library committed with all source records and validator passing.
- Local viewer: search/filter, case links, video seeking, evidence frames,
  transcripts, missing-media handling and read-only file boundary verified.
- Real-video pipeline: observations, metrics and overlay tracks generated and
  inspected, including no-pose/low-confidence behavior.
- Grounded coaching: source selection, evidence references, unknowns, cue/drill
  and reassessment exercised, including model-unavailable behavior.
- iOS: result decoding, persistence, annotated playback, coaching rationale and
  source-linked drill visible through the real analysis flow.
- Canonical docs updated and focused backend/iOS verification passed before the
  implementation commit. Clinical validity or handicap improvement is not
  established by software checks.

## Delivered foundation — 27 September 2026

The viewer and API now load the same 30-source, 145-case corpus. The API generates
real 2D measurements and timed overlays, runs a configurable visual observer and
smart coach, validates source/evidence references and prerequisite checks, and
persists the coaching decision. iOS sends practice context and displays the
result with rationale, cue, reassessment, evidence, source moments and limits.

```text
Recording + practice context
  → pose samples → measured observations + overlay tracks
  → sampled-frame visual review
  → source-case retrieval + alternatives
  → applicability checks → one cue / preserve / request evidence
  → saved Coach notes + source intervention + reassessment
```

The first metrics are whole-clip horizontal/vertical head range and projected
torso-angle range. The first overlays are a torso reference, initial visible head
position and short hand trail. They demonstrate the observation contract without
inventing shaft/clubface/pressure measurements or diagnosing from a range value.

### Verification evidence

- Corpus validation, loader/retrieval and HTTP media boundary checks passed.
- Seven library/coaching unit checks passed, including measurement geometry,
  source-backed recommendation assembly and rejection of invalid/low-confidence
  evidence or unresolved prerequisites. Model responses in these checks are fixtures.
- Synthetic pipeline, no-pose renderer and async run lifecycle checks passed.
- Real pose tracking ran on the local reference video and on its 4–8 second crop
  through the production iOS upload and analysis flow, using test-only local storage.
- Two iOS decoding/persistence unit tests passed in
  `.verification-artifacts/coaching/20260927-first/`.
- The focused UI rerun passed in
  `.verification-artifacts/coaching/20260927-ui-recheck/`: practice goal and club
  reached persisted backend input, real analysis returned measurements and overlays,
  saved results survived relaunch, and a labelled source fixture displayed its cue
  and source moment. Screenshots were inspected. The disposable Simulator and
  verification backend were removed/stopped; cleanup evidence is in that directory.
- Viewer browser checks loaded all cases, narrowed Cameron to two cases and played
  the selected source from 123 seconds. HTTP range playback is covered by tests.
  Browser screenshots were partially clipped/blank and responsive capture failed;
  complete browser visual QA remains unverified. This does not affect the passing
  native Simulator screenshots or the observed viewer search/playback state.

### Next evaluation work

`OPENAI_API_KEY` was absent during verification. No live model diagnosis or quality
claim has been made. Configure it locally to evaluate the complete AI path; the
missing-model behavior is tested and retains measured evidence without drills.
The corpus must accompany any backend deployment; reference videos are only
required for the local viewer. This change has not been deployed.

The next useful increment is reviewing representative personal swings against
source cases, then improving temporal sampling and phase-specific measurements.
A model-supplied confidence score and structurally valid prerequisite checks do
not prove the diagnosis. Track strike/flight and aid-free transfer alongside the
visible change before treating a recommendation as successful coaching.
