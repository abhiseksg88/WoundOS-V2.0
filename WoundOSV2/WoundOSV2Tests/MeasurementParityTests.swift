import XCTest
import simd
@testable import WoundOSV2

/// Parity tests for the on-device measurement pipeline.
///
/// Each test mirrors a Python test in `backend/tests/test_measurement/`,
/// guaranteeing the Swift port produces the same numerical answers as the
/// reference Python implementation. If a Python test changes, update the
/// matching Swift test in lock-step.
final class MeasurementParityTests: XCTestCase {

    // MARK: - SurfaceAreaCalculator parity (test_surface_area.py)

    func testUnitTriangleAreaIsHalfM2() {
        // A right triangle with legs 1m has area 0.5 m².
        let vertices: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0),
        ]
        let faces = [SIMD3<Int>(0, 1, 2)]
        let areas = SurfaceAreaCalculator.computeTriangleAreasM2(vertices: vertices, faces: faces)
        XCTAssertEqual(Double(areas[0]), 0.5, accuracy: 1e-6)
    }

    func testSquareFromTwoTrianglesIs1M2() {
        let vertices: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0),
        ]
        let faces = [SIMD3<Int>(0, 1, 2), SIMD3<Int>(0, 2, 3)]
        let total = SurfaceAreaCalculator.computeSurfaceAreaM2(vertices: vertices, faces: faces)
        XCTAssertEqual(total, 1.0, accuracy: 1e-6)
    }

    func test10mmSquareWoundIs1Cm2() {
        let s: Float = 0.01
        let vertices: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(s, 0, 0), SIMD3(s, s, 0), SIMD3(0, s, 0),
        ]
        let faces = [SIMD3<Int>(0, 1, 2), SIMD3<Int>(0, 2, 3)]
        let cm2 = SurfaceAreaCalculator.computeSurfaceAreaCm2(vertices: vertices, faces: faces)
        XCTAssertEqual(cm2, 1.0, accuracy: 0.01)
    }

    func testFaceMaskSelectsSubset() {
        let s: Float = 0.01
        let vertices: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(s, 0, 0), SIMD3(s, s, 0), SIMD3(0, s, 0),
        ]
        let faces = [SIMD3<Int>(0, 1, 2), SIMD3<Int>(0, 2, 3)]
        let mask = [true, false]
        let cm2 = SurfaceAreaCalculator.computeSurfaceAreaCm2(
            vertices: vertices, faces: faces, faceMask: mask
        )
        XCTAssertEqual(cm2, 0.5, accuracy: 0.01)
    }

    // MARK: - DimensionCalculator parity (test_dimensions.py)

    func testCircularBoundaryDiameter() {
        // 5mm radius circle in the XY plane → 10mm diameter.
        let r: Float = 0.005
        let n = 100
        let boundary: [SIMD3<Float>] = (0..<n).map { i in
            let theta = 2 * Float.pi * Float(i) / Float(n)
            return SIMD3(r * cos(theta), r * sin(theta), 0)
        }
        let result = DimensionCalculator.computeLengthWidthMm(
            boundaryPoints3D: boundary,
            planeCentroid: SIMD3(0, 0, 0),
            planeNormal: SIMD3(0, 0, 1)
        )
        XCTAssertEqual(result.lengthMm, 10.0, accuracy: 0.5)
        XCTAssertEqual(result.widthMm, 10.0, accuracy: 0.5)
    }

    func testElongatedEllipse30x10() {
        // Ellipse with 15mm semi-major and 5mm semi-minor → 30 × 10 mm.
        let n = 100
        let boundary: [SIMD3<Float>] = (0..<n).map { i in
            let theta = 2 * Float.pi * Float(i) / Float(n)
            return SIMD3(0.015 * cos(theta), 0.005 * sin(theta), 0)
        }
        let result = DimensionCalculator.computeLengthWidthMm(
            boundaryPoints3D: boundary,
            planeCentroid: SIMD3(0, 0, 0),
            planeNormal: SIMD3(0, 0, 1)
        )
        XCTAssertGreaterThan(result.lengthMm, result.widthMm)
        XCTAssertEqual(result.lengthMm, 30.0, accuracy: 1.0)
        XCTAssertEqual(result.widthMm, 10.0, accuracy: 1.0)
    }

    func testSinglePointReturnsZeroDimensions() {
        let result = DimensionCalculator.computeLengthWidthMm(
            boundaryPoints3D: [SIMD3(0, 0, 0)],
            planeCentroid: SIMD3(0, 0, 0),
            planeNormal: SIMD3(0, 0, 1)
        )
        XCTAssertEqual(result.lengthMm, 0)
        XCTAssertEqual(result.widthMm, 0)
    }

    func testEndpointIndicesInRange() {
        let n = 32
        let boundary: [SIMD3<Float>] = (0..<n).map { i in
            let theta = 2 * Float.pi * Float(i) / Float(n)
            return SIMD3(0.01 * cos(theta), 0.01 * sin(theta), 0)
        }
        let result = DimensionCalculator.computeLengthWidthWithEndpoints(
            boundaryPoints3D: boundary,
            planeCentroid: SIMD3(0, 0, 0),
            planeNormal: SIMD3(0, 0, 1)
        )
        for idx in [result.lengthEndpointA, result.lengthEndpointB,
                    result.widthEndpointA, result.widthEndpointB] {
            XCTAssertTrue(idx >= 0 && idx < n)
        }
    }

    func testSquarePerimeter() {
        let s: Float = 0.01
        let boundary: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(s, 0, 0), SIMD3(s, s, 0), SIMD3(0, s, 0),
        ]
        let perimeterMm = DimensionCalculator.computePerimeterMm(boundaryPoints3D: boundary)
        XCTAssertEqual(perimeterMm, 40.0, accuracy: 0.1)
    }

    func testCirclePerimeter() {
        let r: Float = 0.005
        let n = 200
        let boundary: [SIMD3<Float>] = (0..<n).map { i in
            let theta = 2 * Float.pi * Float(i) / Float(n)
            return SIMD3(r * cos(theta), r * sin(theta), 0)
        }
        let perimeterMm = DimensionCalculator.computePerimeterMm(boundaryPoints3D: boundary)
        let expected = 2.0 * Double.pi * Double(r) * 1000.0
        XCTAssertEqual(perimeterMm, expected, accuracy: 0.5)
    }

    // MARK: - PlaneFitter parity (test_plane_fitter.py)

    func testFitPlaneSVDOnPerfectXYPlane() {
        // 6 points on the z=0 plane → normal should be (0,0,1).
        let pts: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0),
            SIMD3(1, 1, 0), SIMD3(0.5, 0.5, 0), SIMD3(0.2, 0.8, 0),
        ]
        let (centroid, normal) = PlaneFitter.fitPlaneSVD(points: pts)
        XCTAssertEqual(centroid.z, 0, accuracy: 1e-5)
        XCTAssertEqual(abs(normal.z), 1.0, accuracy: 1e-3)
        XCTAssertEqual(abs(normal.x), 0.0, accuracy: 1e-3)
        XCTAssertEqual(abs(normal.y), 0.0, accuracy: 1e-3)
    }

    func testFitPlaneRANSACTolerantToOutlier() {
        // 8 inliers on z=0 plus one wild outlier should still recover (0,0,1).
        var pts: [SIMD3<Float>] = []
        for i in 0..<8 {
            let theta = Float(i) * Float.pi / 4
            pts.append(SIMD3(0.01 * cos(theta), 0.01 * sin(theta), 0))
        }
        pts.append(SIMD3(0, 0, 0.5))  // outlier 0.5m away
        let (_, normal, mask) = PlaneFitter.fitPlaneRANSAC(boundaryPoints: pts)
        XCTAssertEqual(abs(normal.z), 1.0, accuracy: 0.05)
        // The outlier (last index) should not be an inlier.
        XCTAssertFalse(mask[8])
    }

    // MARK: - DepthCalculator parity (test_depth_calc.py-style)

    func testMaxDepthBelowPlane() {
        // Plane at z=0, normal +Z, vertices at z=-3mm and z=-5mm
        let verts: [SIMD3<Float>] = [
            SIMD3(0, 0, -0.003),
            SIMD3(0.01, 0.01, -0.005),
            SIMD3(0.02, 0, 0),
        ]
        let max = DepthCalculator.computeMaxDepthMm(
            woundVertices: verts,
            planeCentroid: SIMD3(0, 0, 0),
            planeNormal: SIMD3(0, 0, 1)
        )
        XCTAssertEqual(max, 5.0, accuracy: 1e-3)
    }

    func testAvgDepthIgnoresAbovePlane() {
        let verts: [SIMD3<Float>] = [
            SIMD3(0, 0, -0.002),     // 2mm below
            SIMD3(0, 0, -0.004),     // 4mm below
            SIMD3(0, 0,  0.003),     // 3mm above (ignored)
        ]
        let avg = DepthCalculator.computeAvgDepthMm(
            woundVertices: verts,
            planeCentroid: SIMD3(0, 0, 0),
            planeNormal: SIMD3(0, 0, 1)
        )
        XCTAssertEqual(avg, 3.0, accuracy: 1e-3)  // (2 + 4) / 2
    }

    // MARK: - VolumeCalculator parity (test_volume.py)

    func testPrismVolumeOfFlatTriangleIsZero() {
        // Triangle on the plane → no prism height → 0 volume.
        let verts: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(0.01, 0, 0), SIMD3(0, 0.01, 0),
        ]
        let faces = [SIMD3<Int>(0, 1, 2)]
        let volM3 = VolumeCalculator.computeVolumePrismM3(
            woundVertices: verts,
            woundFaces: faces,
            planeCentroid: SIMD3(0, 0, 0),
            planeNormal: SIMD3(0, 0, 1)
        )
        XCTAssertEqual(volM3, 0, accuracy: 1e-12)
    }

    func testPrismVolumeOfDepressedTriangle() {
        // Equilateral triangle with one vertex 5mm below the plane.
        // Volume of one tetrahedron = (1/3) * base_area * height
        //   base = projection on plane = right triangle with legs 1cm = 0.5e-4 m²
        //   height varies — use the unit version for sanity rather than a closed-form
        let verts: [SIMD3<Float>] = [
            SIMD3(0, 0, 0),
            SIMD3(0.01, 0, 0),
            SIMD3(0, 0.01, -0.005),
        ]
        let faces = [SIMD3<Int>(0, 1, 2)]
        let volM3 = VolumeCalculator.computeVolumePrismM3(
            woundVertices: verts,
            woundFaces: faces,
            planeCentroid: SIMD3(0, 0, 0),
            planeNormal: SIMD3(0, 0, 1)
        )
        // Should be > 0 and on the order of (0.5 * 1cm * 1cm * 5mm / 3) ≈ 8.3e-8 m³.
        XCTAssertGreaterThan(volM3, 0)
        XCTAssertLessThan(volM3, 1e-6)
    }

    // MARK: - RaycastProjection / OBJ parser

    func testParseSimpleOBJ() {
        let obj = """
        v 0 0 0
        v 1 0 0
        v 0 1 0
        f 1 2 3
        """
        let data = obj.data(using: .utf8)!
        let parsed = RaycastProjection.parseOBJMesh(data: data)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.vertices.count, 3)
        XCTAssertEqual(parsed?.faces.count, 1)
        XCTAssertEqual(parsed?.faces[0], SIMD3<Int>(0, 1, 2))  // 1-indexed → 0-indexed
    }

    func testParseOBJWithVertexNormalIndices() {
        // f i/vt/vn format used by ARKit exporters.
        let obj = """
        v 0 0 0
        v 1 0 0
        v 0 1 0
        f 1//1 2//1 3//1
        """
        let data = obj.data(using: .utf8)!
        let parsed = RaycastProjection.parseOBJMesh(data: data)
        XCTAssertEqual(parsed?.faces.count, 1)
        XCTAssertEqual(parsed?.faces[0], SIMD3<Int>(0, 1, 2))
    }

    // MARK: - MeasurementEngine end-to-end (synthetic)

    func testMeasurementEngineProducesNonZeroAreaForSquarePolygon() throws {
        // Build a fake snapshot: identity pose, simple intrinsics, no LiDAR mesh.
        // The polygon will be projected via the constant-depth fallback.
        let intrinsics = CameraIntrinsics(
            fx: 1000, fy: 1000,
            cx: 500, cy: 500,
            width: 1000, height: 1000
        )
        let pose = CameraPose.identity
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xD9])  // not a real JPEG; UIImage may fail
        // Use UIGraphicsImageRenderer to make a real 1x1 image so the init doesn't fail.
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { ctx in
            ctx.cgContext.setFillColor(UIColor.gray.cgColor)
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let jpegData = image.jpegData(compressionQuality: 0.5) ?? bytes

        let snapshot = WoundCaptureSnapshot(
            rgbJpegData: jpegData,
            rgbImage: image,
            imageWidth: 1000,
            imageHeight: 1000,
            intrinsics: intrinsics,
            pose: pose,
            meshOBJData: nil,
            depthPNGData: nil,
            cameraToWoundDistanceMeters: 0.20,
            meshAnchorCount: 0,
            worldBoundsMeters: .zero,
            capturedAt: Date()
        )

        // 100x100 pixel square centered at (500,500). At 20cm distance and fx=1000,
        // 100 px → 100/1000 * 0.20 = 0.02 m = 2cm side → 4 cm² area.
        let polygon: [CGPoint] = [
            CGPoint(x: 450, y: 450),
            CGPoint(x: 550, y: 450),
            CGPoint(x: 550, y: 550),
            CGPoint(x: 450, y: 550),
        ]

        let measurement = try MeasurementEngine.measureSync(
            snapshot: snapshot,
            nursePolygonPixels: polygon
        )

        XCTAssertEqual(measurement.areaCm2, 4.0, accuracy: 0.5)
        XCTAssertEqual(measurement.lengthMm, 28.0, accuracy: 3.0)  // diagonal ≈ 2.83cm
        XCTAssertEqual(measurement.boundary3DMeters.count, 4)
        XCTAssertTrue(measurement.computedOnDevice)
    }
}
