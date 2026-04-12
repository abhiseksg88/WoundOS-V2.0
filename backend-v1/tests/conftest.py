"""Shared test fixtures for WoundOS backend tests."""

from __future__ import annotations

import os
import sys
from typing import Generator
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

# ---------------------------------------------------------------------------
# Mock GCP modules before any app code imports them.
# This allows the test suite to run without google-cloud-* packages installed.
# ---------------------------------------------------------------------------

_gcp_mock_modules = {
    "google": MagicMock(),
    "google.cloud": MagicMock(),
    "google.cloud.firestore": MagicMock(),
    "google.cloud.storage": MagicMock(),
    "google.cloud.pubsub_v1": MagicMock(),
    "google.cloud.pubsub": MagicMock(),
    "anthropic": MagicMock(),
}

for mod_name, mock_mod in _gcp_mock_modules.items():
    if mod_name not in sys.modules:
        sys.modules[mod_name] = mock_mod


@pytest.fixture(autouse=True)
def _set_env_vars() -> Generator[None, None, None]:
    """Set required environment variables for tests."""
    env = {
        "WOUNDOS_API_TOKEN": "test-token-12345",
        "WOUNDOS_GCP_PROJECT": "test-project",
        "WOUNDOS_GCS_BUCKET": "test-bucket",
        "WOUNDOS_FIRESTORE_COLLECTION": "test_scans",
        "WOUNDOS_PUBSUB_TOPIC": "test-topic",
    }
    with patch.dict(os.environ, env):
        yield


@pytest.fixture()
def auth_header() -> dict[str, str]:
    """Return a valid Authorization header for tests."""
    return {"Authorization": "Bearer test-token-12345"}


@pytest.fixture()
def client() -> TestClient:
    """FastAPI test client with GCP modules already mocked at sys.modules level."""
    from app.main import app

    return TestClient(app)


def make_scan_request_body() -> dict:
    """Return a valid CreateScanRequest body for tests."""
    return {
        "patient_id": "patient-001",
        "nurse_id": "nurse-001",
        "facility_id": "facility-001",
        "capture_metadata": {
            "device_model": "iPhone 14 Pro",
            "ios_version": "17.4",
            "app_version": "1.0.0",
            "lidar_available": True,
            "capture_distance_m": 0.25,
            "camera_intrinsics": {"fx": 1597.0, "fy": 1597.0, "cx": 960.0, "cy": 540.0},
            "camera_transform": [
                [1.0, 0.0, 0.0, 0.0],
                [0.0, 1.0, 0.0, 0.0],
                [0.0, 0.0, 1.0, -0.25],
                [0.0, 0.0, 0.0, 1.0],
            ],
            "image_width": 1920,
            "image_height": 1440,
        },
        "nurse_boundary": {
            "boundary_2d": [[100, 200], [110, 210], [120, 205], [115, 195]],
            "boundary_3d": [
                [0.01, 0.02, -0.25],
                [0.011, 0.021, -0.251],
                [0.012, 0.0205, -0.252],
                [0.0115, 0.0195, -0.249],
            ],
            "tap_center_2d": [110, 205],
        },
        "measurements": {
            "area_cm2": 4.52,
            "max_depth_mm": 3.1,
            "volume_cm3": 0.87,
            "length_cm": 3.2,
            "width_cm": 1.8,
            "perimeter_cm": 8.9,
            "push_score": 9,
        },
        "wound_type": "pressure_ulcer",
        "wound_location": "sacrum",
        "clinical_notes": "Stage 3, granulation tissue present",
    }
