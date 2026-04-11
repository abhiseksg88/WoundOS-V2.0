"""Tests for length, width, and perimeter computation."""

import numpy as np
import pytest

from pipeline.measurement.dimensions import (
    compute_length_width_mm,
    compute_length_width_with_endpoints,
    compute_perimeter_mm,
    project_to_plane,
)


class TestLengthWidth:
    def test_circular_boundary(self):
        """Circular wound with 10mm diameter."""
        r = 0.005  # 5mm radius
        n = 100
        angles = np.linspace(0, 2 * np.pi, n, endpoint=False)
        boundary = np.column_stack([
            r * np.cos(angles),
            r * np.sin(angles),
            np.zeros(n),
        ])

        centroid = np.array([0, 0, 0.0])
        normal = np.array([0, 0, 1.0])

        length, width = compute_length_width_mm(boundary, centroid, normal)

        # Diameter should be ~10mm
        assert abs(length - 10.0) < 0.5
        assert abs(width - 10.0) < 0.5

    def test_elongated_wound(self):
        """Elongated wound: 30mm x 10mm."""
        # Ellipse
        n = 100
        angles = np.linspace(0, 2 * np.pi, n, endpoint=False)
        boundary = np.column_stack([
            0.015 * np.cos(angles),  # 15mm semi-major
            0.005 * np.sin(angles),  # 5mm semi-minor
            np.zeros(n),
        ])

        centroid = np.array([0, 0, 0.0])
        normal = np.array([0, 0, 1.0])

        length, width = compute_length_width_mm(boundary, centroid, normal)

        assert length > width
        assert abs(length - 30.0) < 1.0
        assert abs(width - 10.0) < 1.0

    def test_single_point(self):
        """Single point should return zero dimensions."""
        boundary = np.array([[0, 0, 0]], dtype=np.float64)
        centroid = np.array([0, 0, 0.0])
        normal = np.array([0, 0, 1.0])

        length, width = compute_length_width_mm(boundary, centroid, normal)
        assert length == 0.0
        assert width == 0.0


class TestLengthWidthEndpoints:
    def test_endpoints_match_extremes_for_ellipse(self):
        """The L endpoints should be on the major axis; W endpoints on the minor axis."""
        n = 100
        angles = np.linspace(0, 2 * np.pi, n, endpoint=False)
        boundary = np.column_stack([
            0.015 * np.cos(angles),  # 15mm semi-major
            0.005 * np.sin(angles),  # 5mm semi-minor
            np.zeros(n),
        ])

        centroid = np.array([0, 0, 0.0])
        normal = np.array([0, 0, 1.0])

        length, width, l_p1, l_p2, w_p1, w_p2 = compute_length_width_with_endpoints(
            boundary, centroid, normal
        )

        # Length endpoints should be roughly at (-0.015, 0) and (0.015, 0)
        assert abs(boundary[l_p1][0]) > 0.013 or abs(boundary[l_p2][0]) > 0.013
        # The dimension values should match the wrapper API
        length2, width2 = compute_length_width_mm(boundary, centroid, normal)
        assert abs(length - length2) < 1e-9
        assert abs(width - width2) < 1e-9

    def test_endpoints_indices_in_range(self):
        """Endpoint indices should be valid array indices."""
        n = 32
        angles = np.linspace(0, 2 * np.pi, n, endpoint=False)
        boundary = np.column_stack([
            0.01 * np.cos(angles),
            0.01 * np.sin(angles),
            np.zeros(n),
        ])
        centroid = np.array([0, 0, 0.0])
        normal = np.array([0, 0, 1.0])

        _, _, l_p1, l_p2, w_p1, w_p2 = compute_length_width_with_endpoints(
            boundary, centroid, normal
        )
        for idx in (l_p1, l_p2, w_p1, w_p2):
            assert 0 <= idx < n

    def test_too_few_points_returns_zeros(self):
        """Empty/single point should return zeros and safe default indices."""
        boundary = np.array([[0, 0, 0]], dtype=np.float64)
        centroid = np.array([0, 0, 0.0])
        normal = np.array([0, 0, 1.0])

        length, width, l_p1, l_p2, w_p1, w_p2 = compute_length_width_with_endpoints(
            boundary, centroid, normal
        )
        assert length == 0.0
        assert width == 0.0


class TestPerimeter:
    def test_square_perimeter(self):
        """A 10mm square should have 40mm perimeter."""
        s = 0.01  # 10mm
        boundary = np.array([
            [0, 0, 0], [s, 0, 0], [s, s, 0], [0, s, 0],
        ], dtype=np.float64)

        perimeter = compute_perimeter_mm(boundary)
        assert abs(perimeter - 40.0) < 0.1

    def test_circle_perimeter(self):
        """A circle with 5mm radius should have ~31.4mm perimeter."""
        r = 0.005
        n = 200
        angles = np.linspace(0, 2 * np.pi, n, endpoint=False)
        boundary = np.column_stack([
            r * np.cos(angles),
            r * np.sin(angles),
            np.zeros(n),
        ])

        perimeter = compute_perimeter_mm(boundary)
        expected = 2 * np.pi * r * 1000  # ~31.4mm
        assert abs(perimeter - expected) < 0.5
