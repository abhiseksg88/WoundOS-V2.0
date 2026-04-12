# WoundOS Pro v1 — Backend Specification

**Status**: Implementation-ready
**Target release**: v1.0 (pilot-ready)
**Companion to**: `architecture.md`
**Primary author**: Engineering
**Last updated**: 2026-04

---

## 1. Overview

The WoundOS Pro v1 backend consists of two Cloud Run services running on Google Cloud Platform (project: `careplix-woundos`, region: `us-central1`):

| Service | Role | Compute | Estimated Cost |
|---------|------|---------|----------------|
| **API Gateway** (`woundos-api-v1`) | Scan CRUD, signed URLs, clinical summary | CPU-only, min-instances=1 | ~$15/mo |
| **Shadow Validation Worker** (`woundos-validator-v1`) | SAM 2 inference + agreement metrics | CPU-only, scale-to-zero | ~$10/mo |

Both services are containerized with Docker and deployed to Cloud Run. Neither requires a GPU.

---

## 2. API Gateway

### 2.1 Technology Stack

- **Runtime**: Python 3.11
- **Framework**: FastAPI 0.115+
- **Server**: Uvicorn
- **Validation**: Pydantic 2.x with pydantic-settings
- **Storage**: Google Cloud Storage (`woundos-scans` bucket)
- **Database**: Firestore Native mode (`wound_scans` collection)
- **Messaging**: Google Cloud Pub/Sub (`scan-validations` topic)
- **LLM**: Anthropic Claude Haiku via `anthropic` SDK
- **Auth**: Single bearer token per deployment (env var `WOUNDOS_API_TOKEN`)

### 2.2 Environment Variables

All environment variables are prefixed with `WOUNDOS_`:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `WOUNDOS_API_TOKEN` | Yes | — | Bearer token for API auth |
| `WOUNDOS_GCP_PROJECT` | No | `careplix-woundos` | GCP project ID |
| `WOUNDOS_GCS_BUCKET` | No | `woundos-scans` | GCS bucket for binary files |
| `WOUNDOS_FIRESTORE_COLLECTION` | No | `wound_scans` | Firestore collection name |
| `WOUNDOS_PUBSUB_TOPIC` | No | `scan-validations` | Pub/Sub topic name |
| `WOUNDOS_ANTHROPIC_API_KEY` | No | — | Anthropic API key for clinical summary |
| `WOUNDOS_SIGNED_URL_EXPIRY_MINUTES` | No | `60` | Signed URL expiry in minutes |

### 2.3 API Endpoints

Base namespace: `/api/wound/v1/`

---

#### `GET /api/wound/v1/health`

Health check endpoint. No authentication required.

**Response** `200 OK`:
```json
{
  "status": "ok",
  "service": "woundos-api-v1",
  "version": "1.0.0",
  "timestamp": "2026-04-12T10:30:00Z"
}
```

---

#### `POST /api/wound/v1/scans`

Create a new scan record in Firestore.

**Headers**: `Authorization: Bearer <token>`

**Request Body** (`CreateScanRequest`):
```json
{
  "patient_id": "patient-uuid",
  "nurse_id": "nurse-uuid",
  "facility_id": "facility-001",
  "capture_metadata": {
    "device_model": "iPhone 14 Pro",
    "ios_version": "17.4",
    "app_version": "1.0.0",
    "lidar_available": true,
    "capture_distance_m": 0.25,
    "camera_intrinsics": {
      "fx": 1597.0,
      "fy": 1597.0,
      "cx": 960.0,
      "cy": 540.0
    },
    "camera_transform": [
      [1.0, 0.0, 0.0, 0.0],
      [0.0, 1.0, 0.0, 0.0],
      [0.0, 0.0, 1.0, -0.25],
      [0.0, 0.0, 0.0, 1.0]
    ],
    "image_width": 1920,
    "image_height": 1440
  },
  "nurse_boundary": {
    "boundary_2d": [[100, 200], [110, 210], [120, 205]],
    "boundary_3d": [[0.01, 0.02, -0.25], [0.011, 0.021, -0.251], [0.012, 0.0205, -0.252]],
    "tap_center_2d": [110, 205]
  },
  "measurements": {
    "area_cm2": 4.52,
    "max_depth_mm": 3.1,
    "volume_cm3": 0.87,
    "length_cm": 3.2,
    "width_cm": 1.8,
    "perimeter_cm": 8.9,
    "push_score": 9
  },
  "wound_type": "pressure_ulcer",
  "wound_location": "sacrum",
  "clinical_notes": "Stage 3, granulation tissue present"
}
```

