import Foundation
import simd

/// Length, width, and perimeter computation.
///
/// Direct Swift port of `backend/pipeline/measurement/dimensions.py`.
/// - Length: greatest pairwise distance between projected boundary points
/// - Width: greatest extent perpendicular to the length axis
/// - Perimeter: sum of 3D edge lengths along the boundary path
enum DimensionCalculator {

    /// Project 3D boundary points onto the wound plane and return 2D (u, v) coordinates.
    /// The plane's local coordinate system is built from a non-parallel reference vector.
    static func projectToPlane(
        points3D: [SIMD3<Float>],
        planeCentroid: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) -> [SIMD2<Float>] {
        let normal = simd_normalize(planeNormal)
        let ref: SIMD3<Float> = abs(normal.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
        var axisU = simd_cross(normal, ref)
        axisU = simd_normalize(axisU)
        var axisV = simd_cross(normal, axisU)
        axisV = simd_normalize(axisV)

        var result = [SIMD2<Float>]()
        result.reserveCapacity(points3D.count)
        for p in points3D {
            let centered = p - planeCentroid
            let u = simd_dot(centered, axisU)
            let v = simd_dot(centered, axisV)
            result.append(SIMD2<Float>(u, v))
        }
        return result
    }

    /// Result of the length/width computation, including the boundary indices
    /// of the L and W axis endpoints (used to draw the cross markers).
    struct LengthWidthResult {
        let lengthMm: Double
        let widthMm: Double
        let lengthEndpointA: Int  // boundary index
        let lengthEndpointB: Int
        let widthEndpointA: Int
        let widthEndpointB: Int
    }

    /// Compute greatest length, perpendicular width, and the boundary indices
    /// of the four endpoints (matches `compute_length_width_with_endpoints` in Python).
    static func computeLengthWidthWithEndpoints(
        boundaryPoints3D: [SIMD3<Float>],
        planeCentroid: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) -> LengthWidthResult {
        guard boundaryPoints3D.count >= 2 else {
            return LengthWidthResult(
                lengthMm: 0, widthMm: 0,
                lengthEndpointA: 0, lengthEndpointB: 0,
                widthEndpointA: 0, widthEndpointB: 0
            )
        }

        let pts2D = projectToPlane(
            points3D: boundaryPoints3D,
            planeCentroid: planeCentroid,
            planeNormal: planeNormal
        )

        // Greatest pairwise distance — O(n^2), n usually < 500
        let n = pts2D.count
        var maxDist: Float = 0
        var p1Idx = 0
        var p2Idx = 1

        for i in 0..<n {
            for j in (i + 1)..<n {
                let d = simd_distance(pts2D[i], pts2D[j])
                if d > maxDist {
                    maxDist = d
                    p1Idx = i
                    p2Idx = j
                }
            }
        }

        let lengthM = maxDist
        if lengthM < 1e-10 {
            return LengthWidthResult(
                lengthMm: 0, widthMm: 0,
                lengthEndpointA: 0, lengthEndpointB: 0,
                widthEndpointA: 0, widthEndpointB: 0
            )
        }

        // Length axis direction
        var lengthDir = pts2D[p2Idx] - pts2D[p1Idx]
        lengthDir = simd_normalize(lengthDir)

        // Perpendicular axis (rotate 90°)
        let perpDir = SIMD2<Float>(-lengthDir.y, lengthDir.x)

        // Project all points onto perpendicular axis to find width extent
        var minProj: Float = .infinity
        var maxProj: Float = -.infinity
        var perpMinIdx = 0
        var perpMaxIdx = 0
        for i in 0..<n {
            let proj = simd_dot(pts2D[i], perpDir)
            if proj < minProj { minProj = proj; perpMinIdx = i }
            if proj > maxProj { maxProj = proj; perpMaxIdx = i }
        }

        let widthM = maxProj - minProj

        return LengthWidthResult(
            lengthMm: Double(lengthM) * 1000,
            widthMm: Double(widthM) * 1000,
            lengthEndpointA: p1Idx,
            lengthEndpointB: p2Idx,
            widthEndpointA: perpMinIdx,
            widthEndpointB: perpMaxIdx
        )
    }

    /// Convenience wrapper that drops endpoint indices.
    static func computeLengthWidthMm(
        boundaryPoints3D: [SIMD3<Float>],
        planeCentroid: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) -> (lengthMm: Double, widthMm: Double) {
        let r = computeLengthWidthWithEndpoints(
            boundaryPoints3D: boundaryPoints3D,
            planeCentroid: planeCentroid,
            planeNormal: planeNormal
        )
        return (r.lengthMm, r.widthMm)
    }

    /// Sum of consecutive 3D edge lengths along the boundary.
    /// Treats the boundary as a closed polygon (last → first).
    static func computePerimeterMm(boundaryPoints3D: [SIMD3<Float>]) -> Double {
        guard boundaryPoints3D.count >= 2 else { return 0 }
        var sum: Float = 0
        let count = boundaryPoints3D.count
        for i in 0..<count {
            let next = (i + 1) % count
            sum += simd_distance(boundaryPoints3D[i], boundaryPoints3D[next])
        }
        return Double(sum) * 1000
    }
}
