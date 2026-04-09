"""3D surface area computation from triangle mesh."""

import numpy as np


def compute_triangle_areas(vertices: np.ndarray, faces: np.ndarray) -> np.ndarray:
    """Compute the area of each triangle in the mesh.

    Args:
        vertices: (V, 3) array of vertex positions.
        faces: (F, 3) array of face vertex indices.

    Returns:
        (F,) array of triangle areas.
    """
    v0 = vertices[faces[:, 0]]
    v1 = vertices[faces[:, 1]]
    v2 = vertices[faces[:, 2]]

    cross = np.cross(v1 - v0, v2 - v0)
    areas = 0.5 * np.linalg.norm(cross, axis=1)
    return areas


def compute_surface_area_m2(
    vertices: np.ndarray,
    faces: np.ndarray,
    face_mask: np.ndarray | None = None,
) -> float:
    """Compute total 3D surface area of wound mesh in square meters.

    Args:
        vertices: (V, 3) array of vertex positions in meters.
        faces: (F, 3) array of face vertex indices.
        face_mask: Optional (F,) boolean mask. If provided, only sum
            areas of faces where mask is True (wound interior).

    Returns:
        Total surface area in square meters.
    """
    areas = compute_triangle_areas(vertices, faces)
    if face_mask is not None:
        areas = areas[face_mask]
    return float(areas.sum())


def compute_surface_area_cm2(
    vertices: np.ndarray,
    faces: np.ndarray,
    face_mask: np.ndarray | None = None,
) -> float:
    """Compute total 3D surface area in square centimeters."""
    return compute_surface_area_m2(vertices, faces, face_mask) * 10000.0