**Response** `201 Created` (`CreateScanResponse`):
```json
{
  "scan_id": "scan-uuid",
  "status": "created",
  "created_at": "2026-04-12T10:30:00Z"
}
```

**Errors**:
- `401 Unauthorized` — missing or invalid bearer token
- `422 Unprocessable Entity` — validation error in request body

---

#### `POST /api/wound/v1/scans/{scan_id}/upload`

Request signed upload URLs for binary files associated with a scan.

**Headers**: `Authorization: Bearer <token>`

**Path Parameters**: `scan_id` (string, UUID)

**Request Body** (`UploadRequest`):
```json
{
  "files": ["rgb.jpg", "depth.bin", "mesh.obj", "annotated.jpg", "mask.png"]
}
```

**Response** `200 OK` (`UploadResponse`):
```json
{
  "scan_id": "scan-uuid",
  "upload_urls": {
    "rgb.jpg": "https://storage.googleapis.com/woundos-scans/scan-uuid/rgb.jpg?X-Goog-Signature=...",
    "depth.bin": "https://storage.googleapis.com/woundos-scans/scan-uuid/depth.bin?X-Goog-Signature=...",
    "mesh.obj": "https://storage.googleapis.com/woundos-scans/scan-uuid/mesh.obj?X-Goog-Signature=...",
    "annotated.jpg": "https://storage.googleapis.com/woundos-scans/scan-uuid/annotated.jpg?X-Goog-Signature=...",
    "mask.png": "https://storage.googleapis.com/woundos-scans/scan-uuid/mask.png?X-Goog-Signature=..."
  },
  "expiry_minutes": 60
}
```

**Side effect**: After generating URLs, the endpoint publishes a `{"scan_id": "scan-uuid"}` message to the `scan-validations` Pub/Sub topic to trigger the shadow validation worker once upload completes.

The scan document status is updated to `"uploading"` in Firestore.

**Errors**:
- `401 Unauthorized`
- `404 Not Found` — scan_id does not exist in Firestore
- `422 Unprocessable Entity` — invalid file names

---

#### `GET /api/wound/v1/scans/{scan_id}`

Retrieve full scan details including measurements and validation results (if available).

**Headers**: `Authorization: Bearer <token>`

**Path Parameters**: `scan_id` (string, UUID)

**Response** `200 OK` (`ScanDetailResponse`):
```json
{
  "scan_id": "scan-uuid",
  "patient_id": "patient-uuid",
  "nurse_id": "nurse-uuid",
  "facility_id": "facility-001",
  "status": "validated",
  "capture_metadata": { "..." : "..." },
  "nurse_boundary": {
    "boundary_2d": [[100, 200], [110, 210], [120, 205]],
    "boundary_3d": [[0.01, 0.02, -0.25], [0.011, 0.021, -0.251], [0.012, 0.0205, -0.252]],
    "tap_center_2d": [110, 205]
  },
  "measurements": {
    "area_cm2": 4.52,
    "max_depth_mm": 3.1,
    "volume_cm3": 0.87,
    "length_cm": 3.2,
    "width_cm": 1.8,
    "perimeter_cm": 8.9,
    "push_score": 9
  },
  "wound_type": "pressure_ulcer",
  "wound_location": "sacrum",
  "clinical_notes": "Stage 3, granulation tissue present",
  "validation": {
    "sam2_model": "facebook/sam2.1-hiera-tiny",
    "iou": 0.87,
    "dice": 0.93,
    "area_delta_percent": -2.1,
    "centroid_displacement_px": 3.4,
    "validated_at": "2026-04-12T10:31:15Z"
  },
  "created_at": "2026-04-12T10:30:00Z",
  "updated_at": "2026-04-12T10:31:15Z"
}
```

