"""Test fixtures for WoundOS V2 backend."""

import os
import sys

import pytest

# Ensure the backend root is on the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

# Override settings for testing
os.environ["WOUNDOS_WORKER_MODE"] = "api"
os.environ["WOUNDOS_ANTHROPIC_API_KEY"] = ""


@pytest.fixture
def sample_intrinsics():
    """Default iPhone camera intrinsics."""
    return {
        "fx": 3088.57,
        "fy": 3088.57,
        "cx": 2016.0,
        "cy": 1512.0,
        "width": 4032,
        "height": 3024,
    }


@pytest.fixture
def identity_pose():
    """Identity 4x4 camera pose."""
    return {
        "timestamp": 0.0,
        "transform": [
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
            [0, 0, 0, 1],
        ],
        "trackingState": "normal",
    }


@pytest.fixture
def sample_pose_looking_down():
    """Camera looking down at wound from 25cm height."""
    return {
        "timestamp": 1.0,
        "transform": [
            [1, 0, 0, 0],
            [0, 1, 0, 0.25],
            [0, 0, 1, 0],
            [0, 0, 0, 1],
        ],
        "trackingState": "normal",
    }
