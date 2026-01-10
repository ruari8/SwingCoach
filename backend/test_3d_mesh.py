#!/usr/bin/env python3
"""
Test SAM 3D Body mesh visualization.

Creates a 3D mesh from SAM 3D Body output and exports it for viewing.
"""

import sys
import io
from pathlib import Path

import numpy as np
from PIL import Image

# Setup path
sys.path.insert(0, str(Path(__file__).parent))

from analysis.body_3d import Body3DDetector, SAM3D_AVAILABLE
from analysis.frame_extractor import FrameExtractor


def main():
    print("=" * 60)
    print("SAM 3D Body Mesh Visualization")
    print("=" * 60)
    
    if not SAM3D_AVAILABLE:
        print("ERROR: SAM 3D Body not available")
        return
    
    # Load model
    print("\nLoading model...")
    detector = Body3DDetector()
    
    # Extract frame from video
    video_path = "swingVideos/IMG_0737.mov"
    print(f"\nExtracting frame from: {video_path}")
    
    with open(video_path, 'rb') as f:
        video_bytes = f.read()
    
    extractor = FrameExtractor()
    frame_bytes_list = extractor.extract_frames(video_bytes, sample_rate=30, max_frames=1)
    frame = np.array(Image.open(io.BytesIO(frame_bytes_list[0])))
    print(f"Frame shape: {frame.shape}")
    
    # Run inference - need to get raw output with mesh
    print("\nRunning inference...")
    result = detector.detect(frame, frame_index=0)
    
    if result is None:
        print("ERROR: No pose detected")
        return
    
    # Check mesh data
    print(f"\nMesh data:")
    print(f"  Vertices shape: {result.vertices.shape if result.vertices is not None else 'None'}")
    
    # Get faces from the model
    faces = detector.estimator.faces
    print(f"  Faces shape: {faces.shape}")
    
    if result.vertices is None:
        print("ERROR: No mesh vertices in output")
        return
    
    vertices = result.vertices.copy()
    
    # Flip Y axis - SAM3D uses negative Y for "up", standard 3D uses positive Y
    vertices[:, 1] = -vertices[:, 1]
    
    # When flipping one axis, we need to reverse face winding to maintain correct normals
    faces = faces[:, ::-1].copy()  # Reverse vertex order in each triangle
    
    print(f"  Vertex range X: [{vertices[:, 0].min():.3f}, {vertices[:, 0].max():.3f}]")
    print(f"  Vertex range Y: [{vertices[:, 1].min():.3f}, {vertices[:, 1].max():.3f}]")
    print(f"  Vertex range Z: [{vertices[:, 2].min():.3f}, {vertices[:, 2].max():.3f}]")
    
    # Create output directory
    output_dir = Path("output")
    output_dir.mkdir(exist_ok=True)
    
    # Export as OBJ file (universal 3D format)
    obj_path = output_dir / "body_mesh.obj"
    print(f"\nExporting mesh to: {obj_path}")
    export_obj(vertices, faces, obj_path)
    
    # Export as GLB (for web viewers)
    try:
        import trimesh
        glb_path = output_dir / "body_mesh.glb"
        print(f"Exporting mesh to: {glb_path}")
        mesh = trimesh.Trimesh(vertices=vertices, faces=faces)
        mesh.export(str(glb_path))
        print(f"  GLB exported successfully")
    except Exception as e:
        print(f"  GLB export failed: {e}")
    
    # Render with pyrender
    try:
        render_path = output_dir / "mesh_render.png"
        print(f"\nRendering mesh to: {render_path}")
        render_mesh(vertices, faces, render_path)
    except Exception as e:
        print(f"Render failed: {e}")
        import traceback
        traceback.print_exc()
    
    # Create multi-angle renders
    try:
        print("\nCreating multi-angle renders...")
        render_multi_angle(vertices, faces, output_dir)
    except Exception as e:
        print(f"Multi-angle render failed: {e}")
    
    print("\n" + "=" * 60)
    print("DONE!")
    print("=" * 60)
    print(f"\nOutput files:")
    print(f"  - {obj_path} (open in Blender, MeshLab, or online 3D viewers)")
    print(f"  - {output_dir / 'body_mesh.glb'} (open in https://gltf-viewer.donmccurdy.com/)")
    print(f"  - {output_dir / 'mesh_render.png'}")
    print(f"  - {output_dir / 'mesh_front.png'}, mesh_side.png, mesh_back.png")


