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

## Current progress

The local viewer and shared corpus loader are implemented. Runtime integration
is next. The previous runtime intentionally returned clean videos and an empty
annotation contract; older metric and drill modules were not active.
