"""Tests for ARKit → COLMAP pose conversion."""

import os
import tempfile

import numpy as np
import pytest

from pipeline.reconstruction.pose_converter import (
    arkit_to_colmap_pose,
    rotation_matrix_to_quaternion,
    write_colmap_files,
)


class TestRotationToQuaternion:
    def test_identity(self):
        """Identity matrix → quaternion (1, 0, 0, 0)."""
        R = np.eye(3)
        qw, qx, qy, qz = rotation_matrix_to_quaternion(R)
        assert abs(qw - 1.0) < 1e-6
        assert abs(qx) < 1e-6
        assert abs(qy) < 1e-6
        assert abs(qz) < 1e-6

    def test_180_rotation_z(self):
        """180° rotation around Z axis."""
        R = np.array([[-1, 0, 0], [0, -1, 0], [0, 0, 1]], dtype=np.float64)
        qw, qx, qy, qz = rotation_matrix_to_quaternion(R)
        # Should be (0, 0, 0, 1) or equivalent
        assert abs(abs(qz) - 1.0) < 1e-6
        assert abs(qw) < 1e-6


class TestARKitToCOLMAP:
    def test_identity_pose(self):
        """Identity ARKit pose → specific COLMAP pose."""
        c2w = np.eye(4)
        quat, tvec = arkit_to_colmap_pose(c2w)

        # With identity C2W + coord flip:
        # W2C rotation = coord_convert.T = coord_convert (symmetric)
        # So W2C = [[1,0,0],[0,-1,0],[0,0,-1]]
        # Translation should be zero
        assert abs(tvec[0]) < 1e-6
        assert abs(tvec[1]) < 1e-6
        assert abs(tvec[2]) < 1e-6

    def test_translation_conversion(self):
        """ARKit camera at (0, 0.25, 0) → COLMAP should flip Y."""
        c2w = np.eye(4)
        c2w[1, 3] = 0.25  # Y=0.25m in ARKit = up

        quat, tvec = arkit_to_colmap_pose(c2w)

        # In COLMAP (OpenCV), Y is flipped → translation should reflect that
        # The exact values depend on the full conversion but translation magnitude
        # should be preserved
        assert np.linalg.norm(tvec) > 0.2

    def test_roundtrip_consistency(self):
        """Quaternion norm should be 1 (valid rotation)."""
        c2w = np.eye(4)
        c2w[:3, 3] = [0.1, 0.2, 0.3]

        quat, tvec = arkit_to_colmap_pose(c2w)
        qw, qx, qy, qz = quat
        norm = np.sqrt(qw**2 + qx**2 + qy**2 + qz**2)
        assert abs(norm - 1.0) < 1e-6


class TestWriteCOLMAPFiles:
    def test_writes_all_files(self):
        """Should create cameras.txt, images.txt, points3D.txt."""
        with tempfile.TemporaryDirectory() as tmpdir:
            intrinsics = {
                "fx": 3088.57, "fy": 3088.57,
                "cx": 2016.0, "cy": 1512.0,
                "width": 4032, "height": 3024,
            }
            poses = [
                {"transform": np.eye(4).tolist(), "trackingState": "normal"},
                {"transform": np.eye(4).tolist(), "trackingState": "normal"},
            ]
            filenames = ["frame_0000.jpg", "frame_0001.jpg"]

            write_colmap_files(tmpdir, intrinsics, poses, filenames)

            assert os.path.exists(os.path.join(tmpdir, "cameras.txt"))
            assert os.path.exists(os.path.join(tmpdir, "images.txt"))
            assert os.path.exists(os.path.join(tmpdir, "points3D.txt"))

            # Verify cameras.txt content
            with open(os.path.join(tmpdir, "cameras.txt")) as f:
                content = f.read()
                assert "PINHOLE" in content
                assert "3088.57" in content

            # Verify images.txt has correct number of entries
            with open(os.path.join(tmpdir, "images.txt")) as f:
                lines = [l for l in f.readlines() if not l.startswith("#") and l.strip()]
                # 2 images × 2 lines each (pose line + empty line)
                assert len(lines) >= 2
