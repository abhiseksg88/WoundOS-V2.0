"""Tests for wound volume computation."""

import numpy as np
import pytest

from pipeline.measurement.volume import compute_volume_ml, compute_volume_prism


class TestVolumePrism:
    def test_flat_mesh_zero_volume(self):
        """A mesh on the plane should have zero volume."""
        vertices = np.array([
            [0, 0, 0], [0.01, 0, 0], [0.01, 0.01, 0], [0, 0.01, 0],
        ], dtype=np.float64)
        faces = np.array([[0, 1, 2], [0, 2, 3]])

        centroid = np.array([0.005, 0.005, 0.0])
        normal = np.array([0, 0, 1.0])

        vol = compute_volume_prism(vertices, faces, centroid, normal)
        assert vol < 1e-10

    def test_box_wound(self):
        """A simple box-shaped wound: 10mm x 10mm x 5mm deep.

        Expected volume: 0.5 mL (500 mm³ = 0.0000005 m³ = 0.5 mL)
        """
        # Bottom of wound (5mm below plane)
        d = 0.005  # 5mm in meters
        s = 0.01   # 10mm in meters
        vertices = np.array([
            [0,  0, -d], [s,  0, -d], [s,  s, -d], [0,  s, -d],
        ], dtype=np.float64)
        faces = np.array([[0, 1, 2], [0, 2, 3]])

        centroid = np.array([s/2, s/2, 0.0])
        normal = np.array([0, 0, 1.0])

        vol_ml = compute_volume_ml(vertices, faces, centroid, normal)
        expected_ml = s * s * d * 1e6  # 0.5 mL
        assert abs(vol_ml - expected_ml) < 0.1


class TestVolumeML:
    def test_empty_mesh(self):
        """Empty mesh should have zero volume."""
        vertices = np.zeros((0, 3))
        faces = np.zeros((0, 3), dtype=int)
        centroid = np.array([0, 0, 0.0])
        normal = np.array([0, 0, 1.0])

        vol = compute_volume_ml(vertices, faces, centroid, normal)
        assert vol == 0.0
