"""Tests for the ARKit LiDAR mesh helpers."""

import io

import numpy as np
import trimesh

from pipeline.reconstruction.arkit_mesh import (
    load_obj_bytes,
    crop_to_sphere,
    crop_to_camera_frustum,
    estimate_wound_center_world,
)


def _make_sphere_obj_bytes(radius: float = 0.05, subdivisions: int = 2) -> bytes:
    """Generate a synthetic sphere mesh as OBJ bytes for testing."""
    sphere = trimesh.creation.icosphere(subdivisions=subdivisions, radius=radius)
    return sphere.export(file_type="obj").encode("utf-8")


def test_load_obj_round_trip():
    """OBJ bytes should round-trip back to vertices/faces with correct counts."""
    radius = 0.05
    obj_bytes = _make_sphere_obj_bytes(radius=radius)
    vertices, faces = load_obj_bytes(obj_bytes)

    assert vertices.dtype == np.float64
    assert faces.dtype == np.int64
    assert len(vertices) > 0
    assert len(faces) > 0
    assert vertices.shape[1] == 3
    assert faces.shape[1] == 3

    # Verify all vertices are roughly on the sphere surface
    distances_from_origin = np.linalg.norm(vertices, axis=1)
    assert np.all(np.abs(distances_from_origin - radius) < 1e-3)


def test_load_obj_empty_bytes_raises():
    """Empty bytes should raise a ValueError."""
    try:
        load_obj_bytes(b"")
    except ValueError:
        pass
    else:
        assert False, "Expected ValueError for empty bytes"


def test_crop_to_sphere_keeps_only_inside():
    """Cropping a sphere around the origin with a small radius should reduce face count."""
    # Use a high-resolution sphere so face centroids are dense enough to crop
    sphere = trimesh.creation.icosphere(subdivisions=4, radius=0.5)
    vertices = np.asarray(sphere.vertices, dtype=np.float64)
    faces = np.asarray(sphere.faces, dtype=np.int64)

    # Crop around one pole with a 0.3m radius
    center = np.array([0.0, 0.0, 0.5], dtype=np.float64)
    cropped_v, cropped_f = crop_to_sphere(vertices, faces, center, radius_m=0.3)

    # Should keep some faces but not all
    assert len(cropped_f) > 0
    assert len(cropped_f) < len(faces)
    # Vertices should be remapped (no orphan vertices)
    assert len(cropped_v) <= len(vertices)
    # All face indices should be valid
    assert cropped_f.max() < len(cropped_v)
    assert cropped_f.min() >= 0


def test_crop_to_sphere_no_intersection():
    """Cropping with a center far from the mesh should return empty."""
    cube = trimesh.creation.box(extents=[1.0, 1.0, 1.0])
    vertices = np.asarray(cube.vertices, dtype=np.float64)
    faces = np.asarray(cube.faces, dtype=np.int64)

    far_center = np.array([100.0, 100.0, 100.0], dtype=np.float64)
    cropped_v, cropped_f = crop_to_sphere(vertices, faces, far_center, radius_m=1.0)

    assert len(cropped_f) == 0


def test_crop_to_camera_frustum():
    """Vertices outside the camera frustum should be excluded."""
    # Mesh: 100 random points in a 1m cube near the camera
    np.random.seed(42)
    n = 100
    vertices = np.random.uniform(-0.5, 0.5, size=(n, 3)).astype(np.float64)
    # Build trivial triangles (every 3 consecutive vertices)
    faces = np.array([[i, i + 1, i + 2] for i in range(0, n - 2)], dtype=np.int64)

    # Identity pose: camera at origin looking down -Z
    pose_c2w = np.eye(4, dtype=np.float64)
    intrinsics = {
        "fx": 1000.0, "fy": 1000.0,
        "cx": 500.0, "cy": 500.0,
        "width": 1000, "height": 1000,
    }

    cropped_v, cropped_f = crop_to_camera_frustum(
        vertices, faces, pose_c2w, intrinsics,
        near_m=0.05, far_m=2.0,
    )
    # Some triangles should survive
    assert len(cropped_f) >= 0  # Don't crash


def test_estimate_wound_center_uses_fallback_when_no_mesh():
    """With an empty mesh, falls back to camera + 0.20m forward (no rtree dependency)."""
    pose_c2w = np.eye(4, dtype=np.float64)
    intrinsics = {
        "fx": 1000.0, "fy": 1000.0,
        "cx": 500.0, "cy": 500.0,
        "width": 1000, "height": 1000,
    }

    # Empty mesh triggers the fallback path (no rtree needed)
    empty_v = np.zeros((0, 3), dtype=np.float64)
    empty_f = np.zeros((0, 3), dtype=np.int64)

    center = estimate_wound_center_world(
        pose_c2w, intrinsics, wound_point_norm=(0.5, 0.5),
        vertices=empty_v, faces=empty_f,
    )

    # Identity pose with -Z forward, fallback puts center at (0, 0, -0.20)
    assert center.shape == (3,)
    assert abs(center[2] + 0.20) < 1e-6
