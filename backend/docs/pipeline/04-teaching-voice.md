# Pipeline stage 4: smart coach and follow-up

The active builder uses two versioned prompts:

1. `prompts/visual_observer_v1.md` reviews up to 24 timestamped, evenly spaced video
   frames and the measured evidence. It returns visible findings, frame references,
   interpretation confidence, strengths and missing evidence.
2. `prompts/smart_coach_v1.md` receives those observations, golfer context and
   candidate library cases. It chooses one conditional recommendation, asks for
   evidence or preserves the existing movement.

Both calls use the OpenAI Responses API with Pydantic structured output and
`store=False`. Set `OPENAI_API_KEY` and optionally `SWINGCOACH_COACH_MODEL` in the
backend environment. The default remains `gpt-4o-mini`; model quality for this
coaching task is not established. See [official structured-output documentation](https://developers.openai.com/api/docs/guides/structured-outputs).

Frames sent to the model are bounded to 768 pixels on the longest edge and JPEG
encoded. These are selected frames from the submitted swing, not a continuous
video. Do not claim precise impact or temporal measurements from that sampling.
Reference coaching videos are not sent to the model: the retrieved source cases
supply reasoning, applicability and intervention text.

The API boundary rejects invented frame/observation/case references and unsupported
prerequisite states. API failure, refusal, incomplete output or invalid references
return measured evidence with an explicit `model_unavailable` coaching state and
no drills. This does not validate the semantic truth of otherwise well-formed
model claims; review and evals on varied real swings remain necessary.

`coach_summary.json` persists the full decision, prompts' version, model name,
observations, retrieved candidates and golfer context alongside the display
bundle. `POST /chat` reloads this run context and answers within the saved decision.
Follow-up does not independently diagnose a new swing or prescribe new drills.
Without a key it returns the saved summary and reassessment.

The mobile `coaching` object is additive and optional. Older saved analyses still
decode. New analyses persist the coaching object locally and display evidence,
source moments and limitations in Coach notes. Coach > Practice context supplies
a goal, club, handedness and reported outcome to new requests until edited.

Tests exercise valid/invalid model responses with a deterministic client fixture.
Those checks prove request construction and response validation, not live model
quality. A configured key and representative swing review are needed for that.
