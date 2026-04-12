"""Health check endpoint."""

from datetime import datetime, timezone

from fastapi import APIRouter

from app.models.schemas import HealthResponse

router = APIRouter()

SERVICE_VERSION = "1.0.0"


@router.get(
    "/health",
    response_model=HealthResponse,
    tags=["health"],
    summary="Health check",
)
async def health_check() -> HealthResponse:
    """Return service health status. No authentication required."""
    return HealthResponse(
        status="ok",
        service="woundos-api-v1",
        version=SERVICE_VERSION,
        timestamp=datetime.now(timezone.utc),
    )
