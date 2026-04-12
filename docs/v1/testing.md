# WoundOS Pro v1 — Testing Strategy

## 1. Test Pyramid

```
                ╱╲
               ╱  ╲
              ╱ E2E╲         Manual: 5 clinical validation tests
             ╱──────╲
            ╱ Integr.╲       API + iOS integration: 10 tests
           ╱──────────╲
          ╱  Unit Tests ╲    iOS + Backend: 40+ tests
         ╱──────────────╲
```

---

## 2. Unit Tests — iOS

### 2.1 BoundaryProjector3D Tests

| Test | Input | Expected Output |
|------|-------|-----------------|
| Flat surface, known depth | 2D points on 640x480 image, uniform depth 0.25m | 3D points at z=-0.25m |
| Boundary at image center | Single point (320,240), depth 0.20m, identity pose | World point (0, 0, -0.20) |
| Boundary at image corner | Point (0,0), depth 0.30m | Correctly offset from center |
| Empty boundary | [] | Returns [] |
| Missing depth at pixel | Depth map has NaN at boundary point | Skip point, interpolate or use nearest |
| Scaled intrinsics | Depth map at 256x192 vs image at 4032x3024 | Intrinsics scaled correctly |

### 2.2 OnDeviceMeasurementEngine Tests

| Test | Geometry | Expected Values |
|------|----------|-----------------|
| Flat circle wound (no depth) | Circular boundary r=20mm on flat plane | Area: ~12.56 cm², depth: 0mm, volume: 0mL |
| Hemisphere wound | Hemisphere r=15mm | Area: ~7.07 cm², depth: 15mm, volume: ~7.07mL |
| Rectangular wound | 40×30mm rectangle, 5mm deep | Area: ~12 cm², L: 40mm, W: 30mm |
| Single point boundary | 1 point | Returns zero measurements |
| Collinear points | All points on a line | Returns zero area, non-zero length |

### 2.3 PlaneFitter Tests (Existing, verify)

| Test | Input | Expected |
|------|-------|----------|
| 3 coplanar points | Triangle on XY plane | Normal: (0,0,1), d: 0 |
| 100 noisy points near plane | Gaussian noise σ=1mm | Normal within 5° of true |
| Insufficient points | 2 points | Returns nil |
| Degenerate (collinear) | 10 points on a line | Returns nil |

### 2.4 SurfaceAreaCalculator Tests (Existing, verify)

| Test | Input | Expected |
|------|-------|----------|
| Unit triangle | (0,0,0), (1,0,0), (0,1,0) | 0.5 m² |
| Two triangles forming square | 1×1 square split diagonally | 1.0 m² |
| Empty mesh | No triangles | 0.0 m² |
| Large wound (~10cm²) | Known triangle mesh | Within 0.01 cm² of analytical value |

### 2.5 DepthVolumeCalculator Tests (Existing, verify)

| Test | Input | Expected |
|------|-------|----------|
| Flat wound (no depth) | All vertices on reference plane | volume: 0, maxDepth: 0 |
| Uniform depth wound | All vertices 5mm below plane | maxDepth: 5mm, avgDepth: 5mm |
| Pyramidal wound | Pyramid base 20×20mm, apex 10mm deep | volume: ~1.33 mL |

### 2.6 DimensionCalculator Tests (Existing, verify)

| Test | Input | Expected |
|------|-------|----------|
| Circle boundary | 100 points on r=25mm circle | L: ~50mm, W: ~50mm, perimeter: ~157mm |
| Elongated ellipse | Major=40mm, minor=10mm | L: ~40mm, W: ~10mm |
| Single point | 1 point | L: 0, W: 0, perimeter: 0 |

### 2.7 DeviceCapabilityChecker Tests

| Test | Input | Expected |
|------|-------|----------|
| iPhone 15 Pro | LiDAR: yes, sceneDepth: yes | .supported |
| iPhone 15 (non-Pro) | LiDAR: no | .unsupported("LiDAR required") |
| iPad Pro 2024 | LiDAR: yes | .supported |

### 2.8 DepthMapUtils Tests

| Test | Input | Expected |
|------|-------|----------|
| Extract depth at pixel | CVPixelBuffer with known values | Correct Float32 value |
| Unproject pixel to 3D | Pixel (320,240), depth 0.25m, known intrinsics | Correct 3D point |
| Out-of-bounds pixel | Pixel (-1, -1) | Returns nil |

---

## 3. Unit Tests — Backend

### 3.1 API Schema Tests

