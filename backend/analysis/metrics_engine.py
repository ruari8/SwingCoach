"""Coachable metric cards with confidence and plain-English guidance."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


@dataclass
class MetricCard:
    key: str
    name: str
    value: Optional[float]
    unit: str
    confidence: float
    explanation: str
    fix_hint: str
