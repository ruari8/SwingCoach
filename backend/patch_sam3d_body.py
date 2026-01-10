#!/usr/bin/env python3
"""
SAM 3D Body macOS Patcher

This script patches the SAM 3D Body package to work on macOS with Apple Silicon.
SAM 3D Body was designed for Linux + NVIDIA GPUs. The MHR (Momentum Human Rig)
model uses CUDA-specific TorchScript operations that don't work on MPS.

The fix: Force MHR to always run on CPU while the rest of the model runs on MPS.
This is based on workarounds from: https://github.com/facebookresearch/sam-3d-body/issues/93

Run this after cloning sam-3d-body:
    python patch_sam3d_body.py

Usage:
    from patch_sam3d_body import apply_patches
    apply_patches()  # Call before importing sam_3d_body
"""

import os
import sys
from pathlib import Path


def get_sam3d_body_path():
    """Find the SAM 3D Body path in the local repository."""
    # Look in the same directory as this script
    script_dir = Path(__file__).parent
    sam3d_path = script_dir / "sam_3d_body" / "sam_3d_body"
    
    if sam3d_path.exists():
        return sam3d_path
    
    return None


def patch_file(filepath: Path, patches: list) -> bool:
    """Apply patches to a file. Each patch is (old_string, new_string)."""
    if not filepath.exists():
        print(f"  WARNING: File not found: {filepath}")
        return False
    
    content = filepath.read_text()
    original_content = content
    
    for old, new in patches:
        if old in content:
            content = content.replace(old, new)
            print(f"  Patched: {old[:50]}...")
        elif new in content:
            print(f"  (already patched)")
            return True
        else:
            print(f"  WARNING: Pattern not found in {filepath.name}")
            print(f"    Looking for: {repr(old[:80])}...")
            return False
    
    if content != original_content:
        filepath.write_text(content)
        return True
    return False


def patch_mhr_head_py(sam3d_path: Path) -> bool:
    """
    Patch models/heads/mhr_head.py - Force MHR to run on CPU.
    
    The MHR model (TorchScript) uses CUDA-specific operations that don't work on MPS.
    We force it to load on CPU and handle device transfers in mhr_forward().
    """
    filepath = sam3d_path / "models" / "heads" / "mhr_head.py"
    print(f"Patching {filepath}...")
    
    patches = [
        # Patch 1: Change MHR loading to always use CPU
        (
            '''        # Load MHR itself
        if MOMENTUM_ENABLED:
            self.mhr = MHR.from_files(
                device=torch.device("cuda" if torch.cuda.is_available() else "cpu"),
                lod=1,
            )
        else:
            self.mhr = torch.jit.load(
                mhr_model_path,
                map_location=("cuda" if torch.cuda.is_available() else "cpu"),
            )''',
            '''        # Load MHR itself
        # PATCHED: Force MHR to always run on CPU for MPS compatibility
        # The MHR TorchScript model uses CUDA-specific ops that don't work on MPS
        self._mhr_device = torch.device("cpu")
        if MOMENTUM_ENABLED:
            self.mhr = MHR.from_files(
                device=self._mhr_device,
                lod=1,
            )
        else:
            self.mhr = torch.jit.load(
                mhr_model_path,
                map_location="cpu",
            )'''
        ),
    ]
    
    success = patch_file(filepath, patches)
    
    # Now patch mhr_forward to handle device transfers
    if success:
        success = patch_mhr_forward(filepath)
    
    return success


def patch_mhr_forward(filepath: Path) -> bool:
    """
    Patch the mhr_forward method to move tensors to CPU before calling MHR,
    then move results back to the original device.
    """
    content = filepath.read_text()
    
    # Find and patch the mhr_forward call
    old_mhr_call = '''        curr_skinned_verts, curr_skel_state = self.mhr(
            shape_params, model_params, expr_params
        )'''
    
    new_mhr_call = '''        # PATCHED: Move tensors to CPU for MHR, then move results back
        original_device = shape_params.device
        shape_params_cpu = shape_params.to(self._mhr_device)
        model_params_cpu = model_params.to(self._mhr_device)
        expr_params_cpu = expr_params.to(self._mhr_device) if expr_params is not None else None
        
        curr_skinned_verts_cpu, curr_skel_state_cpu = self.mhr(
            shape_params_cpu, model_params_cpu, expr_params_cpu
        )
        
        # Move results back to original device
        curr_skinned_verts = curr_skinned_verts_cpu.to(original_device)
        curr_skel_state = curr_skel_state_cpu.to(original_device)'''
    
    if old_mhr_call in content:
        content = content.replace(old_mhr_call, new_mhr_call)
        filepath.write_text(content)
        print(f"  Patched: mhr_forward device transfers")
        return True
    elif "original_device = shape_params.device" in content:
        print(f"  (mhr_forward already patched)")
        return True
    else:
        print(f"  WARNING: mhr_forward call pattern not found")
        return False


