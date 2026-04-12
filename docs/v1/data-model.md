# WoundOS Pro v1 — Data Model Specification

## 1. Firestore Schema

### Collection: `wound_scans`

Each document represents a single wound scan captured by a nurse.

```
wound_scans/{scan_id}
├── scan_id: string (UUID)
├── patient_id: string (UUID)
├── nurse_id: string
├── facility_id: string
├── created_at: string (ISO 8601)
├── updated_at: string (ISO 8601)
│
├── device: map
│   ├── model: string ("iPhone 15 Pro")
│   ├── os_version: string ("iOS 17.4")
│   ├── app_version: string ("1.0.0")
│   ├── lidar_available: boolean
│   └── capture_mode: string ("manual_lidar")
│
├── capture: map
│   ├── body_location: string ("sacrum", "heel", "leg", etc.)
│   ├── wound_type: string ("pressure_ulcer", "venous", "diabetic", "surgical", "other")
│   ├── gcs_paths: map
│   │   ├── rgb: string ("gs://woundos-scans/{scan_id}/rgb.jpg")
│   │   ├── depth: string ("gs://woundos-scans/{scan_id}/depth.bin")
│   │   ├── mesh: string ("gs://woundos-scans/{scan_id}/mesh.obj")
│   │   └── annotated: string ("gs://woundos-scans/{scan_id}/annotated.jpg")
│   ├── camera_intrinsics: map {fx, fy, cx, cy, width, height}
│   └── camera_pose: string (JSON-serialized 4x4 matrix — Firestore can't nest arrays)
│
├── nurse_boundary: map
│   ├── tap_center_2d: array [x, y] (pixel coords where nurse first tapped)
│   ├── boundary_2d: string (JSON array of [x,y] pixel coords — serialized to avoid nested arrays)
│   ├── boundary_3d: string (JSON array of [x,y,z] world coords in meters — serialized)
│   ├── point_count: number
│   └── drawing_time_seconds: number
│
├── measurements: map
│   ├── source: string ("on_device_manual")
│   ├── area_cm2: number
│   ├── max_depth_mm: number
│   ├── avg_depth_mm: number
│   ├── volume_ml: number
│   ├── length_mm: number
│   ├── width_mm: number
│   ├── perimeter_mm: number
│   ├── undermining_mm: number | null
│   ├── tunneling_mm: number | null
│   └── computed_on_device_ms: number
│
├── tissue_composition: map
│   ├── granulation_pct: number (0.0-1.0)
│   ├── slough_pct: number
│   ├── necrotic_pct: number
│   ├── epithelial_pct: number
│   └── source: string ("nurse_input" | "hsv_heuristic")
│
├── push_score: map
│   ├── area_score: number (0-10)
│   ├── exudate_score: number (0-3)
│   ├── surface_type_score: number (0-4)
│   └── total: number (0-17)
│
├── clinical_summary: string (2-4 sentence clinical note)
│
├── validation: map
│   ├── status: string ("pending" | "complete" | "error")
│   ├── completed_at: string | null
│   ├── sam_model: string | null ("sam2.1-hiera-tiny")
│   ├── sam_boundary_2d: string | null (JSON array)
│   ├── agreement: map | null
│   │   ├── iou: number
│   │   ├── dice: number
│   │   ├── area_delta_pct: number
│   │   ├── centroid_displacement_px: number
│   │   └── boundary_f1: number
│   ├── flagged_for_review: boolean
│   ├── flag_reasons: array of strings
│   └── error_message: string | null
│
└── upload: map
    ├── status: string ("pending" | "uploading" | "complete" | "failed")
    ├── uploaded_at: string | null
    └── bytes_uploaded: number
```

### Key Design Decisions

1. **Nested arrays serialized as JSON strings**: Firestore doesn't support arrays of arrays. Camera poses (4x4 matrices) and boundary coordinates (arrays of [x,y] pairs) are stored as JSON-serialized strings. Deserialize on read.

2. **Flat measurement fields**: All measurement values are top-level within the `measurements` map, not nested further. This makes Firestore queries simple (`measurements.area_cm2 > 10`).

3. **Validation is append-only**: The shadow validation worker writes to `validation.*` fields. It never overwrites nurse data. This ensures auditability.

