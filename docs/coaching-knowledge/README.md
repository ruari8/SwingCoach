# Coaching knowledge library

This library connects source lessons to the evidence behind their coaching decisions. It is research material for SwingCoach. The app does not consume these records yet, and source extraction does not establish that a recommendation is correct for another golfer.

## Scope and progress

Completed: all 22 supplied videos and four distinct additional videos from each specified creator, 30 sources and 145 coaching records. A repost of the Cameron review was excluded from the additional count. See [decision examples](decision-examples.md) for contrasting cases and the evidence that changes the recommendation.

[manifest.json](manifest.json) preserves the user's 22 supplied videos in order. It also tracks four additional videos from each of the two specified annotation creators. Process one source at a time. Do not count queued URLs, downloaded captions, or a title summary as an analysed video.

Each analysed source has a readable report and a structured JSON record in `sources/`. Record the full transcript coverage and the exact method of visual review. Sampled video frames are visual inspection of those moments, not a claim to have watched every frame. Capture short sequences around movement and annotated checkpoints when a single frame is insufficient.

Completed source reports:

- [01. Jerome Rufin / Chris: backswing structure, release conditions, and one priority](sources/HQNKUS_BSGY.md). Eleven cases linked to 26 evidence spans. Source checked; independent coach review pending.
- [02. Jerome Rufin / Chris: transition, grip, pitching and bunker decisions](sources/G3QNDLEo2Gw.md). Twelve cases linked to 29 evidence spans, including links to the first lesson's different conditions. Source checked; independent coach review pending.

- [03. Tommy Fleetwood: iron trajectory and contact](sources/1dF_irGY6YM.md). Five cases linked to 14 evidence spans and seven displayed shot results. Source checked; independent coach review pending.
- [04. TPI: Michael Brennan assessment](sources/NOMY1bzMI28.md). Twelve cases linked to 30 evidence spans, with physical-screen context, instrumented evidence, demonstrations and teach-back. Source checked; independent coach review pending.

- [05. TPI: Dylan Menante assessment](sources/BcG-r_13z_I.md). Eleven cases linked to 22 evidence spans, preserving rejected diagnosis, partial drill transfer, instrument readings and training context. Source checked; independent coach review pending.

- [06. TPI: Josh Allen assessment](sources/IJSu7440Ick.md). Fourteen cases linked to 28 evidence spans, including alignment-method comparisons, rejected early-extension hypothesis and successive setup adaptations. Source checked; independent coach review pending.

- [07. Padraig Harrington: hip and pelvis movement](sources/p_HZJ2u0TIo.md). Eight conditional tutorial cases linked to 13 evidence spans; staged examples distinguished from student diagnosis and measured outcomes. Source checked; independent coach review pending.

- [08. Padraig Harrington: grip and setup](sources/JgaKrhspwik.md). Six conditional tutorial cases linked to 10 evidence spans; grip function, hand seating, learning progression and relaxed setup. Source checked; independent coach review pending.

- [09. Pete Cowen / Danny Maude: right-arm delivery](sources/iP0sBzIXRtc.md). Twelve cases linked to 17 evidence spans; preserves failed interpretations, successive corrections and hypothetical slicer branch. Source checked; independent coach review pending.

- [10. Ryan Ruffels: short-game choices by lie and target](sources/Radv4RcktNs.md). Twelve conditional cases linked to 14 evidence spans; preserves grain/rough options, contrasting grip pressures and bunker setup exceptions. Source checked; independent coach review pending.

- [11. Ryan Ruffels: driver speed and effort selection](sources/_nGVs7YNz_Q.md). Six conditional cases linked to 11 evidence spans and eight shot results; course effort, maximum practice and estimated club speed kept distinct. Source checked; independent coach review pending.

- [12. Ryan Ruffels: personal drills and target transfer](sources/vGGIn2IAW-Q.md). Five cases linked to eight evidence spans; personal findings, aid constraints, intentional band release and target transfer retained. Source checked; independent coach review pending.

