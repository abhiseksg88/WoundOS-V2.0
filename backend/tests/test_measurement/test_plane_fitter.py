"""Tests for RANSAC plane fitting."""

import numpy as np
import pytest

from pipeline.measurement.plane_fitter import fit_plane_ransac, fit_plane_svd


class TestFitPlaneSVD:
    def test_flat_plane_xy(self):
        """Points on the XY plane should produce a Z-normal."""
        points = np.array([
            [0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0],
            [0.5, 0.5, 0], [0.2, 0.8, 0],
        ], dtype=np.float64)
        centroid, normal = fit_plane_svd(points)

        # Normal should be approximately [0, 0, 1]
        assert abs(abs(normal[2]) - 1.0) < 0.01
        # Centroid should be near center of points
        assert abs(centroid[2]) < 0.01

    def test_tilted_plane(self):
        """Points on a tilted plane should return the correct normal."""
        # Plane: z = x (45-degree tilt)
        points = np.array([
            [0, 0, 0], [1, 0, 1], [0, 1, 0], [1, 1, 1],
            [0.5, 0.5, 0.5], [0.2, 0.3, 0.2],
        ], dtype=np.float64)
        centroid, normal = fit_plane_svd(points)

        # Normal should be perpendicular to [1,0,1] and [0,1,0]
        # That's [-1, 0, 1] normalized
        expected_normal = np.array([-1, 0, 1]) / np.sqrt(2)
        # Check alignment (dot product close to ±1)
        alignment = abs(np.dot(normal, expected_normal))
        assert alignment > 0.99


class TestFitPlaneRANSAC:
    def test_clean_plane(self):
        """RANSAC on clean planar points should find the exact plane."""
        rng = np.random.default_rng(42)
        n = 100
        xy = rng.uniform(-0.05, 0.05, (n, 2))
        z = np.zeros(n)
        points = np.column_stack([xy, z])

        centroid, normal, mask = fit_plane_ransac(points)

        assert abs(abs(normal[2]) - 1.0) < 0.05
        assert mask.sum() > n * 0.9  # Most points should be inliers

    def test_plane_with_outliers(self):
        """RANSAC should reject outlier points."""
        rng = np.random.default_rng(42)

        # 80 inlier points on z=0 plane
        n_inliers = 80
        xy = rng.uniform(-0.05, 0.05, (n_inliers, 2))
        inliers = np.column_stack([xy, np.zeros(n_inliers)])

        # 20 outlier points at z=0.01 (10mm — well above 2mm threshold)
        n_outliers = 20
        xy_out = rng.uniform(-0.05, 0.05, (n_outliers, 2))
        outliers = np.column_stack([xy_out, np.full(n_outliers, 0.01)])

        points = np.vstack([inliers, outliers])
        centroid, normal, mask = fit_plane_ransac(points)

        # Should find the z=0 plane
        assert abs(abs(normal[2]) - 1.0) < 0.05
        # At least 70% of inliers should be detected
        assert mask[:n_inliers].sum() > n_inliers * 0.7

    def test_minimum_points(self):
        """Should work with exactly 3 points."""
        points = np.array([[0, 0, 0], [1, 0, 0], [0, 1, 0]], dtype=np.float64)
        centroid, normal, mask = fit_plane_ransac(points)
        assert len(mask) == 3

    def test_too_few_points(self):
        """Should raise ValueError with fewer than 3 points."""
        points = np.array([[0, 0, 0], [1, 0, 0]], dtype=np.float64)
        with pytest.raises(ValueError):
            fit_plane_ransac(points)