| Test | Input | Expected |
|------|-------|----------|
| Valid scan creation | Complete JSON body | 201, scan_id returned |
| Missing required fields | No patient_id | 400, validation error |
| Invalid measurement values | area_cm2: -1 | 400, validation error |
| Valid clinical summary request | Measurements + tissue + push | 200, summary string |
| Empty measurements | All zeros | 200, valid template summary |

### 3.2 Health Endpoint Test

| Test | Expected |
|------|----------|
| GET /api/wound/v1/health | 200, {"status": "healthy", "version": "1.0.0"} |

### 3.3 Agreement Metrics Tests

| Test | Input | Expected |
|------|-------|----------|
| Perfect overlap | Same mask for nurse and SAM | IoU: 1.0, Dice: 1.0 |
| No overlap | Disjoint masks | IoU: 0.0, Dice: 0.0 |
| 50% overlap | Half-overlapping masks | IoU: 0.333, Dice: 0.5 |
| Empty nurse mask | All-black mask | IoU: 0.0 (handle gracefully) |
| Empty SAM mask | SAM returns nothing | IoU: 0.0, flagged |

### 3.4 Clinical Summary Tests

| Test | Expected |
|------|----------|
| With API key | Returns Claude-generated summary |
| Without API key | Returns template summary |
| Claude API error | Falls back to template |

---

## 4. Integration Tests

### 4.1 iOS → Backend Integration

| Test | Steps | Expected |
|------|-------|----------|
| Scan upload flow | POST scan metadata → upload files → confirm | Firestore doc created, GCS files present |
| Scan retrieval | Create scan → GET by scan_id | All fields returned correctly |
| Patient history | Create 3 scans for same patient → GET patient scans | 3 scans returned, sorted by date |
| Clinical summary | POST measurements → get summary | Summary text returned |
| Offline queue | Enqueue scan in airplane mode → enable network | Scan uploads successfully |

### 4.2 Shadow Validation Integration

| Test | Steps | Expected |
|------|-------|----------|
| Validation trigger | Upload scan → check Pub/Sub | Message published |
| SAM 2 inference | Worker receives scan → runs SAM 2 | Validation result written to Firestore |
| Agreement computation | Known nurse boundary vs known SAM boundary | Correct IoU/Dice values |
| Error handling | Invalid image → worker processes | validation.status: "error", error_message set |

---

## 5. Clinical Validation (Manual)

### 5.1 Phantom-Based Accuracy Tests

Use silicone wound phantoms with known dimensions.

| Phantom | Known Area | Known Depth | Known Volume | Acceptable Error |
|---------|-----------|-------------|-------------|-----------------|
| Circular flat wound (3cm diameter) | 7.07 cm² | 0 mm | 0 mL | ±5% area |
| Rectangular wound (4×3cm, 5mm deep) | 12.0 cm² | 5.0 mm | 6.0 mL | ±5% area, ±2mm depth |
| Deep oval wound (5×3cm, 10mm deep) | 11.78 cm² | 10.0 mm | ~8 mL | ±5% area, ±2mm depth |
| Irregular wound (silicone mold) | Reference measurement | Reference | Reference | ±10% all metrics |

### 5.2 Test Protocol

1. Place phantom on flat surface
2. Capture with WoundOS Pro (iPhone 15 Pro)
3. Draw boundary carefully
4. Record measurements
5. Compare against reference measurements
6. Repeat 5 times per phantom
7. Compute mean error and standard deviation

### 5.3 Inter-Device Consistency

Test same phantom with different iPhone Pro models:
- iPhone 12 Pro
- iPhone 13 Pro
- iPhone 14 Pro
- iPhone 15 Pro

Expected: measurements agree within ±3% across devices.

### 5.4 Nurse Usability Test

With 3-5 nurses:
1. Time per scan (target: <60 seconds)
2. Number of retakes (target: <1 per 5 scans)
3. Subjective ease of use (1-5 scale, target: ≥4)
4. Boundary drawing accuracy vs expert consensus
5. Identify UX friction points

---

## 6. Test Automation

### iOS Tests

```bash
# Run Swift unit tests via xcodebuild
xcodebuild test \
  -project WoundOSV2/WoundOSV2.xcodeproj \
  -scheme WoundOSV2 \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -resultBundlePath TestResults
```

### Backend Tests

```bash
cd backend-v1
pip install -r requirements.txt
pytest tests/ -v --tb=short
```

### CI/CD Integration (Future)

GitHub Actions workflow:
- On PR: run Swift build + backend pytest
- On merge to main: deploy to staging Cloud Run
- On tag: deploy to production Cloud Run
