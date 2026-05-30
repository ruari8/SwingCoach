"""In-memory analysis run status and event tracking."""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from threading import Condition
from typing import Any, Dict, List, Optional


TERMINAL_STATUSES = {"succeeded", "failed"}


@dataclass
class AnalysisRunState:
    run_id: str
    video_key: str
    vantage: str
    fps: Optional[float]
    status: str = "queued"
    stage: str = "queued"
    progress: float = 0.0
    message: str = "Queued"
    error: Optional[str] = None
    result: Any = None
    created_at: float = field(default_factory=time.time)
    started_at: Optional[float] = None
    completed_at: Optional[float] = None
    sequence: int = 0
    events: List[Dict[str, Any]] = field(default_factory=list)
    condition: Condition = field(default_factory=Condition)


class AnalysisRunManager:
    """Thread-safe status store for locally running analysis jobs."""

    def __init__(self):
        self._runs: Dict[str, AnalysisRunState] = {}

    def create(self, video_key: str, vantage: str, fps: Optional[float]) -> AnalysisRunState:
        run_id = uuid.uuid4().hex[:10]
        state = AnalysisRunState(run_id=run_id, video_key=video_key, vantage=vantage, fps=fps)
        self._runs[run_id] = state
        self.update(run_id, status="queued", stage="queued", progress=0.0, message="Queued")
        return state

    def get(self, run_id: str) -> Optional[AnalysisRunState]:
        return self._runs.get(run_id)

    def update(
        self,
        run_id: str,
        *,
        status: Optional[str] = None,
        stage: Optional[str] = None,
        progress: Optional[float] = None,
        message: Optional[str] = None,
        error: Optional[str] = None,
        result: Any = None,
    ) -> Optional[AnalysisRunState]:
        state = self._runs.get(run_id)
        if state is None:
            return None

        with state.condition:
            now = time.time()
            if status is not None:
                state.status = status
                if status == "running" and state.started_at is None:
                    state.started_at = now
                if status in TERMINAL_STATUSES:
                    state.completed_at = now
            if stage is not None:
                state.stage = stage
            if progress is not None:
                state.progress = max(0.0, min(1.0, float(progress)))
            if message is not None:
                state.message = message
            if error is not None:
                state.error = error
            if result is not None:
                state.result = result

            state.sequence += 1
            event = self._event_from_state(state, now)
            state.events.append(event)
            state.condition.notify_all()
            return state

    def fail(self, run_id: str, message: str) -> None:
        self.update(
            run_id,
            status="failed",
            stage="failed",
            progress=1.0,
            message="Analysis failed",
            error=message,
        )

    def complete(self, run_id: str, result: Any) -> None:
        self.update(
            run_id,
            status="succeeded",
            stage="complete",
            progress=1.0,
            message="Analysis complete",
            result=result,
        )

    def snapshot(self, run_id: str) -> Optional[Dict[str, Any]]:
        state = self._runs.get(run_id)
        if state is None:
            return None
        with state.condition:
            return {
                "run_id": state.run_id,
                "status": state.status,
                "stage": state.stage,
                "progress": state.progress,
                "message": state.message,
                "error": state.error,
                "result": state.result,
                "created_at": state.created_at,
                "started_at": state.started_at,
                "completed_at": state.completed_at,
                "sequence": state.sequence,
            }

    def wait_for_events(
        self,
        run_id: str,
        after_sequence: int,
        timeout: float = 15.0,
    ) -> Optional[List[Dict[str, Any]]]:
        state = self._runs.get(run_id)
        if state is None:
            return None

        with state.condition:
            if state.sequence <= after_sequence and state.status not in TERMINAL_STATUSES:
                state.condition.wait(timeout=timeout)
            return [event for event in state.events if event["sequence"] > after_sequence]

    def _event_from_state(self, state: AnalysisRunState, timestamp: float) -> Dict[str, Any]:
        return {
            "run_id": state.run_id,
            "sequence": state.sequence,
            "status": state.status,
            "stage": state.stage,
            "progress": state.progress,
            "message": state.message,
            "error": state.error,
            "created_at": state.created_at,
            "started_at": state.started_at,
            "completed_at": state.completed_at,
            "timestamp": timestamp,
        }
