"""Open3D TSDF Volumetric Fusion — Tier 1 fast reconstruction.

Integrates depth maps from Depth Pro with ARKit camera poses into a
TSDF volume, then extracts a triangle mesh via marching cubes.
Sub-millimeter voxel resolution at wound scale (~0.97mm voxels).
"""

import logging

import numpy as np
import open3d as o3d

from app.config import settings

logger = logging.getLogger("woundos.reconstruction.tsdf")


def fuse_depth_maps(
    depth_maps: list[np.ndarray],
    color_images: list[np.ndarray],
    poses: list[dict],
    intrinsics: dict,
) -> o3d.geometry.TriangleMesh:
    """Fuse multiple depth maps into a TSDF volume and extract mesh.

    Args:
        depth_maps: List of (H, W) float32 depth maps in meters.
        color_images: List of (H, W, 3) RGB uint8 images (same size as depth).
        poses: List of pose dicts with 'transform' (4x4 camera-to-world).
        intrinsics: Camera intrinsics {fx, fy, cx, cy, width, height}.

    Returns:
        Open3D TriangleMesh extracted from the TSDF volume.
    """
    # Create TSDF volume
    volume = o3d.pipelines.integration.ScalableTSDFVolume(
        voxel_length=settings.tsdf_voxel_length,
        sdf_trunc=settings.tsdf_sdf_trunc,
        color_type=o3d.pipelines.integration.TSDFVolumeColorType.RGB8,
    )

    # Build Open3D camera intrinsic
    fx = intrinsics["fx"]
    fy = intrinsics["fy"]
    cx = intrinsics["cx"]
    cy = intrinsics["cy"]
    width = intrinsics["width"]
    height = intrinsics["height"]

    # Scale intrinsics if depth maps are at different resolution
    depth_h, depth_w = depth_maps[0].shape[:2]
    scale_x = depth_w / width
    scale_y = depth_h / height
    o3d_intrinsic = o3d.camera.PinholeCameraIntrinsic(
        depth_w, depth_h,
        fx * scale_x, fy * scale_y,
        cx * scale_x, cy * scale_y,
    )

    # ARKit to Open3D coordinate conversion
    # ARKit: X-right, Y-up, Z-toward-viewer
    # Open3D TSDF expects OpenCV convention: X-right, Y-down, Z-forward
    coord_convert = np.array([
        [1,  0,  0, 0],
        [0, -1,  0, 0],
        [0,  0, -1, 0],
        [0,  0,  0, 1],
    ], dtype=np.float64)

    for i, (depth, color, pose) in enumerate(zip(depth_maps, color_images, poses)):
        # Convert ARKit C2W to Open3D extrinsic (W2C in OpenCV convention)
        c2w = np.array(pose["transform"], dtype=np.float64)
        # Flip to OpenCV convention, then invert to W2C
        c2w_cv = coord_convert @ c2w
        w2c = np.linalg.inv(c2w_cv)

        # Resize color to match depth if needed
        if color.shape[:2] != depth.shape[:2]:
            import cv2
            color = cv2.resize(color, (depth_w, depth_h))

        # Create Open3D images
        depth_o3d = o3d.geometry.Image(depth.astype(np.float32))
        color_o3d = o3d.geometry.Image(color.astype(np.uint8))
        rgbd = o3d.geometry.RGBDImage.create_from_color_and_depth(
            color_o3d, depth_o3d,
            depth_scale=1.0,  # Already in meters
            depth_trunc=1.0,  # Max 1m depth
            convert_rgb_to_intensity=False,
        )

        # Integrate into TSDF
        volume.integrate(rgbd, o3d_intrinsic, w2c)

        if (i + 1) % 10 == 0:
            logger.info("TSDF integration: %d/%d frames", i + 1, len(depth_maps))

    # Extract mesh via marching cubes
    mesh = volume.extract_triangle_mesh()
    mesh.compute_vertex_normals()

    logger.info(
        "TSDF fusion complete: %d vertices, %d triangles",
        len(mesh.vertices), len(mesh.triangles),
    )
    return mesh


def mesh_to_numpy(mesh: o3d.geometry.TriangleMesh) -> tuple[np.ndarray, np.ndarray]:
    """Convert Open3D mesh to numpy arrays.

    Returns:
        (vertices, faces): vertices (V, 3) float64, faces (F, 3) int32.
    """
    vertices = np.asarray(mesh.vertices)
    faces = np.asarray(mesh.triangles)
    return vertices, faces


def mesh_to_obj_bytes(mesh: o3d.geometry.TriangleMesh) -> bytes:
    """Export Open3D mesh to OBJ format as bytes."""
    import tempfile
    import os

    with tempfile.NamedTemporaryFile(suffix=".obj", delete=False) as f:
        tmp_path = f.name

    o3d.io.write_triangle_mesh(tmp_path, mesh)

    with open(tmp_path, "rb") as f:
        obj_data = f.read()

    os.unlink(tmp_path)
    return obj_data
