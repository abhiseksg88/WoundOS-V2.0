import Foundation
import simd

/// Wound volume computation via prism decomposition + divergence theorem.
///
/// Direct Swift port of `backend/pipeline/measurement/volume.py`.
enum VolumeCalculator {

    /// Closed-mesh signed volume via the divergence theorem.
    /// V = (1/6) * sum(v0 · (v1 × v2))
    /// Always returns the magnitude.
    static func computeVolumeDivergenceM3(
        woundVertices: [SIMD3<Float>],
        woundFaces: [SIMD3<Int>]
    ) -> Double {
        guard !woundFaces.isEmpty else { return 0 }
        var signedVolume: Double = 0
        for face in woundFaces {
            let v0 = woundVertices[face.x]
            let v1 = woundVertices[face.y]
            let v2 = woundVertices[face.z]
            let cross = simd_cross(v1, v2)
            let contrib = simd_dot(v0, cross)
            signedVolume += Double(contrib)
        }
        return abs(signedVolume) / 6.0
    }

    /// Triangular prism decomposition.
    /// For each wound triangle, project its vertices onto the reference plane,
    /// then sum the three tetrahedra that fill the prism between the triangle
    /// and its plane projection.
    static func computeVolumePrismM3(
        woundVertices: [SIMD3<Float>],
        woundFaces: [SIMD3<Int>],
        planeCentroid: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) -> Double {
        guard !woundFaces.isEmpty else { return 0 }

        let normal = simd_normalize(planeNormal)
        var totalVolume: Double = 0

        for face in woundFaces {
            let v = [
                woundVertices[face.x],
                woundVertices[face.y],
                woundVertices[face.z],
            ]

            // Project each triangle vertex onto the plane
            var p = [SIMD3<Float>](repeating: .zero, count: 3)
            for i in 0..<3 {
                let dist = simd_dot(v[i] - planeCentroid, normal)
                p[i] = v[i] - dist * normal
            }

            // Three tetrahedra that fill the prism (v0,v1,v2) → (p0,p1,p2)
            let tetras: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
                (v[0], v[1], v[2], p[0]),
                (v[1], v[2], p[0], p[1]),
                (v[2], p[0], p[1], p[2]),
            ]

            for (a, b, c, d) in tetras {
                let cross = simd_cross(c - a, d - a)
                let vol = abs(simd_dot(b - a, cross)) / 6.0
                totalVolume += Double(vol)
            }
        }
        return totalVolume
    }

    /// Convenience: convert from cubic meters to milliliters (1 m³ = 1e6 mL).
    static func computeVolumeMl(
        woundVertices: [SIMD3<Float>],
        woundFaces: [SIMD3<Int>],
        planeCentroid: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) -> Double {
        let m3 = computeVolumePrismM3(
            woundVertices: woundVertices,
            woundFaces: woundFaces,
            planeCentroid: planeCentroid,
            planeNormal: planeNormal
        )
        return m3 * 1_000_000.0
    }
}
