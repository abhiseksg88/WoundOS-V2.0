import Foundation
import simd

/// Wound depth computation from a reference plane.
///
/// Direct Swift port of `backend/pipeline/measurement/depth_calc.py`.
enum DepthCalculator {

    /// Signed depth (in meters) of each vertex below the plane.
    /// Positive = below plane = wound depth. Negative = above plane.
    static func computeDepthsM(
        woundVertices: [SIMD3<Float>],
        planeCentroid: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) -> [Float] {
        var depths = [Float]()
        depths.reserveCapacity(woundVertices.count)
        for v in woundVertices {
            let offset = v - planeCentroid
            let signedDist = simd_dot(offset, planeNormal)
            // Depth is positive when below the plane (opposite to outward normal)
            depths.append(-signedDist)
        }
        return depths
    }

    /// Maximum positive depth in millimeters. Returns 0 if all points are above the plane.
    static func computeMaxDepthMm(
        woundVertices: [SIMD3<Float>],
        planeCentroid: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) -> Double {
        let depths = computeDepthsM(
            woundVertices: woundVertices,
            planeCentroid: planeCentroid,
            planeNormal: planeNormal
        )
        var maxDepth: Float = 0
        for d in depths where d > 0 {
            if d > maxDepth { maxDepth = d }
        }
        return Double(maxDepth) * 1000.0
    }

    /// Mean positive depth in millimeters.
    static func computeAvgDepthMm(
        woundVertices: [SIMD3<Float>],
        planeCentroid: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) -> Double {
        let depths = computeDepthsM(
            woundVertices: woundVertices,
            planeCentroid: planeCentroid,
            planeNormal: planeNormal
        )
        var sum: Float = 0
        var count: Int = 0
        for d in depths where d > 0 {
            sum += d
            count += 1
        }
        guard count > 0 else { return 0 }
        return Double(sum / Float(count)) * 1000.0
    }

    /// Locate the deepest 3D point and its depth in mm.
    static func findDeepestPoint(
        woundVertices: [SIMD3<Float>],
        planeCentroid: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) -> (point: SIMD3<Float>, depthMm: Double)? {
        let depths = computeDepthsM(
            woundVertices: woundVertices,
            planeCentroid: planeCentroid,
            planeNormal: planeNormal
        )
        guard !depths.isEmpty else { return nil }
        var maxIdx = 0
        var maxDepth = depths[0]
        for i in 1..<depths.count where depths[i] > maxDepth {
            maxDepth = depths[i]
            maxIdx = i
        }
        return (woundVertices[maxIdx], Double(maxDepth) * 1000.0)
    }
}