**Errors**:
- `401 Unauthorized`
- `404 Not Found`

---

#### `GET /api/wound/v1/patients/{patient_id}/scans`

List all scans for a given patient, ordered by creation time descending.

**Headers**: `Authorization: Bearer <token>`

**Path Parameters**: `patient_id` (string, UUID)

**Query Parameters**:
- `limit` (int, optional, default=50, max=200) — number of scans to return
- `offset` (int, optional, default=0) — pagination offset

**Response** `200 OK` (`PatientScansResponse`):
```json
{
  "patient_id": "patient-uuid",
  "scans": [
    {
      "scan_id": "scan-uuid-2",
      "status": "validated",
      "wound_type": "pressure_ulcer",
      "wound_location": "sacrum",
      "measurements": {
        "area_cm2": 4.2,
        "max_depth_mm": 2.8,
        "volume_cm3": 0.75,
        "length_cm": 3.0,
        "width_cm": 1.7,
        "perimeter_cm": 8.5,
        "push_score": 8
      },
      "created_at": "2026-04-13T09:00:00Z"
    },
    {
      "scan_id": "scan-uuid-1",
      "status": "validated",
      "wound_type": "pressure_ulcer",
      "wound_location": "sacrum",
      "measurements": {
        "area_cm2": 4.52,
        "max_depth_mm": 3.1,
        "volume_cm3": 0.87,
        "length_cm": 3.2,
        "width_cm": 1.8,
        "perimeter_cm": 8.9,
        "push_score": 9
      },
      "created_at": "2026-04-12T10:30:00Z"
    }
  ],
  "total": 2,
  "limit": 50,
  "offset": 0
}
```

**Errors**:
- `401 Unauthorized`

---

#### `POST /api/wound/v1/clinical-summary`

Generate a clinical narrative note from scan measurements using Claude Haiku. If no Anthropic API key is configured, returns a template-based summary.

**Headers**: `Authorization: Bearer <token>`

**Request Body** (`ClinicalSummaryRequest`):
```json
{
  "scan_id": "scan-uuid",
  "patient_id": "patient-uuid",
  "wound_type": "pressure_ulcer",
  "wound_location": "sacrum",
  "measurements": {
    "area_cm2": 4.52,
    "max_depth_mm": 3.1,
    "volume_cm3": 0.87,
    "length_cm": 3.2,
    "width_cm": 1.8,
    "perimeter_cm": 8.9,
    "push_score": 9
  },
  "clinical_notes": "Stage 3, granulation tissue present",
  "previous_measurements": {
    "area_cm2": 5.1,
    "max_depth_mm": 3.5,
    "volume_cm3": 1.02
  }
}
```

**Response** `200 OK` (`ClinicalSummaryResponse`):
```json
{
  "scan_id": "scan-uuid",
  "summary": "Wound assessment: Pressure ulcer on sacrum. Current measurements: area 4.52 cm2, maximum depth 3.1 mm, volume 0.87 cm3, length 3.2 cm x width 1.8 cm, perimeter 8.9 cm. PUSH score: 9. Compared to previous assessment, area decreased by 11.4% (from 5.10 to 4.52 cm2), depth decreased by 11.4% (from 3.50 to 3.10 mm), and volume decreased by 14.7% (from 1.02 to 0.87 cm3), indicating improvement. Clinical notes: Stage 3, granulation tissue present.",
  "generated_by": "claude-haiku",
  "generated_at": "2026-04-12T10:30:05Z"
}
```

