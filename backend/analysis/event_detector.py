"""
Swing event detection.
Identifies key positions in the golf swing (address, top, impact, finish).
"""

from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass
import logging
import math

from .pose_detector import PoseResult

logger = logging.getLogger(__name__)


@dataclass
class SwingEvent:
    """A detected swing event."""
    name: str
    frame_index: int
    timestamp: float
    confidence: float


@dataclass
class SwingEvents:
    """All detected swing events (legacy 4-event system)."""
    address: Optional[SwingEvent]
    top: Optional[SwingEvent]
    impact: Optional[SwingEvent]
    finish: Optional[SwingEvent]

    def to_dict(self) -> Dict:
        return {
            "address": self._event_to_dict(self.address),
            "top": self._event_to_dict(self.top),
            "impact": self._event_to_dict(self.impact),
            "finish": self._event_to_dict(self.finish),
        }

    def _event_to_dict(self, event: Optional[SwingEvent]) -> Optional[Dict]:
        if event is None:
            return None
        return {
            "frame": event.frame_index,
            "timestamp": event.timestamp,
            "confidence": event.confidence
        }


# Phase definitions for P1-P10 system
PHASE_NAMES = {
    1: "address",
    2: "takeaway",
    3: "early_backswing",
    4: "mid_backswing",
    5: "top",
    6: "transition",
    7: "early_downswing",
    8: "impact",
    9: "early_followthrough",
    10: "finish",
}

PHASE_DESCRIPTIONS = {
    1: "Address - Setup position",
    2: "Takeaway - Club moves away from ball",
    3: "Early Backswing - Hands at hip height",
    4: "Mid Backswing - Hands at chest height",
    5: "Top - Peak of backswing",
    6: "Transition - Start of downswing",
    7: "Early Downswing - Hands dropping",
    8: "Impact - Ball strike",
    9: "Early Follow-through - Post-impact rotation",
    10: "Finish - Final balanced position",
}


@dataclass
class SwingPhase:
    """A detected swing phase (P1-P10)."""
    phase_number: int
    name: str
    frame_index: int
    timestamp: float
    confidence: float
    description: str = ""

    def to_dict(self) -> Dict:
        return {
            "phase": self.phase_number,
            "name": self.name,
            "frame": self.frame_index,
            "timestamp": round(self.timestamp, 3),
            "confidence": round(self.confidence, 2),
            "description": self.description,
        }


@dataclass
class SwingPhases:
    """All 10 swing phases (P1-P10)."""
    phases: List[SwingPhase]

    @property
    def address(self) -> Optional[SwingPhase]:
        return self._get_phase(1)

    @property
    def takeaway(self) -> Optional[SwingPhase]:
        return self._get_phase(2)

    @property
    def early_backswing(self) -> Optional[SwingPhase]:
        return self._get_phase(3)

    @property
    def mid_backswing(self) -> Optional[SwingPhase]:
        return self._get_phase(4)

    @property
    def top(self) -> Optional[SwingPhase]:
        return self._get_phase(5)

    @property
    def transition(self) -> Optional[SwingPhase]:
        return self._get_phase(6)

    @property
    def early_downswing(self) -> Optional[SwingPhase]:
        return self._get_phase(7)

    @property
    def impact(self) -> Optional[SwingPhase]:
        return self._get_phase(8)

    @property
    def early_followthrough(self) -> Optional[SwingPhase]:
        return self._get_phase(9)

    @property
    def finish(self) -> Optional[SwingPhase]:
        return self._get_phase(10)

    def _get_phase(self, phase_num: int) -> Optional[SwingPhase]:
        for p in self.phases:
            if p.phase_number == phase_num:
                return p
        return None

    def to_dict(self) -> Dict:
        return {
            "phases": [p.to_dict() for p in self.phases],
            "phase_count": len(self.phases),
        }

    def to_events(self) -> SwingEvents:
        """Convert to legacy SwingEvents for backward compatibility."""
        def phase_to_event(phase: Optional[SwingPhase]) -> Optional[SwingEvent]:
            if phase is None:
                return None
            return SwingEvent(
                name=phase.name,
                frame_index=phase.frame_index,
                timestamp=phase.timestamp,
                confidence=phase.confidence
            )

        return SwingEvents(
            address=phase_to_event(self.address),
            top=phase_to_event(self.top),
            impact=phase_to_event(self.impact),
            finish=phase_to_event(self.finish)
        )


