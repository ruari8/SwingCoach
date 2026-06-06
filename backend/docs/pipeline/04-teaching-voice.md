# Pipeline Stage 4: Teaching Voice

## Goal

Generate a clear coaching explanation that connects metrics, visuals, and drills.

## What Is Implemented

### Coaching bundle generation

- Builder: [coach_response_builder.py](../../analysis/coach_response_builder.py)
- Pipeline integration: [pipeline_3d.py](../../analysis/pipeline_3d.py)

Behavior:
- Uses priorities from metric cards and confidence gates.
- Produces `summary`, `top_priorities`, `drills`.
- Falls back to deterministic summary when LLM is unavailable.
- Uses OpenAI client when `OPENAI_API_KEY` is present.

### Follow-up chat

- Endpoint: `POST /chat` in [main.py](../../main.py)
- Context source: prior run artifacts (`metrics.json`, `coach_summary.json`)

## Current Gaps

1. Priority ranking currently uses metric magnitude heuristics; target-aware scoring is limited.
2. Teaching logic is lightweight and not yet a full pedagogy engine.
3. Prompting does not yet deeply connect temporal evidence and visual checkpoints.
4. Frontend is not yet consuming full confidence and uncertainty context.

## Next Development Tasks

1. Replace crude priority scoring with target-distance and confidence-aware scoring.
2. Add teaching templates that reference event timing and specific visual checkpoints.
3. Add user profile context (goal, handicap, constraints) into coaching generation.
4. Add evaluation prompts and regression checks for coaching consistency.

## Key Files

- [analysis/coach_response_builder.py](../../analysis/coach_response_builder.py)
- [main.py](../../main.py)
- [models.py](../../models.py)