When no API key is configured, `generated_by` is `"template"` and the summary is built from a static template.

**Errors**:
- `401 Unauthorized`
- `422 Unprocessable Entity`

---

## 3. Pydantic Model Definitions

### 3.1 Configuration

```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    api_token: str
    gcp_project: str = "careplix-woundos"
    gcs_bucket: str = "woundos-scans"
    firestore_collection: str = "wound_scans"
    pubsub_topic: str = "scan-validations"
    anthropic_api_key: str | None = None
    signed_url_expiry_minutes: int = 60

    model_config = {"env_prefix": "WOUNDOS_"}
```

### 3.2 Request/Response Models

```python
from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional

# --- Shared sub-models ---

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
    boundary_2d: list[list[float]]      # [[x, y], ...] pixel coords
    boundary_3d: list[list[float]]      # [[x, y, z], ...] meters
    tap_center_2d: list[float]          # [x, y] pixel coord

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

# --- Request models ---

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
        description="List of filenames to generate signed URLs for",
        examples=[["rgb.jpg", "depth.bin", "mesh.obj", "annotated.jpg", "mask.png"]]
    )

class ClinicalSummaryRequest(BaseModel):
    scan_id: str
    patient_id: str
    wound_type: str | None = None
    wound_location: str | None = None
    measurements: Measurements
    clinical_notes: str | None = None
    previous_measurements: Measurements | None = None

# --- Response models ---

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
    generated_by: str           # "claude-haiku" or "template"
    generated_at: datetime

class HealthResponse(BaseModel):
    status: str
    service: str
    version: str
    timestamp: datetime

class ErrorResponse(BaseModel):
    error: str
    detail: str | None = None
```

---

## 4. Firestore Document Schema

Collection: `wound_scans`
Document ID: `{scan_id}` (UUID v4, generated by backend)

```json
{
  "scan_id": "uuid-v4",
  "patient_id": "string",
  "nurse_id": "string",
  "facility_id": "string | null",
  "status": "created | uploading | uploaded | validating | validated | validation_failed",

  "capture_metadata": {
    "device_model": "string",
    "ios_version": "string",
    "app_version": "string",
    "lidar_available": true,
    "capture_distance_m": 0.25,
    "camera_intrinsics": { "fx": 0.0, "fy": 0.0, "cx": 0.0, "cy": 0.0 },
    "camera_transform": [[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]],
    "image_width": 1920,
    "image_height": 1440
  },

  "nurse_boundary": {
    "boundary_2d": [[100, 200], [110, 210]],
    "boundary_3d": [[0.01, 0.02, -0.25], [0.011, 0.021, -0.251]],
    "tap_center_2d": [110, 205]
  },

  "measurements": {
    "area_cm2": 4.52,
    "max_depth_mm": 3.1,
    "volume_cm3": 0.87,
    "length_cm": 3.2,
    "width_cm": 1.8,
    "perimeter_cm": 8.9,
    "push_score": 9
  },

  "wound_type": "string | null",
  "wound_location": "string | null",
  "clinical_notes": "string | null",

  "files": ["rgb.jpg", "depth.bin", "mesh.obj", "annotated.jpg", "mask.png"],

  "validation": {
    "sam2_model": "facebook/sam2.1-hiera-tiny",
    "iou": 0.87,
    "dice": 0.93,
    "area_delta_percent": -2.1,
    "centroid_displacement_px": 3.4,
    "validated_at": "2026-04-12T10:31:15Z"
  },

  "created_at": "2026-04-12T10:30:00Z",
  "updated_at": "2026-04-12T10:31:15Z"
}
```

### 4.1 Document Lifecycle

```
created → uploading → uploaded → validating → validated
                                            → validation_failed
```

