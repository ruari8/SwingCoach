# Pipeline stage 3: source-backed coaching decisions

`analysis/knowledge_library.py` loads the committed JSON corpus under
`docs/coaching-knowledge/sources`. Use `SWINGCOACH_KNOWLEDGE_DIR` to select that
folder in a backend-only deployment. The media collection is not required for
runtime retrieval and must not be packaged into the mobile app.

The smart coach retrieves candidate cases using visual topics and the golfer's
context. Search includes titles, tags, observations, reasoning and applicability,
then includes linked alternatives. Ranking is lexical relevance, not diagnostic
confidence. Every candidate retains prerequisites, interventions, unknowns and
source attribution. This replaces the active use of the old fault-tag drill file.

The decision schema supports `recommend`, `need_evidence` and `preserve`. A
recommendation needs one supplied case, cited reliable observations, a visual
interpretation beyond whole-clip metrics, one cue and a reassessment. Each
applicability condition must have a supported check with observation references.
Unknown, contradictory, duplicate or missing conditions reject the recommendation.
This is structural validation; whether the evidence actually supports the
condition still depends on the model and requires coaching evaluation.

The server attaches the selected case's original intervention text as the drill,
plus source evidence timestamps. It does not let the model invent source URLs or
assemble a separate library of untraceable drills. No prescription is returned
when the model is unavailable or the decision fails validation.

The app displays one focus, rationale, cue, reassessment, questions, observations,
source links and limits. Source links open the original page; displayed time
ranges identify the relevant moment. Local timestamp playback is available in
the [knowledge viewer](../../../tools/knowledge-viewer/README.md).

Current limits: the source collection has not received independent expert review;
applicability checks are model judgments, not proven diagnoses; there is no
longitudinal learning/progression engine yet. Reassessment is a saved plan, not
an automatic claim that the drill worked.
