"""Source-backed coaching cases shared by the local viewer and coaching pipeline.

Loading a case establishes provenance, not applicability to a new golfer.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path


class KnowledgeLibrary:
    def __init__(self, directory: Path | None = None):
        self.directory = directory or Path(os.environ.get(
            "SWINGCOACH_KNOWLEDGE_DIR",
            str(Path(__file__).resolve().parents[2] / "docs/coaching-knowledge/sources"),
        ))
        paths = sorted(self.directory.glob("*.json"))
        if not paths:
            raise FileNotFoundError(f"No coaching source records in {self.directory}")
        self.sources = {}
        self.cases = {}
        for path in paths:
            source = json.loads(path.read_text())
            source_id = source["source_id"]
            if source_id in self.sources:
                raise ValueError(f"Duplicate source: {source_id}")
            self.sources[source_id] = source
            evidence = {item["id"]: item for item in source["evidence"]}
            for case in source["cases"]:
                if case["id"] in self.cases:
                    raise ValueError(f"Duplicate case: {case['id']}")
                self.cases[case["id"]] = {
                    **case,
                    "source_id": source_id,
                    "source_title": source["title"],
                    "publisher": source["publisher"],
                    "source_url": source["url"],
                    "evidence": [evidence[key] for key in case["evidence_ids"]],
                }

    def catalogue(self) -> dict:
        return {"sources": list(self.sources.values()), "cases": list(self.cases.values())}

    def search(self, query: str, limit: int = 12) -> list[dict]:
        """Retrieve candidates for review. Search rank is never diagnostic confidence."""
        stopwords = {"the", "a", "an", "and", "or", "of", "to", "in", "on", "at", "is", "are", "as", "with",
                     "from", "for", "this", "that", "your", "across", "clip", "visible", "image", "range", "change"}
        terms = set(re.findall(r"[a-z0-9]+", query.lower())) - stopwords
        ranked = []
        for case in self.cases.values():
            searchable = json.dumps({key: case[key] for key in (
                "title", "tags", "coaching_finding", "coach_reasoning", "applicability"
            )}).lower()
            words = set(re.findall(r"[a-z0-9]+", searchable))
            title_tags = set(re.findall(r"[a-z0-9]+", (case["title"] + json.dumps(case["tags"])).lower()))
            def matches(term, vocabulary):
                return term in vocabulary or (len(term) >= 4 and any(word.startswith(term) for word in vocabulary))
            score = sum(matches(term, words) + 2 * matches(term, title_tags) for term in terms)
            if score:
                ranked.append((score, case))
        ranked.sort(key=lambda item: (-item[0], item[1]["id"]))
        return [case for _, case in ranked[:limit]]
