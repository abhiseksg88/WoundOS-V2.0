# WoundOS Pro v1 — Sprint Timeline

## Overview

| Phase | Duration | Focus | Deliverable |
|-------|----------|-------|-------------|
| Week 1 | 5 days | iOS capture infrastructure | Snapshot freeze + depth extraction working |
| Week 2 | 5 days | iOS measurement pipeline | On-device measurements from drawn boundary |
| Week 3 | 5 days | Backend API + shadow worker | API deployed, SAM 2 validation running |
| Week 4 | 5 days | iOS upload + sync | Background upload to backend, offline queue |
| Week 5 | 5 days | Integration + polish | End-to-end flow working, UX polish |
| Week 6 | 5 days | Clinical validation | Phantom testing, nurse pilot prep |

**Total: 6 weeks to pilot-ready prototype.**

---

## Week 1: iOS Capture Infrastructure

### Goal
Nurse can point camera at wound, tap shutter, and see a frozen frame with LiDAR depth data extracted.

### Tasks

| Day | Task | Acceptance Criteria |
|-----|------|---------------------|
| 1 | Create `DeviceCapabilityChecker.swift` | Returns `.supported` on iPhone Pro, `.unsupported` on non-Pro. Unit tested. |
| 1 | Create `WoundCaptureSnapshot.swift` model | Struct holds UIImage, depth [[Float]], meshAnchors, pose, intrinsics. Compiles. |
| 2 | Create `SnapshotService.swift` | Extracts current ARFrame's sceneDepth + mesh anchors. Freezes state. Unit tested. |
| 2 | Create `DepthMapUtils.swift` | Extracts Float32 from CVPixelBuffer. Unprojects pixel to 3D. Unit tested. |
| 3 | Modify `ARSessionManager.swift` | Add `captureSnapshot() -> WoundCaptureSnapshot`. Verified on device. |
| 3 | Modify `ARCaptureViewController.swift` | Shutter button freezes frame and creates snapshot. |
| 4 | Create `BoundaryProjector3D.swift` | Projects [CGPoint] boundary to [simd_float3] using LiDAR depth. Unit tested. |
| 5 | Integration test | Capture snapshot on iPhone Pro → extract depth → project test point to 3D → verify metric accuracy against ruler measurement. |

### Risks
- LiDAR depth resolution (256×192) vs camera resolution (4032×3024) — must scale correctly
- ARMeshAnchor geometry extraction may need coordinate conversion
- First time accessing sceneDepth from CVPixelBuffer — may have format surprises

---

## Week 2: iOS Measurement Pipeline

### Goal
Nurse draws boundary on frozen frame, app computes area/depth/volume/L×W/perimeter and displays results.

### Tasks

| Day | Task | Acceptance Criteria |
|-----|------|---------------------|
| 1 | Create `OnDeviceMeasurementEngine.swift` | Orchestrator: takes snapshot + boundary → returns WoundMeasurement. Compiles. |
| 1 | Wire `PlaneFitter` to use boundary 3D points | RANSAC plane fit on 3D boundary points. Returns Plane. |
| 2 | Wire `SurfaceAreaCalculator` for wound mesh | Extract wound submesh from ARMeshAnchor geometry. Compute area in cm². |
| 2 | Wire `DepthVolumeCalculator` | Compute max depth, avg depth, volume from wound submesh + reference plane. |
| 3 | Wire `DimensionCalculator` | Project 3D boundary to plane → compute L×W + perimeter in mm. |
| 3 | Compute PUSH score | Use existing PUSHScore.swift with computed area. |
| 4 | Modify `BoundaryEditView` | Accept frozen frame UIImage as input (instead of server response). |
| 4 | Modify `ProcessingViewModel` | Route to on-device pipeline when capture mode is manual_lidar. |
| 5 | Integration test | Draw boundary on test image → get measurements → compare against known geometry. All measurement unit tests pass. |

### Risks
- Extracting submesh from ARMeshAnchor (triangles inside boundary) — geometry intersection code is new
- Measurement accuracy depends on plane fit quality — test with diverse wound shapes
- BoundaryEditView currently expects server response — modification needed

---

## Week 3: Backend API + Shadow Worker

### Goal
Backend API accepts scan uploads and shadow validation worker runs SAM 2 comparison.

### Tasks

| Day | Task | Acceptance Criteria |
|-----|------|---------------------|
| 1 | Build `backend-v1/` FastAPI application | Health endpoint returns 200. All Pydantic models compile. |
| 1 | Implement Firestore CRUD service | create_scan, get_scan, update_scan, list_patient_scans. |
| 2 | Implement GCS signed URL service | Generate PUT/GET signed URLs. Upload test file via signed URL. |
| 2 | Implement scan endpoints | POST /scans, GET /scans/{id}, GET /patients/{id}/scans. Integration tested. |
| 3 | Implement clinical summary endpoint | Claude Haiku integration with template fallback. |
| 3 | Implement Pub/Sub publishing | Scan creation triggers Pub/Sub message. |
| 4 | Build shadow validation worker | SAM 2 Tiny CPU inference + agreement metrics. |
| 4 | Deploy API to Cloud Run | Health check passes from curl. |
| 5 | Deploy worker to Cloud Run | End-to-end: upload scan → Pub/Sub → worker → Firestore validation result. |

