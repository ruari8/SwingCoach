"""LLM-backed coaching summary and grounded chat answers."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional


@dataclass
class DrillSuggestion:
    id: str
    title: str
    source: str
    summary: str


@dataclass
class CoachingBundle:
    summary: str
    top_priorities: List[str]
    drills: List[DrillSuggestion]


class CoachResponseBuilder:
    """Builds coaching seed output and follow-up chat responses."""

    def __init__(self, drill_corpus_path: Optional[Path] = None):
        self.drill_corpus_path = drill_corpus_path or (Path(__file__).parent.parent / "data" / "curated_drills.json")
        self.drills = self._load_drills()
        self.client = None

        api_key = os.getenv("OPENAI_API_KEY")
        if api_key:
            try:
                from openai import OpenAI

                self.client = OpenAI(api_key=api_key)
            except Exception:
                self.client = None

    def _load_drills(self) -> List[Dict[str, Any]]:
        if not self.drill_corpus_path.exists():
            return []
        try:
            return json.loads(self.drill_corpus_path.read_text())
        except Exception:
            return []

    def _pick_priorities(self, metric_cards: List[Any], max_items: int = 2) -> List[str]:
        scored = []
        for card in metric_cards:
            if card.value is None or card.confidence < 0.35:
                continue
            # crude severity estimate: larger normalized magnitude => higher priority
            magnitude = abs(float(card.value))
            scored.append((magnitude * card.confidence, card.name, card.fix_hint))

        scored.sort(reverse=True, key=lambda item: item[0])
        priorities = [f"{name}: {hint}" for _, name, hint in scored[:max_items]]
        if not priorities:
            priorities = ["Capture quality or detection confidence was too low for strong coaching priorities."]
        return priorities

    def _drills_for_priorities(self, priorities: List[str], limit: int = 3) -> List[DrillSuggestion]:
        if not self.drills:
            return []

        text = " ".join(priorities).lower()
        selected: List[DrillSuggestion] = []
        seen = set()
        for drill in self.drills:
            tags = [tag.lower() for tag in drill.get("fault_tags", [])]
            if not any(tag.replace("_", " ") in text or tag in text for tag in tags):
                continue
            did = drill.get("id")
            if did in seen:
                continue
            seen.add(did)
            selected.append(
                DrillSuggestion(
                    id=did,
                    title=drill.get("title", "Drill"),
                    source=drill.get("source", ""),
                    summary=drill.get("summary", ""),
                )
            )
            if len(selected) >= limit:
                break
        return selected

    def _fallback_summary(self, priorities: List[str], warnings: List[str]) -> str:
        lead = priorities[0] if priorities else "No high-confidence priority found."
        if warnings:
            return f"Primary focus: {lead}. Note: {warnings[0]}"
        return f"Primary focus: {lead}"

    def build_coaching_bundle(self, metric_cards: List[Any], quality_warnings: List[str], student_goal: Optional[str] = None) -> CoachingBundle:
        priorities = self._pick_priorities(metric_cards)
        drills = self._drills_for_priorities(priorities)

        if self.client is None:
            return CoachingBundle(
                summary=self._fallback_summary(priorities, quality_warnings),
                top_priorities=priorities,
                drills=drills,
            )

        metric_lines = [
            f"- {card.name}: {card.value} {card.unit} (confidence {card.confidence:.2f})"
            for card in metric_cards
            if card.value is not None
        ]

        prompt = (
            "You are a golf coach. Write a short, plain-English diagnosis in 2-3 sentences. "
            "Focus only on high confidence findings and practical fixes.\n\n"
            f"Student goal: {student_goal or 'Improve consistency and contact'}\n"
            f"Priorities: {priorities}\n"
            f"Quality warnings: {quality_warnings}\n"
            "Metrics:\n"
            + "\n".join(metric_lines)
        )

        try:
            resp = self.client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[
                    {"role": "system", "content": "You are a concise PGA-style coach."},
                    {"role": "user", "content": prompt},
                ],
                temperature=0.4,
                max_tokens=220,
            )
            summary = (resp.choices[0].message.content or "").strip()
        except Exception:
            summary = self._fallback_summary(priorities, quality_warnings)

        return CoachingBundle(summary=summary, top_priorities=priorities, drills=drills)

    def answer_chat(self, question: str, metric_cards: List[Any], coaching_bundle: CoachingBundle, student_goal: Optional[str] = None) -> str:
        if self.client is None:
            return (
                "I can answer using this run's metrics. "
                "Main priorities are: "
                + "; ".join(coaching_bundle.top_priorities[:2])
            )

        metric_lines = [
            f"- {card.name}: {card.value} {card.unit} (confidence {card.confidence:.2f})"
            for card in metric_cards
        ]

        prompt = (
            "Answer the golfer's question using only the provided run context. "
            "If confidence is low for a related metric, state uncertainty clearly.\n\n"
            f"Student goal: {student_goal or 'General improvement'}\n"
            f"Coaching summary: {coaching_bundle.summary}\n"
            f"Top priorities: {coaching_bundle.top_priorities}\n"
            "Run metrics:\n"
            + "\n".join(metric_lines)
            + f"\n\nQuestion: {question}"
        )

        try:
            resp = self.client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[
                    {"role": "system", "content": "You are an evidence-grounded swing coach."},
                    {"role": "user", "content": prompt},
                ],
                temperature=0.3,
                max_tokens=320,
            )
            return (resp.choices[0].message.content or "").strip()
        except Exception:
            return "I couldn't reach the coaching model right now. Please retry your question."

