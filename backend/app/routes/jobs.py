"""GET /api/v2/jobs/{jobId} — Poll job status and results."""

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException

from app.models.job import JobResponse, JobStatus
from app.models.schemas import ServerResponse, MeasurementDelta
from app.services import firestore

logger = logging.getLogger("woundos.routes.jobs")

router = APIRouter(prefix="/api/v2")


@router.get("/jobs/{job_id}", response_model=JobResponse)
async def get_job_status(job_id: str):
    """Poll for job processing status and results.

    Returns preliminary Tier 1 results as soon as available,
    then final Tier 2 gold-standard results when complete.
    """
    doc = firestore.get_job(job_id)
    if doc is None:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found")

    # Compute elapsed time
    created = datetime.fromisoformat(doc.created_at)
    elapsed_ms = int((datetime.now(timezone.utc) - created).total_seconds() * 1000)

    # Build response based on status
    response = JobResponse(
        jobId=doc.job_id,
        status=doc.status,
        tier=doc.tier,
        progress=doc.progress,
        elapsedMs=elapsed_ms,
    )

    if doc.status == JobStatus.FAILED:
        response.error = doc.error

    # Include preliminary result if available
    if doc.preliminary_result:
        response.preliminaryResult = ServerResponse(**doc.preliminary_result)

    # Include final result if complete
    if doc.status == JobStatus.COMPLETE and doc.final_result:
        response.result = ServerResponse(**doc.final_result)
        if doc.measurement_delta:
            response.measurementDelta = MeasurementDelta(**doc.measurement_delta)
    elif doc.status == JobStatus.TIER1_COMPLETE and doc.preliminary_result:
        # Tier 1 done: return preliminary as the main result too
        response.result = ServerResponse(**doc.preliminary_result)

    return response
