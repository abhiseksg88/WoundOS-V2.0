"""Scan CRUD endpoints: create, get, list, and upload URL generation."""

from __future__ import annotations

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.auth import verify_token
from app.config import Settings, get_settings
from app.models.schemas import (
    CreateScanRequest,
    CreateScanResponse,
    ErrorResponse,
    PatientScansResponse,
    ScanDetailResponse,
    ScanSummary,
    UploadRequest,
    UploadResponse,
    ValidationResult,
)
from app.services.firestore_service import FirestoreService
from app.services.gcs_service import GCSService
from app.services.pubsub_service import PubSubService

logger = logging.getLogger(__name__)
router = APIRouter()


# ---------------------------------------------------------------------------
# Dependency helpers (one instance per request; services are lightweight)
# ---------------------------------------------------------------------------


def _firestore(settings: Settings = Depends(get_settings)) -> FirestoreService:
    return FirestoreService(settings)


def _gcs(settings: Settings = Depends(get_settings)) -> GCSService:
    return GCSService(settings)


def _pubsub(settings: Settings = Depends(get_settings)) -> PubSubService:
    return PubSubService(settings)


# ---------------------------------------------------------------------------
# POST /scans — create a scan record
# ---------------------------------------------------------------------------


@router.post(
    "/scans",
    response_model=CreateScanResponse,
    status_code=status.HTTP_201_CREATED,
    responses={401: {"model": ErrorResponse}},
    tags=["scans"],
    summary="Create a new scan record",
)
async def create_scan(
    body: CreateScanRequest,
    _token: str = Depends(verify_token),
    fs: FirestoreService = Depends(_firestore),
) -> CreateScanResponse:
    """Persist scan metadata + measurements to Firestore."""
    doc = fs.create_scan(body.model_dump())
    return CreateScanResponse(
        scan_id=doc["scan_id"],
        status=doc["status"],
        created_at=doc["created_at"],
    )


# ---------------------------------------------------------------------------
# POST /scans/{scan_id}/upload — request signed upload URLs
# ---------------------------------------------------------------------------


@router.post(
    "/scans/{scan_id}/upload",
    response_model=UploadResponse,
    responses={401: {"model": ErrorResponse}, 404: {"model": ErrorResponse}},
    tags=["scans"],
    summary="Get signed upload URLs for scan binary files",
)
async def request_upload_urls(
    scan_id: str,
    body: UploadRequest,
    _token: str = Depends(verify_token),
    settings: Settings = Depends(get_settings),
    fs: FirestoreService = Depends(_firestore),
    gcs: GCSService = Depends(_gcs),
    ps: PubSubService = Depends(_pubsub),
) -> UploadResponse:
    """Generate GCS signed PUT URLs and trigger shadow validation via Pub/Sub."""
    # Verify scan exists
    scan = fs.get_scan(scan_id)
    if scan is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "scan_not_found", "detail": f"Scan {scan_id} not found"},
        )

    # Validate file names
    try:
        urls = gcs.generate_upload_urls(scan_id, body.files)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"error": "validation_error", "detail": str(exc)},
        )

    # Update scan status and store file list
    fs.update_scan(scan_id, {"status": "uploading", "files": body.files})

    # Publish validation message so the worker picks up the scan once
    # binaries land in GCS.
    try:
        ps.publish_scan_validation(scan_id)
    except Exception:
        logger.exception("Failed to publish Pub/Sub message for scan %s", scan_id)
        # Non-fatal: the scan is still usable, validation will be retried.

    return UploadResponse(
        scan_id=scan_id,
        upload_urls=urls,
        expiry_minutes=settings.signed_url_expiry_minutes,
    )


# ---------------------------------------------------------------------------
# GET /scans/{scan_id} — get scan details
# ---------------------------------------------------------------------------


@router.get(
    "/scans/{scan_id}",
    response_model=ScanDetailResponse,
    responses={401: {"model": ErrorResponse}, 404: {"model": ErrorResponse}},
    tags=["scans"],
    summary="Get scan details, measurements, and validation",
)
async def get_scan(
    scan_id: str,
    _token: str = Depends(verify_token),
    fs: FirestoreService = Depends(_firestore),
) -> ScanDetailResponse:
    """Retrieve full scan document from Firestore."""
    scan = fs.get_scan(scan_id)
    if scan is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "scan_not_found", "detail": f"Scan {scan_id} not found"},
        )

    validation = None
    if scan.get("validation"):
        validation = ValidationResult(**scan["validation"])

    return ScanDetailResponse(
        scan_id=scan["scan_id"],
        patient_id=scan["patient_id"],
        nurse_id=scan["nurse_id"],
        facility_id=scan.get("facility_id"),
        status=scan["status"],
        capture_metadata=scan["capture_metadata"],
        nurse_boundary=scan["nurse_boundary"],
        measurements=scan["measurements"],
        wound_type=scan.get("wound_type"),
        wound_location=scan.get("wound_location"),
        clinical_notes=scan.get("clinical_notes"),
        validation=validation,
        created_at=scan["created_at"],
        updated_at=scan["updated_at"],
    )


# ---------------------------------------------------------------------------
# GET /patients/{patient_id}/scans — list patient scans
# ---------------------------------------------------------------------------


@router.get(
    "/patients/{patient_id}/scans",
    response_model=PatientScansResponse,
    responses={401: {"model": ErrorResponse}},
    tags=["scans"],
    summary="List a patient's scan history",
)
async def list_patient_scans(
    patient_id: str,
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    _token: str = Depends(verify_token),
    fs: FirestoreService = Depends(_firestore),
) -> PatientScansResponse:
    """Return paginated scan history for a patient, newest first."""
    scans, total = fs.list_patient_scans(patient_id, limit=limit, offset=offset)

    summaries = [
        ScanSummary(
            scan_id=s["scan_id"],
            status=s["status"],
            wound_type=s.get("wound_type"),
            wound_location=s.get("wound_location"),
            measurements=s["measurements"],
            created_at=s["created_at"],
        )
        for s in scans
    ]

    return PatientScansResponse(
        patient_id=patient_id,
        scans=summaries,
        total=total,
        limit=limit,
        offset=offset,
    )
