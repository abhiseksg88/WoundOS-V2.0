"""ARKit mesh helpers for LiDAR-native reconstruction pipeline.

When iOS captures with LiDAR, it serializes the ARKit scene reconstruction mesh
(ARMeshAnchor objects) to Wavefront OBJ bytes and uploads them. These helpers
parse the OBJ, optionally crop to the wound region, and return numpy arrays
compatible with the existing measurement pipeline (orchestrator._extract_wound_submesh
and the measurement modules).

All coordinates are in ARKit world space: meters, Y-up, right-handed,
with -Z forward in the camera frame. The orchestrator already handles this
convention (see orchestrator.py line 353: dirs_cam[:, 2] = -dirs_cam[:, 2]).
"""

import io
import logging

import numpy as np
import trimesh

logger = logging.getLogger("woundos.reconstruction.arkit_mesh")


def load_obj_bytes(obj_bytes: bytes) -> tuple[np.ndarray, np.ndarray]:
    """Parse a Wavefront OBJ byte blob into (vertices, faces) numpy arrays.

    Args:
        obj_bytes: OBJ file content as bytes (UTF-8 encoded).

    Returns:
        vertices: (N, 3) float64 array of vertex positions in meters.
        faces: (M, 3) int64 array of triangle vertex indices.

    Raises:
        ValueError: if OBJ is malformed or contains no triangles.
    """
    if not obj_bytes:
        raise ValueError("Empty OBJ bytes")

    try:
        # trimesh.load returns a Trimesh, Scene, or other geometry depending on contents.
        loaded = trimesh.load(
            file_obj=io.BytesIO(obj_bytes),
            file_type="obj",
            process=False,  # Skip merge_vertices/fix_normals for speed
            force="mesh",   # Concatenate any sub-meshes
        )
    except Exception as e:
        raise ValueError(f"Failed to parse OBJ: {e}") from e

    if not isinstance(loaded, trimesh.Trimesh):
        raise ValueError(f"OBJ produced unexpected geometry type: {type(loaded)}")

    vertices = np.asarray(loaded.vertices, dtype=np.float64)
    faces = np.asarray(loaded.faces, dtype=np.int64)

    if len(vertices) == 0 or len(faces) == 0:
        raise ValueError("OBJ contains no triangles")

    logger.info(
        "Parsed ARKit OBJ mesh: %d vertices, %d faces",
        len(vertices), len(faces),
    )
    return vertices, faces


def crop_to_sphere(
    vertices: np.ndarray,
    faces: np.ndarray,
    center_world: np.ndarray,
    radius_m: float,
) -> tuple[np.ndarray, np.ndarray]:
    """Keep triangles whose centroid lies within radius_m of center_world.

    This is the primary cropping step used by the LiDAR pipeline to isolate
    the wound region from the full ARKit scene mesh (which may cover the
    entire room).

    Args:
        vertices: (N, 3) float64 vertex positions.
        faces: (M, 3) int64 face indices.
        center_world: (3,) float64 sphere center in world space.
        radius_m: sphere radius in meters.

    Returns:
        (cropped_vertices, cropped_faces) with vertex indices remapped.
    """
    if len(faces) == 0:
        return vertices[:0], faces[:0]

    # Compute triangle centroids: average of 3 vertices per face
    tri_verts = vertices[faces]  # (M, 3, 3)
    centroids = tri_verts.mean(axis=1)  # (M, 3)

    # Filter triangles whose centroid is inside the sphere
    distances = np.linalg.norm(centroids - center_world, axis=1)
    inside_mask = distances <= radius_m

    if not inside_mask.any():
        logger.warning(
            "Sphere crop returned no triangles (radius=%.3fm, center=%s)",
            radius_m, center_world.tolist(),
        )
        return vertices[:0], np.zeros((0, 3), dtype=np.int64)

    kept_faces = faces[inside_mask]

    # Remap vertex indices to a compact set
    used_vertex_ids = np.unique(kept_faces.ravel())
    remap = np.full(len(vertices), -1, dtype=np.int64)
    remap[used_vertex_ids] = np.arange(len(used_vertex_ids))

    cropped_vertices = vertices[used_vertex_ids]
    cropped_faces = remap[kept_faces]

    logger.info(
        "Sphere crop: %d/%d faces kept (%.1f%%) within %.0fcm",
        len(cropped_faces), len(faces),
        100 * len(cropped_faces) / max(len(faces), 1),
        radius_m * 100,
    )
    return cropped_vertices, cropped_faces


