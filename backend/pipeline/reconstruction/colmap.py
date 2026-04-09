"""COLMAP Multi-View Stereo pipeline — Tier 2 gold-standard reconstruction.

Uses known ARKit poses (skips SfM) to run dense stereo matching
and Poisson surface reconstruction. Produces the highest-quality
mesh for clinical-grade measurements.
"""

import logging
import os
import shutil
import subprocess
import tempfile

import numpy as np
import open3d as o3d

from app.config import settings
from pipeline.reconstruction.pose_converter import write_colmap_files

logger = logging.getLogger("woundos.reconstruction.colmap")


def run_colmap_mvs(
    frames: list[bytes],
    poses: list[dict],
    intrinsics: dict,
    workspace: str | None = None,
) -> o3d.geometry.TriangleMesh:
    """Run full COLMAP MVS pipeline with known poses.

    Steps:
    1. Write COLMAP model files from ARKit poses
    2. Undistort images
    3. PatchMatch stereo (GPU)
    4. Stereo fusion
    5. Poisson surface reconstruction
    6. Taubin mesh smoothing

    Args:
        frames: List of JPEG frame bytes.
        poses: List of pose dicts with 'transform' (4x4).
        intrinsics: Camera intrinsics dict.
        workspace: Optional workspace directory. If None, uses tempdir.

    Returns:
        Smoothed Open3D TriangleMesh.
    """
    cleanup = workspace is None
    if workspace is None:
        workspace = tempfile.mkdtemp(prefix="colmap_")

    try:
        return _run_pipeline(frames, poses, intrinsics, workspace)
    finally:
        if cleanup:
            shutil.rmtree(workspace, ignore_errors=True)


def _run_pipeline(
    frames: list[bytes],
    poses: list[dict],
    intrinsics: dict,
    workspace: str,
) -> o3d.geometry.TriangleMesh:
    """Internal pipeline execution."""
    colmap = settings.colmap_binary

    # Create directory structure
    images_dir = os.path.join(workspace, "images")
    sparse_dir = os.path.join(workspace, "sparse", "0")
    dense_dir = os.path.join(workspace, "dense")
    mesh_dir = os.path.join(workspace, "mesh")
    os.makedirs(images_dir, exist_ok=True)
    os.makedirs(sparse_dir, exist_ok=True)
    os.makedirs(dense_dir, exist_ok=True)
    os.makedirs(mesh_dir, exist_ok=True)

    # Write frame images
    frame_filenames = []
    for i, frame_data in enumerate(frames):
        filename = f"frame_{i:04d}.jpg"
        frame_filenames.append(filename)
        with open(os.path.join(images_dir, filename), "wb") as f:
            f.write(frame_data)

    # Write COLMAP model files (cameras.txt, images.txt, points3D.txt)
    write_colmap_files(sparse_dir, intrinsics, poses, frame_filenames)

    # Step 1: Image undistortion
    logger.info("COLMAP: Running image undistorter...")
    _run_cmd([
        colmap, "image_undistorter",
        "--image_path", images_dir,
        "--input_path", sparse_dir,
        "--output_path", dense_dir,
        "--output_type", "COLMAP",
        "--max_image_size", str(settings.colmap_max_image_size),
    ])

    # Step 2: PatchMatch Stereo (GPU-accelerated)
    logger.info("COLMAP: Running PatchMatch stereo...")
    _run_cmd([
        colmap, "patch_match_stereo",
        "--workspace_path", dense_dir,
        "--workspace_format", "COLMAP",
        "--PatchMatchStereo.gpu_index", str(settings.colmap_gpu_index),
        "--PatchMatchStereo.max_image_size", str(settings.colmap_max_image_size),
        "--PatchMatchStereo.num_iterations", str(settings.colmap_num_iterations),
        "--PatchMatchStereo.geom_consistency", "true",
        "--PatchMatchStereo.window_radius", "5",
        "--PatchMatchStereo.window_step", "1",
        "--PatchMatchStereo.filter_min_ncc", "0.1",
        "--PatchMatchStereo.filter_min_num_consistent", "2",
        "--PatchMatchStereo.cache_size", "32",
    ])

    # Step 3: Stereo Fusion
    fused_path = os.path.join(dense_dir, "fused.ply")
    logger.info("COLMAP: Running stereo fusion...")
    _run_cmd([
        colmap, "stereo_fusion",
        "--workspace_path", dense_dir,
        "--workspace_format", "COLMAP",
        "--input_type", "geometric",
        "--output_path", fused_path,
        "--StereoFusion.min_num_pixels", "3",
        "--StereoFusion.max_reproj_error", "2.0",
        "--StereoFusion.max_depth_error", "0.01",
    ])

    # Step 4: Poisson Surface Reconstruction
    mesh_path = os.path.join(mesh_dir, "wound_colmap.ply")
    logger.info("COLMAP: Running Poisson mesher...")
    _run_cmd([
        colmap, "poisson_mesher",
        "--input_path", fused_path,
        "--output_path", mesh_path,
        "--PoissonMeshing.depth", "10",
        "--PoissonMeshing.trim", "7.0",
        "--PoissonMeshing.color", "1",
    ])

    # Load mesh
    mesh = o3d.io.read_triangle_mesh(mesh_path)
    if not mesh.has_vertices():
        raise RuntimeError("COLMAP produced an empty mesh")

    logger.info(
        "COLMAP mesh: %d vertices, %d triangles",
        len(mesh.vertices), len(mesh.triangles),
    )

    # Step 5: Taubin mesh smoothing (addresses SALVE finding about noisy COLMAP meshes)
    mesh = mesh.filter_smooth_taubin(number_of_iterations=10)
    mesh.compute_vertex_normals()

    logger.info("COLMAP MVS pipeline complete")
    return mesh


def _run_cmd(cmd: list[str], timeout: int = 300) -> None:
    """Run a subprocess command with logging and error handling."""
    logger.debug("Running: %s", " ".join(cmd))
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if result.returncode != 0:
        logger.error("COLMAP command failed (exit %d):\n%s", result.returncode, result.stderr)
        raise RuntimeError(f"COLMAP failed: {result.stderr[:500]}")
