import Foundation
import simd

struct SurfaceAreaCalculator {
    static func calculateArea(vertices: [simd_float3], triangleIndices: [Int]) -> Float {
        var totalArea: Float = 0
        let triangleCount = triangleIndices.count / 3

        for i in 0..<triangleCount {
            let i0 = triangleIndices[i * 3]
            let i1 = triangleIndices[i * 3 + 1]
            let i2 = triangleIndices[i * 3 + 2]

            guard i0 < vertices.count, i1 < vertices.count, i2 < vertices.count else { continue }

            let v0 = vertices[i0]
            let v1 = vertices[i1]
            let v2 = vertices[i2]

            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let crossProduct = simd_cross(edge1, edge2)
            totalArea += simd_length(crossProduct) / 2.0
        }

        return totalArea
    }

    static func projectedArea(boundaryPoints: [simd_float2]) -> Float {
        guard boundaryPoints.count >= 3 else { return 0 }

        // Shoelace formula for polygon area
        var area: Float = 0
        let n = boundaryPoints.count

        for i in 0..<n {
            let j = (i + 1) % n
            area += boundaryPoints[i].x * boundaryPoints[j].y
            area -= boundaryPoints[j].x * boundaryPoints[i].y
        }

        return abs(area) / 2.0
    }
}
