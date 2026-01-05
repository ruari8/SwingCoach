#!/usr/bin/env python3
"""
SAM3 macOS Patcher

This script patches the SAM3 package to work on macOS with Apple Silicon.
SAM3 was designed for Linux + NVIDIA GPUs and has hard dependencies on:
- Triton (NVIDIA's GPU kernel compiler - not available on macOS)
- CUDA (hardcoded device references)
- decord (video library without macOS wheels)

Run this after installing SAM3:
    pip install 'git+https://github.com/facebookresearch/sam3.git'
    python patch_sam3.py

Based on fixes from: https://github.com/facebookresearch/sam3/issues/179
"""

import os
import sys
import site


def get_sam3_path():
    """Find the SAM3 installation path in site-packages."""
    # Check common locations
    for path in site.getsitepackages() + [site.getusersitepackages()]:
        sam3_path = os.path.join(path, "sam3")
        if os.path.exists(sam3_path):
            return sam3_path
    
    # Check if we're in a venv
    if hasattr(sys, 'prefix'):
        venv_path = os.path.join(sys.prefix, "lib")
        for item in os.listdir(venv_path):
            if item.startswith("python"):
                sam3_path = os.path.join(venv_path, item, "site-packages", "sam3")
                if os.path.exists(sam3_path):
                    return sam3_path
    
    return None


def patch_file(filepath, patches):
    """Apply patches to a file. Each patch is (old_string, new_string)."""
    if not os.path.exists(filepath):
        print(f"  WARNING: File not found: {filepath}")
        return False
    
    with open(filepath, 'r') as f:
        content = f.read()
    
    original_content = content
    for old, new in patches:
        if old in content:
            content = content.replace(old, new)
        elif new in content:
            print(f"  (already patched)")
            return True
        else:
            print(f"  WARNING: Pattern not found in {filepath}")
            print(f"    Looking for: {old[:50]}...")
            return False
    
    if content != original_content:
        with open(filepath, 'w') as f:
            f.write(content)
        return True
    return False