- `created`: Scan record created via `POST /scans`
- `uploading`: Upload URLs requested via `POST /scans/{id}/upload`
- `uploaded`: (Set by worker when it begins processing)
- `validating`: Worker has started SAM 2 inference
- `validated`: Worker completed successfully, metrics stored
- `validation_failed`: Worker encountered an error (error details stored)

---

## 5. Shadow Validation Worker

### 5.1 Architecture

The worker is a separate Cloud Run service that receives Pub/Sub push messages at `POST /pubsub/push`. It is not publicly accessible except through the Pub/Sub push subscription.

### 5.2 Push Endpoint

```
POST /pubsub/push
```

Receives Pub/Sub push messages containing `{"scan_id": "uuid"}`.

### 5.3 Processing Pipeline

For each scan:

1. **Decode message**: Extract `scan_id` from Pub/Sub envelope
2. **Read Firestore**: Fetch scan document, get `nurse_boundary.tap_center_2d` and `nurse_boundary.boundary_2d`
3. **Download RGB**: Fetch `{scan_id}/rgb.jpg` from GCS
4. **SAM 2 inference**:
   - Load model: `SAM2ImagePredictor.from_pretrained("facebook/sam2.1-hiera-tiny", device="cpu")`
   - Set image
   - Use `tap_center_2d` as point prompt (label=1, foreground)
   - Predict mask
5. **Compute agreement metrics**:
   - Convert nurse `boundary_2d` to binary mask
   - Compare with SAM 2 mask
   - Compute: IoU, Dice, area_delta_percent, centroid_displacement_px
6. **Store results**: Update Firestore document with `validation` field
7. **Acknowledge**: Return 200 to Pub/Sub

### 5.4 SAM 2 Installation

SAM 2 is installed via pip from GitHub (not editable install):

```
pip install git+https://github.com/facebookresearch/sam2.git
```

This installs SAM 2 as a proper Python package, avoiding the Hydra config path issues that plagued the old editable install approach. The `from_pretrained` method downloads the model weights automatically and bypasses Hydra configuration entirely.

### 5.5 Agreement Metrics

| Metric | Formula | Description |
|--------|---------|-------------|
| **IoU** | intersection / union | Intersection over Union of nurse mask vs SAM 2 mask |
| **Dice** | 2 * intersection / (area_nurse + area_sam2) | Dice similarity coefficient |
| **area_delta_percent** | (area_sam2 - area_nurse) / area_nurse * 100 | Percentage difference in mask area |
| **centroid_displacement_px** | euclidean(centroid_nurse, centroid_sam2) | Pixel distance between mask centroids |

---

## 6. Error Handling

### 6.1 HTTP Error Responses

All errors return a consistent JSON format:

```json
{
  "error": "short_error_code",
  "detail": "Human-readable description of the error"
}
```

### 6.2 Error Codes

| Status | Error Code | When |
|--------|-----------|------|
| 401 | `unauthorized` | Missing or invalid bearer token |
| 404 | `scan_not_found` | Scan ID does not exist in Firestore |
| 422 | `validation_error` | Pydantic validation failure |
| 500 | `internal_error` | Unexpected server error |
| 503 | `service_unavailable` | Firestore/GCS/Pub/Sub unreachable |

### 6.3 Worker Error Handling

- If SAM 2 inference fails, set scan status to `validation_failed` and store error details
- If GCS download fails, retry up to 3 times with exponential backoff, then fail
- If Firestore write fails, return 500 to Pub/Sub (message will be redelivered)
- All errors are logged to Cloud Logging with structured JSON

---

## 7. Deployment Configuration

### 7.1 API Gateway (`woundos-api-v1`)

