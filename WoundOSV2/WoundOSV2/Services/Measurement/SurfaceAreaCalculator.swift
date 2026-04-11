import Foundation
import simd

/// 3D surface area computation from triangle mesh.
///
/// Direct Swift port of `backend/pipeline/measurement/surface_area.py`.
enum SurfaceAreaCalculator {

    /// Triangle areas via the half cross-product norm.
    /// area_i = 0.5 * |(v1 - v0) × (v2 - v0)|
    static func computeTriangleAreasM2(
        vertices: [SIMD3<Float>],
        faces: [SIMD3<Int>]
    ) -> [Float] {
        var areas = [Float]()
        areas.reserveCapacity(faces.count)
        for face in faces {
            let v0 = vertices[face.x]
            let v1 = vertices[face.y]
            let v2 = vertices[face.z]
            let cross = simd_cross(v1 - v0, v2 - v0)
            areas.append(0.5 * simd_length(cross))
        }
        return areas
    }

    /// Sum of all (or masked) triangle areas in square meters.
    static func computeSurfaceAreaM2(
        vertices: [SIMD3<Float>],
        faces: [SIMD3<Int>],
        faceMask: [Bool]? = nil
    ) -> Double {
        let areas = computeTriangleAreasM2(vertices: vertices, faces: faces)
        var total: Double = 0
        if let mask = faceMask {
            precondition(mask.count == areas.count, "Face mask count must equal face count")
            for i in 0..<areas.count where mask[i] {
                total += Double(areas[i])
            }
        } else {
            for a in areas {
                total += Double(a)
            }
        }
        return total
    }

    /// Convenience: square centimeters (m² × 10000).
    static func computeSurfaceAreaCm2(
        vertices: [SIMD3<Float>],
        faces: [SIMD3<Int>],
        faceMask: [Bool]? = nil
    ) -> Double {
        return computeSurfaceAreaM2(vertices: vertices, faces: faces, faceMask: faceMask) * 10_000.0
    }

    // MARK: - Polygon area helper (no mesh)

    /// Compute the area of an arbitrary 3D polygon (not necessarily planar) using
    /// the Newell's method projected onto its best-fit plane.
    /// Used by the on-device pipeline when we have a nurse-drawn polygon and no mesh triangulation.
    /// Returns area in square meters.
    static func computePolygonAreaM2(polygon3D: [SIMD3<Float>]) -> Double {
        guard polygon3D.count >= 3 else { return 0 }

        // Newell's method: sum cross products to get the polygon's normal,
        // then half the magnitude is the area.
        var n = SIMD3<Float>(0, 0, 0)
        let count = polygon3D.count
        for i in 0..<count {
            let curr = polygon3D[i]
            let next = polygon3D[(i + 1) % count]
            n.x += (curr.y - next.y) * (curr.z + next.z)
            n.y += (curr.z - next.z) * (curr.x + next.x)
            n.z += (curr.x - next.x) * (curr.y + next.y)
        }
        return Double(0.5 * simd_length(n))
    }

    static func computePolygonAreaCm2(polygon3D: [SIMD3<Float>]) -> Double {
        return computePolygonAreaM2(polygon3D: polygon3D) * 10_000.0
    }
}