def crop_to_camera_frustum(
    vertices: np.ndarray,
    faces: np.ndarray,
    pose_c2w: np.ndarray,
    intrinsics: dict,
    near_m: float = 0.05,
    far_m: float = 0.6,
    margin_px: int = 64,
) -> tuple[np.ndarray, np.ndarray]:
    """Keep triangles with at least one vertex visible in the camera frustum.

    Args:
        vertices: (N, 3) world-space vertex positions.
        faces: (M, 3) face indices.
        pose_c2w: (4, 4) camera-to-world transform.
        intrinsics: dict with fx, fy, cx, cy, width, height.
        near_m: minimum depth in camera space.
        far_m: maximum depth in camera space.
        margin_px: pixel margin around image bounds (allows partial visibility).

    Returns:
        (cropped_vertices, cropped_faces) with vertex indices remapped.
    """
    if len(faces) == 0:
        return vertices[:0], faces[:0]

    # World-to-camera transform
    w2c = np.linalg.inv(pose_c2w)
    R = w2c[:3, :3]
    t = w2c[:3, 3]

    # Transform vertices to camera space
    cam_verts = (R @ vertices.T).T + t  # (N, 3)

    # ARKit convention: -Z is forward (camera looks down -Z)
    # So forward depth is -cam_verts[:, 2]
    depths = -cam_verts[:, 2]

    fx = intrinsics["fx"]
    fy = intrinsics["fy"]
    cx = intrinsics["cx"]
    cy = intrinsics["cy"]
    width = intrinsics["width"]
    height = intrinsics["height"]

    # Project to image plane (only points with positive depth)
    valid_depth = (depths > near_m) & (depths < far_m)

    # Pixel coordinates (with margin tolerance)
    px = fx * cam_verts[:, 0] / np.where(depths > 1e-6, -cam_verts[:, 2], 1e6) + cx
    py = fy * cam_verts[:, 1] / np.where(depths > 1e-6, -cam_verts[:, 2], 1e6) + cy

    in_image = (
        (px >= -margin_px) & (px < width + margin_px) &
        (py >= -margin_px) & (py < height + margin_px)
    )

    visible = valid_depth & in_image

    # Keep faces with at least one visible vertex
    face_visibility = visible[faces].any(axis=1)
    kept_faces = faces[face_visibility]

    if len(kept_faces) == 0:
        logger.warning("Frustum crop returned no triangles")
        return vertices[:0], np.zeros((0, 3), dtype=np.int64)

    # Remap vertex indices
    used_vertex_ids = np.unique(kept_faces.ravel())
    remap = np.full(len(vertices), -1, dtype=np.int64)
    remap[used_vertex_ids] = np.arange(len(used_vertex_ids))

    cropped_vertices = vertices[used_vertex_ids]
    cropped_faces = remap[kept_faces]

    logger.info(
        "Frustum crop: %d/%d faces kept (%.1f%%)",
        len(cropped_faces), len(faces),
        100 * len(cropped_faces) / max(len(faces), 1),
    )
    return cropped_vertices, cropped_faces


def estimate_wound_center_world(
    pose_c2w: np.ndarray,
    intrinsics: dict,
    wound_point_norm: tuple[float, float] | None,
    vertices: np.ndarray,
    faces: np.ndarray,
) -> np.ndarray:
    """Ray-cast the wound tap point against the mesh to find a 3D seed center.

    If no wound_point provided, uses image center. Returns the first ray-mesh
    intersection in world space, which is then used as the sphere crop center.

    Args:
        pose_c2w: (4, 4) ARKit camera-to-world transform.
        intrinsics: camera intrinsics dict.
        wound_point_norm: (x, y) in [0, 1] normalized image coordinates, or None.
        vertices: (N, 3) full mesh vertices.
        faces: (M, 3) full mesh faces.

    Returns:
        (3,) float64 world-space hit point. Falls back to camera position
        + 0.20m forward if no intersection found.
    """
    fx = intrinsics["fx"]
    fy = intrinsics["fy"]
    cx = intrinsics["cx"]
    cy = intrinsics["cy"]
    width = intrinsics["width"]
    height = intrinsics["height"]

    # Default to image center if no wound point given
    if wound_point_norm is None:
        nx, ny = 0.5, 0.5
    else:
        nx, ny = wound_point_norm

    px = nx * width
    py = ny * height

    # Build ray in camera space
    # Camera convention: pixel (px, py) maps to ray direction (px-cx)/fx, (py-cy)/fy, 1
    # In ARKit: -Z is forward, so we negate Z below
    dir_cam = np.array([
        (px - cx) / fx,
        (py - cy) / fy,
        -1.0,  # ARKit: -Z forward
    ], dtype=np.float64)
    dir_cam /= np.linalg.norm(dir_cam)

    # Transform to world space
    R = pose_c2w[:3, :3]
    camera_pos = pose_c2w[:3, 3]
    dir_world = R @ dir_cam

    # Ray-cast against mesh
    if len(faces) == 0:
        logger.warning("estimate_wound_center_world: empty mesh, using fallback")
        return camera_pos + dir_world * 0.20

    mesh = trimesh.Trimesh(vertices=vertices, faces=faces, process=False)
    locations, _, _ = mesh.ray.intersects_location(
        ray_origins=camera_pos.reshape(1, 3),
        ray_directions=dir_world.reshape(1, 3),
        multiple_hits=False,
    )

    if len(locations) == 0:
        logger.warning("Ray-cast missed mesh, using camera+0.20m fallback")
        return camera_pos + dir_world * 0.20

    return np.asarray(locations[0], dtype=np.float64)