def patch_edt_py(sam3_path):
    """Patch model/edt.py - Add triton fallback with scipy CPU implementation."""
    filepath = os.path.join(sam3_path, "model", "edt.py")
    print(f"Patching {filepath}...")
    
    new_content = '''# Copyright (c) Meta Platforms, Inc. and affiliates. All Rights Reserved

"""Triton kernel for euclidean distance transform (EDT)"""

import torch

# Try to import triton, but provide fallback for macOS and other platforms
try:
    import triton
    import triton.language as tl
    HAS_TRITON = True
except (ImportError, ModuleNotFoundError):
    HAS_TRITON = False
    triton = None
    tl = None

"""
Disclaimer: This implementation is not meant to be extremely efficient. A CUDA kernel would likely be more efficient.
Even in Triton, there may be more suitable algorithms.

The goal of this kernel is to mimic cv2.distanceTransform(input, cv2.DIST_L2, 0).
Recall that the euclidean distance transform (EDT) calculates the L2 distance to the closest zero pixel for each pixel of the source image.

For images of size NxN, the naive algorithm would be to compute pairwise distances between every pair of points, leading to a O(N^4) algorithm, which is obviously impractical.
One can do better using the following approach:
- First, compute the distance to the closest point in the same row. We can write it as Row_EDT[i,j] = min_k (sqrt((k-j)^2) if input[i,k]==0 else +infinity). With a naive implementation, this step has a O(N^3) complexity
- Then, because of triangular inequality, we notice that the EDT for a given location [i,j] is the min of the row EDTs in the same column. EDT[i,j] = min_k Row_EDT[k, j]. This is also O(N^3)

Overall, this algorithm is quite amenable to parallelization, and has a complexity O(N^3). Can we do better?

It turns out that we can leverage the structure of the L2 distance (nice and convex) to find the minimum in a more efficient way.
We follow the algorithm from "Distance Transforms of Sampled Functions" (https://cs.brown.edu/people/pfelzens/papers/dt-final.pdf), which is also what's implemented in opencv

For a single dimension EDT, we can compute the EDT of an arbitrary function F, that we discretize over the grid. Note that for the binary EDT that we're interested in, we can set F(i,j) = 0 if input[i,j]==0 else +infinity
For now, we'll compute the EDT squared, and will take the sqrt only at the very end.
The basic idea is that each point at location i spawns a parabola around itself, with a bias equal to F(i). So specifically, we're looking at the parabola (x - i)^2 + F(i)
When we're looking for the row EDT at location j, we're effectively looking for min_i (x-i)^2 + F(i). In other word we want to find the lowest parabola at location j.

To do this efficiently, we need to maintain the lower envelope of the union of parabolas. This can be constructed on the fly using a sort of stack approach:
 - every time we want to add a new parabola, we check if it may be covering the current right-most parabola. If so, then that parabola was useless, so we can pop it from the stack
 - repeat until we can't find any more parabola to pop. Then push the new one.

This algorithm runs in O(N) for a single row, so overall O(N^2) when applied to all rows
Similarly as before, we notice that we can decompose the algorithm for rows and columns, leading to an overall run-time of O(N^2)

This algorithm is less suited for to GPUs, since the one-dimensional EDT computation is quite sequential in nature. However, we can parallelize over batch and row dimensions.
In Triton, things are particularly bad at the moment, since there is no support for reading/writing to the local memory at a specific index (a local gather is coming soon, see https://github.com/triton-lang/triton/issues/974, but no mention of writing, ie scatter)
One could emulate these operations with masking, but in initial tests, it proved to be worst than naively reading and writing to the global memory. My guess is that the cache is compensating somewhat for the repeated single-point accesses.


The timing obtained on a H100 for a random batch of masks of dimension 256 x 1024 x 1024 are as follows:
- OpenCV: 1780ms (including round-trip to cpu, but discounting the fact that it introduces a synchronization point)
- triton, O(N^3) algo: 627ms
- triton, O(N^2) algo: 322ms

Overall, despite being quite naive, this implementation is roughly 5.5x faster than the openCV cpu implem

"""


# Only define the triton kernel if triton is available
if HAS_TRITON:
    @triton.jit
    def edt_kernel(inputs_ptr, outputs_ptr, v, z, height, width, horizontal: tl.constexpr):
        # This is a somewhat verbatim implementation of the efficient 1D EDT algorithm described above
        # It can be applied horizontally or vertically depending if we're doing the first or second stage.
        # It's parallelized across batch+row (or batch+col if horizontal=False)
        # TODO: perhaps the implementation can be revisited if/when local gather/scatter become available in triton
        batch_id = tl.program_id(axis=0)
        if horizontal:
            row_id = tl.program_id(axis=1)
            block_start = (batch_id * height * width) + row_id * width
            length = width
            stride = 1
        else:
            col_id = tl.program_id(axis=1)
            block_start = (batch_id * height * width) + col_id
            length = height
            stride = width

        # This will be the index of the right most parabola in the envelope ("the top of the stack")
        k = 0
        for q in range(1, length):
            # Read the function value at the current location. Note that we're doing a singular read, not very efficient
            cur_input = tl.load(inputs_ptr + block_start + (q * stride))
            # location of the parabola on top of the stack
            r = tl.load(v + block_start + (k * stride))
            # associated boundary
            z_k = tl.load(z + block_start + (k * stride))
            # value of the function at the parabola location
            previous_input = tl.load(inputs_ptr + block_start + (r * stride))
            # intersection between the two parabolas
            s = (cur_input - previous_input + q * q - r * r) / (q - r) / 2

            # we'll pop as many parabolas as required
            while s <= z_k and k - 1 >= 0:
                k = k - 1
                r = tl.load(v + block_start + (k * stride))
                z_k = tl.load(z + block_start + (k * stride))
                previous_input = tl.load(inputs_ptr + block_start + (r * stride))
                s = (cur_input - previous_input + q * q - r * r) / (q - r) / 2

            # Store the new one
            k = k + 1
            tl.store(v + block_start + (k * stride), q)
            tl.store(z + block_start + (k * stride), s)
            if k + 1 < length:
                tl.store(z + block_start + ((k + 1) * stride), 1e9)

        # Last step, we read the envelope to find the min in every location
        k = 0
        for q in range(length):
            while (
                k + 1 < length
                and tl.load(
                    z + block_start + ((k + 1) * stride), mask=(k + 1) < length, other=q
                )
                < q
            ):
                k += 1
            r = tl.load(v + block_start + (k * stride))
            d = q - r
            old_value = tl.load(inputs_ptr + block_start + (r * stride))
            tl.store(outputs_ptr + block_start + (q * stride), old_value + d * d)


def edt_cpu_fallback(data: torch.Tensor):
    """
    CPU fallback for EDT using scipy's distance_transform_edt.
    Used when Triton is not available (e.g., on macOS).
    """
    try:
        from scipy.ndimage import distance_transform_edt
    except ImportError:
        raise ImportError(
            "scipy is required for CPU EDT fallback. "
            "Install with: pip install scipy"
        )
    
    assert data.dim() == 3
    B, H, W = data.shape
    
    # Move to CPU if on GPU
    device = data.device
    data_cpu = data.cpu().numpy()
    
    # Compute EDT for each image in batch
    output = torch.zeros_like(data, dtype=torch.float32)
    for i in range(B):
        # Invert: 1 -> 0, 0 -> 1 for scipy
        inverted = 1 - data_cpu[i]
        edt_result = distance_transform_edt(inverted)
        output[i] = torch.from_numpy(edt_result)
    
    # Move back to original device
    return output.to(device)


def edt_triton(data: torch.Tensor):
    """
    Computes the Euclidean Distance Transform (EDT) of a batch of binary images.

    Args:
        data: A tensor of shape (B, H, W) representing a batch of binary images.

    Returns:
        A tensor of the same shape as data containing the EDT.
        It should be equivalent to a batched version of cv2.distanceTransform(input, cv2.DIST_L2, 0)
    """
    # Use CPU fallback if triton is not available or data is not on CUDA
    if not HAS_TRITON or not data.is_cuda:
        return edt_cpu_fallback(data)
    
    assert data.dim() == 3
    assert data.is_cuda
    B, H, W = data.shape
    data = data.contiguous()

    # Allocate the "function" tensor. Implicitly the function is 0 if data[i,j]==0 else +infinity
    output = torch.where(data, 1e18, 0.0)
    assert output.is_contiguous()

    # Scratch tensors for the parabola stacks
    parabola_loc = torch.zeros(B, H, W, dtype=torch.uint32, device=data.device)
    parabola_inter = torch.empty(B, H, W, dtype=torch.float, device=data.device)
    parabola_inter[:, :, 0] = -1e18
    parabola_inter[:, :, 1] = 1e18

    # Grid size (number of blocks)
    grid = (B, H)

    # Launch initialization kernel
    edt_kernel[grid](
        output.clone(),
        output,
        parabola_loc,
        parabola_inter,
        H,
        W,
        horizontal=True,
    )

    # reset the parabola stacks
    parabola_loc.zero_()
    parabola_inter[:, :, 0] = -1e18
    parabola_inter[:, :, 1] = 1e18

    grid = (B, W)
    edt_kernel[grid](
        output.clone(),
        output,
        parabola_loc,
        parabola_inter,
        H,
        W,
        horizontal=False,
    )
    # don't forget to take sqrt at the end
    return output.sqrt()
'''
    
    with open(filepath, 'w') as f:
        f.write(new_content)
    print("  OK - Replaced with triton-optional version")
    return True


