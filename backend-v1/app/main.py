"""WoundOS API Gateway — FastAPI application entry point."""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.routes import clinical_summary, health, scans

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Lifespan
# ---------------------------------------------------------------------------


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Application startup / shutdown lifecycle."""
    logger.info("WoundOS API Gateway starting up")
    yield
    logger.info("WoundOS API Gateway shutting down")


# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

API_PREFIX = "/api/wound/v1"

app = FastAPI(
    title="WoundOS Pro API",
    description="Backend API for WoundOS Pro wound measurement platform",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS — permissive for v1 pilot, restrict in production
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
    max_age=600,
)

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

app.include_router(health.router, prefix=API_PREFIX)
app.include_router(scans.router, prefix=API_PREFIX)
app.include_router(clinical_summary.router, prefix=API_PREFIX)

# ---------------------------------------------------------------------------
# Global exception handler
# ---------------------------------------------------------------------------


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Catch unhandled exceptions and return a structured error response."""
    logger.exception("Unhandled exception on %s %s", request.method, request.url.path)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"error": "internal_error", "detail": "An unexpected error occurred"},
    )
