import Foundation
import Accelerate
import simd

struct PlaneFitter {
    struct Plane {
        let normal: simd_float3
        let point: simd_float3
        let d: Float

        func distanceTo(_ p: simd_float3) -> Float {
            simd_dot(normal, p - point)
        }
    }

    static func fitPlane(to points: [simd_float3]) -> Plane? {
        guard points.count >= 3 else { return nil }

        // Compute centroid
        var centroid = simd_float3.zero
        for p in points { centroid += p }
        centroid /= Float(points.count)

        // Build covariance matrix
        var xx: Float = 0, xy: Float = 0, xz: Float = 0
        var yy: Float = 0, yz: Float = 0, zz: Float = 0

        for p in points {
            let r = p - centroid
            xx += r.x * r.x
            xy += r.x * r.y
            xz += r.x * r.z
            yy += r.y * r.y
            yz += r.y * r.z
            zz += r.z * r.z
        }

        let det_x = yy * zz - yz * yz
        let det_y = xx * zz - xz * xz
        let det_z = xx * yy - xy * xy

        let maxDet = max(det_x, max(det_y, det_z))
        guard maxDet > 0 else { return nil }

        var normal: simd_float3
        if maxDet == det_x {
            normal = simd_float3(det_x, xz * yz - xy * zz, xy * yz - xz * yy)
        } else if maxDet == det_y {
            normal = simd_float3(xz * yz - xy * zz, det_y, xy * xz - yz * xx)
        } else {
            normal = simd_float3(xy * yz - xz * yy, xy * xz - yz * xx, det_z)
        }

        normal = simd_normalize(normal)
        let d = -simd_dot(normal, centroid)

        return Plane(normal: normal, point: centroid, d: d)
    }
}
