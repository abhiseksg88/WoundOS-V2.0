# WoundOS Pro v1 — System Architecture

**Status**: Design locked
**Target release**: v1.0 (pilot-ready)
**Device support**: iPhone 12 Pro or later, iPad Pro (2020+), iOS 16+
**Primary author**: Engineering
**Last updated**: 2026-04

---

## 1. Product Vision

WoundOS Pro is a **clinical-grade wound measurement application** for nurses and wound care specialists. It uses the iPhone's LiDAR sensor and ARKit to capture accurate 3D wound geometry, allowing nurses to measure wound area, depth, volume, length, width, and perimeter with clinical accuracy comparable to the $15,000 ARANZ Silhouette device.

### 1.1 Core design principles

1. **Nurse workflow is never blocked by network.** Measurement happens entirely on-device. Cloud is for backup, sync, and secondary validation only.
2. **AI observes, never decides.** SAM 2 runs in the cloud as a silent validator. Nurses always do the primary segmentation manually. AI output is never shown in the clinical path.
3. **Everything is an API call.** The backend is the source of truth for cross-device queries, clinical dashboard, and longitudinal analysis.
4. **Data is the product.** Every scan creates expert-labeled training data. The long-term moat is accumulated nurse-annotated wound data, not the iOS app itself.
5. **Progressive disclosure.** Nurses see a simple capture workflow. Clinicians (later, via dashboard) see comparison reviews. Analysts see FWA dashboards. Each role sees only what they need.

### 1.2 Non-goals for v1

- **Non-LiDAR iPhone support.** Deferred to a separate product (WoundOS Measure with calibration stickers).
- **Android support.** Deferred.
- **On-device AI segmentation.** Deferred to v2. Manual drawing is the only clinical path in v1.
- **Real-time boundary tracking.** Not needed. Nurse captures then draws on frozen frame.
- **EHR integration (Epic/Cerner).** Deferred to v1.5+.
- **Clinical dashboard UI.** Separate product, consumes v1 API. Not built in v1.
- **FWA detection logic.** Infrastructure ready (data is collected), but detection rules not implemented in v1.
- **Multi-tenant auth.** v1 uses a single bearer token per deployment.

---

## 2. System Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│                      iPhone 12 Pro+ (iOS 16+)                    │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  CLINICAL PATH (100% offline, <3 sec)                    │   │
│  │                                                          │   │
│  │  ARKit + LiDAR → Snapshot freeze → Nurse draws boundary  │   │
│  │  → Project 2D→3D (LiDAR depth) → Compute measurements    │   │
│  │  → Display + Save to Core Data                           │   │
│  └──────────────────────────────────────────────────────────┘   │
│                          │                                       │
│                          │ (async, when network available)       │
│                          ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  BACKGROUND UPLOAD (OfflineScanQueue)                    │   │
│  │  Metadata JSON → API → Signed URLs → GCS binary upload   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│                     BACKEND (Google Cloud Run)                   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  INGESTION API (woundos-api-v1)                          │   │
│  │  FastAPI, CPU-only, ~$15/mo                              │   │
│  │                                                          │   │
│  │  POST /api/wound/v1/scans                                │   │
│  │  POST /api/wound/v1/scans/{id}/upload                    │   │
│  │  GET  /api/wound/v1/scans/{id}                           │   │
│  │  GET  /api/wound/v1/patients/{id}/scans                  │   │
│  │  POST /api/wound/v1/clinical-summary                     │   │
│  │  GET  /api/wound/v1/health                               │   │
│  │                                                          │   │
│  │  Writes Firestore → Publishes Pub/Sub                    │   │
│  └──────────────────────────────────────────────────────────┘   │
│                          │                                       │
│                          ▼ (async, Pub/Sub trigger)              │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  SHADOW VALIDATION WORKER (woundos-validator-v1)         │   │
│  │  FastAPI, CPU-only, scale-to-zero, ~$10/mo               │   │
│  │                                                          │   │
│  │  1. Download RGB from GCS                                │   │
│  │  2. Run SAM 2 Tiny on CPU (PyTorch, 5-15 sec)            │   │
│  │  3. Compute agreement metrics (IoU, Dice, area delta)    │   │
│  │  4. Store validation results in Firestore                │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  STORAGE LAYER                                           │   │
│  │                                                          │   │
│  │  GCS:       woundos-scans/{scan_id}/{rgb,depth,mesh,*}   │   │
│  │  Firestore: scans/{scan_id} (metadata + validation)      │   │
│  │  Pub/Sub:   scan-validations topic                       │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                          │
                          ▼ (future, Phase 2+)