- [13. Ron Chang / Nick Faldo: preset-and-turn drill](sources/DdNBm5SKGvb.md). One conditional drill linked to four evidence spans, local ASR and 47 inspected portrait frames. Testimonial separated from demonstration and outcomes.

- [14. Alex Clapp: forearm rotation timing](sources/Dc-kqu1qKgW.md). Two related teaching cases linked to five evidence spans and 75 inspected frames. Early versus later rotation and guided rehearsal versus measured outcome remain distinct.

- [15. Jenny Kim: early-extension drill alternatives](sources/DdHAGJkKLFB.md). Four alternative tutorial cases linked to five evidence spans and 53 inspected frames. On-screen text and creator rationale retained; unreliable ASR excluded from claims.

- [16. Ace Hong: chicken-wing contrast and shirt drill](sources/DdAsxHSSYY8.md). One conditional drill linked to four evidence spans, 43 sampled frames and a native shirt-setup close-up. Visual interpretation and missing release instructions are explicit.

- [17. AndyCap: banked-foot compression drill](sources/Dc2-Qk5oAP3.md). One conditional drill linked to four evidence spans. Exaggeration, foot-bank geometry, missing diagnosis and unsupported universal draw prediction preserved.

- [18. Gary McGrane: earlier release and transfer](sources/DcsppaMOFHi.md). Two records linked to six evidence spans: one conditional release feel and one incomplete mechanism explanation. Source universals, missing contexts and course-transfer difficulty retained.

- [19. Trace Martin: patience and later-power feel](sources/DcriXkulItf.md). One conditional feel linked to three evidence spans and 43 inspected frames. Missing opening transcription recovered; course promotion separated from taught content.

- [20. Emily: Coca-Cola tempo cue](sources/Dcljq_yCRGl.md). One conditional rhythm cue linked to three evidence spans and 29 inspected frames. Source attribution, editing and timing limits retained.

- [21. Teagan Moore: Cameron review and bump-then-turn drill](sources/DcqwwGio81y.md). Two decisions linked to six evidence spans and 82 inspected frames. Accepted swing differences, face-on reasoning and the prop sequence retained.

- [22. Dom Caminiti: Ryan backswing review](sources/DVI2JDpDC5Z.md). Two sequential decisions linked to six evidence spans and 56 inspected frames. Actual swing observations are distinguished from desired drawings and predicted results.

- [23. Teagan Moore: Marius: setup before an under-plane push correction](sources/DcY33a3Ck73.md). Two conditional decisions linked to five evidence spans and 51 inspected frames; setup dependency and unassociated instrument display retained.

- [24. Teagan Moore: Kyle: two-month grip-to-transition progression](sources/Dcthf1xDWe9.md). Three staged decisions linked to six evidence spans and 49 inspected frames; reported follow-up and comparison limits retained.

- [25. Teagan Moore: Shallowing barrier: prerequisites and swing-under setup](sources/DcwID0KRE5Q.md). One conditional drill linked to three evidence spans and 34 inspected frames; written prerequisites, prop geometry and rejected ASR retained.

- [26. Teagan Moore: Mohammad: keep the cut or choose an optional draw change](sources/DbTWAp7gCEt.md). Two goal-dependent branches linked to four evidence spans and 38 inspected frames; retained cut pattern and optional draw change kept separate.

- [27. Dom Caminiti | Golf Swing Reviews: Eli: a drill checkpoint reached through the wrong movement](sources/DdOg8DTnQr-.md). One drill-correction case linked to four evidence spans and 49 inspected frames; endpoint-versus-mechanism distinction retained.

- [28. Dom Caminiti | Golf Swing Reviews: Tyler: preserve backswing and let arms catch up in transition](sources/DdL8LyFjuAL.md). Two alternative transition cases linked to five evidence spans and 38 inspected frames; retained backswing and probable flight distinguished.

