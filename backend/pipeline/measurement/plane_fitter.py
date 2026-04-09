"""RANSAC plane fitting on wound boundary points.

The wound plane is the reference surface from which depth is measured.
We fit the plane using ONLY boundary (perimeter) points — not interior
wound points, which would bias the plane downward into the wound.
"""

import numpy as np
from scipy.spatial.transform import Rotation


def fit_plane_svd(points: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Fit a plane to points using SVD (least-squares).

    Args:
        points: (N, 3) array of 3D points.

    Returns:
        (centroid, normal): centroid (3,) and unit normal (3,) of the plane.
    """
    centroid = points.mean(axis=0)
    centered = points - centroid
    _, _, Vt = np.linalg.svd(centered, full_matrices=False)
    normal = Vt[-1]  # Last row of Vt = direction of least variance
    # Ensure normal points "outward" (positive Z in most wound configurations)
    if normal[2] < 0:
        normal = -normal
    return centroid, normal


def fit_plane_ransac(
    boundary_points: np.ndarray,
    num_iterations: int = 1000,
    inlier_threshold_m: float = 0.002,  # 2mm
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """RANSAC plane fitting on wound boundary points.

    Args:
        boundary_points: (N, 3) array of 3D boundary vertices.
        num_iterations: Number of RANSAC iterations.
        inlier_threshold_m: Distance threshold for inliers in meters.

    Returns:
        (centroid, normal, inlier_mask): plane centroid, unit normal,
            and boolean mask of inlier points.
    """
    n = len(boundary_points)
    if n < 3:
        raise ValueError(f"Need at least 3 boundary points, got {n}")

    best_inlier_count = 0
    best_centroid = None
    best_normal = None
    best_mask = None

    rng = np.random.default_rng(42)

    for _ in range(num_iterations):
        # Sample 3 random points
        idx = rng.choice(n, size=3, replace=False)
        p0, p1, p2 = boundary_points[idx]

        # Compute plane normal from cross product
        v1 = p1 - p0
        v2 = p2 - p0
        normal = np.cross(v1, v2)
        norm_len = np.linalg.norm(normal)
        if norm_len < 1e-10:
            continue  # Degenerate triangle
        normal /= norm_len

        # Plane centroid from the 3 sample points
        centroid = (p0 + p1 + p2) / 3.0

        # Compute distances of all boundary points to plane
        dists = np.abs((boundary_points - centroid) @ normal)
        inlier_mask = dists < inlier_threshold_m
        inlier_count = inlier_mask.sum()

        if inlier_count > best_inlier_count:
            best_inlier_count = inlier_count
            best_centroid = centroid
            best_normal = normal
            best_mask = inlier_mask

    if best_centroid is None:
        # Fallback: SVD on all points
        centroid, normal = fit_plane_svd(boundary_points)
        return centroid, normal, np.ones(n, dtype=bool)

    # Refine with SVD on inliers
    inlier_points = boundary_points[best_mask]
    if len(inlier_points) >= 3:
        centroid, normal = fit_plane_svd(inlier_points)
    else:
        centroid, normal = best_centroid, best_normal

    # Orient normal consistently (away from wound depth = toward camera generally)
    # Convention: normal points in positive Z direction in world space
    if normal[2] < 0:
        normal = -normal

    return centroid, normal, best_mask


def fit_paraboloid(
    boundary_points: np.ndarray,
) -> tuple[np.ndarray, callable]:
    """Paraboloid fitting for wounds on curved body surfaces.

    Fits z = ax^2 + by^2 + cxy + dx + ey + f to boundary points.
    Used as fallback when RANSAC plane fitting has <50% inliers.

    Args:
        boundary_points: (N, 3) array of boundary vertices.

    Returns:
        (coefficients, depth_func): coefficients (6,) and a function
            that computes distance from a point to the paraboloid surface.
    """
    x = boundary_points[:, 0]
    y = boundary_points[:, 1]
    z = boundary_points[:, 2]

    # Design matrix for z = ax^2 + by^2 + cxy + dx + ey + f
    A = np.column_stack([x**2, y**2, x * y, x, y, np.ones_like(x)])
    coeffs, _, _, _ = np.linalg.lstsq(A, z, rcond=None)

    def depth_from_paraboloid(points: np.ndarray) -> np.ndarray:
        """Compute signed distance below paraboloid surface."""
        px, py, pz = points[:, 0], points[:, 1], points[:, 2]
        surface_z = (
            coeffs[0] * px**2 + coeffs[1] * py**2 + coeffs[2] * px * py
            + coeffs[3] * px + coeffs[4] * py + coeffs[5]
        )
        return surface_z - pz  # Positive = below surface = wound depth

    return coeffs, depth_from_paraboloid