def patch_sam3_image_dataset_py(sam3_path):
    """Patch train/data/sam3_image_dataset.py - Make decord import optional."""
    filepath = os.path.join(sam3_path, "train", "data", "sam3_image_dataset.py")
    print(f"Patching {filepath}...")
    
    patches = [(
        """import torch
import torch.utils.data
import torchvision
from decord import cpu, VideoReader
from iopath.common.file_io import g_pathmgr""",
        """import torch
import torch.utils.data
import torchvision

# Conditional import for decord (not available on macOS)
try:
    from decord import cpu, VideoReader
    HAS_DECORD = True
except (ImportError, ModuleNotFoundError):
    HAS_DECORD = False
    VideoReader = None
    cpu = None

from iopath.common.file_io import g_pathmgr"""
    )]
    
    return patch_file(filepath, patches)


def patch_position_encoding_py(sam3_path):
    """Patch model/position_encoding.py - Auto-detect device instead of hardcoding cuda."""
    filepath = os.path.join(sam3_path, "model", "position_encoding.py")
    print(f"Patching {filepath}...")
    
    patches = [(
        """            for size in precompute_sizes:
                tensors = torch.zeros((1, 1) + size, device="cuda")
                self.forward(tensors)""",
        """            for size in precompute_sizes:
                # Use CPU for precompute if CUDA is not available
                device = "cuda" if torch.cuda.is_available() else "cpu"
                tensors = torch.zeros((1, 1) + size, device=device)
                self.forward(tensors)"""
    )]
    
    return patch_file(filepath, patches)