4. **No subcollections in v1**: Everything is in a single document per scan. Subcollections (e.g., for review history) come in v2.

---

## 2. API Request/Response Contracts

### POST /api/wound/v1/scans

Creates a new scan record.

**Request:**
```json
{
  "patient_id": "uuid-string",
  "nurse_id": "nurse-123",
  "facility_id": "hospital-A",
  "device": {
    "model": "iPhone 15 Pro",
    "os_version": "iOS 17.4",
    "app_version": "1.0.0",
    "lidar_available": true,
    "capture_mode": "manual_lidar"
  },
  "capture": {
    "body_location": "sacrum",
    "wound_type": "pressure_ulcer",
    "camera_intrinsics": {
      "fx": 3088.57, "fy": 3088.57,
      "cx": 2016.0, "cy": 1512.0,
      "width": 4032, "height": 3024
    },
    "camera_pose": [[1,0,0,0],[0,1,0,0],[0,0,1,-0.25],[0,0,0,1]]
  },
  "nurse_boundary": {
    "tap_center_2d": [1920, 1440],
    "boundary_2d": [[142,87],[168,82],[195,85]],
    "boundary_3d": [[0.152,0.043,0.201],[0.168,0.041,0.199]],
    "point_count": 87,
    "drawing_time_seconds": 42.3
  },
  "measurements": {
    "area_cm2": 12.4,
    "max_depth_mm": 5.2,
    "avg_depth_mm": 2.8,
    "volume_ml": 3.1,
    "length_mm": 45.0,
    "width_mm": 32.0,
    "perimeter_mm": 128.0,
    "undermining_mm": null,
    "tunneling_mm": null,
    "computed_on_device_ms": 247
  },
  "tissue_composition": {
    "granulation_pct": 0.70,
    "slough_pct": 0.25,
    "necrotic_pct": 0.03,
    "epithelial_pct": 0.02,
    "source": "nurse_input"
  },
  "push_score": {
    "area_score": 9,
    "exudate_score": 2,
    "surface_type_score": 3
  }
}
```

**Response (201):**
```json
{
  "scan_id": "uuid-string",
  "status": "created",
  "upload_urls": {
    "rgb": "https://storage.googleapis.com/woundos-scans/...(signed PUT URL)",
    "depth": "https://storage.googleapis.com/woundos-scans/...",
    "mesh": "https://storage.googleapis.com/woundos-scans/...",
    "annotated": "https://storage.googleapis.com/woundos-scans/..."
  },
  "upload_urls_expire_at": "ISO timestamp (1 hour from now)"
}
```

### GET /api/wound/v1/scans/{scan_id}

**Response (200):**
```json
{
  "scan_id": "uuid",
  "patient_id": "uuid",
  "nurse_id": "nurse-123",
  "created_at": "ISO timestamp",
  "measurements": {
    "area_cm2": 12.4,
    "max_depth_mm": 5.2,
    "avg_depth_mm": 2.8,
    "volume_ml": 3.1,
    "length_mm": 45.0,
    "width_mm": 32.0,
    "perimeter_mm": 128.0
  },
  "push_score": {
    "area_score": 9,
    "exudate_score": 2,
    "surface_type_score": 3,
    "total": 14
  },
  "clinical_summary": "Stage III pressure injury...",
  "validation": {
    "status": "complete",
    "agreement": {
      "iou": 0.89,
      "dice": 0.94,
      "area_delta_pct": 5.6
    },
    "flagged_for_review": false
  },
  "upload": {
    "status": "complete"
  }
}
```

### GET /api/wound/v1/patients/{patient_id}/scans

**Response (200):**
```json
{
  "patient_id": "uuid",
  "scans": [
    {
      "scan_id": "uuid-1",
      "created_at": "2026-04-10T14:32:00Z",
      "body_location": "sacrum",
      "wound_type": "pressure_ulcer",
      "measurements": {
        "area_cm2": 12.4,
        "max_depth_mm": 5.2
      },
      "push_score": { "total": 14 },
      "validation_status": "complete"
    },
    {
      "scan_id": "uuid-2",
      "created_at": "2026-04-17T14:45:00Z",
      "body_location": "sacrum",
      "wound_type": "pressure_ulcer",
      "measurements": {
        "area_cm2": 10.8,
        "max_depth_mm": 4.1
      },
      "push_score": { "total": 12 },
      "validation_status": "pending"
    }
  ],
  "total_scans": 2
}
```

