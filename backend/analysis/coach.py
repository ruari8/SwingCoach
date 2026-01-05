"""
LLM-powered swing coaching.
Generates natural language feedback and drill recommendations from metrics.
"""

import os
import json
from typing import Dict, List, Optional
from dataclasses import dataclass
import logging

from .metrics import SwingMetrics
from .event_detector import SwingEvents

logger = logging.getLogger(__name__)

try:
    import openai
    OPENAI_AVAILABLE = True
except ImportError:
    OPENAI_AVAILABLE = False
    logger.warning("OpenAI not installed. LLM coaching will use rule-based fallback.")


@dataclass
class DrillRecommendation:
    """A recommended drill."""
    id: str
    title: str
    description: str
    url: Optional[str] = None
    platform: str = "youtube"
    priority: int = 1


@dataclass
class CoachingFeedback:
    """Complete coaching feedback for a swing."""
    summary: str
    diagnosis: str
    drills: List[DrillRecommendation]
    key_issues: List[str]
    positives: List[str]


DRILL_DATABASE = {
    "head_stability": DrillRecommendation(
        id="head_stability",
        title="Headcover Drill",
        description="Place a headcover on your head during practice swings. Focus on keeping it balanced.",
        url="https://youtube.com/watch?v=example",
        priority=1
    ),
    "early_extension": DrillRecommendation(
        id="early_extension",
        title="Wall Drill for Early Extension",
        description="Set up with your glutes against a wall. Maintain contact through the swing.",
        url="https://youtube.com/watch?v=example2",
        priority=1
    ),
    "shaft_lean": DrillRecommendation(
        id="shaft_lean",
        title="Impact Bag Drill",
        description="Practice hitting an impact bag with forward shaft lean. Feel hands ahead at impact.",
        url="https://youtube.com/watch?v=example3",
        priority=1
    ),
    "hip_slide": DrillRecommendation(
        id="hip_slide",
        title="Hip Rotation Drill",
        description="Focus on rotating hips rather than sliding. Use alignment stick at lead hip.",
        url="https://youtube.com/watch?v=example4",
        priority=2
    ),
    "shoulder_turn": DrillRecommendation(
        id="shoulder_turn",
        title="Full Turn Drill",
        description="Cross arms on chest, practice turning shoulders 90 degrees to target.",
        url="https://youtube.com/watch?v=example5",
        priority=2
    ),
    "tempo": DrillRecommendation(
        id="tempo",
        title="3:1 Tempo Drill",
        description="Count 1-2-3 on backswing, 1 on downswing. Practice with half swings first.",
        url="https://youtube.com/watch?v=example6",
        priority=3
    ),
}


