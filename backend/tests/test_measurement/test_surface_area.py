"""Tests for surface area computation."""

import numpy as np
import pytest

from pipeline.measurement.surface_area import (
    compute_triangle_areas,
    compute_surface_area_cm2,
)


class TestTriangleAreas:
    def test_unit_triangle(self):
        """A right triangle with legs 1m should have area 0.5 m²."""
        vertices = np.array([
            [0, 0, 0],
            [1, 0, 0],
            [0, 1, 0],
        ], dtype=np.float64)
        faces = np.array([[0, 1, 2]])

        areas = compute_triangle_areas(vertices, faces)
        assert abs(areas[0] - 0.5) < 1e-10

    def test_square_from_two_triangles(self):
        """A 1m x 1m square split into 2 triangles should have area 1 m²."""
        vertices = np.array([
            [0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0],
        ], dtype=np.float64)
        faces = np.array([[0, 1, 2], [0, 2, 3]])

        areas = compute_triangle_areas(vertices, faces)
        total = areas.sum()
        assert abs(total - 1.0) < 1e-10


class TestSurfaceAreaCm2:
    def test_10mm_square_wound(self):
        """A 10mm x 10mm flat wound = 1 cm²."""
        # 10mm = 0.01m
        vertices = np.array([
            [0, 0, 0], [0.01, 0, 0], [0.01, 0.01, 0], [0, 0.01, 0],
        ], dtype=np.float64)
        faces = np.array([[0, 1, 2], [0, 2, 3]])

        area_cm2 = compute_surface_area_cm2(vertices, faces)
        assert abs(area_cm2 - 1.0) < 0.01

    def test_with_face_mask(self):
        """Face mask should select only wound-interior faces."""
        vertices = np.array([
            [0, 0, 0], [0.01, 0, 0], [0.01, 0.01, 0], [0, 0.01, 0],
        ], dtype=np.float64)
        faces = np.array([[0, 1, 2], [0, 2, 3]])
        mask = np.array([True, False])  # Only first triangle

        area_cm2 = compute_surface_area_cm2(vertices, faces, mask)
        assert abs(area_cm2 - 0.5) < 0.01
