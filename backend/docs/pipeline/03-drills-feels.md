# Pipeline Stage 3: Drills and Feels

## Goal

Map diagnosed issues to practical drills/feels worth practicing.

## What Is Implemented

### Drill corpus and selection

- Drill data source: [data/curated_drills.json](/Users/ruari/Documents/Startups/SwingCoach/backend/data/curated_drills.json)
- Selection logic: [coach_response_builder.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/coach_response_builder.py)

Current flow:
1. Rank top priorities from metric cards.
2. Match drill `fault_tags` to priority text.
3. Return up to 3 drill suggestions in coaching bundle.

## Current Gaps

1. Corpus is small and currently contains placeholder links.
2. Tag matching is simple text matching; no personalized ranking model.
3. No progression tracking across sessions yet.
4. No explicit adaptation by equipment constraints, injury constraints, or session context.

## Next Development Tasks

1. Replace placeholder drill sources with validated media.
2. Expand taxonomy (`fault_tags`, constraints, skill levels, prerequisites).
3. Add ranking that uses confidence, severity, and recent user history.
4. Add closed-loop feedback: did the prescribed drill improve the target metric next session?

## Key Files

- [analysis/coach_response_builder.py](/Users/ruari/Documents/Startups/SwingCoach/backend/analysis/coach_response_builder.py)
- [data/curated_drills.json](/Users/ruari/Documents/Startups/SwingCoach/backend/data/curated_drills.json)

