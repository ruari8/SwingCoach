#!/usr/bin/env python3
"""Regression checks for async analysis run state."""

from __future__ import annotations

from analysis.run_status import AnalysisRunManager


def test_run_manager_orders_progress_events() -> None:
    manager = AnalysisRunManager()
    state = manager.create("uploads/example.mp4", "DTL", None)

    manager.update(
        state.run_id,
        status="running",
        stage="dense_scan",
        progress=0.25,
        message="Analyzing the swing window",
    )
    manager.complete(state.run_id, result={"analysis_id": state.run_id})

    events = manager.wait_for_events(state.run_id, after_sequence=0)

    assert events is not None
    assert [event["sequence"] for event in events] == [1, 2, 3]
    assert events[-1]["status"] == "succeeded"
    assert events[-1]["progress"] == 1.0
    assert manager.snapshot(state.run_id)["result"]["analysis_id"] == state.run_id


if __name__ == "__main__":
    test_run_manager_orders_progress_events()
    print("analysis run regression checks passed")
