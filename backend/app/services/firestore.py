"""Firestore service for job state management."""

import logging
from datetime import datetime, timezone

from google.cloud import firestore

from app.config import settings
from app.models.job import JobDocument, JobStatus

logger = logging.getLogger("woundos.firestore")

_client: firestore.Client | None = None


def _get_client() -> firestore.Client:
    global _client
    if _client is None:
        _client = firestore.Client(project=settings.gcp_project_id)
    return _client


def _collection():
    return _get_client().collection(settings.firestore_collection)


def create_job(doc: JobDocument) -> None:
    """Create a new job document in Firestore."""
    _collection().document(doc.job_id).set(doc.model_dump())
    logger.info("Created job %s", doc.job_id)


def get_job(job_id: str) -> JobDocument | None:
    """Read a job document. Returns None if not found."""
    doc_ref = _collection().document(job_id)
    doc = doc_ref.get()
    if not doc.exists:
        return None
    return JobDocument(**doc.to_dict())


def update_job_status(
    job_id: str,
    status: JobStatus,
    tier: int | None = None,
    progress: float | None = None,
    error: str | None = None,
) -> None:
    """Update job status and progress."""
    updates: dict = {
        "status": status.value,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    if tier is not None:
        updates["tier"] = tier
    if progress is not None:
        updates["progress"] = progress
    if error is not None:
        updates["error"] = error
    _collection().document(job_id).update(updates)
    logger.info("Updated job %s: status=%s tier=%s", job_id, status.value, tier)


def update_job_preliminary_result(job_id: str, result: dict) -> None:
    """Store Tier 1 preliminary results."""
    _collection().document(job_id).update({
        "status": JobStatus.TIER1_COMPLETE.value,
        "tier": 1,
        "progress": 0.5,
        "preliminary_result": result,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    })
    logger.info("Stored preliminary result for job %s", job_id)


def update_job_final_result(job_id: str, result: dict, measurement_delta: dict | None = None) -> None:
    """Store Tier 2 final results."""
    updates = {
        "status": JobStatus.COMPLETE.value,
        "tier": 2,
        "progress": 1.0,
        "final_result": result,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    if measurement_delta:
        updates["measurement_delta"] = measurement_delta
    _collection().document(job_id).update(updates)
    logger.info("Stored final result for job %s", job_id)


def update_job_splat_url(job_id: str, splat_url: str) -> None:
    """Update the splat URL in the final result."""
    doc = get_job(job_id)
    if doc and doc.final_result:
        doc.final_result["splatURL"] = splat_url
        _collection().document(job_id).update({
            "final_result": doc.final_result,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        })
    logger.info("Updated splat URL for job %s", job_id)
