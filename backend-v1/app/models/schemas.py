"""Pydantic models for the WoundOS API request/response schemas."""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Shared sub-models
# ---------------------------------------------------------------------------

class CameraIntrinsics(BaseModel):
    fx: float
    fy: float
    cx: float
    cy: float


class CaptureMetadata(BaseModel):
    device_model: str
    ios_version: str
    app_version: str
    lidar_available: bool
    capture_distance_m: float
    camera_intrinsics: CameraIntrinsics
    camera_transform: list[list[float]]  # 4x4 matrix
    image_width: int
    image_height: int


class NurseBoundary(BaseModel):
    boundary_2d: list[list[float]]  # [[x, y], ...] pixel coords
    boundary_3d: list[list[float]]  # [[x, y, z], ...] metres
    tap_center_2d: list[float]      # [x, y] pixel coord of nurse tap


class Measurements(BaseModel):
    area_cm2: float
    max_depth_mm: float
    volume_cm3: float
    length_cm: float
    width_cm: float
    perimeter_cm: float
    push_score: int | None = None


class ValidationResult(BaseModel):
    sam2_model: str
    iou: float
    dice: float
    area_delta_percent: float
    centroid_displacement_px: float
    validated_at: datetime


# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------

class CreateScanRequest(BaseModel):
    patient_id: str
    nurse_id: str
    facility_id: str | None = None
    capture_metadata: CaptureMetadata
    nurse_boundary: NurseBoundary
    measurements: Measurements
    wound_type: str | None = None
    wound_location: str | None = None
    clinical_notes: str | None = None


class UploadRequest(BaseModel):
    files: list[str] = Field(
        ...,
        description="Filenames to generate signed upload URLs for",
        examples=[["rgb.jpg", "depth.bin", "mesh.obj", "annotated.jpg", "mask.png"]],
    )


class ClinicalSummaryRequest(BaseModel):
    scan_id: str
    patient_id: str
    wound_type: str | None = None
    wound_location: str | None = None
    measurements: Measurements
    clinical_notes: str | None = None
    previous_measurements: Measurements | None = None


# ---------------------------------------------------------------------------
# Response models
# ---------------------------------------------------------------------------

class CreateScanResponse(BaseModel):
    scan_id: str
    status: str
    created_at: datetime


class UploadResponse(BaseModel):
    scan_id: str
    upload_urls: dict[str, str]
    expiry_minutes: int


class ScanSummary(BaseModel):
    scan_id: str
    status: str
    wound_type: str | None = None
    wound_location: str | None = None
    measurements: Measurements
    created_at: datetime


class ScanDetailResponse(BaseModel):
    scan_id: str
    patient_id: str
    nurse_id: str
    facility_id: str | None = None
    status: str
    capture_metadata: CaptureMetadata
    nurse_boundary: NurseBoundary
    measurements: Measurements
    wound_type: str | None = None
    wound_location: str | None = None
    clinical_notes: str | None = None
    validation: ValidationResult | None = None
    created_at: datetime
    updated_at: datetime


class PatientScansResponse(BaseModel):
    patient_id: str
    scans: list[ScanSummary]
    total: int
    limit: int
    offset: int


class ClinicalSummaryResponse(BaseModel):
    scan_id: str
    summary: str
    generated_by: str  # "claude-haiku" or "template"
    generated_at: datetime


class HealthResponse(BaseModel):
    status: str
    service: str
    version: str
    timestamp: datetime


class ErrorResponse(BaseModel):
    error: str
    detail: str | None = None