- [29. Dom Caminiti | Golf Swing Reviews: Brad: grip and wrist conditions before setup compensation](sources/DdJ8PHAjcvP.md). Two related decisions linked to three evidence spans and 32 inspected frames; grip context, product illustration and missing retest retained.

- [30. Dom Caminiti | Golf Swing Reviews: Carter: shoulder barrier for backswing depth and hip turn](sources/DdJXqvkEZHI.md). One conditional drill linked to four evidence spans and 32 inspected frames; student/coach distinction, hip-angle limits and transfer check retained.

Raw media, downloaded metadata, captions, and extracted frames live under the existing ignored `.videos/coaching-knowledge/<source-id>/` directory. They remain local source evidence and are not bundled into the app or committed as a redistributed media collection. Reports link to original source timestamps and local evidence. JSON paths are relative to the repository root.

## What a case preserves

- Context: golfer, shot intent, handedness, club, relevant reported limitations, and available camera views.
- Evidence: visible swing behavior, annotated checkpoints, spoken observations, displayed measurements, and reported ball flight. Preserve original terms without automatically treating ambiguous phrases as synonyms.
- Reasoning: what the coach explicitly connects to the finding. Mark the model's interpretation separately and leave missing causes unknown.
- Intervention: intended physical change, verbal feel, drill procedure, and source demonstration. Exaggerated rehearsals are not normal-swing templates.
- Applicability: prerequisite observations, alternatives, exceptions, and reasons to withhold a recommendation.
- Result: immediate demonstrations, golfer feedback, measured changes, and later follow-up. Edited success examples do not establish retention or causation.
- Provenance: source URL, timestamp spans, speaker attribution, inspected frames, and review status.

An evidence item has a stable `id`, `span_seconds`, `attribution`, and `summary`. Its `frames` contain an inspected timestamp, local path, and visual observation. A case references those IDs instead of losing the connection between diagnosis, instruction, and retest.

Keep the source type explicit. An assessed lesson can show a particular golfer's problem, the coach's decision and a retest. A general tutorial supplies conditional instructions and demonstrations; it does not establish that a student had the problem or improved. Mark those cases as `conditional_tutorial_template_not_assessed_student`. Deliberately demonstrated wrong positions must not be labelled as the instructor's natural swing faults.

`source_checked_not_expert_validated` means the extraction was checked against the explicitly recorded source channels and inspected visuals: platform captions, locally generated speech transcription, on-screen text or creator description. It does not claim independent biomechanical validation or qualified-coach approval. Preserve uncertainty separately for transcript wording, visual interpretation, and applicability.

## Selection principles for future coaching logic

The library can contain several interventions for the same finding. Preserve their conditions and disagreements. Do not resolve them by popularity or merge them into one universal instruction.

The user's preference is one coaching focus and normally one action, with at most two compatible cues or actions at a time. That is a future presentation constraint, not a limit on stored knowledge. A cue and its supporting drill can express the same action. Store priority, prerequisite, and reassessment rules alongside each case so retrieval can select an intervention rather than list everything.

TPI and Greg Rose are preferred sources for the user's technical learning style. Record their body-screening and body-handicap context when present. Current phone-video evidence must not be treated as a substitute for physical screening, a clinical assessment, or measured mobility/force data. Explanations for other golfers may need a simpler level of detail while retaining the same source evidence.

## Reusable preparation and checks

The local `.videos/coaching-runtime` environment contains the current downloader, Pillow and MLX Whisper. `ffmpeg` and `ffprobe` are also required. The older system downloader retrieved captions but failed to download the first lesson; isolated yt-dlp 2026.8.19 succeeded.