### Risks
- SAM 2 from_pretrained on CPU may be slow to initialize (~30s cold start)
- Pub/Sub push subscription setup — need correct IAM permissions
- Firestore security rules may block Cloud Run service account

---

## Week 4: iOS Upload + Sync

### Goal
Scans captured offline sync to backend when network is available.

### Tasks

| Day | Task | Acceptance Criteria |
|-----|------|---------------------|
| 1 | Create `ScanUploadService.swift` | POST scan metadata, receive signed URLs, upload binaries. |
| 1 | Create API client models | Swift Codable structs matching backend request/response schemas. |
| 2 | Wire `OfflineScanQueue` to new upload service | Scans enqueue on save, dequeue on successful upload. |
| 2 | Background upload implementation | Upload happens in background task, not blocking UI. |
| 3 | Handle upload errors and retries | Exponential backoff, max 3 retries, then leave in queue. |
| 3 | Update `ServerConfig.swift` | New v1 API endpoints. |
| 4 | Clinical summary integration | After upload, fetch clinical summary from backend. Display in ResultsView. |
| 5 | Test offline flow | Capture in airplane mode → enable WiFi → verify scan appears in backend. |

### Risks
- iOS background task limitations (iOS may kill background uploads)
- Large files (depth.bin ~4MB, mesh.obj ~5MB) — need efficient upload
- Signed URL expiration (1 hour) — handle refresh if upload is delayed

---

## Week 5: Integration + Polish

### Goal
Complete end-to-end flow works smoothly. UX is nurse-ready.

### Tasks

| Day | Task | Acceptance Criteria |
|-----|------|---------------------|
| 1 | End-to-end flow test | Capture → draw → measure → save → upload → validate. All steps work. |
| 1 | Fix integration bugs | Any issues found in E2E testing. |
| 2 | Error handling polish | Network errors, depth extraction failures, empty meshes — all handled gracefully. |
| 2 | Loading states and progress indicators | Nurse sees clear feedback during each step. |
| 3 | Results screen polish | Annotated image, depth heatmap, dimension lines render correctly. |
| 3 | PDF report integration | Existing PDFReportGenerator works with on-device measurements. |
| 4 | Patient scan history | List of previous scans for a patient, with upload status indicator. |
| 4 | Settings screen update | Capture mode selector, API endpoint configuration, version info. |
| 5 | Code cleanup | Remove dead code paths (old cloud reconstruction flow), add documentation comments. |

### Risks
- Visualization rendering may need adjustment for on-device data format
- PDF report generator may expect server response format — adapt
- Performance profiling on older iPhone 12 Pro (slower than 15 Pro)

---

## Week 6: Clinical Validation

### Goal
Validated accuracy on wound phantoms. Ready for nurse pilot.

### Tasks

| Day | Task | Acceptance Criteria |
|-----|------|---------------------|
| 1 | Phantom accuracy testing | 5 phantoms × 5 repetitions = 25 measurements. All within ±5% area, ±2mm depth. |
| 2 | Multi-device consistency | Same phantom on 2+ iPhone Pro models. Agreement within ±3%. |
| 3 | Nurse usability session | 3-5 nurses test the app. Feedback collected. Critical issues addressed. |
| 4 | Shadow validation review | Check SAM 2 agreement on phantom scans. Tune flagging thresholds. |
| 5 | Pilot deployment prep | Build for TestFlight distribution. Write nurse training guide. Prepare pilot protocol. |

### Risks
- Phantom availability — need silicone wound models with known dimensions
- Nurse scheduling — coordinate availability for usability testing
- TestFlight requires Apple Developer Program enrollment ($99/year)

---

## Definition of Done (v1 Pilot-Ready)

- [ ] Nurse can capture wound, draw boundary, see measurements in <60 seconds
- [ ] All measurements within ±5% of phantom ground truth
- [ ] App works fully offline (airplane mode test)
- [ ] Scans upload to backend when network available
- [ ] Shadow validation runs SAM 2 and stores agreement metrics
- [ ] Clinical summary endpoint works (template or Claude Haiku)
- [ ] PDF report generates correctly
- [ ] Tested on iPhone 12 Pro and iPhone 15 Pro
- [ ] No crashes in 25+ consecutive scans
- [ ] Code committed to `feature/v1-lidar-ondevice` branch
- [ ] Backend deployed to Cloud Run
- [ ] TestFlight build available for pilot nurses
