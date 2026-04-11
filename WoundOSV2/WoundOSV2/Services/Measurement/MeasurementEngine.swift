import Foundation
import simd
import CoreGraphics

/// On-device measurement orchestrator.
///
/// Takes a frozen `WoundCaptureSnapshot` plus a nurse-drawn 2D polygon (in image
/// pixel coordinates) and produces a fully populated `PrimaryMeasurement` —
/// area, length, width, perimeter, depth, volume — without any network calls.
///
/// Pipeline:
/// 1. Parse the LiDAR mesh from the snapshot's OBJ.
/// 2. Ray-cast each nurse polygon vertex onto the mesh → 3D boundary points.
///    (Falls back to constant-depth back-projection on non-LiDAR devices.)
/// 3. RANSAC plane fit on the 3D boundary points → wound reference plane.
/// 4. Surface area via Newell's polygon area on the projected 3D boundary.
/// 5. Filter mesh vertices that fall inside the polygon (in image space) → wound interior.
///    Use those + their faces to compute max/avg depth and prism volume.
/// 6. Length / width / perimeter via the existing dimension calculator.
/// 7. Project the L/W endpoints back to 2D image pixels for marker rendering.
enum MeasurementEngine {

    enum Error: Swift.Error, LocalizedError {
        case insufficientPolygon
        case projectionFailed
        case noMeshAndNoFallbackDepth

        var errorDescription: String? {
            switch self {
            case .insufficientPolygon:
                return "Need at least 3 boundary points to measure a wound."
            case .projectionFailed:
                return "Could not project the boundary onto the 3D scene."
            case .noMeshAndNoFallbackDepth:
                return "No LiDAR mesh and no fallback distance was captured."
            }
        }
    }

    /// Async entry point — runs on a background task so the UI stays responsive.
    static func measure(
        snapshot: WoundCaptureSnapshot,
        nursePolygonPixels: [CGPoint]
    ) async throws -> PrimaryMeasurement {
        try await Task.detached(priority: .userInitiated) {
            try measureSync(snapshot: snapshot, nursePolygonPixels: nursePolygonPixels)
        }.value
    }