### POST /api/wound/v1/clinical-summary

**Request:**
```json
{
  "measurements": {
    "area_cm2": 12.4,
    "max_depth_mm": 5.2,
    "avg_depth_mm": 2.8,
    "volume_ml": 3.1,
    "length_mm": 45.0,
    "width_mm": 32.0,
    "perimeter_mm": 128.0
  },
  "tissue_composition": {
    "granulation_pct": 0.70,
    "slough_pct": 0.25,
    "necrotic_pct": 0.03,
    "epithelial_pct": 0.02
  },
  "push_score": {
    "area_score": 9,
    "exudate_score": 2,
    "surface_type_score": 3
  },
  "body_location": "sacrum",
  "wound_type": "pressure_ulcer"
}
```

**Response (200):**
```json
{
  "clinical_summary": "Stage III pressure injury on sacrum measuring 12.4 cm² with maximum depth of 5.2 mm. Wound bed predominantly granulation tissue (70%) with moderate slough (25%). PUSH score 14/17 indicates significant concern. Recommend continued offloading protocol and moisture-retentive dressing changes every 48 hours.",
  "source": "claude_haiku" | "template",
  "generated_at": "ISO timestamp"
}
```

### GET /api/wound/v1/health

**Response (200):**
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "service": "woundos-wound-api",
  "timestamp": "ISO timestamp"
}
```

---

## 3. GCS Storage Layout

```
gs://woundos-scans/
├── {scan_id}/
│   ├── rgb.jpg              (4032x3024, ~2-3 MB)
│   ├── depth.bin            (Float32 array, ~4 MB compressed)
│   ├── mesh.obj             (ARMeshAnchor export, ~2-5 MB)
│   └── annotated.jpg        (boundary + dimension lines, ~1 MB)
```

### Upload Flow
1. iOS calls `POST /api/wound/v1/scans` with metadata
2. Backend creates Firestore doc, returns signed PUT URLs (1-hour expiry)
3. iOS uploads binary files directly to GCS using signed URLs
4. iOS calls `POST /api/wound/v1/scans/{scan_id}/upload-complete` to confirm
5. Backend publishes to Pub/Sub for shadow validation

### Retention Policy
- v1: No automatic deletion (scans retained indefinitely for dataset building)
- Future: configurable retention per facility (HIPAA compliance)

---

## 4. Pub/Sub Message Format

### Topic: scan-validations

**Message data (JSON):**
```json
{
  "scan_id": "uuid-string",
  "gcs_rgb_path": "gs://woundos-scans/{scan_id}/rgb.jpg",
  "nurse_boundary_2d": [[142,87],[168,82]],
  "tap_center_2d": [1920, 1440],
  "image_width": 4032,
  "image_height": 3024,
  "published_at": "ISO timestamp"
}
```

**Message attributes:**
- `scan_id`: string
- `priority`: "normal" (all v1 scans are normal priority)

---

## 5. Authentication

### v1: Shared Bearer Token
- Single token per deployment, set via env var `WOUNDOS_API_TOKEN`
- iOS sends: `Authorization: Bearer {token}`
- Backend validates: `request.headers["Authorization"] == f"Bearer {settings.api_token}"`
- If token is empty/unset, auth is disabled (development mode)

### Future (v2+): JWT with per-nurse identity
- Firebase Auth or Auth0
- JWT tokens with nurse_id, facility_id claims
- Role-based access (nurse, clinician, admin)

---

## 6. Error Response Format

All errors follow this structure:

```json
{
  "error": {
    "code": "SCAN_NOT_FOUND",
    "message": "Scan with ID abc-123 was not found",
    "status": 404
  }
}
```

Error codes:
- `VALIDATION_ERROR` (400): Invalid request body
- `UNAUTHORIZED` (401): Missing or invalid bearer token
- `SCAN_NOT_FOUND` (404): Scan ID doesn't exist
- `PATIENT_NOT_FOUND` (404): Patient ID doesn't exist
- `UPLOAD_FAILED` (500): GCS signed URL generation failed
- `CLINICAL_SUMMARY_FAILED` (500): Claude API call failed (returns template instead)
- `INTERNAL_ERROR` (500): Unexpected server error
