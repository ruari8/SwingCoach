"""
Export smoothed 3D pose sequences to animated GLTF files.

Creates GLTF animation files that can be viewed in any 3D viewer.
Uses direct JSON/binary GLTF format for maximum compatibility.
"""

import numpy as np
import logging
import json
import base64
import struct
from typing import List, Dict, Optional
from pathlib import Path

logger = logging.getLogger(__name__)


class AnimationExporter:
    """Export 3D pose sequences to animated GLTF files."""

    def __init__(self):
        """Initialize exporter."""
        self.buffer_data = bytearray()
        self.accessors = []
        self.buffer_views = []

    def export_animation(
        self,
        poses: List,
        output_path: str,
        fps: float = 30.0,
        joint_subset: Optional[List[str]] = None,
        output_dir: Optional[str] = None,
    ) -> bool:
        """
        Export poses to animated GLTF file.

        Args:
            poses: List of Pose3DResult objects (must be smoothed)
            output_path: Filename to save (will be placed in output_dir)
            fps: Frames per second
            joint_subset: Optional list of joints to export
            output_dir: Directory to save file (default: backend/output/)

        Returns:
            True if successful
        """
        # Default output directory
        if output_dir is None:
            output_dir = str(Path(__file__).parent.parent / "output")

        output_dir_path = Path(output_dir)
        output_dir_path.mkdir(parents=True, exist_ok=True)

        # Full output path
        full_output_path = output_dir_path / output_path
        if not poses:
            logger.error("No poses to export")
            return False

        try:
            logger.info(f"Exporting {len(poses)} frames to {full_output_path}")

            # Reset buffers
            self.buffer_data = bytearray()
            self.accessors = []
            self.buffer_views = []

            # Build GLTF structure
            gltf = self._build_gltf(poses, fps, joint_subset)

            # Convert buffer data to base64 data URI
            buffer_b64 = base64.b64encode(self.buffer_data).decode("utf-8")
            gltf["buffers"][0]["uri"] = f"data:application/octet-stream;base64,{buffer_b64}"

            # Save JSON
            with open(full_output_path, "w") as f:
                json.dump(gltf, f, indent=2)

            file_size = full_output_path.stat().st_size
            logger.info(f"✓ Animation exported to {full_output_path}")
            logger.info(f"  File size: {file_size / 1024:.1f} KB")
            logger.info(f"  Duration: {len(poses) / fps:.2f}s at {fps}fps")
            logger.info(f"  Joints: {len([n for n in gltf['nodes']])}")
            logger.info(f"  View in: https://gltf-viewer.donmccurdy.com/")

            return True

        except Exception as e:
            logger.error(f"Failed to export animation: {e}", exc_info=True)
            return False

    def _build_gltf(self, poses: List, fps: float, joint_subset: Optional[List[str]]) -> dict:
        """Build GLTF JSON structure."""
        dt = 1.0 / fps
        num_frames = len(poses)

        # Get joint names
        joint_names = list(poses[0].keypoints_3d.keys())
        if joint_subset:
            joint_names = [j for j in joint_names if j in joint_subset]

        logger.info(f"Exporting {len(joint_names)} joints")

        # Create nodes
        nodes = []
        for joint_name in joint_names:
            kp = poses[0].keypoints_3d[joint_name]
            node = {
                "name": joint_name,
                "translation": [float(kp.x), float(kp.y), float(kp.z)],
                "rotation": [0.0, 0.0, 0.0, 1.0],  # [x, y, z, w]
                "scale": [1.0, 1.0, 1.0],
            }
            nodes.append(node)

        # Create time accessor (animation data - no byteStride)
        times = np.arange(num_frames, dtype=np.float32) * dt
        times_data = times.tobytes()
        self._add_accessor(
            times_data,
            "SCALAR",
            "FLOAT",
            num_frames,
            list(times),
            is_animation=True,
        )
        times_accessor = len(self.accessors) - 1

        # Create animation channels and samplers
        channels = []
        samplers = []

        for node_idx, joint_name in enumerate(joint_names):
            # Extract translation for this joint
            positions = []
            for pose in poses:
                kp = pose.keypoints_3d.get(joint_name)
                if kp:
                    positions.append([kp.x, kp.y, kp.z])
                else:
                    positions.append([0, 0, 0])

            positions = np.array(positions, dtype=np.float32).flatten()
            positions_data = positions.tobytes()

            # Create accessor for positions (animation data - no byteStride)
            self._add_accessor(
                positions_data,
                "VEC3",
                "FLOAT",
                num_frames,
                positions.tolist(),
                is_animation=True,
            )
            positions_accessor = len(self.accessors) - 1

            # Create sampler
            sampler = {
                "input": times_accessor,
                "interpolation": "LINEAR",
                "output": positions_accessor,
            }
            samplers.append(sampler)
            sampler_idx = len(samplers) - 1

            # Create channel
            channel = {
                "sampler": sampler_idx,
                "target": {"node": node_idx, "path": "translation"},
            }
            channels.append(channel)

        # Build GLTF structure
        gltf = {
            "asset": {
                "generator": "SwingCoach Animation Exporter",
                "version": "2.0",
            },
            "scene": 0,
            "scenes": [{"nodes": list(range(len(nodes)))}],
            "nodes": nodes,
            "animations": [
                {
                    "name": "swing",
                    "channels": channels,
                    "samplers": samplers,
                }
            ],
            "accessors": self.accessors,
            "bufferViews": self.buffer_views,
            "buffers": [{"byteLength": len(self.buffer_data)}],
        }

        return gltf

    def _add_accessor(
        self,
        data: bytes,
        data_type: str,
        component_type_str: str,
        count: int,
        values: list,
        is_animation: bool = False,
    ) -> int:
        """
        Add data to buffer and create accessor.

        Args:
            data: Binary data
            data_type: 'SCALAR', 'VEC2', 'VEC3', 'VEC4', 'MAT2', 'MAT3', 'MAT4'
            component_type_str: 'FLOAT', 'INT', etc.
            count: Number of elements
            values: Flattened values for min/max calculation
            is_animation: If True, don't set byteStride (GLTF spec requirement for animation)

        Returns:
            Accessor index
        """
        # Component type mapping
        component_types = {
            "FLOAT": 5126,
            "UNSIGNED_INT": 5125,
            "INT": 5125,
        }
        component_type = component_types.get(component_type_str, 5126)

        # Add buffer view (WITHOUT byteStride for animation data per GLTF spec)
        buffer_view = {
            "buffer": 0,
            "byteOffset": len(self.buffer_data),
            "byteLength": len(data),
        }

        # Only add byteStride for non-animation data
        if not is_animation:
            type_counts = {
                "SCALAR": 1,
                "VEC2": 2,
                "VEC3": 3,
                "VEC4": 4,
                "MAT2": 4,
                "MAT3": 9,
                "MAT4": 16,
            }
            type_count = type_counts.get(data_type, 1)
            if component_type_str == "FLOAT":
                buffer_view["byteStride"] = type_count * 4
        self.buffer_views.append(buffer_view)
        buffer_view_idx = len(self.buffer_views) - 1

        # Add accessor
        accessor = {
            "bufferView": buffer_view_idx,
            "byteOffset": 0,
            "componentType": component_type,
            "count": count,
            "type": data_type,
        }

        # Calculate min/max (convert to native Python floats for JSON serialization)
        if data_type == "SCALAR":
            accessor["min"] = [float(min(values))]
            accessor["max"] = [float(max(values))]
        elif data_type == "VEC3":
            flat_vals = np.array(values, dtype=np.float32).reshape(-1, 3)
            accessor["min"] = [
                float(flat_vals[:, 0].min()),
                float(flat_vals[:, 1].min()),
                float(flat_vals[:, 2].min()),
            ]
            accessor["max"] = [
                float(flat_vals[:, 0].max()),
                float(flat_vals[:, 1].max()),
                float(flat_vals[:, 2].max()),
            ]

        self.accessors.append(accessor)

        # Add to buffer
        self.buffer_data.extend(data)

        return len(self.accessors) - 1


def export_swing_animation(
    poses: List,
    filename: str,
    fps: float = 30.0,
    output_dir: Optional[str] = None,
) -> bool:
    """
    Convenience function to export swing animation.

    Args:
        poses: List of smoothed Pose3DResult objects
        filename: Filename to save (will be placed in output_dir)
        fps: Frames per second of video
        output_dir: Directory to save file (default: backend/output/)

    Returns:
        True if successful
    """
    exporter = AnimationExporter()
    return exporter.export_animation(poses, filename, fps=fps, output_dir=output_dir)