```yaml
# Cloud Run service configuration
service: woundos-api-v1
region: us-central1
platform: managed

container:
  image: us-central1-docker.pkg.dev/careplix-woundos/woundos/api-v1:latest
  port: 8080
  resources:
    cpu: 1
    memory: 512Mi
  env:
    - WOUNDOS_API_TOKEN (from Secret Manager)
    - WOUNDOS_GCP_PROJECT=careplix-woundos
    - WOUNDOS_GCS_BUCKET=woundos-scans
    - WOUNDOS_FIRESTORE_COLLECTION=wound_scans
    - WOUNDOS_PUBSUB_TOPIC=scan-validations
    - WOUNDOS_ANTHROPIC_API_KEY (from Secret Manager, optional)

scaling:
  min_instances: 1
  max_instances: 10
  concurrency: 80

timeout: 60s
```

### 7.2 Shadow Validation Worker (`woundos-validator-v1`)

```yaml
# Cloud Run service configuration
service: woundos-validator-v1
region: us-central1
platform: managed

container:
  image: us-central1-docker.pkg.dev/careplix-woundos/woundos/validator-v1:latest
  port: 8080
  resources:
    cpu: 2
    memory: 2Gi
  env:
    - WOUNDOS_GCP_PROJECT=careplix-woundos
    - WOUNDOS_GCS_BUCKET=woundos-scans
    - WOUNDOS_FIRESTORE_COLLECTION=wound_scans

scaling:
  min_instances: 0
  max_instances: 5
  concurrency: 1

timeout: 300s
```

### 7.3 Pub/Sub Push Subscription

```
Topic: scan-validations
Subscription: scan-validations-push
Push endpoint: https://woundos-validator-v1-<hash>.run.app/pubsub/push
Ack deadline: 300 seconds
Retry policy: exponential backoff, min 10s, max 600s
```

### 7.4 Docker Build

**API Gateway** (`Dockerfile`):
```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ ./app/
EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

**Worker** (`Dockerfile.worker`):
```dockerfile
FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*
COPY requirements-worker.txt .
RUN pip install --no-cache-dir -r requirements-worker.txt
RUN pip install --no-cache-dir git+https://github.com/facebookresearch/sam2.git
COPY worker/ ./worker/
EXPOSE 8080
CMD ["uvicorn", "worker.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

---

## 8. CORS Configuration

The API Gateway enables CORS for the following scenarios:

- **Allowed origins**: `*` (in v1 pilot; restrict in production)
- **Allowed methods**: `GET`, `POST`, `OPTIONS`
- **Allowed headers**: `Authorization`, `Content-Type`
- **Max age**: 600 seconds

---

## 9. Testing Strategy

### 9.1 Unit Tests

- Pydantic model serialization/deserialization
- Agreement metric computations (IoU, Dice, area delta, centroid displacement)
- Clinical summary template generation

### 9.2 Integration Tests

- API endpoint request/response validation (using FastAPI TestClient)
- Firestore mock for CRUD operations
- GCS mock for signed URL generation
- Pub/Sub mock for message publishing

### 9.3 End-to-End Tests

- Full scan creation → upload → validation flow
- Clinical summary generation with and without API key

---

## 10. File Structure

```
backend-v1/
├── Dockerfile
├── Dockerfile.worker
├── requirements.txt
├── app/
│   ├── __init__.py
│   ├── main.py                   # FastAPI app with CORS, lifespan
│   ├── config.py                 # Pydantic settings
│   ├── auth.py                   # Bearer token middleware
│   ├── routes/
│   │   ├── __init__.py
│   │   ├── health.py
│   │   ├── scans.py
│   │   └── clinical_summary.py
│   ├── models/
│   │   ├── __init__.py
│   │   └── schemas.py
│   └── services/
│       ├── __init__.py
│       ├── firestore_service.py
│       ├── gcs_service.py
│       └── pubsub_service.py
├── worker/
│   ├── __init__.py
│   ├── main.py
│   ├── sam2_inference.py
│   └── agreement_metrics.py
└── tests/
    ├── __init__.py
    ├── conftest.py
    ├── test_health.py
    └── test_schemas.py
```