class EventDetector:
    """Detects key swing events from pose sequences."""
    
    def __init__(self, fps: float = 30.0):
        self.fps = fps
    
    def detect_events(
        self,
        poses: List[Optional[PoseResult]],
        vantage: str = "DTL"
    ) -> SwingEvents:
        """
        Detect swing events from a sequence of poses.
        
        Uses motion analysis and pose geometry to identify:
        - Address: Initial stable position
        - Top: Maximum backswing (hands highest, shoulder turn max)
        - Impact: Hands return to ball position, maximum speed
        - Finish: Final stable position
        
        Args:
            poses: List of PoseResult from pose detection
            vantage: "DTL" or "FO" for different detection strategies
            
        Returns:
            SwingEvents with detected positions
        """
        valid_poses = [(i, p) for i, p in enumerate(poses) if p is not None]
        
        if len(valid_poses) < 4:
            logger.warning("Not enough valid poses to detect events")
            return SwingEvents(None, None, None, None)
        
        hand_positions = self._get_hand_trajectory(valid_poses)
        motion = self._calculate_motion(hand_positions)
        
        address_idx = self._find_address(valid_poses, motion)
        top_idx = self._find_top(valid_poses, hand_positions, motion, address_idx)
        impact_idx = self._find_impact(valid_poses, hand_positions, motion, top_idx)
        finish_idx = self._find_finish(valid_poses, motion, impact_idx)
        
        def make_event(name: str, idx: Optional[int]) -> Optional[SwingEvent]:
            if idx is None:
                return None
            frame_idx = valid_poses[idx][0]
            pose = valid_poses[idx][1]
            return SwingEvent(
                name=name,
                frame_index=frame_idx,
                timestamp=frame_idx / self.fps,
                confidence=pose.confidence if pose else 0.5
            )
        
        events = SwingEvents(
            address=make_event("address", address_idx),
            top=make_event("top", top_idx),
            impact=make_event("impact", impact_idx),
            finish=make_event("finish", finish_idx)
        )
        
        logger.info(f"Detected events: address={address_idx}, top={top_idx}, impact={impact_idx}, finish={finish_idx}")
        
        return events
    
    def _get_hand_trajectory(
        self,
        valid_poses: List[Tuple[int, PoseResult]]
    ) -> List[Tuple[float, float]]:
        """Extract hand positions through swing (average of both wrists)."""
        positions = []
        for _, pose in valid_poses:
            left = pose.keypoints.get("left_wrist")
            right = pose.keypoints.get("right_wrist")
            
            if left and right:
                x = (left.x + right.x) / 2
                y = (left.y + right.y) / 2
                positions.append((x, y))
            elif left:
                positions.append((left.x, left.y))
            elif right:
                positions.append((right.x, right.y))
            else:
                positions.append(positions[-1] if positions else (0.5, 0.5))
        
        return positions
    
    def _calculate_motion(
        self,
        positions: List[Tuple[float, float]]
    ) -> List[float]:
        """Calculate frame-to-frame motion magnitude."""
        motion = [0.0]
        for i in range(1, len(positions)):
            dx = positions[i][0] - positions[i-1][0]
            dy = positions[i][1] - positions[i-1][1]
            motion.append(math.sqrt(dx**2 + dy**2))
        return motion
    
    def _find_address(
        self,
        valid_poses: List[Tuple[int, PoseResult]],
        motion: List[float]
    ) -> Optional[int]:
        """Find address position (first stable frame before motion starts)."""
        window = 3
        threshold = 0.005
        
        for i in range(len(motion) - window):
            avg_motion = sum(motion[i:i+window]) / window
            if avg_motion < threshold:
                continue
            return max(0, i - 1)
        
        return 0
    
    def _find_top(
        self,
        valid_poses: List[Tuple[int, PoseResult]],
        hand_positions: List[Tuple[float, float]],
        motion: List[float],
        address_idx: Optional[int]
    ) -> Optional[int]:
        """Find top of backswing (hands highest relative to body, motion slows)."""
        start = address_idx + 1 if address_idx else 1
        
        min_y = float('inf')
        min_y_idx = start
        
        for i in range(start, len(hand_positions)):
            y = hand_positions[i][1]
            if y < min_y:
                min_y = y
                min_y_idx = i
            
            if i > min_y_idx + 5:
                break
        
        return min_y_idx
    
    def _find_impact(
        self,
        valid_poses: List[Tuple[int, PoseResult]],
        hand_positions: List[Tuple[float, float]],
        motion: List[float],
        top_idx: Optional[int]
    ) -> Optional[int]:
        """Find impact (hands return to address-ish position, maximum speed)."""
        start = top_idx + 1 if top_idx else len(motion) // 2
        
        max_motion = 0.0
        max_motion_idx = start
        
        for i in range(start, len(motion)):
            if motion[i] > max_motion:
                max_motion = motion[i]
                max_motion_idx = i
        
        return max_motion_idx
    
    def _find_finish(
        self,
        valid_poses: List[Tuple[int, PoseResult]],
        motion: List[float],
        impact_idx: Optional[int]
    ) -> Optional[int]:
        """Find finish position (stable position after impact)."""
        start = impact_idx + 1 if impact_idx else len(motion) - 10
        
        window = 3
        threshold = 0.008
        
        for i in range(start, len(motion) - window):
            avg_motion = sum(motion[i:i+window]) / window
            if avg_motion < threshold:
                return i + window
        
        return len(motion) - 1
    
    def get_key_frame_indices(self, events: SwingEvents) -> List[int]:
        """Get list of frame indices for all detected events."""
        indices = []
        for event in [events.address, events.top, events.impact, events.finish]:
            if event:
                indices.append(event.frame_index)
        return sorted(set(indices))

    def detect_phases(
        self,
        poses: List[Optional[PoseResult]],
        vantage: str = "DTL"
    ) -> SwingPhases:
        """
        Detect all 10 swing phases (P1-P10).

        Phases:
        - P1: Address - Initial stable position
        - P2: Takeaway - Motion starts, hands move away
        - P3: Early Backswing - Hands at ~hip height
        - P4: Mid Backswing - Hands at ~chest height
        - P5: Top - Maximum backswing (hands highest)
        - P6: Transition - Motion begins increasing after top
        - P7: Early Downswing - Hands dropping toward impact
        - P8: Impact - Maximum hand speed
        - P9: Early Follow-through - Hands rising post-impact
        - P10: Finish - Final stable position

        Args:
            poses: List of PoseResult from pose detection
            vantage: "DTL" or "FO"

        Returns:
            SwingPhases with all detected phases
        """
        valid_poses = [(i, p) for i, p in enumerate(poses) if p is not None]

        if len(valid_poses) < 4:
            logger.warning("Not enough valid poses to detect phases")
            return SwingPhases(phases=[])

        hand_positions = self._get_hand_trajectory(valid_poses)
        motion = self._calculate_motion(hand_positions)

        # First detect anchor phases (P1, P5, P8, P10) using existing logic
        address_idx = self._find_address(valid_poses, motion)
        top_idx = self._find_top(valid_poses, hand_positions, motion, address_idx)
        impact_idx = self._find_impact(valid_poses, hand_positions, motion, top_idx)
        finish_idx = self._find_finish(valid_poses, motion, impact_idx)

        # Then detect intermediate phases
        takeaway_idx = self._find_takeaway(motion, address_idx, top_idx)
        early_backswing_idx = self._find_backswing_position(
            hand_positions, address_idx, top_idx, target_ratio=0.33
        )
        mid_backswing_idx = self._find_backswing_position(
            hand_positions, address_idx, top_idx, target_ratio=0.66
        )
        transition_idx = self._find_transition(motion, top_idx, impact_idx)
        early_downswing_idx = self._find_downswing_position(
            hand_positions, top_idx, impact_idx, target_ratio=0.5
        )
        early_followthrough_idx = self._find_early_followthrough(
            hand_positions, motion, impact_idx, finish_idx
        )

        # Build phases list
        def make_phase(
            phase_num: int,
            idx: Optional[int]
        ) -> Optional[SwingPhase]:
            if idx is None or idx < 0 or idx >= len(valid_poses):
                return None
            frame_idx = valid_poses[idx][0]
            pose = valid_poses[idx][1]
            return SwingPhase(
                phase_number=phase_num,
                name=PHASE_NAMES[phase_num],
                frame_index=frame_idx,
                timestamp=frame_idx / self.fps,
                confidence=pose.confidence if pose else 0.5,
                description=PHASE_DESCRIPTIONS[phase_num]
            )

        phases = []
        phase_indices = [
            (1, address_idx),
            (2, takeaway_idx),
            (3, early_backswing_idx),
            (4, mid_backswing_idx),
            (5, top_idx),
            (6, transition_idx),
            (7, early_downswing_idx),
            (8, impact_idx),
            (9, early_followthrough_idx),
            (10, finish_idx),
        ]

        for phase_num, idx in phase_indices:
            phase = make_phase(phase_num, idx)
            if phase is not None:
                phases.append(phase)

        # Sort by frame index to ensure temporal order
        phases.sort(key=lambda p: p.frame_index)

        logger.info(f"Detected {len(phases)} phases: {[p.name for p in phases]}")

        return SwingPhases(phases=phases)

    def _find_takeaway(
        self,
        motion: List[float],
        address_idx: Optional[int],
        top_idx: Optional[int]
    ) -> Optional[int]:
        """
        P2: Find takeaway - first sustained motion increase after address.
        """
        if address_idx is None or top_idx is None:
            return None

        start = address_idx + 1
        end = min(top_idx, len(motion))

        threshold = 0.008  # Motion threshold for "active" movement
        sustained_frames = 2  # Need this many frames above threshold

        for i in range(start, end - sustained_frames):
            if all(motion[j] > threshold for j in range(i, i + sustained_frames)):
                return i

        # Fallback: 10% into backswing
        return start + max(1, (end - start) // 10)

    def _find_backswing_position(
        self,
        hand_positions: List[Tuple[float, float]],
        address_idx: Optional[int],
        top_idx: Optional[int],
        target_ratio: float
    ) -> Optional[int]:
        """
        P3/P4: Find backswing position at target_ratio of the way to top.
        Uses Y-coordinate interpolation (lower Y = higher hands).
        """
        if address_idx is None or top_idx is None:
            return None

        if address_idx >= top_idx:
            return None

        address_y = hand_positions[address_idx][1]
        top_y = hand_positions[top_idx][1]

        # Target Y value (interpolate between address and top)
        target_y = address_y + (top_y - address_y) * target_ratio

        # Find frame closest to target Y
        best_idx = address_idx
        best_diff = float('inf')

        for i in range(address_idx + 1, top_idx):
            diff = abs(hand_positions[i][1] - target_y)
            if diff < best_diff:
                best_diff = diff
                best_idx = i

        return best_idx

    def _find_transition(
        self,
        motion: List[float],
        top_idx: Optional[int],
        impact_idx: Optional[int]
    ) -> Optional[int]:
        """
        P6: Find transition - first frame after top where motion increases.
        This is the "pause" point before downswing accelerates.
        """
        if top_idx is None or impact_idx is None:
            return None

        # Look for minimum motion point after top (the pause)
        # Then return the frame where motion starts increasing
        search_end = min(top_idx + 10, impact_idx)

        min_motion = float('inf')
        min_idx = top_idx + 1

        for i in range(top_idx + 1, search_end):
            if i < len(motion) and motion[i] < min_motion:
                min_motion = motion[i]
                min_idx = i

        # Return frame after the minimum (start of acceleration)
        return min(min_idx + 1, impact_idx - 1)

    def _find_downswing_position(
        self,
        hand_positions: List[Tuple[float, float]],
        top_idx: Optional[int],
        impact_idx: Optional[int],
        target_ratio: float
    ) -> Optional[int]:
        """
        P7: Find downswing position at target_ratio of the way to impact.
        """
        if top_idx is None or impact_idx is None:
            return None

        if top_idx >= impact_idx:
            return None

        top_y = hand_positions[top_idx][1]
        impact_y = hand_positions[impact_idx][1]

        # Target Y value
        target_y = top_y + (impact_y - top_y) * target_ratio

        # Find frame closest to target Y
        best_idx = top_idx
        best_diff = float('inf')

        for i in range(top_idx + 1, impact_idx):
            diff = abs(hand_positions[i][1] - target_y)
            if diff < best_diff:
                best_diff = diff
                best_idx = i

        return best_idx

    def _find_early_followthrough(
        self,
        hand_positions: List[Tuple[float, float]],
        motion: List[float],
        impact_idx: Optional[int],
        finish_idx: Optional[int]
    ) -> Optional[int]:
        """
        P9: Find early follow-through - hands rising after impact.
        Look for when hands start moving upward post-impact.
        """
        if impact_idx is None or finish_idx is None:
            return None

        if impact_idx >= finish_idx:
            return None

        # Find where hands start rising (Y decreasing = hands going up)
        # after the initial impact motion
        search_start = impact_idx + 2  # Skip immediate impact frames
        search_end = min(impact_idx + 10, finish_idx)

        impact_y = hand_positions[impact_idx][1]

        for i in range(search_start, search_end):
            if i < len(hand_positions):
                # Hands have risen significantly from impact
                if hand_positions[i][1] < impact_y - 0.05:
                    return i

        # Fallback: 30% into follow-through
        return impact_idx + max(1, (finish_idx - impact_idx) // 3)
