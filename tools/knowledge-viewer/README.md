# Local coaching knowledge viewer

From the repository root:

```bash
python3 scripts/knowledge_viewer.py
```

Open <http://127.0.0.1:8769>. Use `--port 8770` if the default is occupied.
The server uses Python's standard library, binds only to loopback, and has no
write API. Stop it with Ctrl-C. Restart after changing source JSON records.

Search all 145 cases by text, source or phase. Select a case to read the finding,
reasoning, intervention, applicability, unknowns and reassessment notes. Evidence
buttons play the recorded time span in the full local video and stop at its end.
Turn off “Stop at end of moment” to continue watching. Frames and transcript rows
also seek the player. Case URLs use a stable `#case-id` fragment.

Videos, transcripts and frames remain in ignored `.videos/coaching-knowledge/`.
Only files explicitly referenced by the corpus are served. Missing local media
does not prevent reading cases or opening the original source. No media is
copied, uploaded or cut into separate clips by the viewer.

The viewer and backend share `backend/analysis/knowledge_library.py`. Search
returns candidate cases, not a diagnosis or a coaching-confidence score.

Verification:

```bash
cd backend
python3 -m unittest test_knowledge_library
```