┌──────────────────────────────────────────────────────────────────┐
│  CLINICAL DASHBOARD (separate product, reads v1 API)             │
│  Not in v1 scope. Built after v1 ships.                          │
└──────────────────────────────────────────────────────────────────┘
```

---

## 3. Component Responsibilities

### 3.1 iOS Application

**Owns:**
- Patient management (Core Data)
- ARKit session lifecycle
- LiDAR depth capture
- Scene mesh reconstruction
- Snapshot freezing (capture + depth + mesh + pose at one instant)
- Boundary drawing UX (using existing `BezierPathEngine`)
- 2D → 3D boundary projection via LiDAR depth
- All measurement computations (porting existing Python algorithms to Swift)
- Results display (annotated image, depth heatmap, measurement cards)
- PDF report generation
- Core Data persistence of scans and patients
- Offline scan queue for upload
- Background sync to backend

**Does NOT own:**
- AI segmentation (backend does this asynchronously)
- Cross-device data sync (backend handles this)
- Clinical dashboard views (separate product)
- Historical analytics beyond what Core Data stores locally

### 3.2 Backend API (Ingestion)

**Owns:**
- Scan metadata persistence in Firestore
- Signed URL generation for binary uploads to GCS
- Pub/Sub publishing to trigger shadow validation
- Clinical summary generation via Claude Haiku
- Cross-device scan retrieval
- Patient scan history lookup

**Does NOT own:**
- Measurement computation (iOS does this)
- Real-time AI inference (worker does this asynchronously)
- Image storage (GCS does this, API just generates URLs)
- Authentication beyond simple bearer token (v1 simplicity)

### 3.3 Shadow Validation Worker

**Owns:**
- Pub/Sub subscription to `scan-validations` topic
- Downloading RGB images from GCS
- Running SAM 2 inference on CPU
- Computing agreement metrics vs nurse boundary (IoU, Dice, area delta, Hausdorff)
- Storing validation results in Firestore

**Does NOT own:**
- Any user-facing API (it's async background work)
- Flagging decisions (stores metrics; flagging logic comes in v2 clinical dashboard)
- Real-time responses (deliberately async)

### 3.4 Storage Layer

**Google Cloud Storage (`woundos-scans` bucket):**
- `{scan_id}/rgb.jpg` — Captured RGB frame (compressed JPEG)
- `{scan_id}/depth.bin` — LiDAR depth map (float32 array)
- `{scan_id}/mesh.obj` — Scene reconstruction mesh
- `{scan_id}/annotated.jpg` — Pre-rendered visualization for dashboard
- `{scan_id}/mask.png` — Binary wound mask from nurse drawing

**Firestore `scans` collection:**
- One document per scan keyed by `scan_id` (UUID)
- Contains all metadata, measurements, validation results
- Full schema in `data-model.md`

**Pub/Sub `scan-validations` topic:**
- Triggered by backend after scan upload completes
- Message contains: `{"scan_id": "uuid"}`
- Subscribed by Shadow Validation Worker (push subscription)

---

## 4. Data Flow (End-to-End)

### 4.1 Nurse captures a wound (100% offline)

```
T+0.0s  Nurse opens app, selects patient
T+0.1s  Tap "New Scan"
T+0.2s  ARKit session starts with LiDAR + sceneReconstruction
T+1.0s  Live preview shows camera feed + distance indicator
T+4.0s  Nurse aims camera at wound, waits for green tracking indicator
T+5.0s  Nurse taps shutter button
T+5.1s  SnapshotService freezes:
          - RGB frame (UIImage)
          - Depth map ([Float32] in meters)
          - Scene mesh (vertices + faces)
          - Camera transform (4x4 matrix)
          - Camera intrinsics (fx, fy, cx, cy)