    /// Synchronous core. Public so unit tests can call it directly without an async hop.
    static func measureSync(
        snapshot: WoundCaptureSnapshot,
        nursePolygonPixels: [CGPoint]
    ) throws -> PrimaryMeasurement {
        let startedAt = Date()

        guard nursePolygonPixels.count >= 3 else {
            throw Error.insufficientPolygon
        }

        let poseC2W = simd4x4(from: snapshot.pose.transform)
        let poseW2C = poseC2W.inverse

        // -------- Step 1: parse mesh (optional) --------
        var meshVertices: [SIMD3<Float>] = []
        var meshFaces: [SIMD3<Int>] = []
        if let objData = snapshot.meshOBJData,
           let parsed = RaycastProjection.parseOBJMesh(data: objData) {
            meshVertices = parsed.vertices
            meshFaces = parsed.faces
        }

        // -------- Step 2: project polygon to 3D --------
        let boundary3D: [SIMD3<Float>]
        if !meshFaces.isEmpty {
            let result = RaycastProjection.projectPolygonOntoMesh(
                polygon2D: nursePolygonPixels,
                intrinsics: snapshot.intrinsics,
                poseC2W: poseC2W,
                meshVertices: meshVertices,
                meshFaces: meshFaces
            )
            // If too many vertices missed the mesh, fall back to constant depth.
            let missRatio = Double(result.misses) / Double(nursePolygonPixels.count)
            if result.world3D.count >= 3 && missRatio < 0.3 {
                boundary3D = result.world3D
            } else if let depth = snapshot.cameraToWoundDistanceMeters {
                boundary3D = RaycastProjection.projectPolygonAtConstantDepth(
                    polygon2D: nursePolygonPixels,
                    intrinsics: snapshot.intrinsics,
                    poseC2W: poseC2W,
                    depthMeters: depth
                )
            } else {
                throw Error.projectionFailed
            }
        } else if let depth = snapshot.cameraToWoundDistanceMeters {
            boundary3D = RaycastProjection.projectPolygonAtConstantDepth(
                polygon2D: nursePolygonPixels,
                intrinsics: snapshot.intrinsics,
                poseC2W: poseC2W,
                depthMeters: depth
            )
        } else {
            throw Error.noMeshAndNoFallbackDepth
        }

        guard boundary3D.count >= 3 else {
            throw Error.projectionFailed
        }

        // -------- Step 3: fit reference plane on the boundary --------
        let plane: (centroid: SIMD3<Float>, normal: SIMD3<Float>)
        if boundary3D.count >= 4 {
            let ransac = PlaneFitter.fitPlaneRANSAC(boundaryPoints: boundary3D)
            plane = (ransac.centroid, ransac.normal)
        } else {
            plane = PlaneFitter.fitPlaneSVD(points: boundary3D)
        }

        // Orient the normal so it points back toward the camera (so depth-below-plane
        // gives positive numbers for points sunken away from the camera).
        let cameraOrigin = SIMD3<Float>(
            poseC2W.columns.3.x,
            poseC2W.columns.3.y,
            poseC2W.columns.3.z
        )
        var planeNormal = plane.normal
        if simd_dot(cameraOrigin - plane.centroid, planeNormal) < 0 {
            planeNormal = -planeNormal
        }

        // -------- Step 4: surface area (Newell on the boundary polygon) --------
        let areaCm2 = SurfaceAreaCalculator.computePolygonAreaCm2(polygon3D: boundary3D)

        // -------- Step 5: dimensions (L, W, perimeter) + endpoints --------
        let dims = DimensionCalculator.computeLengthWidthWithEndpoints(
            boundaryPoints3D: boundary3D,
            planeCentroid: plane.centroid,
            planeNormal: planeNormal
        )
        let perimeterMm = DimensionCalculator.computePerimeterMm(boundaryPoints3D: boundary3D)

        // -------- Step 6: depth + volume from the wound interior submesh --------
        var maxDepthMm = 0.0
        var avgDepthMm = 0.0
        var volumeMl = 0.0

        if !meshVertices.isEmpty {
            let submesh = extractWoundSubmesh(
                vertices: meshVertices,
                faces: meshFaces,
                polygonPixels: nursePolygonPixels,
                intrinsics: snapshot.intrinsics,
                poseW2C: poseW2C
            )
            if !submesh.vertices.isEmpty {
                maxDepthMm = DepthCalculator.computeMaxDepthMm(
                    woundVertices: submesh.vertices,
                    planeCentroid: plane.centroid,
                    planeNormal: planeNormal
                )
                avgDepthMm = DepthCalculator.computeAvgDepthMm(
                    woundVertices: submesh.vertices,
                    planeCentroid: plane.centroid,
                    planeNormal: planeNormal
                )
                if !submesh.faces.isEmpty {
                    volumeMl = VolumeCalculator.computeVolumeMl(
                        woundVertices: submesh.vertices,
                        woundFaces: submesh.faces,
                        planeCentroid: plane.centroid,
                        planeNormal: planeNormal
                    )
                }
            }
        }

        // If volume is still zero (no mesh / empty submesh), approximate as
        // area × avg depth (frustum approximation, conservative).
        if volumeMl <= 0 && avgDepthMm > 0 {
            volumeMl = areaCm2 * (avgDepthMm / 10.0)  // cm² × cm = cm³ = mL
        }

        // -------- Step 7: project marker endpoints back to image pixels --------
        let markerPixels = projectMarkerEndpoints(
            boundary3D: boundary3D,
            indices: [
                dims.lengthEndpointA, dims.lengthEndpointB,
                dims.widthEndpointA, dims.widthEndpointB,
            ],
            intrinsics: snapshot.intrinsics,
            poseW2C: poseW2C
        )

        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)

