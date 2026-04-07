import Foundation
import simd

struct DimensionCalculator {
    struct Dimensions {
        let length: Float // Greatest length
        let width: Float // Greatest width perpendicular to length
        let perimeter: Float
    }

    static func calculateDimensions(boundaryPoints: [simd_float2]) -> Dimensions {
        guard boundaryPoints.count >= 3 else {
            return Dimensions(length: 0, width: 0, perimeter: 0)
        }

        // Calculate perimeter
        var perimeter: Float = 0
        for i in 0..<boundaryPoints.count {
            let j = (i + 1) % boundaryPoints.count
            perimeter += simd_distance(boundaryPoints[i], boundaryPoints[j])
        }

        // Find greatest length using rotating calipers (simplified: brute force for small point counts)
        var maxLength: Float = 0
        var lengthP0 = simd_float2.zero
        var lengthP1 = simd_float2.zero

        for i in 0..<boundaryPoints.count {
            for j in (i + 1)..<boundaryPoints.count {
                let dist = simd_distance(boundaryPoints[i], boundaryPoints[j])
                if dist > maxLength {
                    maxLength = dist
                    lengthP0 = boundaryPoints[i]
                    lengthP1 = boundaryPoints[j]
                }
            }
        }

        // Find greatest width perpendicular to length axis
        let lengthAxis = simd_normalize(lengthP1 - lengthP0)
        let perpAxis = simd_float2(-lengthAxis.y, lengthAxis.x)

        var minProj: Float = .greatestFiniteMagnitude
        var maxProj: Float = -.greatestFiniteMagnitude

        for p in boundaryPoints {
            let proj = simd_dot(p - lengthP0, perpAxis)
            minProj = min(minProj, proj)
            maxProj = max(maxProj, proj)
        }

        let width = maxProj - minProj

        return Dimensions(length: maxLength, width: width, perimeter: perimeter)
    }
}
