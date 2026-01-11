"""
3D visualization of body mesh with skeletal overlay.

Converts SAM 3D Body outputs to interactive 3D models with:
- Semi-transparent mesh for body shape
- Skeletal joints and connections
- Proper coordinate transformations
"""

import numpy as np
from typing import Optional, Tuple
from pathlib import Path
import logging
from scipy.spatial.transform import Rotation

logger = logging.getLogger(__name__)

try:
    import trimesh
    TRIMESH_AVAILABLE = True
except ImportError:
    TRIMESH_AVAILABLE = False


class Mesh3DVisualizer:
    """Create interactive 3D visualizations of body pose with mesh and skeleton."""

    def __init__(self):
        if not TRIMESH_AVAILABLE:
            raise RuntimeError(
                "3D visualization requires trimesh. Install with:\n"
                "pip install trimesh scipy"
            )

    def create_skeleton(
        self,
        pose_result,
        joint_radius: float = 0.01,
        bone_radius: float = 0.008,
        joint_color: Tuple = (1.0, 0.2, 0.2),
        bone_color: Tuple = (0.5, 0.5, 0.5),
        flip_y: bool = True,
    ) -> trimesh.Trimesh:
        """
        Create skeleton geometry from pose keypoints.

        Args:
            pose_result: Pose3DResult with 3D keypoints
            joint_radius: Radius of joint spheres (meters)
            bone_radius: Radius of bone cylinders (meters)
            joint_color: RGB color for joints (0-1 range)
            bone_color: RGB color for bones (0-1 range)
            flip_y: Flip Y-axis to match graphics convention (camera→graphics)

        Returns:
            Combined trimesh of skeleton
        """
        # Define skeleton connections (pairs of joint names)
        connections = [
            ("left_shoulder", "right_shoulder"),
            ("left_shoulder", "left_elbow"),
            ("right_shoulder", "right_elbow"),
            ("left_elbow", "left_wrist"),
            ("right_elbow", "right_wrist"),
            ("left_hip", "right_hip"),
            ("left_shoulder", "left_hip"),
            ("right_shoulder", "right_hip"),
            ("left_hip", "left_knee"),
            ("right_hip", "right_knee"),
            ("left_knee", "left_ankle"),
            ("right_knee", "right_ankle"),
            ("neck", "left_shoulder"),
            ("neck", "right_shoulder"),
        ]

        meshes = []

        # Add joint spheres
        for name, keypoint in pose_result.keypoints_3d.items():
            if keypoint.confidence > 0.5:  # Only visualize confident joints
                pos = keypoint.to_array()
                # Convert from camera coords (image convention, Y-down) to graphics coords (Y-up)
                if flip_y:
                    pos[1] = -pos[1]
                sphere = trimesh.creation.icosphere(
                    subdivisions=2, radius=joint_radius
                )
                sphere.apply_translation(pos)
                sphere.visual.face_colors = [
                    int(c * 255) for c in joint_color
                ] + [255]
                meshes.append(sphere)

        # Add bone cylinders
        for joint1_name, joint2_name in connections:
            j1 = pose_result.keypoints_3d.get(joint1_name)
            j2 = pose_result.keypoints_3d.get(joint2_name)

            if j1 and j2 and j1.confidence > 0.3 and j2.confidence > 0.3:
                p1 = j1.to_array()
                p2 = j2.to_array()
                # Convert from camera coords to graphics coords
                if flip_y:
                    p1[1] = -p1[1]
                    p2[1] = -p2[1]
                length = np.linalg.norm(p2 - p1)

                if length > 0:
                    cyl = trimesh.creation.cylinder(
                        radius=bone_radius, height=length
                    )
                    # Position cylinder between joints
                    midpoint = (p1 + p2) / 2
                    direction = (p2 - p1) / length
                    # Rotate cylinder to align with direction
                    z_axis = np.array([0, 0, 1])
                    rotation = Rotation.align_vectors(
                        [direction], [z_axis]
                    )[0]
                    # Create 4x4 transformation matrix
                    rot_matrix = rotation.as_matrix()
                    transform = np.eye(4)
                    transform[:3, :3] = rot_matrix
                    transform[:3, 3] = midpoint
                    cyl.apply_transform(transform)
                    cyl.visual.face_colors = [
                        int(c * 255) for c in bone_color
                    ] + [200]
                    meshes.append(cyl)

        if meshes:
            return trimesh.util.concatenate(meshes)
        else:
            # Return empty mesh if no valid skeleton
            return trimesh.Trimesh()

    def create_body_mesh(
        self,
        pose_result,
        transparency: float = 0.3,
        color: Tuple = (0.7, 0.8, 1.0),
        flip_y: bool = True,
    ) -> Optional[trimesh.Trimesh]:
        """
        Create semi-transparent body mesh from vertices.

        Args:
            pose_result: Pose3DResult with vertices
            transparency: Alpha transparency (0.0 = opaque, 1.0 = transparent)
            color: RGB color (0-1 range)
            flip_y: Flip Y-axis to match graphics convention (camera→graphics)

        Returns:
            Trimesh of body or None if no vertices available
        """
        if pose_result.vertices is None:
            logger.warning("No vertices available in pose result")
            return None

        vertices = pose_result.vertices.copy()
        # Convert from camera coords to graphics coords
        if flip_y:
            vertices[:, 1] = -vertices[:, 1]

        if vertices.shape[0] > 2:
            # Use faces if available; otherwise create convex hull
            if pose_result.faces is not None:
                faces = pose_result.faces
                mesh = trimesh.Trimesh(
                    vertices=vertices, faces=faces, process=False
                )
            else:
                # Fallback: create convex hull if no faces provided
                logger.debug(f"No faces provided, using ConvexHull for {vertices.shape[0]} vertices")
                mesh = trimesh.Trimesh(
                    vertices=vertices, process=True
                )

            # Set semi-transparent appearance
            alpha = int((1.0 - transparency) * 255)
            mesh.visual.face_colors = [
                int(color[0] * 255),
                int(color[1] * 255),
                int(color[2] * 255),
                alpha,
            ]

            return mesh

        return None

    def combine_visualizations(
        self,
        pose_result,
        body_transparency: float = 0.4,
        output_path: Optional[str] = None,
        flip_y: bool = True,
    ) -> Tuple[trimesh.Trimesh, Optional[trimesh.Trimesh]]:
        """
        Combine body mesh and skeleton into single visualization.

        Args:
            pose_result: Pose3DResult from Body3DDetector
            body_transparency: Transparency level for body mesh
            output_path: Optional path to save combined mesh
            flip_y: Flip Y-axis to match graphics convention

        Returns:
            Tuple of (combined_mesh, skeleton_only_mesh)
        """
        # Create skeleton
        skeleton = self.create_skeleton(pose_result, flip_y=flip_y)

        # Create body mesh
        body_mesh = self.create_body_mesh(
            pose_result, transparency=body_transparency, flip_y=flip_y
        )

        # Combine meshes
        if body_mesh is not None and skeleton.vertices.shape[0] > 0:
            combined = trimesh.util.concatenate([body_mesh, skeleton])
        elif body_mesh is not None:
            combined = body_mesh
        elif skeleton.vertices.shape[0] > 0:
            combined = skeleton
        else:
            combined = trimesh.Trimesh()

        # Save if requested
        if output_path:
            self._save_mesh(combined, output_path)

        return combined, skeleton

    def _save_mesh(self, mesh: trimesh.Trimesh, output_path: str) -> None:
        """Save mesh to file."""
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)

        file_ext = output_path.suffix.lower()

        if file_ext == ".obj":
            mesh.export(str(output_path))
        elif file_ext in [".glb", ".gltf"]:
            mesh.export(str(output_path))
        elif file_ext == ".ply":
            mesh.export(str(output_path))
        else:
            # Default to OBJ
            obj_path = output_path.with_suffix(".obj")
            mesh.export(str(obj_path))
            logger.info(f"Saved mesh to {obj_path}")

    def export_for_viewer(
        self, pose_result, output_dir: str = "/output", flip_y: bool = True
    ) -> str:
        """
        Export mesh in multiple formats for easy viewing.

        Args:
            pose_result: Pose3DResult from detector
            output_dir: Directory to save files
            flip_y: Flip Y-axis to match graphics convention

        Returns:
            Path to main mesh file (GLB format)
        """
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        # Create combined visualization
        combined_mesh, skeleton_mesh = self.combine_visualizations(
            pose_result, body_transparency=0.4, flip_y=flip_y
        )

        # Export as GLB (most compatible for web viewers)
        output_path = output_dir / "golfer_3d.glb"
        combined_mesh.export(str(output_path))
        logger.info(f"Exported mesh to {output_path}")

        # Also export as OBJ for alternative viewers
        obj_path = output_dir / "golfer_3d.obj"
        combined_mesh.export(str(obj_path))

        return str(output_path)
