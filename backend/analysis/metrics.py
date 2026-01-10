"""
Swing metrics calculation.
Computes biomechanical metrics from pose keypoints at key swing positions.
"""

from typing import Dict, Optional, List, Tuple
from dataclasses import dataclass, field
import math
import logging

from .pose_detector import PoseResult, Keypoint
from .event_detector import SwingEvents

logger = logging.getLogger(__name__)


@dataclass
class SwingMetrics:
    """Calculated swing metrics."""
    head_sway_inches: Optional[float] = None
    head_dip_inches: Optional[float] = None
    hip_slide_inches: Optional[float] = None
    hip_turn_degrees: Optional[float] = None
    shoulder_turn_degrees: Optional[float] = None
    spine_angle_address: Optional[float] = None
    spine_angle_impact: Optional[float] = None
    spine_angle_change: Optional[float] = None
    shaft_lean_degrees: Optional[float] = None
    lead_arm_extension: Optional[float] = None
    x_factor: Optional[float] = None
    tempo_ratio: Optional[float] = None

    # Clubhead velocity metrics
    clubhead_peak_speed_mph: Optional[float] = None
    clubhead_impact_speed_mph: Optional[float] = None
    clubhead_speed_confidence: Optional[float] = None

    raw_values: Dict = field(default_factory=dict)
    
    def to_dict(self) -> Dict[str, Optional[float]]:
        return {
            "head_sway_inches": self.head_sway_inches,
            "head_dip_inches": self.head_dip_inches,
            "hip_slide_inches": self.hip_slide_inches,
            "hip_turn_degrees": self.hip_turn_degrees,
            "shoulder_turn_degrees": self.shoulder_turn_degrees,
            "spine_angle_address": self.spine_angle_address,
            "spine_angle_impact": self.spine_angle_impact,
            "spine_angle_change": self.spine_angle_change,
            "shaft_lean_degrees": self.shaft_lean_degrees,
            "lead_arm_extension": self.lead_arm_extension,
            "x_factor": self.x_factor,
            "tempo_ratio": self.tempo_ratio,
            "clubhead_peak_speed_mph": self.clubhead_peak_speed_mph,
            "clubhead_impact_speed_mph": self.clubhead_impact_speed_mph,
            "clubhead_speed_confidence": self.clubhead_speed_confidence,
        }
    
    def to_display_dict(self) -> Dict[str, str]:
        """Format metrics for display with units and context."""
        display = {}
        
        if self.head_sway_inches is not None:
            status = "good" if abs(self.head_sway_inches) < 2 else "too much"
            display["Head Sway"] = f"{self.head_sway_inches:.1f} inches ({status})"
        
        if self.head_dip_inches is not None:
            status = "good" if abs(self.head_dip_inches) < 1.5 else "excessive"
            display["Head Dip"] = f"{self.head_dip_inches:.1f} inches ({status})"
        
        if self.hip_slide_inches is not None:
            status = "good" if 2 <= self.hip_slide_inches <= 5 else "check this"
            display["Hip Slide"] = f"{self.hip_slide_inches:.1f} inches ({status})"
        
        if self.spine_angle_change is not None:
            status = "good" if abs(self.spine_angle_change) < 5 else "early extension" if self.spine_angle_change > 5 else "loss of posture"
            display["Spine Angle Change"] = f"{self.spine_angle_change:.1f}° ({status})"
        
        if self.shaft_lean_degrees is not None:
            status = "forward lean (good)" if self.shaft_lean_degrees > 3 else "flipping (issue)"
            display["Shaft Lean"] = f"{self.shaft_lean_degrees:.1f}° ({status})"
        
        if self.shoulder_turn_degrees is not None:
            status = "good" if self.shoulder_turn_degrees > 80 else "limited"
            display["Shoulder Turn"] = f"{self.shoulder_turn_degrees:.0f}° ({status})"
        
        if self.x_factor is not None:
            display["X-Factor"] = f"{self.x_factor:.0f}°"
        
        if self.tempo_ratio is not None:
            status = "good" if 2.5 <= self.tempo_ratio <= 3.5 else "rushed" if self.tempo_ratio < 2.5 else "slow"
            display["Tempo"] = f"{self.tempo_ratio:.1f}:1 ({status})"

        if self.clubhead_peak_speed_mph is not None:
            # Amateur: 70-100 mph, Pro: 100-130 mph
            if self.clubhead_peak_speed_mph >= 110:
                status = "tour-level"
            elif self.clubhead_peak_speed_mph >= 95:
                status = "good"
            elif self.clubhead_peak_speed_mph >= 80:
                status = "average"
            else:
                status = "below average"
            display["Club Speed"] = f"{self.clubhead_peak_speed_mph:.0f} mph ({status})"

        return display


