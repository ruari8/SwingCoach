# SwingCoach MVP roadmap

Updated 2026-09-03.

The MVP goal is a complete practice loop: supply a swing video, inspect useful evidence, understand one coaching finding, try a drill or feel, and compare later swings.

## Epics organise the work

Each epic groups tickets by the part of the product they improve. A ticket describes a concrete outcome and how to verify it. Technical checks belong in that ticket's acceptance criteria unless a separate investigation is needed to resolve an unknown.

The epics are not a requirement to finish every feature in one area before starting another. A release milestone can select a small set of tickets across epics to deliver one complete coaching path. No release dates are assigned yet.

| Epic | MVP outcome | Current tickets |
| --- | --- | --- |
| [Foundation: capture, library and review #4](https://github.com/ruari8/SwingCoach/issues/4) | Supply usable swing video and find and review it reliably. | [Duplicate capture #2](https://github.com/ruari8/SwingCoach/issues/2), [detector validation #10](https://github.com/ruari8/SwingCoach/issues/10), [test-library organisation #11](https://github.com/ruari8/SwingCoach/issues/11), [local project organisation #12](https://github.com/ruari8/SwingCoach/issues/12), [optional practice-swing capture #13](https://github.com/ruari8/SwingCoach/issues/13) |
| [Visual coaching #5](https://github.com/ruari8/SwingCoach/issues/5) | Show useful annotations at the correct swing checkpoints. | [Selected-swing P1-P10 specification #3](https://github.com/ruari8/SwingCoach/issues/3). The first annotation feature still needs to be selected. |
| [Metric coaching #6](https://github.com/ruari8/SwingCoach/issues/6) | Show validated measurements that help explain a finding. | Outline only. Choose measurements for the first coached behavior. |
| [Coaching explanation #7](https://github.com/ruari8/SwingCoach/issues/7) | Explain one primary finding and its supporting evidence. | Outline only. The first finding and selection logic remain undecided. |
| [Drills and feels #8](https://github.com/ruari8/SwingCoach/issues/8) | Give a practical action tied to the selected finding. | Outline only. Select and review the action for the first finding. |
| [Practice loop #9](https://github.com/ruari8/SwingCoach/issues/9) | Compare later swings against the same finding and record whether the action helped. | Outline only. Define the comparison around the first complete coaching path. |

## Foundation priorities

Foundation covers the old M0 concerns, including specific capture, import, Library, and video-player defects. New UI issues can be added here without reopening the coaching design.

- Detector validation uses Replay Debug for repeatable diagnosis and live Capture for physical-camera and saved-clip behavior. The two routes prove different claims. Issue #10 records the validation; issue #2 remains the separate duplicate-capture fix.
- [Optional practice-swing capture #13](https://github.com/ruari8/SwingCoach/issues/13) records the request to retain full swings without ball impact for home testing. Capture has partial support in source, but the feature needs verification and consistent testing through Replay Debug and the local evaluator. Real-shot baseline testing keeps practice mode off.
- Library organisation is test setup first. Issue #11 starts by locating and inventorying the messy library, separating personal footage from pro/reference footage, and identifying clips that need review. It does not assume a new Library feature is required or authorise deletion of recordings.
- Local project organisation is tracked separately in issue #12. It covers the repository, ignored media, model experiments, and the boundary with the `detectSwings` workspace; it starts with an inventory rather than moving or deleting files.
- Later player bugs become individual tickets with expected behavior, observed behavior, and a reproduction route. There is no generic requirement to complete all UI polish before coaching work begins.

## Visual coaching includes checkpoints and annotations

Visual coaching combines the previous M1 evidence work and M2 annotation work. P1-P10 detection is a prerequisite within this epic, not a separate product milestone. The saved checkpoints can also serve Metrics and Coaching explanation.

Issue #3 retains the detailed selected-swing specification. Its previously proposed seven implementation tickets were never published and are not the adopted roadmap. Future child tickets should describe usable outcomes. Matching the research model, mapping timestamps correctly, and handling incomplete clips remain necessary requirements within that work.

The current direction remains DTL-first. Checkpoint preparation runs on-device when the golfer requests coaching for a saved swing. It does not replace the live capture detector. Any P-position can support coaching, and a visual finding does not require a numeric metric.

## Verification and release readiness

The [verification skill](../.agents/skills/verify-swingcoach/SKILL.md) supports tickets across all epics. Its Library paging baseline has recorded proof; the feature map is not proof that every listed workflow has passed. Tickets add the relevant UI, hardware, backend, or visual checks as their completion criteria.

Physical-iPhone work requires session-specific readiness confirmation. Library organisation preserves originals and separates ambiguous clips for review. No media was changed by this roadmap reorganisation.

Before broader release, the chosen coaching path still needs device coverage, human review of coaching claims, backend reliability checks, and clear upload, retention, deletion, and training-consent rules. These are release requirements, not completed work.

## Relationship to older plans

This epic structure replaces the milestone numbering in the [June master plan](master_plan.html#roadmap). That document remains background research and design material, not the current ticket order. Foundation maps to old M0; Visual coaching combines old M1 and M2; Coaching explanation and Drills separate the concerns in old M3; Metrics and Practice loop retain old M4 and M5's goals.

The [domain glossary](../CONTEXT.md), [architecture decision](adr/0001-hybrid-on-device-and-api-coaching.md), and [out-of-scope notes](OUT_OF_SCOPE.md) still apply. In particular, live cues and advanced 3D measurements are not part of the current checkpoint spec, and capture-framing guidance remains outside MVP scope.