T+5.2s  ARKit session paused (save battery)
T+5.3s  Frozen frame displayed with drawing overlay
T+5.3s  Nurse begins drawing boundary with finger
T+35s   Nurse completes boundary drawing (30 seconds average)
T+35.1s BoundaryProjector3D projects 2D points to 3D via LiDAR depth
T+35.2s PlaneFitter runs RANSAC on boundary_3d
T+35.3s SurfaceAreaCalculator, DepthVolumeCalculator, DimensionCalculator run
T+35.5s PushScoreCalculator computes score
T+35.5s ResultsView displays measurements + annotated image + heatmap
T+35.5s Nurse taps "Save"
T+35.6s Scan persisted to Core Data, added to OfflineScanQueue
T+35.7s Nurse returns to patient list
```

**Total nurse time: ~35 seconds from tap to save.** Network not required at any point.

### 4.2 Background upload (async, when network available)

```
Trigger: Network becomes available OR app is opened
  ↓
OfflineScanQueue.processQueue()
  ↓
For each pending scan:
  ↓
  POST /api/wound/v1/scans (metadata JSON)
    Payload: patient_id, nurse_id, capture metadata, boundary_2d, boundary_3d,
             measurements, push_score, clinical_summary
    Response: {"scan_id": "uuid", "upload_urls": {rgb_url, depth_url, mesh_url, annotated_url}}
  ↓
  For each upload URL:
    PUT to GCS signed URL with binary data
    (rgb.jpg, depth.bin, mesh.obj, annotated.jpg)
  ↓
  POST /api/wound/v1/scans/{scan_id}/upload-complete
    (tells backend all files are uploaded)
  ↓
  Backend publishes to Pub/Sub: {"scan_id": "uuid"}
  ↓
  Mark scan as "uploaded" in Core Data
```

**Total time per scan upload: 3-10 seconds** depending on network speed.
**Nurse impact: zero** — this happens silently in background.

### 4.3 Shadow validation (async, in cloud)

```
Pub/Sub push delivery to Shadow Validation Worker
  ↓
Worker receives: {"scan_id": "uuid"}
  ↓
1. Read scan from Firestore (get nurse boundary, tap point, measurements)
2. Download rgb.jpg from GCS
3. Decode image to numpy array
4. Run SAM 2 inference on CPU:
   - Use nurse tap point as prompt
   - Model: sam2.1_hiera_tiny (smallest, ~79 MB, CPU-friendly)
   - Runtime: 5-15 seconds on modern CPU
   - Output: binary mask
5. Compute agreement metrics:
   - IoU (Intersection over Union)
   - Dice coefficient
   - Area delta (percentage)
   - Boundary Hausdorff distance
   - Centroid displacement