class MetricsCalculator:
    """Calculates swing metrics from poses at key positions."""
    
    BALL_DIAMETER_INCHES = 1.68
    ASSUMED_SHOULDER_WIDTH_INCHES = 18.0
    
    def __init__(self, frame_width: int = 1920, frame_height: int = 1080):
        self.frame_width = frame_width
        self.frame_height = frame_height
        self._scale_factor: Optional[float] = None
    
    def calculate_metrics(
        self,
        poses: Dict[str, Optional[PoseResult]],
        events: SwingEvents,
        vantage: str = "DTL"
    ) -> SwingMetrics:
        """
        Calculate all swing metrics from poses at key positions.
        
        Args:
            poses: Dict mapping event names to PoseResult
            events: Detected swing events with timing
            vantage: "DTL" or "FO"
            
        Returns:
            SwingMetrics with calculated values
        """
        metrics = SwingMetrics()
        
        address_pose = poses.get("address")
        top_pose = poses.get("top")
        impact_pose = poses.get("impact")
        finish_pose = poses.get("finish")
        
        if address_pose:
            self._estimate_scale(address_pose)
        
        if vantage == "DTL":
            metrics = self._calculate_dtl_metrics(
                address_pose, top_pose, impact_pose, finish_pose, events, metrics
            )
        else:
            metrics = self._calculate_fo_metrics(
                address_pose, top_pose, impact_pose, finish_pose, events, metrics
            )
        
        if events.address and events.top and events.impact:
            metrics.tempo_ratio = self._calculate_tempo(events)
        
        return metrics
    
    def _estimate_scale(self, pose: PoseResult) -> None:
        """Estimate pixels-to-inches conversion from shoulder width."""
        left_shoulder = pose.keypoints.get("left_shoulder")
        right_shoulder = pose.keypoints.get("right_shoulder")
        
        if left_shoulder and right_shoulder:
            shoulder_width_norm = math.sqrt(
                (left_shoulder.x - right_shoulder.x) ** 2 +
                (left_shoulder.y - right_shoulder.y) ** 2
            )
            shoulder_width_pixels = shoulder_width_norm * self.frame_width
            self._scale_factor = self.ASSUMED_SHOULDER_WIDTH_INCHES / shoulder_width_pixels
            logger.debug(f"Scale factor: {self._scale_factor:.4f} inches/pixel")
    
    def _pixels_to_inches(self, pixels: float) -> float:
        """Convert pixel distance to inches."""
        if self._scale_factor is None:
            return pixels * (self.ASSUMED_SHOULDER_WIDTH_INCHES / 150)
        return pixels * self._scale_factor
    
    def _norm_to_inches(self, norm_dist: float) -> float:
        """Convert normalized distance to inches."""
        pixels = norm_dist * self.frame_width
        return self._pixels_to_inches(pixels)
    
    def _calculate_dtl_metrics(
        self,
        address: Optional[PoseResult],
        top: Optional[PoseResult],
        impact: Optional[PoseResult],
        finish: Optional[PoseResult],
        events: SwingEvents,
        metrics: SwingMetrics
    ) -> SwingMetrics:
        """Calculate metrics visible from DTL view."""
        
        if address and impact:
            head_sway = self._calculate_head_sway(address, impact)
            if head_sway is not None:
                metrics.head_sway_inches = self._norm_to_inches(head_sway)
            
            head_dip = self._calculate_head_dip(address, impact)
            if head_dip is not None:
                metrics.head_dip_inches = self._norm_to_inches(head_dip)
            
            hip_slide = self._calculate_hip_slide(address, impact)
            if hip_slide is not None:
                metrics.hip_slide_inches = self._norm_to_inches(hip_slide)
        
        if address:
            metrics.spine_angle_address = self._calculate_spine_angle(address)
        
        if impact:
            metrics.spine_angle_impact = self._calculate_spine_angle(impact)
        
        if metrics.spine_angle_address is not None and metrics.spine_angle_impact is not None:
            metrics.spine_angle_change = metrics.spine_angle_impact - metrics.spine_angle_address
        
        if top:
            metrics.shoulder_turn_degrees = self._estimate_shoulder_turn_dtl(top)
        
        if address and top:
            metrics.x_factor = self._calculate_x_factor(top)
        
        return metrics
    
    def _calculate_fo_metrics(
        self,
        address: Optional[PoseResult],
        top: Optional[PoseResult],
        impact: Optional[PoseResult],
        finish: Optional[PoseResult],
        events: SwingEvents,
        metrics: SwingMetrics
    ) -> SwingMetrics:
        """Calculate metrics visible from Face-On view."""
        
        if address and impact:
            hip_slide = self._calculate_lateral_hip_movement(address, impact)
            if hip_slide is not None:
                metrics.hip_slide_inches = self._norm_to_inches(hip_slide)
        
        if impact:
            metrics.shaft_lean_degrees = self._estimate_shaft_lean(impact)
        
        if top:
            metrics.shoulder_turn_degrees = self._calculate_shoulder_turn_fo(top)
            metrics.hip_turn_degrees = self._calculate_hip_turn_fo(top)
            
            if metrics.shoulder_turn_degrees and metrics.hip_turn_degrees:
                metrics.x_factor = metrics.shoulder_turn_degrees - metrics.hip_turn_degrees
        
        return metrics
    
    def _calculate_head_sway(
        self,
        address: PoseResult,
        impact: PoseResult
    ) -> Optional[float]:
        """Calculate lateral head movement (normalized coords)."""
        addr_nose = address.keypoints.get("nose")
        impact_nose = impact.keypoints.get("nose")
        
        if addr_nose and impact_nose:
            return impact_nose.x - addr_nose.x
        return None
    
    def _calculate_head_dip(
        self,
        address: PoseResult,
        impact: PoseResult
    ) -> Optional[float]:
        """Calculate vertical head movement (normalized coords)."""
        addr_nose = address.keypoints.get("nose")
        impact_nose = impact.keypoints.get("nose")
        
        if addr_nose and impact_nose:
            return impact_nose.y - addr_nose.y
        return None
    
    def _calculate_hip_slide(
        self,
        address: PoseResult,
        impact: PoseResult
    ) -> Optional[float]:
        """Calculate hip lateral movement (DTL view)."""
        addr_left_hip = address.keypoints.get("left_hip")
        addr_right_hip = address.keypoints.get("right_hip")
        impact_left_hip = impact.keypoints.get("left_hip")
        impact_right_hip = impact.keypoints.get("right_hip")
        
        if all([addr_left_hip, addr_right_hip, impact_left_hip, impact_right_hip]):
            addr_center = (addr_left_hip.x + addr_right_hip.x) / 2
            impact_center = (impact_left_hip.x + impact_right_hip.x) / 2
            return impact_center - addr_center
        return None
    
    def _calculate_lateral_hip_movement(
        self,
        address: PoseResult,
        impact: PoseResult
    ) -> Optional[float]:
        """Calculate hip movement toward target (FO view)."""
        return self._calculate_hip_slide(address, impact)
    
    def _calculate_spine_angle(self, pose: PoseResult) -> Optional[float]:
        """Calculate spine angle from vertical (DTL view)."""
        left_hip = pose.keypoints.get("left_hip")
        right_hip = pose.keypoints.get("right_hip")
        left_shoulder = pose.keypoints.get("left_shoulder")
        right_shoulder = pose.keypoints.get("right_shoulder")
        
        if all([left_hip, right_hip, left_shoulder, right_shoulder]):
            hip_center = ((left_hip.x + right_hip.x) / 2, (left_hip.y + right_hip.y) / 2)
            shoulder_center = ((left_shoulder.x + right_shoulder.x) / 2, (left_shoulder.y + right_shoulder.y) / 2)
            
            dx = shoulder_center[0] - hip_center[0]
            dy = shoulder_center[1] - hip_center[1]
            
            angle_from_vertical = math.degrees(math.atan2(dx, -dy))
            return angle_from_vertical
        return None
    
    def _estimate_shoulder_turn_dtl(self, pose: PoseResult) -> Optional[float]:
        """Estimate shoulder turn from DTL view using shoulder width compression."""
        left_shoulder = pose.keypoints.get("left_shoulder")
        right_shoulder = pose.keypoints.get("right_shoulder")
        
        if left_shoulder and right_shoulder:
            visible_width = abs(left_shoulder.x - right_shoulder.x)
            assumed_full_width = 0.15
            
            if visible_width < assumed_full_width:
                compression_ratio = visible_width / assumed_full_width
                compression_ratio = min(1.0, max(0.0, compression_ratio))
                turn_angle = math.degrees(math.acos(compression_ratio))
                return turn_angle
        return None
    
    def _calculate_shoulder_turn_fo(self, pose: PoseResult) -> Optional[float]:
        """Calculate shoulder rotation from Face-On view."""
        left_shoulder = pose.keypoints.get("left_shoulder")
        right_shoulder = pose.keypoints.get("right_shoulder")
        
        if left_shoulder and right_shoulder:
            dx = right_shoulder.x - left_shoulder.x
            dy = right_shoulder.y - left_shoulder.y
            angle = math.degrees(math.atan2(dy, dx))
            return abs(angle)
        return None
    
    def _calculate_hip_turn_fo(self, pose: PoseResult) -> Optional[float]:
        """Calculate hip rotation from Face-On view."""
        left_hip = pose.keypoints.get("left_hip")
        right_hip = pose.keypoints.get("right_hip")
        
        if left_hip and right_hip:
            dx = right_hip.x - left_hip.x
            dy = right_hip.y - left_hip.y
            angle = math.degrees(math.atan2(dy, dx))
            return abs(angle)
        return None
    
    def _calculate_x_factor(self, top_pose: PoseResult) -> Optional[float]:
        """Calculate X-Factor (shoulder-hip differential) at top."""
        shoulder_turn = self._estimate_shoulder_turn_dtl(top_pose)
        
        left_hip = top_pose.keypoints.get("left_hip")
        right_hip = top_pose.keypoints.get("right_hip")
        
        if left_hip and right_hip and shoulder_turn:
            hip_width = abs(left_hip.x - right_hip.x)
            assumed_full_width = 0.12
            
            if hip_width < assumed_full_width:
                compression = hip_width / assumed_full_width
                hip_turn = math.degrees(math.acos(min(1.0, max(0.0, compression))))
                return shoulder_turn - hip_turn
        
        return shoulder_turn
    
    def _estimate_shaft_lean(self, impact_pose: PoseResult) -> Optional[float]:
        """Estimate shaft lean at impact (positive = forward lean)."""
        left_wrist = impact_pose.keypoints.get("left_wrist")
        right_wrist = impact_pose.keypoints.get("right_wrist")
        left_hip = impact_pose.keypoints.get("left_hip")
        right_hip = impact_pose.keypoints.get("right_hip")
        
        if all([left_wrist, right_wrist, left_hip, right_hip]):
            hands_x = (left_wrist.x + right_wrist.x) / 2
            hips_x = (left_hip.x + right_hip.x) / 2
            
            lean = (hips_x - hands_x) * 100
            return lean
        return None
    
    def _calculate_tempo(self, events: SwingEvents) -> Optional[float]:
        """Calculate tempo ratio (backswing time : downswing time)."""
        if events.address and events.top and events.impact:
            backswing_time = events.top.timestamp - events.address.timestamp
            downswing_time = events.impact.timestamp - events.top.timestamp
            
            if downswing_time > 0:
                return backswing_time / downswing_time
        return None
