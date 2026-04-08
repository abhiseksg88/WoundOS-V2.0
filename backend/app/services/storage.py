"""Google Cloud Storage service for frame uploads and result storage."""

import logging
from datetime import timedelta

from google.cloud import storage as gcs

from app.config import settings

logger = logging.getLogger("woundos.storage")

_client: gcs.Client | None = None


def _get_client() -> gcs.Client:
    global _client
    if _client is None:
        _client = gcs.Client(project=settings.gcp_project_id)
    return _client


def upload_frame(job_id: str, frame_index: int, data: bytes) -> str:
    """Upload a single JPEG frame to GCS. Returns the GCS URI."""
    client = _get_client()
    bucket = client.bucket(settings.gcs_bucket)
    blob_name = f"{job_id}/frames/frame_{frame_index:04d}.jpg"
    blob = bucket.blob(blob_name)
    blob.upload_from_string(data, content_type="image/jpeg")
    logger.info("Uploaded frame %d for job %s", frame_index, job_id)
    return f"gs://{settings.gcs_bucket}/{blob_name}"


def upload_frames(job_id: str, frames: list[bytes]) -> str:
    """Upload all frames for a job. Returns the GCS prefix."""
    for i, frame_data in enumerate(frames):
        upload_frame(job_id, i, frame_data)
    prefix = f"{job_id}/frames/"
    logger.info("Uploaded %d frames for job %s", len(frames), job_id)
    return prefix


def download_frames(job_id: str) -> list[bytes]:
    """Download all frames for a job from GCS."""
    client = _get_client()
    bucket = client.bucket(settings.gcs_bucket)
    prefix = f"{job_id}/frames/"
    blobs = sorted(bucket.list_blobs(prefix=prefix), key=lambda b: b.name)
    frames = []
    for blob in blobs:
        if blob.name.endswith(".jpg"):
            frames.append(blob.download_as_bytes())
    logger.info("Downloaded %d frames for job %s", len(frames), job_id)
    return frames


def upload_result_file(job_id: str, filename: str, data: bytes, content_type: str = "application/octet-stream") -> str:
    """Upload a result file (mesh, annotated image, etc.) to GCS."""
    client = _get_client()
    bucket = client.bucket(settings.gcs_bucket)
    blob_name = f"{job_id}/results/{filename}"
    blob = bucket.blob(blob_name)
    blob.upload_from_string(data, content_type=content_type)
    return f"gs://{settings.gcs_bucket}/{blob_name}"


def upload_splat(job_id: str, data: bytes) -> str:
    """Upload a .splat file and return a signed URL."""
    client = _get_client()
    bucket = client.bucket(settings.gcs_splat_bucket)
    blob_name = f"{job_id}/wound.splat"
    blob = bucket.blob(blob_name)
    blob.upload_from_string(data, content_type="application/octet-stream")

    signed_url = blob.generate_signed_url(
        version="v4",
        expiration=timedelta(days=settings.gcs_signed_url_expiry_days),
        method="GET",
    )
    logger.info("Uploaded splat for job %s, signed URL generated", job_id)
    return signed_url


def download_file(bucket_name: str, blob_name: str) -> bytes:
    """Download a file from GCS."""
    client = _get_client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(blob_name)
    return blob.download_as_bytes()
