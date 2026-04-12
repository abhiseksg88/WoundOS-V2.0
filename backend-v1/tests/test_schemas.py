"""Tests for Pydantic model validation and serialization."""

from __future__ import annotations

from datetime import datetime, timezone

import pytest

from app.models.schemas import (
    CameraIntrinsics,
    CaptureMetadata,
    ClinicalSummaryRequest,
    ClinicalSummaryResponse,
    CreateScanRequest,
    CreateScanResponse,
    HealthResponse,
    Measurements,
    NurseBoundary,
    PatientScansResponse,
    ScanDetailResponse,
    ScanSummary,
    UploadRequest,
    UploadResponse,
    ValidationResult,
)


class TestMeasurements:
    """Tests for the Measurements model."""

    def test_valid_measurements(self) -> None:
        m = Measurements(
            area_cm2=4.52,
            max_depth_mm=3.1,
            volume_cm3=0.87,
            length_cm=3.2,
            width_cm=1.8,
            perimeter_cm=8.9,
            push_score=9,
        )
        assert m.area_cm2 == 4.52
        assert m.push_score == 9

    def test_push_score_optional(self) -> None:
        m = Measurements(
            area_cm2=1.0,
            max_depth_mm=1.0,
            volume_cm3=0.5,
            length_cm=2.0,
            width_cm=1.0,
            perimeter_cm=5.0,
        )
        assert m.push_score is None

    def test_serialization_round_trip(self) -> None:
        m = Measurements(
            area_cm2=4.52,
            max_depth_mm=3.1,
            volume_cm3=0.87,
            length_cm=3.2,
            width_cm=1.8,
            perimeter_cm=8.9,
            push_score=9,
        )
        data = m.model_dump()
        m2 = Measurements(**data)
        assert m == m2


class TestNurseBoundary:
    """Tests for the NurseBoundary model."""

    def test_valid_boundary(self) -> None:
        nb = NurseBoundary(
            boundary_2d=[[100, 200], [110, 210]],
            boundary_3d=[[0.01, 0.02, -0.25], [0.011, 0.021, -0.251]],
            tap_center_2d=[110, 205],
        )
        assert len(nb.boundary_2d) == 2
        assert len(nb.tap_center_2d) == 2

    def test_empty_boundary_valid(self) -> None:
        nb = NurseBoundary(
            boundary_2d=[],
            boundary_3d=[],
            tap_center_2d=[0, 0],
        )
        assert nb.boundary_2d == []


class TestCaptureMetadata:
    """Tests for CaptureMetadata model."""

    def test_valid_metadata(self) -> None:
        cm = CaptureMetadata(
            device_model="iPhone 14 Pro",
            ios_version="17.4",
            app_version="1.0.0",
            lidar_available=True,
            capture_distance_m=0.25,
            camera_intrinsics=CameraIntrinsics(fx=1597.0, fy=1597.0, cx=960.0, cy=540.0),
            camera_transform=[
                [1.0, 0.0, 0.0, 0.0],
                [0.0, 1.0, 0.0, 0.0],
                [0.0, 0.0, 1.0, -0.25],
                [0.0, 0.0, 0.0, 1.0],
            ],
            image_width=1920,
            image_height=1440,
        )
        assert cm.device_model == "iPhone 14 Pro"
        assert cm.camera_intrinsics.fx == 1597.0


class TestCreateScanRequest:
    """Tests for CreateScanRequest model."""

    def test_full_request(self) -> None:
        from tests.conftest import make_scan_request_body

        body = make_scan_request_body()
        req = CreateScanRequest(**body)
        assert req.patient_id == "patient-001"
        assert req.measurements.area_cm2 == 4.52
        assert req.nurse_boundary.tap_center_2d == [110, 205]

    def test_optional_fields_default_to_none(self) -> None:
        body = {
            "patient_id": "p1",
            "nurse_id": "n1",
            "capture_metadata": {
                "device_model": "iPhone 14 Pro",
                "ios_version": "17.4",
                "app_version": "1.0.0",
                "lidar_available": True,
                "capture_distance_m": 0.25,
                "camera_intrinsics": {"fx": 1597.0, "fy": 1597.0, "cx": 960.0, "cy": 540.0},
                "camera_transform": [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]],
                "image_width": 1920,
                "image_height": 1440,
            },
            "nurse_boundary": {
                "boundary_2d": [[100, 200]],
                "boundary_3d": [[0.01, 0.02, -0.25]],
                "tap_center_2d": [100, 200],
            },
            "measurements": {
                "area_cm2": 1.0,
                "max_depth_mm": 1.0,
                "volume_cm3": 0.5,
                "length_cm": 2.0,
                "width_cm": 1.0,
                "perimeter_cm": 5.0,
            },
        }
        req = CreateScanRequest(**body)
        assert req.facility_id is None
        assert req.wound_type is None
        assert req.wound_location is None
        assert req.clinical_notes is None

    def test_missing_required_field_raises(self) -> None:
        with pytest.raises(Exception):
            CreateScanRequest(patient_id="p1")  # type: ignore[call-arg]


class TestUploadRequest:
    """Tests for UploadRequest model."""

    def test_valid_files(self) -> None:
        req = UploadRequest(files=["rgb.jpg", "depth.bin"])
        assert len(req.files) == 2

    def test_empty_files_list(self) -> None:
        # Empty is technically valid at the Pydantic level;
        # GCS service will handle accordingly
        req = UploadRequest(files=[])
        assert req.files == []


