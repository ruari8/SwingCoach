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
    """All detected swing events."""
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