        return PrimaryMeasurement(
            source: .nurseDrawn,
            boundary2DPixels: nursePolygonPixels,
            boundary3DMeters: boundary3D,
            areaCm2: areaCm2,
            maxDepthMm: maxDepthMm,
            avgDepthMm: avgDepthMm,
            volumeMl: volumeMl,
            lengthMm: dims.lengthMm,
            widthMm: dims.widthMm,
            perimeterMm: perimeterMm,
            pushScore: nil,
            markerEndpointsPixels: markerPixels,
            computedOnDevice: true,
            processingTimeMs: elapsedMs
        )
    }

    // MARK: - Wound interior submesh

    /// Filter the LiDAR mesh down to the vertices/faces inside the nurse-drawn polygon.
    /// A vertex is "inside" if its perspective projection falls within the polygon
    /// (in image pixel space). A face is included if all three vertices are inside.
    static func extractWoundSubmesh(
        vertices: [SIMD3<Float>],
        faces: [SIMD3<Int>],
        polygonPixels: [CGPoint],
        intrinsics: CameraIntrinsics,
        poseW2C: simd_float4x4
    ) -> (vertices: [SIMD3<Float>], faces: [SIMD3<Int>]) {
        let bbox = polygonBoundingBox(polygonPixels)

        // For each vertex: project to image, mark inside-or-not, and remap index.
        var insideMask = [Bool](repeating: false, count: vertices.count)
        var newIndex = [Int](repeating: -1, count: vertices.count)
        var subVerts = [SIMD3<Float>]()
        subVerts.reserveCapacity(vertices.count / 4)

        for i in 0..<vertices.count {
            guard let pix = projectWorldToPixel(vertices[i], intrinsics: intrinsics, poseW2C: poseW2C) else {
                continue
            }
            // Cheap bbox reject first
            if pix.x < bbox.minX || pix.x > bbox.maxX || pix.y < bbox.minY || pix.y > bbox.maxY {
                continue
            }
            if pointInPolygon(pix, polygon: polygonPixels) {
                insideMask[i] = true
                newIndex[i] = subVerts.count
                subVerts.append(vertices[i])
            }
        }

        var subFaces = [SIMD3<Int>]()
        subFaces.reserveCapacity(faces.count / 4)
        for face in faces {
            if insideMask[face.x] && insideMask[face.y] && insideMask[face.z] {
                subFaces.append(SIMD3<Int>(newIndex[face.x], newIndex[face.y], newIndex[face.z]))
            }
        }
        return (subVerts, subFaces)
    }

    // MARK: - Geometry helpers

    /// Convert a `CameraPose.transform` (row-major `[[Float]]`) to a column-major `simd_float4x4`.
    static func simd4x4(from rows: [[Float]]) -> simd_float4x4 {
        // rows[r][c]; simd_float4x4 takes columns.
        return simd_float4x4(
            SIMD4<Float>(rows[0][0], rows[1][0], rows[2][0], rows[3][0]),
            SIMD4<Float>(rows[0][1], rows[1][1], rows[2][1], rows[3][1]),
            SIMD4<Float>(rows[0][2], rows[1][2], rows[2][2], rows[3][2]),
            SIMD4<Float>(rows[0][3], rows[1][3], rows[2][3], rows[3][3])
        )
    }

    /// Project a world-space point through ARKit camera intrinsics into image pixels.
    /// Returns nil if the point is behind the camera.
    static func projectWorldToPixel(
        _ pointWorld: SIMD3<Float>,
        intrinsics: CameraIntrinsics,
        poseW2C: simd_float4x4
    ) -> CGPoint? {
        let homog = SIMD4<Float>(pointWorld.x, pointWorld.y, pointWorld.z, 1)
        let cam = poseW2C * homog
        // ARKit camera convention: -Z is forward → visible points have z < 0
        if cam.z >= -1e-6 { return nil }
        let xn = cam.x / -cam.z
        let yn = cam.y / -cam.z
        let u = xn * intrinsics.fx + intrinsics.cx
        let v = yn * intrinsics.fy + intrinsics.cy
        return CGPoint(x: CGFloat(u), y: CGFloat(v))
    }

    /// Reproject a subset of 3D boundary points back to 2D image pixels.
    /// Used to render the L/W cross markers on top of the frozen frame.
    static func projectMarkerEndpoints(
        boundary3D: [SIMD3<Float>],
        indices: [Int],
        intrinsics: CameraIntrinsics,
        poseW2C: simd_float4x4
    ) -> [CGPoint] {
        var pixels = [CGPoint]()
        pixels.reserveCapacity(indices.count)
        for idx in indices {
            guard idx >= 0, idx < boundary3D.count else {
                pixels.append(.zero)
                continue
            }
            if let p = projectWorldToPixel(boundary3D[idx], intrinsics: intrinsics, poseW2C: poseW2C) {
                pixels.append(p)
            } else {
                pixels.append(.zero)
            }
        }
        return pixels
    }

    /// Standard ray-casting "point in polygon" test (works for any simple polygon).
    static func pointInPolygon(_ p: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            if ((pi.y > p.y) != (pj.y > p.y)),
               p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Axis-aligned bounding box of a polygon (used for fast vertex rejection).
    static func polygonBoundingBox(_ polygon: [CGPoint]) -> CGRect {
        guard let first = polygon.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in polygon.dropFirst() {
            if p.x < minX { minX = p.x }
            if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }
            if p.y > maxY { maxY = p.y }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
