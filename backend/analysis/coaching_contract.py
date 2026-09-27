"""Version-one boundaries between video evidence, the smart coach and the app."""

from typing import Literal
from pydantic import BaseModel, ConfigDict, Field


class Contract(BaseModel):
    model_config = ConfigDict(extra="forbid")


class VisualFinding(Contract):
    id: str
    description: str
    frame_indices: list[int]
    confidence: float = Field(ge=0, le=1)
    topic: str
    phase: Literal["setup", "backswing", "top", "transition", "downswing", "follow_through", "unknown"]


class VisualReview(Contract):
    findings: list[VisualFinding]
    strengths: list[str]
    missing_evidence: list[str]


class PrerequisiteCheck(Contract):
    condition_index: int
    status: Literal["supported", "unknown", "contradicted"]
    observation_ids: list[str]
    explanation: str


class CoachDecision(Contract):
    status: Literal["recommend", "need_evidence", "preserve"]
    summary: str
    focus: str
    rationale: str
    observation_ids: list[str]
    case_id: str | None
    prerequisite_checks: list[PrerequisiteCheck]
    cue: str | None
    reassess: str
    questions: list[str]


class CoachingEvidence(Contract):
    id: str
    description: str
    kind: str
    confidence: float
    timestamps: list[float]


class CoachingSource(Contract):
    case_id: str
    title: str
    publisher: str
    url: str
    start_seconds: float
    end_seconds: float
    review_status: str


class CoachingDetail(Contract):
    version: int = 1
    status: str
    focus: str
    rationale: str
    cue: str | None = None
    reassess: str
    questions: list[str] = Field(default_factory=list)
    evidence: list[CoachingEvidence] = Field(default_factory=list)
    sources: list[CoachingSource] = Field(default_factory=list)
    limitations: list[str] = Field(default_factory=list)