def patch_decoder_py(sam3_path):
    """Patch model/decoder.py - Auto-detect device instead of hardcoding cuda."""
    filepath = os.path.join(sam3_path, "model", "decoder.py")
    print(f"Patching {filepath}...")
    
    patches = [(
        """            if resolution is not None and stride is not None:
                feat_size = resolution // stride
                coords_h, coords_w = self._get_coords(
                    feat_size, feat_size, device="cuda"
                )""",
        """            if resolution is not None and stride is not None:
                feat_size = resolution // stride
                # Use CPU if CUDA is not available
                device = "cuda" if torch.cuda.is_available() else "cpu"
                coords_h, coords_w = self._get_coords(
                    feat_size, feat_size, device=device
                )"""
    )]
    
    return patch_file(filepath, patches)


def patch_sam3_image_processor_py(sam3_path):
    """Patch model/sam3_image_processor.py - Auto-detect device instead of hardcoding cuda."""
    filepath = os.path.join(sam3_path, "model", "sam3_image_processor.py")
    print(f"Patching {filepath}...")
    
    patches = [(
        """class Sam3Processor:
    \"\"\" \"\"\"

    def __init__(self, model, resolution=1008, device="cuda", confidence_threshold=0.5):
        self.model = model
        self.resolution = resolution
        self.device = device""",
        """class Sam3Processor:
    \"\"\" \"\"\"

    def __init__(self, model, resolution=1008, device=None, confidence_threshold=0.5):
        if device is None:
            device = "cuda" if torch.cuda.is_available() else "cpu"
        self.model = model
        self.resolution = resolution
        self.device = device"""
    )]
    
    return patch_file(filepath, patches)


