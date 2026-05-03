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
    AnalysisDrill,
    AnalysisMetric,
    AnalysisVideo,
    AnalyzeRequest,
    AnalyzeResponse,
    ArtifactURLRequest,
    ArtifactURLResponse,
    CoachChatRequest,
    CoachChatResponse,
    ArtifactBundleResponse,
    HealthResponse,
    UploadURLResponse,
)
from r2_client import get_r2_client

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

BACKEND_DIR = Path(__file__).parent
MOCK_ANNOTATED_VIDEO_PATH = BACKEND_DIR / "output" / "full_annotation.mp4"
MOCK_ANNOTATED_VIDEO_KEY = "mock/full_annotation.mp4"

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
            "mock_analyze": "/mock/analyze",
            "artifact_url": "/artifact-url",
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


def _format_metric_value(value: Optional[float], unit: str) -> str:
    """Format a metric value for the app-facing MVP response."""
    if value is None:
        return ""

    if unit == ":1":
        formatted = f"{value:.1f}:1"
    elif unit:
        formatted = f"{value:.1f} {unit}"
    else:
        formatted = f"{value:.1f}"

    return formatted.replace(".0 ", " ").replace(".0:", ":")


def _dummy_annotated_video() -> AnalysisVideo:
    """Ensure the dummy annotated video is in R2 and return a signed URL with its key."""
    if not MOCK_ANNOTATED_VIDEO_PATH.exists():
        raise HTTPException(
            status_code=500,
            detail=f"Mock annotated video not found at {MOCK_ANNOTATED_VIDEO_PATH}",
        )

    r2 = get_r2_client()
    if not r2.object_exists(MOCK_ANNOTATED_VIDEO_KEY):
        r2.upload_video(
            MOCK_ANNOTATED_VIDEO_KEY,
            MOCK_ANNOTATED_VIDEO_PATH.read_bytes(),
            content_type="video/mp4",
        )

    return AnalysisVideo(
        key=MOCK_ANNOTATED_VIDEO_KEY,
        url=r2.generate_download_url(MOCK_ANNOTATED_VIDEO_KEY),
    )


def _artifact_video(key: Optional[str], url: Optional[str]) -> Optional[AnalysisVideo]:
    if not key or not url:
        return None
    return AnalysisVideo(key=key, url=url)


@app.post("/artifact-url", response_model=ArtifactURLResponse)
async def artifact_url(request: ArtifactURLRequest):
    """Return a fresh signed URL for an existing R2 artifact key."""
    try:
        r2 = get_r2_client()
        if not r2.object_exists(request.key):
            raise HTTPException(status_code=404, detail="Artifact not found in storage")
        return ArtifactURLResponse(
            key=request.key,
            url=r2.generate_download_url(request.key),
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Artifact URL generation failed: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/mock/analyze", response_model=AnalyzeResponse)
async def mock_analyze_swing(request: AnalyzeRequest):
    """R2-backed dummy analysis used to test the mobile MVP loop without running models."""
    try:
        r2 = get_r2_client()
        if not r2.video_exists(request.video_key):
            raise HTTPException(status_code=404, detail="Video not found in storage")

        return AnalyzeResponse(
            analysis_id=f"mock-{Path(request.video_key).stem}",
            summary=(
                "Demo analysis: your setup looks stable, but you lose posture slightly "
                "as you move through impact."
            ),
            metrics=[
                AnalysisMetric(key="tempo_ratio", name="Tempo", value="3.1:1"),
                AnalysisMetric(key="spine_angle_change", name="Spine Angle Change", value="7 deg"),
                AnalysisMetric(key="head_sway", name="Head Sway", value="1.8 in"),
            ],
            annotated_video=_dummy_annotated_video(),
            drills=[
                AnalysisDrill(
                    title="Chair Drill",
                    summary="Rehearse keeping your hips back through impact to maintain posture.",
                ),
                AnalysisDrill(
                    title="Tempo Count",
                    summary="Use a smooth three-count backswing and one-count downswing.",
                ),
            ],
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Mock analysis failed: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/analyze", response_model=AnalyzeResponse)
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

        metrics = [
            AnalysisMetric(
                key=card.key,
                name=card.name,
                value=_format_metric_value(card.value, card.unit),
            )
            for card in result.metrics
            if card.value is not None
        ]

        return AnalyzeResponse(
            analysis_id=result.run_id,
            summary=result.coaching.summary,
            metrics=metrics,
            annotated_video=_artifact_video(artifacts.annotated_video_key, artifacts.annotated_video_url),
            drills=[
                AnalysisDrill(
                    title=drill.title,
                    summary=drill.summary,
                )
                for drill in result.coaching.drills
            ],
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
