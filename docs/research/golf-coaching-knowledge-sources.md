# Golf coaching knowledge sources

Status: proposal for discussion, not an implemented pipeline or an approved coaching specification.

Checked: 2026-09-13.

## Findings

YouTube supports a transcript view for videos that have captions. Transcript lines link to the corresponding video moment. However, the official Data API caption-download endpoint requires permission to edit the video. A public URL alone therefore does not guarantee programmatic transcript access through that endpoint. Begin with accessible transcripts or supplied media, and record unavailable input explicitly. [YouTube transcript help](https://support.google.com/youtube/answer/15930243?hl=en), [YouTube caption-download API](https://developers.google.com/youtube/v3/docs/captions/download).

Automatic captions can misrepresent speech because of accents, pronunciation, noise, or overlapping speakers. Their availability and accuracy should be input-quality fields. Check the audio around any consequential coaching claim rather than treating the transcript as ground truth. [YouTube automatic-caption documentation](https://support.google.com/youtube/answer/6373554?hl=en).

Golf instruction has a motor-learning component beyond describing body mechanics. Wulf, Lauterbach, and Toole's 1999 experiment compared attention to arm motion with attention to club motion in 22 golf novices practicing pitch shots. The club-focused group performed better during practice and on a next-day retention test without instructions. This is a small, task-specific study, not evidence that one cue fits every golfer. It supports storing the intended movement separately from the cue used to teach it, and evaluating later performance without prompts. [Original study abstract](https://pubmed.ncbi.nlm.nih.gov/10380243/).

Trackman's first-party definitions show why measurement context matters. Club-delivery values depend on where and when they are measured; impact location changes the relevant face orientation. Proposed implication: keep measured impact data, video observations, and inferred causes separate. A visible swing feature alone should not be stored as a verified explanation of ball flight. [Trackman club-data definitions](https://www.trackman.com/blog/club-data-definitions).

## Proposed extraction unit

Save a contextual lesson case, with linked source moments, rather than an isolated tip:

- Source identity, speaker, timestamps, transcript provenance, and accessible media.
- Golfer context, shot goal, observed problem, and evidence the coach actually used.
- Coach's stated explanation, distinguished from the model's interpretation.
- Applicability, exceptions, and missing information. Leave these unknown when the source does not establish them.
- Demonstration, verbal cue, drill, and intended physical change as separate fields.
- Observed result, retest procedure, and whether later retention or on-course transfer was assessed.
- Topic tags, such as grip, transition, or P4, for retrieval.

A transcript pass can propose candidate spans, but also inspect a coarse visual sweep for silent demonstrations. Expand each span until its setup, qualification, demonstration, and result are understood. Link separated moments when a coach explains a problem early and retests it later. Mark an exaggerated drill as a drill, not a model of a normal swing.

Use the model to extract and organize claims, not to certify that they are correct. Review a small collection before automating volume. Retrieve reviewed cases when generating coaching; training a model can wait until there is evidence that retrieval is insufficient.

For Ruari's personal experiment, choose one problem, establish a baseline, try one intervention, and record immediate results plus a later test without reminders. This can establish what appears useful for Ruari. It does not establish that the same intervention works for all golfers or guarantees a low handicap.

## Open questions

- Which sources and supplied media can the first implementation actually access reliably?
- What evidence is sufficient to move a case from extracted to reviewed?
- How will a qualified coach review ambiguous or conflicting advice?
- Which outcomes can the app measure reliably enough to support an intervention decision?
