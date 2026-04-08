"""Wound depth computation from reference plane."""

import numpy as np


def compute_depths(
    wound_vertices: np.ndarray,
    plane_centroid: np.ndarray,
    plane_normal: np.ndarray,
) -> np.ndarray:
    """Compute signed depth of each wound vertex below the reference plane.

    Positive values = below the plane (wound depth).
    Negative values = above the plane (should be rare for interior points).

    Args:
        wound_vertices: (N, 3) array of 3D wound interior vertices in meters.
        plane_centroid: (3,) point on the reference plane.
        plane_normal: (3,) unit normal of the reference plane (pointing outward).

    Returns:
        (N,) array of signed depths in meters.
    """
    offsets = wound_vertices - plane_centroid
    signed_distances = offsets @ plane_normal
    # Depth is positive when point is below plane (opposite to normal direction)
    depths = -signed_distances
    return depths


def compute_max_depth_mm(
    wound_vertices: np.ndarray,
    plane_centroid: np.ndarray,
    plane_normal: np.ndarray,
) -> float:
    """Maximum wound depth in millimeters."""
    depths = compute_depths(wound_vertices, plane_centroid, plane_normal)
    positive_depths = depths[depths > 0]
    if len(positive_depths) == 0:
        return 0.0
    return float(positive_depths.max()) * 1000.0


def compute_avg_depth_mm(
    wound_vertices: np.ndarray,
    plane_centroid: np.ndarray,
    plane_normal: np.ndarray,
) -> float:
    """Average wound depth in millimeters (only positive-depth vertices)."""
    depths = compute_depths(wound_vertices, plane_centroid, plane_normal)
    positive_depths = depths[depths > 0]
    if len(positive_depths) == 0:
        return 0.0
    return float(positive_depths.mean()) * 1000.0


def find_deepest_point(
    wound_vertices: np.ndarray,
    plane_centroid: np.ndarray,
    plane_normal: np.ndarray,
) -> tuple[np.ndarray, float]:
    """Find the deepest point in the wound and its depth.

    Returns:
        (point, depth_mm): 3D coordinates of deepest point, depth in mm.
    """
    depths = compute_depths(wound_vertices, plane_centroid, plane_normal)
    if len(depths) == 0:
        return np.zeros(3), 0.0
    idx = depths.argmax()
    return wound_vertices[idx], float(depths[idx]) * 1000.0