```bash
# Fetch only the current source. Replace SOURCE_ID and URL.
.videos/coaching-runtime/bin/yt-dlp --skip-download --write-info-json \
  --write-subs --write-auto-subs --sub-langs en-orig,en --sub-format json3 \
  -o '.videos/coaching-knowledge/SOURCE_ID/%(id)s.%(ext)s' URL
.videos/coaching-runtime/bin/yt-dlp \
  -f 'bestvideo[height<=480]+bestaudio/best[height<=480]' --merge-output-format mp4 \
  -o '.videos/coaching-knowledge/SOURCE_ID/%(id)s.%(ext)s' URL

python3 scripts/coaching_knowledge.py normalize CAPTIONS_JSON3 OUTPUT_DIRECTORY
.videos/coaching-runtime/bin/python scripts/coaching_knowledge.py sheet \
  VIDEO_PATH OUTPUT_DIRECTORY --times 120,125,130
python3 scripts/coaching_knowledge.py validate
```

YouTube JSON3 timing represents overlapping caption display windows. The helper retains original text-event timing, drops empty display events, and creates a 30-second reading index without paraphrasing. Do not interpret caption end times as precise speech boundaries. Instagram and other sources may require a different extraction/transcription route; record it explicitly when used.

For media without captions, use the full audio with the local [MLX Whisper implementation](https://github.com/ml-explore/mlx-examples/tree/main/whisper) and record the selected model. The first Instagram source uses [Whisper large-v3-turbo in MLX format](https://huggingface.co/mlx-community/whisper-large-v3-turbo). Model files are cached in the ignored runtime directory; source audio stays local.

```bash
HF_HOME=.videos/coaching-runtime/hf-cache .videos/coaching-runtime/bin/python \
  scripts/coaching_knowledge.py transcribe VIDEO_PATH OUTPUT_DIRECTORY \
  --model mlx-community/whisper-large-v3-turbo
.videos/coaching-runtime/bin/python scripts/coaching_knowledge.py sheet \
  VIDEO_PATH OUTPUT_DIRECTORY --portrait --times 0,2,4,6
```

The transcription command saves raw ASR segments and word estimates, a normalized transcript, a reading copy and provenance including model, package version and source hash. ASR is not a human-verified transcript. Compare consequential wording against available embedded captions and demonstrations; preserve unresolved wording separately. Portrait sheets use taller cells to keep vertical-video annotations readable. All frame requests must precede the measured video end.

Language detection is the default for transcription; use `--language en` only when English is established, or another Whisper language code when appropriate. Provenance records the requested and detected languages. A creator's post language does not establish the language of a reused soundtrack.

For a horizontal lesson embedded inside a vertical post, `sheet --crop WIDTH:HEIGHT:X:Y` can remove letterboxing before resizing. Inspect an uncropped frame to choose source-pixel coordinates. The sheet index records the crop; keep uncropped evidence because subtitles or other context may fall outside it. Source 17 includes both versions.

Check ASR coverage against the visual sequence. A successful transcription can still omit speech: source 19's first pass skipped the opening advice. Transcribing its first 19 seconds separately recovered the text. Preserve the initial result, the extracted audio and both raw ASR outputs; record how the composite transcript was assembled. Offset segment times by the clip's source start when it is nonzero. Never silently replace a missing section with a model paraphrase.

If ASR fails to produce reliable coaching speech, retain the attempt and label it rejected for coaching use. A visual tutorial can still be extracted from inspected on-screen text and its creator description. In that case, `transcript_kind`, the reading copy and provenance must explicitly say **on-screen text**, with sampled timing limits. Keep the audio attempt in separate assets; never present visual text as a verified spoken transcript. Source 15 demonstrates this route. Its `raw_captions` asset is the manually recorded on-screen text, while `raw_audio_asr` preserves the rejected machine output.

MLX needs GPU access on this Mac. The sandboxed transcription attempt failed with no Metal device; an approved run with GPU access succeeded. Once the model is cached, `HF_HUB_OFFLINE=1` permits subsequent transcription without model-network access.

The validator checks actual media duration, local evidence availability, time bounds, and case references. For each completed additional-creator request, it also verifies the requested count, unique registered source IDs, exclusion of the seed, and completed source records. It reports only unfinished creator requests as pending. It cannot verify that a coaching claim is true or that an image interpretation is correct; those require inspection and review.
