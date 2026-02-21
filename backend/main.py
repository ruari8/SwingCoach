"""FastAPI backend for SwingCoach unified coachable analysis."""

from __future__ import annotations

import logging
from pathlib import Path
from types import SimpleNamespace
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from analysis import SwingCoachPipeline3D
from analysis.coach_response_builder import CoachResponseBuilder, CoachingBundle
from models import (
    AnalyzeRequest,
    CoachChatRequest,
    CoachChatResponse,
    CoachableAnalysisResponse,
    CoachableDrill,
    CoachableMetricCard,
    CoachingBundleResponse,
    ArtifactBundleResponse,
    HealthResponse,
    QualityBundleResponse,
    UploadURLResponse,
)
from r2_client import get_r2_client

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ANALYSIS_AVAILABLE = True
try:
    _pipeline = SwingCoachPipeline3D()
except Exception as exc:  # pragma: no cover - startup guard
    ANALYSIS_AVAILABLE = False
    _pipeline = None
    logger.warning("Pipeline initialization failed: %s", exc)

app = FastAPI(
    title="SwingCoach API",
    description="Unified backend for coachable golf swing analysis",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    return {
        "name": "SwingCoach API",
        "version": "1.0.0",
        "analysis_available": ANALYSIS_AVAILABLE,
        "endpoints": {
            "health": "/health",
            "upload_url": "/upload-url",
            "analyze": "/analyze",
            "chat": "/chat",
        },
    }


@app.get("/health", response_model=HealthResponse)
async def health_check():
    try:
        get_r2_client()
        r2_configured = True
    except Exception as exc:
        logger.error("R2 not configured: %s", exc)
        r2_configured = False

    return HealthResponse(
        status="healthy" if r2_configured else "degraded",
        r2_configured=r2_configured,
        analysis_ready=ANALYSIS_AVAILABLE,
    )


@app.get("/upload-url", response_model=UploadURLResponse)
async def get_upload_url():
    try:
        r2 = get_r2_client()
        result = r2.generate_upload_url()
        return UploadURLResponse(upload_url=result["upload_url"], video_key=result["video_key"])
    except Exception as exc:
        logger.error("Failed to generate upload URL: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


def _upload_run_artifacts(run_id: str, run_dir: Path) -> ArtifactBundleResponse:
    """Upload generated artifacts from local run dir to R2 and return URLs."""
    r2 = get_r2_client()

    annotated_name = "annotated.mp4"
    swing_name = "swing_3d.gltf"

    annotated_path = run_dir / annotated_name
    swing_path = run_dir / swing_name

    annotated_key: Optional[str] = None
    swing_key: Optional[str] = None
    annotated_url: Optional[str] = None
    swing_url: Optional[str] = None

    if annotated_path.exists():
        annotated_key = f"analysis_runs/{run_id}/{annotated_name}"
        r2.upload_video(annotated_key, annotated_path.read_bytes(), content_type="video/mp4")
        annotated_url = r2.generate_download_url(annotated_key)

    if swing_path.exists():
        swing_key = f"analysis_runs/{run_id}/{swing_name}"
        r2.upload_bytes(swing_key, swing_path.read_bytes(), content_type="model/gltf+json")
        swing_url = r2.generate_download_url(swing_key)

    return ArtifactBundleResponse(
        annotated_video_url=annotated_url,
        annotated_video_key=annotated_key,
        swing_3d_url=swing_url,
        swing_3d_key=swing_key,
        debug_urls=[],
    )


@app.post("/analyze", response_model=CoachableAnalysisResponse)
async def analyze_swing(request: AnalyzeRequest):
    if not ANALYSIS_AVAILABLE or _pipeline is None:
        raise HTTPException(status_code=503, detail="Analysis pipeline is unavailable")

    try:
        r2 = get_r2_client()
        if not r2.video_exists(request.video_key):
            raise HTTPException(status_code=404, detail="Video not found in storage")

        logger.info("Starting analysis for %s", request.video_key)
        video_bytes = r2.download_video(request.video_key)
        result = _pipeline.analyze_video(
            video_bytes=video_bytes,
            vantage=request.vantage.value,
            requested_fps=request.fps,
        )

        artifacts = _upload_run_artifacts(result.run_id, Path(result.run_dir))

        metric_cards = [
            CoachableMetricCard(
                key=card.key,
                name=card.name,
                value=card.value,
                unit=card.unit,
                confidence=card.confidence,
                explanation=card.explanation,
                fix_hint=card.fix_hint,
            )
            for card in result.metrics
        ]

        coaching = CoachingBundleResponse(
            summary=result.coaching.summary,
            top_priorities=result.coaching.top_priorities,
            drills=[
                CoachableDrill(
                    id=drill.id,
                    title=drill.title,
                    source=drill.source,
                    summary=drill.summary,
                )
                for drill in result.coaching.drills
            ],
        )

        quality = QualityBundleResponse(
            warnings=result.quality.get("warnings", []),
            missing_data=result.quality.get("missing_data", []),
            timings=result.quality.get("timings", {}),
        )

        return CoachableAnalysisResponse(
            run_id=result.run_id,
            metrics=metric_cards,
            coaching=coaching,
            artifacts=artifacts,
            quality=quality,
        )

    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Analysis failed: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


def _load_run_context(run_id: str):
    run_dir = Path(__file__).parent / "output" / "runs" / run_id
    if not run_dir.exists():
        raise HTTPException(status_code=404, detail="Run ID not found")

    metrics_file = run_dir / "metrics.json"
    coach_file = run_dir / "coach_summary.json"

    if not metrics_file.exists() or not coach_file.exists():
        raise HTTPException(status_code=404, detail="Run context files missing")

    import json

    metrics_payload = json.loads(metrics_file.read_text())
    coach_payload = json.loads(coach_file.read_text())

    metric_cards = [SimpleNamespace(**card) for card in metrics_payload.get("cards", [])]
    coaching_bundle = CoachingBundle(
        summary=coach_payload.get("summary", ""),
        top_priorities=coach_payload.get("top_priorities", []),
        drills=[SimpleNamespace(**drill) for drill in coach_payload.get("drills", [])],
    )
    return metric_cards, coaching_bundle


@app.post("/chat", response_model=CoachChatResponse)
async def coach_chat(request: CoachChatRequest):
    try:
        metric_cards, coaching_bundle = _load_run_context(request.run_id)
        builder = CoachResponseBuilder()
        answer = builder.answer_chat(
            question=request.question,
            metric_cards=metric_cards,
            coaching_bundle=coaching_bundle,
            student_goal=request.student_goal,
        )
        return CoachChatResponse(run_id=request.run_id, answer=answer)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Chat failed: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