def patch_vl_combiner_py(sam3_path):
    """Patch model/vl_combiner.py - Auto-detect device instead of hardcoding cuda."""
    filepath = os.path.join(sam3_path, "model", "vl_combiner.py")
    print(f"Patching {filepath}...")
    
    patches = [
        # First patch: forward_text method
        (
            """    def forward_text(
        self, captions, input_boxes=None, additional_text=None, device="cuda"
    ):
        return activation_ckpt_wrapper(self._forward_text_no_ack_ckpt)(""",
            """    def forward_text(
        self, captions, input_boxes=None, additional_text=None, device=None
    ):
        if device is None:
            device = "cuda" if torch.cuda.is_available() else "cpu"
        return activation_ckpt_wrapper(self._forward_text_no_ack_ckpt)("""
        ),
        # Second patch: _forward_text_no_ack_ckpt method
        (
            """    def _forward_text_no_ack_ckpt(
        self,
        captions,
        input_boxes=None,
        additional_text=None,
        device="cuda",
    ):
        output = {}""",
            """    def _forward_text_no_ack_ckpt(
        self,
        captions,
        input_boxes=None,
        additional_text=None,
        device=None,
    ):
        if device is None:
            device = "cuda" if torch.cuda.is_available() else "cpu"
        output = {}"""
        )
    ]
    
    success = True
    for old, new in patches:
        if not patch_file(filepath, [(old, new)]):
            success = False
    return success


def patch_geometry_encoders_py(sam3_path):
    """Patch model/geometry_encoders.py - Fix pin_memory for non-CUDA devices."""
    filepath = os.path.join(sam3_path, "model", "geometry_encoders.py")
    print(f"Patching {filepath}...")
    
    patches = [(
        """            boxes_xyxy = box_cxcywh_to_xyxy(boxes)
            scale = torch.tensor([W, H, W, H], dtype=boxes_xyxy.dtype)
            scale = scale.pin_memory().to(device=boxes_xyxy.device, non_blocking=True)
            scale = scale.view(1, 1, 4)""",
        """            boxes_xyxy = box_cxcywh_to_xyxy(boxes)
            scale = torch.tensor([W, H, W, H], dtype=boxes_xyxy.dtype)
            # Only pin memory for CUDA, not for MPS or CPU
            if boxes_xyxy.device.type == "cuda":
                scale = scale.pin_memory().to(device=boxes_xyxy.device, non_blocking=True)
            else:
                scale = scale.to(device=boxes_xyxy.device)
            scale = scale.view(1, 1, 4)"""
    )]
    
    return patch_file(filepath, patches)


def main():
    print("=" * 60)
    print("SAM3 macOS Patcher")
    print("=" * 60)
    print()
    
    # Find SAM3 installation
    sam3_path = get_sam3_path()
    if not sam3_path:
        print("ERROR: SAM3 not found in site-packages!")
        print("Make sure you've installed it with:")
        print("  pip install 'git+https://github.com/facebookresearch/sam3.git'")
        sys.exit(1)
    
    print(f"Found SAM3 at: {sam3_path}")
    print()
    
    # Apply patches
    patches = [
        ("model/edt.py (triton fallback)", patch_edt_py),
        ("train/data/sam3_image_dataset.py (decord fallback)", patch_sam3_image_dataset_py),
        ("model/position_encoding.py (cuda auto-detect)", patch_position_encoding_py),
        ("model/decoder.py (cuda auto-detect)", patch_decoder_py),
        ("model/sam3_image_processor.py (cuda auto-detect)", patch_sam3_image_processor_py),
        ("model/vl_combiner.py (cuda auto-detect)", patch_vl_combiner_py),
        ("model/geometry_encoders.py (pin_memory fix)", patch_geometry_encoders_py),
    ]
    
    success_count = 0
    for name, patch_func in patches:
        try:
            if patch_func(sam3_path):
                success_count += 1
        except Exception as e:
            print(f"  ERROR: {e}")
    
    print()
    print("=" * 60)
    print(f"Patching complete: {success_count}/{len(patches)} patches applied")
    print("=" * 60)
    
    # Test import
    print()
    print("Testing SAM3 import...")
    try:
        from sam3.model_builder import build_sam3_image_model
        print("SUCCESS: SAM3 imports correctly!")
    except Exception as e:
        print(f"ERROR: Import failed: {e}")
        sys.exit(1)
    
    print()
    print("Next steps:")
    print("1. Download SAM3 weights from https://huggingface.co/facebook/sam3")
    print("2. See SAM3_SETUP.md for detailed instructions")


if __name__ == "__main__":
    main()