def export_obj(vertices, faces, path):
    """Export mesh as OBJ file."""
    with open(path, 'w') as f:
        f.write("# SAM 3D Body mesh export\n")
        f.write(f"# Vertices: {len(vertices)}\n")
        f.write(f"# Faces: {len(faces)}\n\n")
        
        # Write vertices
        for v in vertices:
            f.write(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")
        
        f.write("\n")
        
        # Write faces (OBJ uses 1-indexed)
        for face in faces:
            f.write(f"f {face[0]+1} {face[1]+1} {face[2]+1}\n")
    
    print(f"  OBJ exported: {len(vertices)} vertices, {len(faces)} faces")


def render_mesh(vertices, faces, output_path, camera_pose=None):
    """Render mesh using pyrender."""
    import trimesh
    import pyrender
    
    # Create trimesh (vertices already Y-flipped in main())
    mesh = trimesh.Trimesh(vertices=vertices, faces=faces)
    
    # Create pyrender mesh with double-sided material to avoid normal issues
    material = pyrender.MetallicRoughnessMaterial(
        baseColorFactor=[0.7, 0.7, 0.8, 1.0],
        metallicFactor=0.2,
        roughnessFactor=0.8,
        doubleSided=True,
    )
    mesh_pyrender = pyrender.Mesh.from_trimesh(mesh, material=material, smooth=True)
    
    # Create scene
    scene = pyrender.Scene(ambient_light=[0.3, 0.3, 0.3])
    scene.add(mesh_pyrender)
    
    # Add lights
    light = pyrender.DirectionalLight(color=[1.0, 1.0, 1.0], intensity=3.0)
    light_pose = np.eye(4)
    light_pose[:3, 3] = [0, 2, 2]
    scene.add(light, pose=light_pose)
    
    # Add camera
    camera = pyrender.PerspectiveCamera(yfov=np.pi / 3.0)
    if camera_pose is None:
        # Default: front view, looking at body center (Y=0.8 after flip)
        camera_pose = np.array([
            [1, 0, 0, 0],
            [0, 1, 0, 0.8],
            [0, 0, 1, 3],
            [0, 0, 0, 1],
        ])
    scene.add(camera, pose=camera_pose)
    
    # Render
    renderer = pyrender.OffscreenRenderer(800, 1000)
    color, depth = renderer.render(scene)
    renderer.delete()
    
    # Save
    Image.fromarray(color).save(output_path)
    print(f"  Rendered: {output_path}")


def render_multi_angle(vertices, faces, output_dir):
    """Render mesh from multiple angles."""
    import trimesh
    import pyrender
    
    # Create trimesh (vertices already Y-flipped in main())
    mesh = trimesh.Trimesh(vertices=vertices, faces=faces)
    
    # Camera poses for different angles (camera looks at Y=0.8, center of body after flip)
    angles = {
        'front': np.array([
            [1, 0, 0, 0],
            [0, 1, 0, 0.8],
            [0, 0, 1, 3],
            [0, 0, 0, 1],
        ]),
        'side': np.array([
            [0, 0, 1, 3],
            [0, 1, 0, 0.8],
            [-1, 0, 0, 0],
            [0, 0, 0, 1],
        ]),
        'back': np.array([
            [-1, 0, 0, 0],
            [0, 1, 0, 0.8],
            [0, 0, -1, -3],
            [0, 0, 0, 1],
        ]),
        'top': np.array([
            [1, 0, 0, 0],
            [0, 0, 1, 3],
            [0, -1, 0, 0.8],
            [0, 0, 0, 1],
        ]),
    }
    
    material = pyrender.MetallicRoughnessMaterial(
        baseColorFactor=[0.6, 0.7, 0.9, 1.0],
        metallicFactor=0.1,
        roughnessFactor=0.9,
        doubleSided=True,
    )
    mesh_pyrender = pyrender.Mesh.from_trimesh(mesh, material=material, smooth=True)
    
    for name, camera_pose in angles.items():
        scene = pyrender.Scene(ambient_light=[0.4, 0.4, 0.4], bg_color=[0.1, 0.1, 0.15, 1.0])
        scene.add(mesh_pyrender)
        
        # Lights
        light = pyrender.DirectionalLight(color=[1.0, 1.0, 1.0], intensity=2.5)
        light_pose = np.eye(4)
        light_pose[:3, 3] = [1, 2, 2]
        scene.add(light, pose=light_pose)
        
        light2 = pyrender.DirectionalLight(color=[0.8, 0.8, 1.0], intensity=1.5)
        light2_pose = np.eye(4)
        light2_pose[:3, 3] = [-1, 1, -1]
        scene.add(light2, pose=light2_pose)
        
        # Camera
        camera = pyrender.PerspectiveCamera(yfov=np.pi / 3.0)
        scene.add(camera, pose=camera_pose)
        
        # Render
        renderer = pyrender.OffscreenRenderer(600, 800)
        color, _ = renderer.render(scene)
        renderer.delete()
        
        output_path = output_dir / f"mesh_{name}.png"
        Image.fromarray(color).save(output_path)
        print(f"  {name}: {output_path}")


if __name__ == "__main__":
    main()