6. Write results to Firestore: scans/{scan_id}/validation = {...}
7. Ack Pub/Sub message
```

**Total backend time per scan: 15-30 seconds.** Async, does not affect nurse experience. Fully invisible to end user in v1 (results appear later in clinical dashboard, built in Phase 2).

---

## 5. Accuracy Expectations

### 5.1 LiDAR depth accuracy

Apple's LiDAR on iPhone Pro has specified accuracy of **±1-2mm at 10-50cm range**. This is the exact range for wound measurement.

### 5.2 Measurement accuracy (v1)

| Metric | Target | Comparable to |
|--------|--------|---------------|
| Surface area | ±3-5% error | Matches eKare inSight, beats most phone-based |
| Max depth | ±1-2mm error | Matches ARANZ Silhouette ($15K device) |
| Volume | ±5-8% error | Matches ARANZ Silhouette |
| Length/Width | ±1-2% error | Matches or beats ARANZ |
| Perimeter | ±2-3% error | Matches ARANZ |

**Reference:** ARANZ Silhouette reports area ±2%, depth ±5%, volume ±5%. Our target is clinically equivalent for iPhone Pro LiDAR.

### 5.3 Sources of error

1. **Nurse boundary drawing precision** — human finger precision ~1-2mm on screen
2. **LiDAR depth noise** — ~1-2mm at wound distance
3. **Camera pose jitter** — ARKit tracking, typically <1mm at close range
4. **RANSAC plane fitting** — depends on wound shape and boundary quality

Total expected error budget: **~3-5mm combined** for depth-dependent measurements, **~3-5%** for area.

---

## 6. Technology Stack

### 6.1 iOS Application

- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI (primary) + UIKit (ARKit integration)
- **AR/3D:** ARKit, RealityKit, SceneKit, Metal
- **ML (future):** CoreML (v2+)
- **Persistence:** Core Data
- **Networking:** URLSession with Codable
- **Minimum iOS:** 16.0
- **Target iOS:** 17.0+

### 6.2 Backend

- **Language:** Python 3.11
- **API Framework:** FastAPI
- **Server:** Uvicorn
- **Deployment:** Google Cloud Run (CPU-only)
- **Storage:** Google Cloud Storage, Firestore (Native mode)
- **Messaging:** Google Cloud Pub/Sub
- **ML (worker):** PyTorch, SAM 2 (CPU inference)
- **LLM:** Anthropic Claude Haiku API

### 6.3 Infrastructure

- **Cloud:** Google Cloud Platform
- **Region:** us-central1 (primary) — low latency to North America, cheapest
- **Container Registry:** Artifact Registry (`us-central1-docker.pkg.dev`)
- **CI/CD (future):** Cloud Build or GitHub Actions
- **Monitoring:** Cloud Logging, Cloud Monitoring
- **IAM:** Service accounts with least-privilege

---

## 7. Security & Privacy Considerations

### 7.1 Data classification

**Protected Health Information (PHI):**
- Patient identifiers
- Wound images
- Depth maps
- Measurements tied to a patient

**Non-PHI:**
- Aggregate statistics
- Anonymized training data (post-v1)

### 7.2 Data flow security

- **At rest on iPhone:** Core Data encrypted via iOS Data Protection
- **In transit (iOS → backend):** HTTPS via URLSession
- **In cloud (GCS):** Encrypted at rest by default (Google-managed keys in v1)
- **In Firestore:** Encrypted at rest by default
- **Signed URLs:** Short-lived (1 hour), single-use preferred

### 7.3 v1 simplifications (to be hardened in v2)

- **Auth:** Single bearer token, stored in iOS Keychain, per-deployment
- **No per-user PHI access control** (all app users see all patients)
- **No audit logging** beyond basic Cloud Logging
- **No HIPAA BAA** with Google until production deployment (v1 is pilot)

### 7.4 v2 hardening roadmap

- Multi-tenant auth (one account per facility/nurse)
- Row-level security in Firestore
- Audit logging for every PHI access
- Customer-managed encryption keys (CMEK) for GCS
- Google Cloud BAA for HIPAA compliance
- SOC 2 Type II certification path

---

## 8. Cost Model

### 8.1 v1 projected costs (at 100 scans/day, 3000/month)

| Component | Monthly cost |
|-----------|-------------|
| Cloud Run API (ingestion, CPU, min=1) | ~$10 |
| Cloud Run Validation Worker (CPU, scale-to-zero) | ~$5 |
| GCS storage (3000 scans × ~10MB = 30GB) | ~$1 |
| GCS egress (dashboard access, later) | ~$2 |
| Firestore reads/writes | ~$2 |
| Pub/Sub messages | ~$1 |
| Claude Haiku API (3000 × $0.001) | ~$3 |
| Artifact Registry storage | ~$1 |
| **Total** | **~$25/month** |

### 8.2 Cost scaling

At 1000 scans/day (10x v1):
- Cloud Run scales up linearly: ~$50
- Storage grows: ~$10
- Validation worker: ~$30
- LLM: ~$30
- **Total: ~$150/month**

At 10,000 scans/day (100x v1):
- **Total: ~$800/month**
- Consider GPU for validation worker at this scale

### 8.3 Cost vs failed v0 approach

| | v0 (Cloud GPU pipeline) | v1 (On-device + CPU shadow) |
|---|-----|-----|
| Monthly cost @ 100/day | ~$515 | ~$25 |
| **Reduction** | — | **95% cheaper** |

---

## 9. Risk Register

### 9.1 Technical risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| LiDAR depth accuracy insufficient | Low | High | Validated on phantoms before pilot; ARANZ-class accuracy documented |
| ARKit scene mesh too coarse | Medium | Medium | Use LiDAR depth directly as primary, mesh as fallback |
| Nurse drawing precision too coarse | Medium | Medium | Pinch-to-zoom for precise drawing; allow point-by-point editing |
| Swift port of measurement code introduces bugs | High | High | Comprehensive unit tests matching Python reference implementation |
| SAM 2 CPU inference too slow at scale | Low | Low | Async, not time-critical; upgrade to GPU if >10k scans/day |
| Core Data schema migration for future versions | Low | Medium | Version Core Data model from v1 |

### 9.2 Product risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Nurses find manual drawing too slow | Medium | Medium | Pilot testing; add v2 automatic mode if needed |
| LiDAR-only restriction limits market | High | Medium | Accepted trade-off; WoundOS Measure (sticker app) covers non-LiDAR |
| FDA regulatory concerns about AI in critical path | Low | High | Nurse is always primary; AI is passive observer only |
| HIPAA compliance gaps in v1 | Medium | High | v1 is pilot only; production deployment requires BAA and hardening |

### 9.3 Operational risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Developer cannot build iOS (no Mac available) | High | Critical | Procure Mac before development starts OR use cloud Mac service |
| Cloud Run cold start delays | Low | Low | Set min-instances=1 on API service (extra ~$5/mo) |
| GCS upload failures from iOS | Medium | Low | OfflineScanQueue retries with exponential backoff |
| Lost data during Core Data migration | Low | High | Version schema, test migrations, backup before deploy |

---

## 10. Success Criteria for v1

### 10.1 Must-have (blocking for pilot release)

- [ ] Nurse can capture a wound snapshot in under 5 seconds
- [ ] Nurse can draw boundary and get measurements in under 60 seconds total
- [ ] Measurements match Python reference implementation within 0.1% floating-point tolerance
- [ ] App works fully offline (airplane mode test)
- [ ] Scans sync to backend when network available
- [ ] LiDAR device capability detection works (graceful failure on non-LiDAR)
- [ ] PDF report generation works and matches existing quality
- [ ] Shadow validation worker processes scans within 60 seconds of upload
- [ ] API endpoints pass integration tests
- [ ] No hardcoded secrets in iOS app or backend code

### 10.2 Should-have (nice for pilot but not blocking)

- [ ] Scan history shows upload status (synced/pending)
- [ ] Clinical summary via Claude Haiku integrated
- [ ] Annotated image thumbnails in patient history
- [ ] Pinch-to-zoom for precise boundary drawing
- [ ] Undo/redo for boundary drawing

### 10.3 Won't-have (explicitly deferred to v1.5+)

- On-device SAM 2 / automatic mode
- EHR integration
- Real-time boundary tracking
- Multi-language support
- Android / non-LiDAR iPhone support
- Clinical dashboard UI
- FWA detection rules

---

## 11. Next Steps

1. Review this architecture document and confirm scope
2. Delete failing cloud GPU infrastructure (see `deployment.md`)
3. Begin iOS implementation per `ios-spec.md`
4. Begin backend implementation per `backend-spec.md`
5. Week-by-week execution per `timeline.md`

**Ready to execute. See companion documents for implementation details.**
