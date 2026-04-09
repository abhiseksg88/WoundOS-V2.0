"""Tests for health check endpoint."""

import pytest
from fastapi.testclient import TestClient

from app.main import create_app


@pytest.fixture
def client():
    app = create_app()
    return TestClient(app)


class TestHealthEndpoint:
    def test_health_returns_200(self, client):
        response = client.get("/health")
        assert response.status_code == 200

    def test_health_returns_status(self, client):
        response = client.get("/health")
        data = response.json()
        assert data["status"] == "healthy"

    def test_health_returns_version(self, client):
        response = client.get("/health")
        data = response.json()
        assert "version" in data
        assert data["version"] == "2.0.0"
