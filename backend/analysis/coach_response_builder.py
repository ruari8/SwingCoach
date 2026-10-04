"""Grounded visual review, source-case selection and follow-up coaching."""
from __future__ import annotations

import base64
from dataclasses import asdict, dataclass, field
import io
import json
import logging
import os
from pathlib import Path
from typing import Any
from PIL import Image

from .coaching_contract import CoachDecision, CoachingDetail, CoachingEvidence, CoachingSource, VisualReview
from .knowledge_library import KnowledgeLibrary

logger = logging.getLogger(__name__)
PROMPTS = Path(__file__).resolve().parents[1] / "prompts"


@dataclass
class DrillSuggestion:
    id: str
    title: str
    source: str
    summary: str


@dataclass
class CoachingBundle:
    summary: str
    top_priorities: list[str]
    drills: list[DrillSuggestion]
    detail: dict | None = None
    context: dict = field(default_factory=dict)


def intervention_text(value: Any) -> str:
    if isinstance(value, dict):
        return "\n".join(f"{key.replace('_', ' ').capitalize()}: {intervention_text(item)}" for key, item in value.items())
    if isinstance(value, list):
        return "\n".join(intervention_text(item) for item in value)
    return str(value)


class CoachResponseBuilder:
    def __init__(self, *, client=None, library: KnowledgeLibrary | None = None):
        self.library = library or KnowledgeLibrary()
        self.client = client
        if self.client is None and os.getenv("SWINGCOACH_COACH_PROVIDER") == "codex":
            from .codex_client import CodexClient
            self.client = CodexClient()
        elif self.client is None and os.getenv("OPENAI_API_KEY"):
            from openai import OpenAI
            self.client = OpenAI(timeout=90, max_retries=1)
        self.model = os.getenv("SWINGCOACH_COACH_MODEL", "gpt-6.1-sol")
        self.reasoning = {"effort": os.getenv("SWINGCOACH_COACH_REASONING", "low")}

    def _parse(self, schema, prompt_name, content):
        response = self.client.responses.parse(
            model=self.model, reasoning=self.reasoning, store=False,
            instructions=(PROMPTS / prompt_name).read_text(),
            input=[{"role": "user", "content": content}], text_format=schema,
        )
        if response.status != "completed" or response.output_parsed is None:
            raise ValueError("Coach response was incomplete or declined")
        return response.output_parsed

    def observe(self, frames: list[tuple[int, bytes]], context: dict) -> VisualReview:
        content = [{"type": "input_text", "text": json.dumps(context)}]
        for index, image_bytes in frames:
            with Image.open(io.BytesIO(image_bytes)) as image:
                image.thumbnail((768, 768))
                buffer = io.BytesIO()
                image.convert("RGB").save(buffer, "JPEG", quality=80)
            content.extend([
                {"type": "input_text", "text": f"Frame {index}, timestamp {index / context['fps']:.3f}s"},
                {"type": "input_image", "image_url": "data:image/jpeg;base64," + base64.b64encode(buffer.getvalue()).decode(), "detail": "high"},
            ])
        review = self._parse(VisualReview, "visual_observer_v1.md", content)
        supplied = {index for index, _ in frames}
        ids = {o["id"] for o in context["observations"]}
        for finding in review.findings:
            if finding.id in ids:
                raise ValueError("Duplicate observation ID")
            ids.add(finding.id)
            if not finding.frame_indices or not set(finding.frame_indices) <= supplied:
                raise ValueError("Visual finding cites frames the model did not receive")
        return review

    def candidates(self, observations, student_goal):
        selected = {}
        for observation in observations:
            query = observation.get("topic") or observation["description"]
            for case in self.library.search(query, limit=4):
                selected[case["id"]] = case
        if student_goal:
            for case in self.library.search(student_goal, limit=4):
                selected[case["id"]] = case
        for case in list(selected.values()):
            for alternative in case["alternative_case_ids"]:
                if alternative in self.library.cases:
                    selected[alternative] = self.library.cases[alternative]
        return [{k: v for k, v in case.items() if k != "evidence"} for case in selected.values()]

    def validate_decision(self, decision: CoachDecision, observations, candidates):
        by_id = {o["id"]: o for o in observations}
        if not set(decision.observation_ids) <= by_id.keys():
            raise ValueError("Unknown coaching observation reference")
        selected = next((c for c in candidates if c["id"] == decision.case_id), None)
        if decision.case_id and selected is None:
            raise ValueError("Coach selected a case outside the supplied evidence")
        if decision.status != "recommend":
            if decision.cue is not None:
                raise ValueError("Withheld decision must not prescribe a cue")
            return selected
        if not selected or not decision.observation_ids or not decision.cue or not decision.reassess.strip():
            raise ValueError("Recommendation needs a case, evidence, cue and reassessment")
        if not any(by_id[key]["kind"] == "visual_interpretation" for key in decision.observation_ids):
            raise ValueError("A whole-clip metric or reported goal alone cannot diagnose a swing")
        if any(by_id[key]["confidence"] < 0.65 for key in decision.observation_ids):
            raise ValueError("Recommendation relies on low-confidence observations")
        expected = set(range(len(selected["applicability"])))
        checks = decision.prerequisite_checks
        if len(checks) != len(expected) or {c.condition_index for c in checks} != expected:
            raise ValueError("Missing or duplicate prerequisite checks")
        for check in checks:
            if check.status != "supported" or not check.observation_ids:
                raise ValueError("Recommendation has unresolved prerequisites")
            if any(key not in by_id or by_id[key]["confidence"] < 0.65 for key in check.observation_ids):
                raise ValueError("Prerequisite has no reliable evidence")
        return selected

    def build_coaching_bundle(self, metric_cards, quality_warnings, student_goal=None, *,
                              observations=None, frames=None, fps=30.0, vantage="DTL", golfer_context=None):
        observations = list(observations or [])
        observations.extend({"id": f"context.{key}", "kind": "golfer_report", "description": f"{key}: {value}",
                             "confidence": 1.0, "frame_indices": []}
                            for key, value in (golfer_context or {}).items() if value.strip())
        context = {"version": 1, "vantage": vantage, "fps": fps, "student_goal": student_goal,
                   "golfer_context": golfer_context or {}, "observations": observations,
                   "metrics": [asdict(c) for c in metric_cards], "warnings": quality_warnings,
                   "prompt_version": "v1", "model": self.model}
        review = None
        decision = None
        status = "model_unavailable"
        if self.client is not None and frames:
            try:
                review = self.observe(frames, context)
                for finding in review.findings:
                    observations.append({**finding.model_dump(), "kind": "visual_interpretation"})
                context["visual_review"] = review.model_dump()
                candidates = self.candidates(observations, student_goal)
                context["candidate_cases"] = candidates
                decision = self._parse(CoachDecision, "smart_coach_v1.md",
                                       [{"type": "input_text", "text": json.dumps(context)}])
                self.validate_decision(decision, observations, candidates)
                status = decision.status
            except Exception as exc:
                # Model failures must not discard measured video evidence.
                logger.warning("Grounded coach unavailable: %s", type(exc).__name__)
                context["model_error"] = type(exc).__name__
                decision = None
                status = "model_unavailable"
        evidence = [CoachingEvidence(id=o["id"], description=o["description"], kind=o["kind"],
                                     confidence=o["confidence"], timestamps=[i / fps for i in o["frame_indices"]])
                    for o in observations]
        if decision is None:
            summary = ("Your video measurements and reference overlays are ready. "
                       "The coaching model is unavailable, so no swing correction has been selected."
                       if metric_cards else
                       "There isn't enough reliable evidence to select a swing correction from this recording.")
            detail = CoachingDetail(status=status, focus="Establish a useful baseline",
                                    rationale="A movement measurement alone does not establish a fault or the right drill. Compare it with your intended shot and actual result.",
                                    reassess="Record the same club and camera view, and note the strike and ball flight.",
                                    questions=["What club did you use, what shot did you intend, and what actually happened?"],
                                    evidence=evidence, limitations=quality_warnings)
            return CoachingBundle(summary, [detail.focus], [], detail.model_dump(), context)
        context["decision"] = decision.model_dump()
        sources, drills = [], []
        if decision.case_id:
            case = self.library.cases[decision.case_id]
            for item in case["evidence"]:
                sources.append(CoachingSource(case_id=case["id"], title=case["title"], publisher=case["publisher"],
                                               url=case["source_url"], start_seconds=item["span_seconds"][0],
                                               end_seconds=item["span_seconds"][1], review_status=case["review_status"]))
            if decision.status == "recommend":
                drills.append(DrillSuggestion(case["id"], case["title"], case["source_url"], intervention_text(case["intervention"])))
        detail = CoachingDetail(status=status, focus=decision.focus, rationale=decision.rationale, cue=decision.cue,
                                reassess=decision.reassess, questions=decision.questions, evidence=evidence,
                                sources=sources, limitations=quality_warnings + (review.missing_evidence if review else []))
        return CoachingBundle(decision.summary, [decision.focus], drills, detail.model_dump(), context)

    def answer_chat(self, question, metric_cards, coaching_bundle, student_goal=None):
        if self.client is None:
            return coaching_bundle.summary + " " + (coaching_bundle.detail or {}).get("reassess", "")
        context = {**coaching_bundle.context, "coaching": coaching_bundle.detail,
                   "summary": coaching_bundle.summary, "question": question, "student_goal": student_goal}
        try:
            response = self.client.responses.create(
                model=self.model, reasoning=self.reasoning, store=False,
                instructions=(PROMPTS / "smart_coach_v1.md").read_text() +
                "\nAnswer the follow-up in plain text using only this saved run. Do not introduce new diagnoses or drills. "
                "A reported outcome is not a new visual measurement. Explain the selected action, its limits or the next evidence needed.",
                input=json.dumps(context),
            )
            if response.status != "completed" or not response.output_text.strip():
                raise ValueError("Incomplete chat response")
            return response.output_text.strip()
        except Exception:
            return "The coaching model is unavailable. " + coaching_bundle.summary
