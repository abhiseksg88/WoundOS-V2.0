import Foundation
import simd

struct DepthVolumeCalculator {
    static func calculateVolume(
        vertices: [simd_float3],
        triangleIndices: [Int],
        referencePlane: PlaneFitter.Plane
    ) -> (volume: Float, maxDepth: Float, avgDepth: Float) {
        var totalVolume: Float = 0
        var maxDepth: Float = 0
        var depthSum: Float = 0
        var depthCount: Int = 0

        let triangleCount = triangleIndices.count / 3

        for i in 0..<triangleCount {
            let i0 = triangleIndices[i * 3]
            let i1 = triangleIndices[i * 3 + 1]
            let i2 = triangleIndices[i * 3 + 2]

            guard i0 < vertices.count, i1 < vertices.count, i2 < vertices.count else { continue }

            let v0 = vertices[i0]
            let v1 = vertices[i1]
            let v2 = vertices[i2]

            let d0 = referencePlane.distanceTo(v0)
            let d1 = referencePlane.distanceTo(v1)
            let d2 = referencePlane.distanceTo(v2)

            // Only count below-plane triangles (wound cavity)
            if d0 < 0 || d1 < 0 || d2 < 0 {
                let avgDepthTri = abs(d0 + d1 + d2) / 3.0
                let edge1 = v1 - v0
                let edge2 = v2 - v0
                let area = simd_length(simd_cross(edge1, edge2)) / 2.0
                totalVolume += area * avgDepthTri

                for d in [d0, d1, d2] {
                    let absD = abs(d)
                    maxDepth = max(maxDepth, absD)
                    depthSum += absD
                    depthCount += 1
                }
            }
        }

        let avgDepth = depthCount > 0 ? depthSum / Float(depthCount) : 0
        return (totalVolume, maxDepth, avgDepth)
    }
}