def patch_build_models_py(sam3d_path: Path) -> bool:
    """
    Patch build_models.py - Support MPS device and pass device to load_sam_3d_body.
    """
    filepath = sam3d_path / "build_models.py"
    print(f"Patching {filepath}...")
    
    patches = [
        # Patch 1: Add MPS device support
        (
            '''def load_sam_3d_body(checkpoint_path: str = "", device: str = "cuda", mhr_path: str = ""):''',
            '''def load_sam_3d_body(checkpoint_path: str = "", device: str = None, mhr_path: str = ""):
    # PATCHED: Auto-detect device, support MPS
    if device is None:
        if torch.cuda.is_available():
            device = "cuda"
        elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            device = "mps"
        else:
            device = "cpu"'''
        ),
        # Patch 2: Pass device to load_sam_3d_body_hf
        (
            '''def load_sam_3d_body_hf(repo_id, **kwargs):
    ckpt_path, mhr_path = _hf_download(repo_id)
    return load_sam_3d_body(checkpoint_path=ckpt_path, mhr_path=mhr_path)''',
            '''def load_sam_3d_body_hf(repo_id, device: str = None, **kwargs):
    ckpt_path, mhr_path = _hf_download(repo_id)
    return load_sam_3d_body(checkpoint_path=ckpt_path, device=device, mhr_path=mhr_path)'''
        ),
    ]
    
    return patch_file(filepath, patches)


def patch_sam3d_body_py(sam3d_path: Path) -> bool:
    """
    Patch models/meta_arch/sam3d_body.py - Fix hardcoded .cuda() calls.
    """
    filepath = sam3d_path / "models" / "meta_arch" / "sam3d_body.py"
    print(f"Patching {filepath}...")
    
    patches = [
        # Patch: Replace .cuda() with device-agnostic code
        (
            ''').cuda()''',
            ''').to(batch["img"].device)'''
        ),
    ]
    
    return patch_file(filepath, patches)


def patch_utils_init_py(sam3d_path: Path) -> bool:
    """
    Patch utils/__init__.py - Add MPS support to recursive_to function.
    """
    filepath = sam3d_path / "utils" / "__init__.py"
    print(f"Patching {filepath}...")
    
    # Read the file to check what we're working with
    content = filepath.read_text()
    
    # Check if recursive_to exists and patch it
    if "def recursive_to" in content:
        old_pattern = '''def recursive_to(x, device):'''
        new_pattern = '''def recursive_to(x, device):
    # PATCHED: Handle MPS device string
    if device == "mps" and not torch.backends.mps.is_available():
        device = "cpu"'''
        
        if old_pattern in content and "# PATCHED: Handle MPS device string" not in content:
            content = content.replace(old_pattern, new_pattern)
            filepath.write_text(content)
            print(f"  Patched: recursive_to MPS support")
            return True
        elif "# PATCHED: Handle MPS device string" in content:
            print(f"  (already patched)")
            return True
    
    print(f"  (no changes needed or pattern not found)")
    return True


def apply_patches():
    """Apply all patches to SAM 3D Body. Call this before importing sam_3d_body."""
    print("=" * 60)
    print("SAM 3D Body macOS Patcher")
    print("=" * 60)
    print()
    
    # Find SAM 3D Body installation
    sam3d_path = get_sam3d_body_path()
    if not sam3d_path:
        print("ERROR: SAM 3D Body not found!")
        print("Make sure you've cloned it to backend/sam_3d_body/")
        return False
    
    print(f"Found SAM 3D Body at: {sam3d_path}")
    print()
    
    # Apply patches
    patches = [
        ("models/heads/mhr_head.py (MHR CPU fallback)", patch_mhr_head_py),
        ("build_models.py (MPS device support)", patch_build_models_py),
        ("models/meta_arch/sam3d_body.py (cuda() fix)", patch_sam3d_body_py),
        ("utils/__init__.py (recursive_to MPS)", patch_utils_init_py),
    ]
    
    success_count = 0
    for name, patch_func in patches:
        print(f"\n[{name}]")
        try:
            if patch_func(sam3d_path):
                success_count += 1
        except Exception as e:
            print(f"  ERROR: {e}")
            import traceback
            traceback.print_exc()
    
    print()
    print("=" * 60)
    print(f"Patching complete: {success_count}/{len(patches)} patches applied")
    print("=" * 60)
    
    return success_count == len(patches)


def main():
    success = apply_patches()
    
    if success:
        print()
        print("Testing SAM 3D Body import...")
        
        # Add the sam_3d_body directory to path
        script_dir = Path(__file__).parent
        sys.path.insert(0, str(script_dir / "sam_3d_body"))
        
        try:
            from sam_3d_body import load_sam_3d_body_hf
            print("SUCCESS: SAM 3D Body imports correctly!")
        except Exception as e:
            print(f"WARNING: Import test failed: {e}")
            print("This may be OK if dependencies aren't installed yet.")
    
    print()
    print("Next steps:")
    print("1. Install dependencies: pip install -r requirements-3d.txt")
    print("2. Download checkpoint (already done to models/sam-3d-body-dinov3/)")
    print("3. Run test_3d_body.py to validate")
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