class TestValidationResult:
    """Tests for ValidationResult model."""

    def test_valid_result(self) -> None:
        now = datetime.now(timezone.utc)
        vr = ValidationResult(
            sam2_model="facebook/sam2.1-hiera-tiny",
            iou=0.87,
            dice=0.93,
            area_delta_percent=-2.1,
            centroid_displacement_px=3.4,
            validated_at=now,
        )
        assert vr.iou == 0.87
        assert vr.sam2_model == "facebook/sam2.1-hiera-tiny"


class TestResponseModels:
    """Tests for response model serialization."""

    def test_create_scan_response(self) -> None:
        now = datetime.now(timezone.utc)
        resp = CreateScanResponse(scan_id="uuid-1", status="created", created_at=now)
        data = resp.model_dump()
        assert data["scan_id"] == "uuid-1"
        assert data["status"] == "created"

    def test_upload_response(self) -> None:
        resp = UploadResponse(
            scan_id="uuid-1",
            upload_urls={"rgb.jpg": "https://example.com/signed"},
            expiry_minutes=60,
        )
        assert resp.upload_urls["rgb.jpg"] == "https://example.com/signed"

    def test_health_response(self) -> None:
        now = datetime.now(timezone.utc)
        resp = HealthResponse(
            status="ok",
            service="woundos-api-v1",
            version="1.0.0",
            timestamp=now,
        )
        data = resp.model_dump()
        assert data["status"] == "ok"

    def test_patient_scans_response(self) -> None:
        now = datetime.now(timezone.utc)
        resp = PatientScansResponse(
            patient_id="p1",
            scans=[
                ScanSummary(
                    scan_id="s1",
                    status="validated",
                    wound_type="pressure_ulcer",
                    wound_location="sacrum",
                    measurements=Measurements(
                        area_cm2=4.52,
                        max_depth_mm=3.1,
                        volume_cm3=0.87,
                        length_cm=3.2,
                        width_cm=1.8,
                        perimeter_cm=8.9,
                        push_score=9,
                    ),
                    created_at=now,
                )
            ],
            total=1,
            limit=50,
            offset=0,
        )
        assert resp.total == 1
        assert len(resp.scans) == 1
        assert resp.scans[0].scan_id == "s1"

    def test_clinical_summary_response(self) -> None:
        now = datetime.now(timezone.utc)
        resp = ClinicalSummaryResponse(
            scan_id="s1",
            summary="Test summary text.",
            generated_by="template",
            generated_at=now,
        )
        assert resp.generated_by == "template"

    def test_scan_detail_with_validation(self) -> None:
        now = datetime.now(timezone.utc)
        resp = ScanDetailResponse(
            scan_id="s1",
            patient_id="p1",
            nurse_id="n1",
            facility_id="f1",
            status="validated",
            capture_metadata=CaptureMetadata(
                device_model="iPhone 14 Pro",
                ios_version="17.4",
                app_version="1.0.0",
                lidar_available=True,
                capture_distance_m=0.25,
                camera_intrinsics=CameraIntrinsics(fx=1597.0, fy=1597.0, cx=960.0, cy=540.0),
                camera_transform=[[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]],
                image_width=1920,
                image_height=1440,
            ),
            nurse_boundary=NurseBoundary(
                boundary_2d=[[100, 200]],
                boundary_3d=[[0.01, 0.02, -0.25]],
                tap_center_2d=[100, 200],
            ),
            measurements=Measurements(
                area_cm2=4.52,
                max_depth_mm=3.1,
                volume_cm3=0.87,
                length_cm=3.2,
                width_cm=1.8,
                perimeter_cm=8.9,
                push_score=9,
            ),
            wound_type="pressure_ulcer",
            wound_location="sacrum",
            clinical_notes="Stage 3",
            validation=ValidationResult(
                sam2_model="facebook/sam2.1-hiera-tiny",
                iou=0.87,
                dice=0.93,
                area_delta_percent=-2.1,
                centroid_displacement_px=3.4,
                validated_at=now,
            ),
            created_at=now,
            updated_at=now,
        )
        assert resp.validation is not None
        assert resp.validation.iou == 0.87

    def test_scan_detail_without_validation(self) -> None:
        now = datetime.now(timezone.utc)
        resp = ScanDetailResponse(
            scan_id="s1",
            patient_id="p1",
            nurse_id="n1",
            status="created",
            capture_metadata=CaptureMetadata(
                device_model="iPhone 14 Pro",
                ios_version="17.4",
                app_version="1.0.0",
                lidar_available=True,
                capture_distance_m=0.25,
                camera_intrinsics=CameraIntrinsics(fx=1597.0, fy=1597.0, cx=960.0, cy=540.0),
                camera_transform=[[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]],
                image_width=1920,
                image_height=1440,
            ),
            nurse_boundary=NurseBoundary(
                boundary_2d=[[100, 200]],
                boundary_3d=[[0.01, 0.02, -0.25]],
                tap_center_2d=[100, 200],
            ),
            measurements=Measurements(
                area_cm2=4.52,
                max_depth_mm=3.1,
                volume_cm3=0.87,
                length_cm=3.2,
                width_cm=1.8,
                perimeter_cm=8.9,
            ),
            created_at=now,
            updated_at=now,
        )
        assert resp.validation is None
        assert resp.facility_id is None
