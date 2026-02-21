"""Run artifact management and stage timing helpers."""

from __future__ import annotations

import json
import time
import uuid
from contextlib import contextmanager
from dataclasses import asdict, is_dataclass
from pathlib import Path
from typing import Any, Dict, Iterator, Optional

import numpy as np


def _to_serializable(value: Any) -> Any:
    """Recursively convert numpy/dataclass values to JSON-serializable data."""
    if is_dataclass(value):
        return _to_serializable(asdict(value))
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, (np.floating, np.integer)):
        return value.item()
    if isinstance(value, dict):
        return {k: _to_serializable(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_to_serializable(v) for v in value]
    return value


class RunStore:
    """Stores all artifacts for a single pipeline run."""

    def __init__(self, root_dir: Path, run_id: Optional[str] = None):
        self.root_dir = root_dir
        self.run_id = run_id or uuid.uuid4().hex[:10]
        self.run_dir = self.root_dir / self.run_id
        self.debug_dir = self.run_dir / "debug_overlays"
        self.timings: Dict[str, Dict[str, Any]] = {}

        self.run_dir.mkdir(parents=True, exist_ok=True)
        self.debug_dir.mkdir(parents=True, exist_ok=True)

    def path(self, name: str) -> Path:
        return self.run_dir / name

    def save_json(self, name: str, payload: Any) -> Path:
        output = self.path(name)
        output.write_text(json.dumps(_to_serializable(payload), indent=2))
        return output

    def save_npz(self, name: str, **arrays: Any) -> Path:
        output = self.path(name)
        serializable = {k: np.array(_to_serializable(v), dtype=object) for k, v in arrays.items()}
        np.savez_compressed(output, **serializable)
        return output

    def save_bytes(self, name: str, payload: bytes) -> Path:
        output = self.path(name)
        output.write_bytes(payload)
        return output

    @contextmanager
    def stage(self, stage_name: str, details: Optional[Dict[str, Any]] = None) -> Iterator[None]:
        """Time a stage and store metadata."""
        start = time.perf_counter()
        try:
            yield
        finally:
            elapsed = time.perf_counter() - start
            entry: Dict[str, Any] = {"seconds": round(elapsed, 4)}
            if details:
                entry.update(_to_serializable(details))
            self.timings[stage_name] = entry

    def add_timing_details(self, stage_name: str, details: Dict[str, Any]) -> None:
        self.timings.setdefault(stage_name, {})
        self.timings[stage_name].update(_to_serializable(details))

    def finalize_timings(self) -> Path:
        return self.save_json("timings.json", self.timings)

