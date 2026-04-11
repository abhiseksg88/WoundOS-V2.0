"""Job lifecycle models for async processing."""

from enum import Enum
from datetime import datetime, timezone

from pydantic import BaseModel, Field

from app.models.schemas import ServerResponse, MeasurementDelta


class JobStatus(str, Enum):
    QUEUED = "queued"
    TIER1_PROCESSING = "tier1_processing"
    TIER1_COMPLETE = "tier1_complete"
    TIER2_PROCESSING = "tier2_processing"
    COMPLETE = "complete"
    FAILED = "failed"


class JobSubmitResponse(BaseModel):
    jobId: str
    status: JobStatus = JobStatus.QUEUED
    estimatedDurationSeconds: int = 60


class JobResponse(BaseModel):
    jobId: str
    status: JobStatus
    tier: int | None = None
    progress: float | None = None
    elapsedMs: int | None = None
    result: ServerResponse | None = None
    preliminaryResult: ServerResponse | None = None
    measurementDelta: MeasurementDelta | None = None
    error: str | None = None


class JobDocument(BaseModel):
    """Internal Firestore document representation."""
    job_id: str
    status: JobStatus = JobStatus.QUEUED
    tier: int | None = None
    progress: float | None = None
    created_at: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    updated_at: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    preliminary_result: dict | None = None
    final_result: dict | None = None
    measurement_delta: dict | None = None
    error: str | None = None
    # Upload metadata
    mode: str = "multiview"  # "multiview" (Depth Pro + COLMAP) or "lidar" (ARKit native)
    frames_count: int = 0
    gcs_frames_prefix: str = ""
    gcs_mesh_path: str | None = None  # Set when mode == "lidar"
    gcs_depth_path: str | None = None  # Optional 16-bit depth PNG
    wound_point: str | None = None
    use_woundambit: bool = False
    generate_splat: bool = False
    source_platform: str = ""
    device_model: str = ""
    intrinsics: dict | None = None
    poses: list | None = None
