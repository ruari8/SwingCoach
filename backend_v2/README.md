# backend_v2

The replacement coaching backend. Work in progress; nothing here is deployed or called by the app yet.

The live backend stays in [`backend/`](../backend/README.md) until v2 replaces it. Copy what you want to keep instead of importing from `backend/`, so the old backend can be deleted cleanly later.

## Why a v2

On October 24 the current coaching was tested on real range swings and judged not useful:

- The app uploads 320×568 video, and the coach sees 24 still frames, about 2 of them in the downswing.
- The measurements are whole-clip ranges, not positions in the swing.
- The overlays only track the body: a torso line, a first-head-position circle and a hand trail. There is no club, no phases and no key positions.
- The coach notes run to about 600 words of hedged text.

The direction since 15 November: metrics and drawings are computed on the phone, with no backend ([docs/COACHING.md](../docs/COACHING.md)). Nothing here is needed for that. This folder is where a backend for the later pieces (coaching voice, drills, chat) would go.

## Possibly reusable from `backend/`

| Piece | Where |
| --- | --- |
| Async runs with status and progress events | `main.py` (`/analysis-runs`), `analysis/run_status.py`, `analysis/run_store.py` |
| R2 upload URLs and signed downloads | `r2_client.py` |
| Codex CLI model calls on the ChatGPT plan | `analysis/codex_client.py` |
| Sourced coaching cases (145 cases from 30 videos) | `docs/coaching-knowledge/`, `analysis/knowledge_library.py` |
| MediaPipe pose | `analysis/pose_detector.py`, `models/pose_landmarker_heavy.task` |
| API key header, blue/green VPS deploy | `main.py`, [DEPLOYMENT.md](../docs/DEPLOYMENT.md) |
