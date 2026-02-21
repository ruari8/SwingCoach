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

    # Bone connections for skeleton visualization (from visualization_3d.py)
    BONE_CONNECTIONS = [
        # Spine and neck
        ("neck", "left_shoulder"),
        ("neck", "right_shoulder"),
        # Shoulders and torso
        ("left_shoulder", "right_shoulder"),
        ("left_shoulder", "left_hip"),
        ("right_shoulder", "right_hip"),
        ("left_hip", "right_hip"),
        # Arms
        ("left_shoulder", "left_elbow"),
        ("left_elbow", "left_wrist"),
        ("right_shoulder", "right_elbow"),
        ("right_elbow", "right_wrist"),
        # Legs
        ("left_hip", "left_knee"),
        ("left_knee", "left_ankle"),
        ("right_hip", "right_knee"),
        ("right_knee", "right_ankle"),
    ]

    def __init__(self):
        """Initialize exporter."""
        self.buffer_data = bytearray()
        self.accessors = []
        self.buffer_views = []

    def _create_icosphere_geometry(self, radius: float = 0.01, subdivisions: int = 1) -> tuple:
        """
        Create icosphere vertices and indices for joint visualization.

        Args:
            radius: Sphere radius in meters
            subdivisions: Number of subdivision iterations (1 = 42 verts, 2 = 162 verts)

        Returns:
            Tuple of (vertices as np.float32, indices as np.uint16)
        """
        # Golden ratio for icosahedron
        phi = (1 + np.sqrt(5)) / 2

        # Icosahedron vertices (12 vertices)
        verts = np.array([
            [-1,  phi, 0], [ 1,  phi, 0], [-1, -phi, 0], [ 1, -phi, 0],
            [ 0, -1,  phi], [ 0,  1,  phi], [ 0, -1, -phi], [ 0,  1, -phi],
            [ phi, 0, -1], [ phi, 0,  1], [-phi, 0, -1], [-phi, 0,  1],
        ], dtype=np.float32)

        # Normalize to unit sphere then scale
        verts = verts / np.linalg.norm(verts[0])

        # Icosahedron faces (20 triangles)
        faces = np.array([
            [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
            [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
            [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
            [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
        ], dtype=np.uint16)

        # Subdivide
        for _ in range(subdivisions):
            verts, faces = self._subdivide_icosphere(verts, faces)

        # Scale to desired radius
        verts = verts * radius

        return verts.astype(np.float32), faces.flatten().astype(np.uint16)

    def _subdivide_icosphere(self, verts: np.ndarray, faces: np.ndarray) -> tuple:
        """Subdivide icosphere by splitting each triangle into 4."""
        edge_midpoints = {}
        new_faces = []
        new_verts = list(verts)

        def get_midpoint(i1, i2):
            key = (min(i1, i2), max(i1, i2))
            if key in edge_midpoints:
                return edge_midpoints[key]
            mid = (verts[i1] + verts[i2]) / 2
            mid = mid / np.linalg.norm(mid)  # Project onto unit sphere
            idx = len(new_verts)
            new_verts.append(mid)
            edge_midpoints[key] = idx
            return idx

        for tri in faces:
            v0, v1, v2 = tri
            a = get_midpoint(v0, v1)
            b = get_midpoint(v1, v2)
            c = get_midpoint(v2, v0)
            new_faces.extend([
                [v0, a, c], [v1, b, a], [v2, c, b], [a, b, c]
            ])

        return np.array(new_verts, dtype=np.float32), np.array(new_faces, dtype=np.uint16)

    def _add_geometry_accessor(
        self,
        data: bytes,
        data_type: str,
        component_type_str: str,
        count: int,
        values: list,
    ) -> int:
        """
        Add geometry data to buffer and create accessor (non-animation data).

        Args:
            data: Binary data
            data_type: 'SCALAR', 'VEC3', etc.
            component_type_str: 'FLOAT', 'UNSIGNED_SHORT', etc.
            count: Number of elements
            values: Flattened values for min/max calculation

        Returns:
            Accessor index
        """
        component_types = {
            "FLOAT": 5126,
            "UNSIGNED_SHORT": 5123,
            "UNSIGNED_INT": 5125,
        }
        component_type = component_types.get(component_type_str, 5126)

        # Add buffer view
        buffer_view = {
            "buffer": 0,
            "byteOffset": len(self.buffer_data),
            "byteLength": len(data),
        }
        # Add target for geometry data
        if data_type == "SCALAR":
            buffer_view["target"] = 34963  # ELEMENT_ARRAY_BUFFER (indices)
        else:
            buffer_view["target"] = 34962  # ARRAY_BUFFER (vertices)

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

        # Calculate min/max
        if data_type == "SCALAR":
            accessor["min"] = [int(min(values))]
            accessor["max"] = [int(max(values))]
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
        self.buffer_data.extend(data)

        return len(self.accessors) - 1

    def export_animation(
        self,
        poses: List,
        output_path: str,
        fps: float = 30.0,
        joint_subset: Optional[List[str]] = None,
        club_frames: Optional[List] = None,
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
            gltf = self._build_gltf(poses, fps, joint_subset, club_frames)

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

    def _build_gltf(self, poses: List, fps: float, joint_subset: Optional[List[str]], club_frames: Optional[List]) -> dict:
        """Build GLTF JSON structure with visible geometry."""
        dt = 1.0 / fps
        num_frames = len(poses)

        # Get joint names
        joint_names = list(poses[0].keypoints_3d.keys())
        if joint_subset:
            joint_names = [j for j in joint_names if j in joint_subset]

        logger.info(f"Exporting {len(joint_names)} joints")

        # Create sphere geometry for joints (added to buffer first)
        sphere_verts, sphere_indices = self._create_icosphere_geometry(radius=0.01, subdivisions=1)

        # Add sphere vertices to buffer
        sphere_verts_data = sphere_verts.flatten().tobytes()
        sphere_verts_accessor = self._add_geometry_accessor(
            sphere_verts_data, "VEC3", "FLOAT", len(sphere_verts), sphere_verts.flatten().tolist()
        )

        # Add sphere indices to buffer
        sphere_indices_data = sphere_indices.tobytes()
        sphere_indices_accessor = self._add_geometry_accessor(
            sphere_indices_data, "SCALAR", "UNSIGNED_SHORT", len(sphere_indices), sphere_indices.tolist()
        )

        # Add animated body mesh using morph targets
        body_mesh_accessor = None
        body_indices_accessor = None
        morph_target_accessors = []
        has_body_mesh = (
            hasattr(poses[0], 'vertices') and
            poses[0].vertices is not None and
            hasattr(poses[0], 'faces') and
            poses[0].faces is not None
        )

        if has_body_mesh:
            # Base mesh from frame 0
            base_verts = poses[0].vertices.copy()
            base_verts[:, 1] = -base_verts[:, 1]  # Flip Y
            base_verts = base_verts.astype(np.float32)

            body_faces = poses[0].faces.astype(np.uint32).flatten()

            # Add base vertices to buffer
            body_verts_data = base_verts.flatten().tobytes()
            body_mesh_accessor = self._add_geometry_accessor(
                body_verts_data, "VEC3", "FLOAT", len(base_verts), base_verts.flatten().tolist()
            )

            # Add body indices to buffer
            body_indices_data = body_faces.tobytes()
            body_indices_accessor = self._add_geometry_accessor(
                body_indices_data, "SCALAR", "UNSIGNED_INT", len(body_faces), body_faces.tolist()
            )

            # Create morph targets for each frame (delta from frame 0)
            # Skip frame 0 since it's the base
            for frame_idx in range(1, num_frames):
                if hasattr(poses[frame_idx], 'vertices') and poses[frame_idx].vertices is not None:
                    frame_verts = poses[frame_idx].vertices.copy()
                    frame_verts[:, 1] = -frame_verts[:, 1]  # Flip Y

                    # Calculate delta from base mesh
                    delta = (frame_verts - base_verts).astype(np.float32)

                    # Add morph target accessor
                    delta_data = delta.flatten().tobytes()
                    morph_accessor = self._add_geometry_accessor(
                        delta_data, "VEC3", "FLOAT", len(delta), delta.flatten().tolist()
                    )
                    morph_target_accessors.append(morph_accessor)
                else:
                    # No mesh for this frame, use zero delta
                    zero_delta = np.zeros_like(base_verts, dtype=np.float32)
                    delta_data = zero_delta.flatten().tobytes()
                    morph_accessor = self._add_geometry_accessor(
                        delta_data, "VEC3", "FLOAT", len(zero_delta), zero_delta.flatten().tolist()
                    )
                    morph_target_accessors.append(morph_accessor)

            logger.info(f"Added animated body mesh: {len(base_verts)} vertices, {len(body_faces)//3} triangles, {len(morph_target_accessors)} morph targets")

        # Create nodes with mesh reference
        nodes = []
        for joint_name in joint_names:
            kp = poses[0].keypoints_3d[joint_name]
            node = {
                "name": joint_name,
                # Flip Y: camera coords (Y-down) → graphics coords (Y-up)
                "translation": [float(kp.x), float(-kp.y), float(kp.z)],
                "rotation": [0.0, 0.0, 0.0, 1.0],  # [x, y, z, w]
                "scale": [1.0, 1.0, 1.0],
                "mesh": 0,  # Reference shared sphere mesh
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
            # Flip Y: camera coords (Y-down) → graphics coords (Y-up)
            positions = []
            for pose in poses:
                kp = pose.keypoints_3d.get(joint_name)
                if kp:
                    positions.append([kp.x, -kp.y, kp.z])
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

        # Optional club nodes (grip + clubhead) animated with fused club track
        club_grip_node_idx = None
        club_head_node_idx = None
        if club_frames:
            club_frame_map = {getattr(frame, "frame_index", -1): frame for frame in club_frames}

            grip_positions = []
            head_positions = []
            last_grip = [0.0, 0.0, 0.0]
            last_head = [0.0, 0.0, 0.0]

            for pose in poses:
                frame_idx = getattr(pose, "frame_index", -1)
                club_frame = club_frame_map.get(frame_idx)
                if club_frame is not None:
                    grip = list(club_frame.grip_point)
                    head = list(club_frame.clubhead_point)
                    grip[1] = -grip[1]
                    head[1] = -head[1]
                    last_grip = grip
                    last_head = head
                grip_positions.append(last_grip)
                head_positions.append(last_head)

            club_grip_node_idx = len(nodes)
            nodes.append(
                {
                    "name": "club_grip",
                    "translation": [float(v) for v in grip_positions[0]],
                    "rotation": [0.0, 0.0, 0.0, 1.0],
                    "scale": [1.0, 1.0, 1.0],
                    "mesh": 0,
                }
            )

            club_head_node_idx = len(nodes)
            nodes.append(
                {
                    "name": "clubhead",
                    "translation": [float(v) for v in head_positions[0]],
                    "rotation": [0.0, 0.0, 0.0, 1.0],
                    "scale": [1.0, 1.0, 1.0],
                    "mesh": 0,
                }
            )

            for node_idx, positions in [
                (club_grip_node_idx, grip_positions),
                (club_head_node_idx, head_positions),
            ]:
                flat_positions = np.array(positions, dtype=np.float32).flatten()
                pos_data = flat_positions.tobytes()
                self._add_accessor(
                    pos_data,
                    "VEC3",
                    "FLOAT",
                    num_frames,
                    flat_positions.tolist(),
                    is_animation=True,
                )
                pos_accessor = len(self.accessors) - 1

                sampler = {
                    "input": times_accessor,
                    "interpolation": "LINEAR",
                    "output": pos_accessor,
                }
                samplers.append(sampler)
                sampler_idx = len(samplers) - 1
                channels.append(
                    {
                        "sampler": sampler_idx,
                        "target": {"node": node_idx, "path": "translation"},
                    }
                )

        # Build meshes array
        meshes = [
            {
                "name": "joint_sphere",
                "primitives": [
                    {
                        "attributes": {"POSITION": sphere_verts_accessor},
                        "indices": sphere_indices_accessor,
                        "material": 0,
                    }
                ],
            }
        ]

        # Build materials array
        materials = [
            {
                "name": "joint_red",
                "pbrMetallicRoughness": {
                    "baseColorFactor": [1.0, 0.2, 0.2, 1.0],  # Red
                    "metallicFactor": 0.1,
                    "roughnessFactor": 0.5,
                },
            }
        ]

        # Add animated body mesh if available
        body_node_idx = None
        if has_body_mesh and body_mesh_accessor is not None and morph_target_accessors:
            # Build morph targets array
            targets = [{"POSITION": acc} for acc in morph_target_accessors]

            # Add body mesh with morph targets (mesh index 1)
            meshes.append({
                "name": "body_mesh",
                "primitives": [
                    {
                        "attributes": {"POSITION": body_mesh_accessor},
                        "indices": body_indices_accessor,
                        "material": 1,
                        "targets": targets,
                    }
                ],
                "weights": [0.0] * len(morph_target_accessors),  # Initial weights (all zero = base mesh)
            })

            # Add semi-transparent blue material for body
            materials.append({
                "name": "body_blue",
                "pbrMetallicRoughness": {
                    "baseColorFactor": [0.7, 0.8, 1.0, 0.6],  # Light blue, semi-transparent
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.8,
                },
                "alphaMode": "BLEND",
            })

            # Add body node with morph weights
            body_node_idx = len(nodes)
            body_node = {
                "name": "body",
                "mesh": 1,
                "translation": [0.0, 0.0, 0.0],
                "weights": [0.0] * len(morph_target_accessors),
            }
            nodes.append(body_node)

            # Create morph target animation
            # Each frame directly uses the morph target for that frame
            # Frame 0: base mesh (all weights = 0)
            # Frame N: 100% morph target N-1 (weight[N-1] = 1.0)
            num_morph_targets = len(morph_target_accessors)

            # Create weights data: for each keyframe, output all morph target weights
            weights_data = []
            for frame_idx in range(num_frames):
                frame_weights = [0.0] * num_morph_targets
                if frame_idx > 0 and frame_idx <= num_morph_targets:
                    frame_weights[frame_idx - 1] = 1.0
                elif frame_idx > num_morph_targets:
                    # Past last morph target, stay at last frame
                    frame_weights[num_morph_targets - 1] = 1.0
                weights_data.extend(frame_weights)

            weights_array = np.array(weights_data, dtype=np.float32)
            weights_bytes = weights_array.tobytes()

            # Add weights accessor
            # Per GLTF spec: for "weights" path, count = num_keyframes,
            # but data contains num_keyframes * num_morph_targets floats
            # Buffer view length determines actual data size
            buffer_view = {
                "buffer": 0,
                "byteOffset": len(self.buffer_data),
                "byteLength": len(weights_bytes),
            }
            self.buffer_views.append(buffer_view)
            buffer_view_idx = len(self.buffer_views) - 1

            weights_accessor_def = {
                "bufferView": buffer_view_idx,
                "byteOffset": 0,
                "componentType": 5126,  # FLOAT
                "count": num_frames * num_morph_targets,
                "type": "SCALAR",
                "min": [0.0],
                "max": [1.0],
            }
            self.accessors.append(weights_accessor_def)
            self.buffer_data.extend(weights_bytes)
            weights_accessor = len(self.accessors) - 1

            # Add sampler for morph weights
            morph_sampler = {
                "input": times_accessor,
                "interpolation": "STEP",  # STEP for discrete frame switching
                "output": weights_accessor,
            }
            samplers.append(morph_sampler)
            morph_sampler_idx = len(samplers) - 1

            # Add channel for morph weights
            morph_channel = {
                "sampler": morph_sampler_idx,
                "target": {
                    "node": body_node_idx,
                    "path": "weights",
                },
            }
            channels.append(morph_channel)

        # Build scene nodes list
        scene_nodes = list(range(len(nodes)))

        # Build GLTF structure with meshes and materials
        gltf = {
            "asset": {
                "generator": "SwingCoach Animation Exporter",
                "version": "2.0",
            },
            "scene": 0,
            "scenes": [{"nodes": scene_nodes}],
            "nodes": nodes,
            "meshes": meshes,
            "materials": materials,
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
    club_frames: Optional[List] = None,
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
    return exporter.export_animation(
        poses,
        filename,
        fps=fps,
        output_dir=output_dir,
        club_frames=club_frames,
    )
