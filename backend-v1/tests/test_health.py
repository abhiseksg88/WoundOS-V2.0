"""Tests for the health check endpoint."""

from fastapi.testclient import TestClient


def test_health_returns_ok(client: TestClient) -> None:
    """GET /api/wound/v1/health returns 200 with correct fields."""
    resp = client.get("/api/wound/v1/health")
    assert resp.status_code == 200

    body = resp.json()
    assert body["status"] == "ok"
    assert body["service"] == "woundos-api-v1"
    assert body["version"] == "1.0.0"
    assert "timestamp" in body


def test_health_no_auth_required(client: TestClient) -> None:
    """Health endpoint should work without any Authorization header."""
    resp = client.get("/api/wound/v1/health")
    assert resp.status_code == 200


def test_health_response_schema(client: TestClient) -> None:
    """Verify all expected keys are present in health response."""
    resp = client.get("/api/wound/v1/health")
    body = resp.json()
    expected_keys = {"status", "service", "version", "timestamp"}
    assert expected_keys == set(body.keys())
