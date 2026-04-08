"""Wound volume computation via mesh capping and divergence theorem."""

import numpy as np


def compute_volume_divergence(
    wound_vertices: np.ndarray,
    wound_faces: np.ndarray,
    plane_centroid: np.ndarray,
    plane_normal: np.ndarray,
) -> float:
    """Compute wound volume by capping the wound mesh with the reference plane.

    Method: Project wound boundary vertices onto the plane to create a cap,
    then compute the signed volume of the closed mesh using the divergence
    theorem: V = (1/6) * sum(dot(v0, cross(v1, v2))) for each face.

    Args:
        wound_vertices: (V, 3) wound interior vertex positions in meters.
        wound_faces: (F, 3) face indices into wound_vertices.
        plane_centroid: (3,) point on wound reference plane.
        plane_normal: (3,) unit normal (outward direction).

    Returns:
        Volume in cubic meters (always positive).
    """
    if len(wound_faces) == 0:
        return 0.0

    # Get triangle vertices
    v0 = wound_vertices[wound_faces[:, 0]]
    v1 = wound_vertices[wound_faces[:, 1]]
    v2 = wound_vertices[wound_faces[:, 2]]

    # Signed volume contribution of each triangle
    # Using divergence theorem: V = (1/6) * sum(v0 . (v1 x v2))
    cross_product = np.cross(v1, v2)
    volume_contributions = np.sum(v0 * cross_product, axis=1)
    signed_volume = volume_contributions.sum() / 6.0

    return abs(signed_volume)


def compute_volume_prism(
    wound_vertices: np.ndarray,
    wound_faces: np.ndarray,
    plane_centroid: np.ndarray,
    plane_normal: np.ndarray,
) -> float:
    """Compute wound volume using triangular prism decomposition.

    For each wound triangle, project its vertices onto the plane
    to form a prism, then decompose into tetrahedra.

    Args:
        wound_vertices: (V, 3) wound interior vertices in meters.
        wound_faces: (F, 3) face indices.
        plane_centroid: (3,) point on reference plane.
        plane_normal: (3,) unit normal.

    Returns:
        Volume in cubic meters.
    """
    if len(wound_faces) == 0:
        return 0.0

    total_volume = 0.0
    normal = plane_normal / np.linalg.norm(plane_normal)

    for face in wound_faces:
        v = wound_vertices[face]  # (3, 3) — three vertices

        # Project each vertex onto the plane
        projected = np.zeros_like(v)
        for i in range(3):
            dist = np.dot(v[i] - plane_centroid, normal)
            projected[i] = v[i] - dist * normal

        # Decompose the prism (v0,v1,v2) → (p0,p1,p2) into tetrahedra
        # Tetra 1: (v0, v1, v2, p0)
        # Tetra 2: (v1, v2, p0, p1)
        # Tetra 3: (v2, p0, p1, p2)
        tetras = [
            (v[0], v[1], v[2], projected[0]),
            (v[1], v[2], projected[0], projected[1]),
            (v[2], projected[0], projected[1], projected[2]),
        ]

        for a, b, c, d in tetras:
            vol = abs(np.dot(b - a, np.cross(c - a, d - a))) / 6.0
            total_volume += vol

    return total_volume


def compute_volume_ml(
    wound_vertices: np.ndarray,
    wound_faces: np.ndarray,
    plane_centroid: np.ndarray,
    plane_normal: np.ndarray,
) -> float:
    """Compute wound volume in milliliters using prism method."""
    volume_m3 = compute_volume_prism(
        wound_vertices, wound_faces, plane_centroid, plane_normal
    )
    return volume_m3 * 1e6  # 1 m^3 = 1,000,000 mL
