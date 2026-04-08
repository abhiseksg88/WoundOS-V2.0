"""WoundOS V2 Backend — FastAPI application."""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.routes import health, reconstruct, jobs, segment, woundambit

logger = logging.getLogger("woundos")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup/shutdown lifecycle."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )
    logger.info(
        "WoundOS V2 backend starting (mode=%s, version=%s)",
        settings.worker_mode,
        settings.api_version,
    )

    # Models are loaded lazily on first request (not at startup)
    # This ensures the HTTP server starts quickly and passes Cloud Run health checks
    if settings.worker_mode in ("gpu", "all"):
        logger.info("GPU worker mode — ML models will load on first request")

    yield

    logger.info("WoundOS V2 backend shutting down.")


def create_app() -> FastAPI:
    app = FastAPI(
        title="WoundOS V2 API",
        version=settings.api_version,
        lifespan=lifespan,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(health.router)
    app.include_router(reconstruct.router)
    app.include_router(jobs.router)
    app.include_router(segment.router)
    app.include_router(woundambit.router)

    return app


app = create_app()
