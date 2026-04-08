"""Length, width, and perimeter computation.

Length = greatest distance between any two wound boundary points
         (projected onto the wound plane).
Width = greatest extent perpendicular to the length axis.
Perimeter = sum of 3D edge lengths along wound boundary.
"""

import numpy as np


def project_to_plane(
    points_3d: np.ndarray,
    plane_centroid: np.ndarray,
    plane_normal: np.ndarray,
) -> np.ndarray:
    """Project 3D points onto the wound plane and return 2D coordinates.

    Uses the plane's local coordinate system (two orthogonal axes on the plane).

    Args:
        points_3d: (N, 3) array of 3D points.
        plane_centroid: (3,) point on the plane.
        plane_normal: (3,) unit normal.

    Returns:
        (N, 2) array of 2D coordinates on the plane.
    """
    normal = plane_normal / np.linalg.norm(plane_normal)

    # Find two orthogonal axes on the plane
    # Choose a non-parallel vector to cross with normal
    if abs(normal[0]) < 0.9:
        ref = np.array([1.0, 0.0, 0.0])
    else:
        ref = np.array([0.0, 1.0, 0.0])

    axis_u = np.cross(normal, ref)
    axis_u /= np.linalg.norm(axis_u)
    axis_v = np.cross(normal, axis_u)
    axis_v /= np.linalg.norm(axis_v)

    # Project: compute (u, v) coordinates for each point
    centered = points_3d - plane_centroid
    u_coords = centered @ axis_u
    v_coords = centered @ axis_v

    return np.column_stack([u_coords, v_coords])


def compute_length_width_mm(
    boundary_points_3d: np.ndarray,
    plane_centroid: np.ndarray,
    plane_normal: np.ndarray,
) -> tuple[float, float]:
    """Compute greatest length and perpendicular width in millimeters.

    Length: Maximum pairwise distance between boundary points (projected onto plane).
    Width: Maximum extent perpendicular to the length axis.

    Args:
        boundary_points_3d: (N, 3) array of ordered wound boundary vertices.
        plane_centroid: (3,) reference plane point.
        plane_normal: (3,) reference plane normal.

    Returns:
        (length_mm, width_mm)
    """
    if len(boundary_points_3d) < 2:
        return (0.0, 0.0)

    # Project onto plane
    pts_2d = project_to_plane(boundary_points_3d, plane_centroid, plane_normal)

    # Find greatest pairwise distance (O(n^2) but n is typically <500)
    n = len(pts_2d)
    max_dist = 0.0
    p1_idx, p2_idx = 0, 1

    for i in range(n):
        diffs = pts_2d[i + 1:] - pts_2d[i]
        dists = np.sqrt((diffs ** 2).sum(axis=1))
        if len(dists) > 0:
            local_max_idx = dists.argmax()
            if dists[local_max_idx] > max_dist:
                max_dist = dists[local_max_idx]
                p1_idx = i
                p2_idx = i + 1 + local_max_idx

    length_m = max_dist

    # Length axis direction
    if length_m < 1e-10:
        return (0.0, 0.0)

    length_dir = pts_2d[p2_idx] - pts_2d[p1_idx]
    length_dir /= np.linalg.norm(length_dir)

    # Perpendicular direction
    perp_dir = np.array([-length_dir[1], length_dir[0]])

    # Project all boundary points onto perpendicular axis
    perp_projections = pts_2d @ perp_dir
    width_m = perp_projections.max() - perp_projections.min()

    return (length_m * 1000.0, width_m * 1000.0)


def compute_perimeter_mm(boundary_points_3d: np.ndarray) -> float:
    """Compute wound perimeter from ordered 3D boundary vertices.

    Sums the 3D edge lengths along the boundary path (not the projected 2D path).

    Args:
        boundary_points_3d: (N, 3) ordered wound boundary vertices in meters.

    Returns:
        Perimeter in millimeters.
    """
    if len(boundary_points_3d) < 2:
        return 0.0

    # Sum consecutive edge lengths (closed boundary)
    shifted = np.roll(boundary_points_3d, -1, axis=0)
    edge_lengths = np.linalg.norm(shifted - boundary_points_3d, axis=1)
    perimeter_m = edge_lengths.sum()

    return perimeter_m * 1000.0