class SwingCoach:
    """Generates coaching feedback from swing metrics."""
    
    def __init__(self, use_llm: bool = True):
        self.use_llm = use_llm and OPENAI_AVAILABLE and os.getenv("OPENAI_API_KEY")
        
        if self.use_llm:
            self.client = openai.OpenAI()
            logger.info("SwingCoach initialized with LLM support")
        else:
            logger.info("SwingCoach initialized with rule-based feedback")
    
    def generate_feedback(
        self,
        metrics: SwingMetrics,
        events: SwingEvents,
        vantage: str = "DTL"
    ) -> CoachingFeedback:
        """
        Generate coaching feedback from swing analysis.
        
        Args:
            metrics: Calculated swing metrics
            events: Detected swing events
            vantage: Camera vantage point
            
        Returns:
            CoachingFeedback with summary, diagnosis, and drills
        """
        issues = self._identify_issues(metrics)
        positives = self._identify_positives(metrics)
        drills = self._recommend_drills(issues)
        
        if self.use_llm:
            try:
                diagnosis = self._generate_llm_diagnosis(metrics, issues, positives, vantage)
                summary = self._generate_llm_summary(metrics, issues)
            except Exception as e:
                logger.error(f"LLM generation failed, falling back to rules: {e}")
                diagnosis = self._generate_rule_diagnosis(metrics, issues)
                summary = self._generate_rule_summary(issues)
        else:
            diagnosis = self._generate_rule_diagnosis(metrics, issues)
            summary = self._generate_rule_summary(issues)
        
        return CoachingFeedback(
            summary=summary,
            diagnosis=diagnosis,
            drills=drills,
            key_issues=issues,
            positives=positives
        )
    
    def _identify_issues(self, metrics: SwingMetrics) -> List[str]:
        """Identify swing issues from metrics."""
        issues = []
        
        if metrics.head_sway_inches is not None and abs(metrics.head_sway_inches) > 2:
            direction = "toward target" if metrics.head_sway_inches > 0 else "away from target"
            issues.append(f"Excessive head sway ({abs(metrics.head_sway_inches):.1f}\" {direction})")
        
        if metrics.head_dip_inches is not None and abs(metrics.head_dip_inches) > 1.5:
            direction = "down" if metrics.head_dip_inches > 0 else "up"
            issues.append(f"Head moving {direction} through impact")
        
        if metrics.spine_angle_change is not None and metrics.spine_angle_change > 5:
            issues.append("Early extension (losing spine angle)")
        
        if metrics.spine_angle_change is not None and metrics.spine_angle_change < -5:
            issues.append("Loss of posture (spine angle decreasing)")
        
        if metrics.shaft_lean_degrees is not None and metrics.shaft_lean_degrees < 0:
            issues.append("Flipping at impact (shaft leaning backward)")
        
        if metrics.hip_slide_inches is not None and metrics.hip_slide_inches > 6:
            issues.append("Excessive hip slide toward target")
        
        if metrics.shoulder_turn_degrees is not None and metrics.shoulder_turn_degrees < 75:
            issues.append("Limited shoulder turn in backswing")
        
        if metrics.tempo_ratio is not None:
            if metrics.tempo_ratio < 2.5:
                issues.append("Rushing the transition (tempo too quick)")
            elif metrics.tempo_ratio > 4.0:
                issues.append("Slow transition (may lose power)")
        
        return issues
    
    def _identify_positives(self, metrics: SwingMetrics) -> List[str]:
        """Identify positive aspects of the swing."""
        positives = []
        
        if metrics.head_sway_inches is not None and abs(metrics.head_sway_inches) < 2:
            positives.append("Good head stability")
        
        if metrics.spine_angle_change is not None and abs(metrics.spine_angle_change) < 5:
            positives.append("Maintained spine angle well")
        
        if metrics.shaft_lean_degrees is not None and metrics.shaft_lean_degrees > 3:
            positives.append("Good forward shaft lean at impact")
        
        if metrics.shoulder_turn_degrees is not None and metrics.shoulder_turn_degrees >= 85:
            positives.append("Full shoulder turn")
        
        if metrics.tempo_ratio is not None and 2.5 <= metrics.tempo_ratio <= 3.5:
            positives.append("Good tempo")
        
        if metrics.x_factor is not None and metrics.x_factor >= 40:
            positives.append("Good X-factor (hip-shoulder separation)")
        
        return positives
    
    def _recommend_drills(self, issues: List[str]) -> List[DrillRecommendation]:
        """Recommend drills based on identified issues."""
        drills = []
        
        for issue in issues:
            issue_lower = issue.lower()
            
            if "head" in issue_lower:
                drills.append(DRILL_DATABASE["head_stability"])
            
            if "early extension" in issue_lower or "spine angle" in issue_lower:
                drills.append(DRILL_DATABASE["early_extension"])
            
            if "flip" in issue_lower or "shaft lean" in issue_lower:
                drills.append(DRILL_DATABASE["shaft_lean"])
            
            if "hip slide" in issue_lower:
                drills.append(DRILL_DATABASE["hip_slide"])
            
            if "shoulder turn" in issue_lower:
                drills.append(DRILL_DATABASE["shoulder_turn"])
            
            if "tempo" in issue_lower or "rushing" in issue_lower:
                drills.append(DRILL_DATABASE["tempo"])
        
        seen = set()
        unique_drills = []
        for drill in drills:
            if drill.id not in seen:
                seen.add(drill.id)
                unique_drills.append(drill)
        
        unique_drills.sort(key=lambda d: d.priority)
        
        return unique_drills[:3]
    
    def _generate_llm_diagnosis(
        self,
        metrics: SwingMetrics,
        issues: List[str],
        positives: List[str],
        vantage: str
    ) -> str:
        """Generate natural language diagnosis using LLM."""
        metrics_dict = metrics.to_dict()
        
        prompt = f"""You are a professional golf instructor analyzing a swing from a {vantage} camera angle.

Swing Metrics:
{json.dumps({k: v for k, v in metrics_dict.items() if v is not None}, indent=2)}

Identified Issues:
{chr(10).join(f"- {issue}" for issue in issues) if issues else "None identified"}

Positive Aspects:
{chr(10).join(f"- {pos}" for pos in positives) if positives else "None identified"}

Provide a 2-3 sentence coaching diagnosis. Focus on the most impactful issue first.
Be direct and actionable. Use golf terminology but explain clearly.
Do not repeat the metrics - explain what they mean for the golfer's swing."""

        response = self.client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are a PGA golf instructor giving concise, actionable feedback."},
                {"role": "user", "content": prompt}
            ],
            max_tokens=200,
            temperature=0.7
        )
        
        return response.choices[0].message.content.strip()
    
    def _generate_llm_summary(self, metrics: SwingMetrics, issues: List[str]) -> str:
        """Generate a one-line summary using LLM."""
        if not issues:
            return "Solid swing fundamentals. Focus on consistency."
        
        prompt = f"""Summarize these golf swing issues in one short sentence (max 15 words):
Issues: {', '.join(issues[:3])}

Be direct. Example: "Head movement and early extension are costing you distance and consistency." """

        response = self.client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[{"role": "user", "content": prompt}],
            max_tokens=50,
            temperature=0.7
        )
        
        return response.choices[0].message.content.strip()
    
    def _generate_rule_diagnosis(self, metrics: SwingMetrics, issues: List[str]) -> str:
        """Generate diagnosis using rules (fallback)."""
        if not issues:
            return "Your swing fundamentals look solid. Continue working on consistency and tempo."
        
        priority_issue = issues[0]
        
        diagnoses = {
            "head": "Your head is moving too much during the swing, which affects your ability to make consistent contact. Focus on keeping your eyes fixed on a spot behind the ball.",
            "early extension": "You're losing your spine angle through impact (early extension). This pushes your body toward the ball and often leads to blocks or hooks. Work on maintaining your posture through the hitting zone.",
            "flip": "You're flipping the club at impact rather than having the shaft leaning forward. This reduces compression and leads to inconsistent distance control. Practice feeling your hands ahead of the clubhead at impact.",
            "hip slide": "Your hips are sliding too much toward the target instead of rotating. This can cause you to hang back and flip. Focus on rotating your lead hip back and around.",
            "shoulder turn": "Your shoulder turn is limited, which reduces your ability to generate power. Work on getting your back to the target at the top of the backswing.",
            "tempo": "Your tempo needs work. A smooth transition from backswing to downswing is crucial for consistent ball striking.",
        }
        
        for key, diagnosis in diagnoses.items():
            if key in priority_issue.lower():
                return diagnosis
        
        return f"Main issue to address: {priority_issue}. Work on this before moving to other aspects of your swing."
    
    def _generate_rule_summary(self, issues: List[str]) -> str:
        """Generate summary using rules (fallback)."""
        if not issues:
            return "Solid swing. Focus on consistency."
        
        if len(issues) == 1:
            return f"Focus on: {issues[0]}"
        
        return f"Priority: {issues[0]}. Also address: {issues[1]}"
