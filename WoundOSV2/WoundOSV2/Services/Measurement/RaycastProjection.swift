import Foundation
import simd
import UIKit

/// Projects a 2D polygon (nurse-drawn boundary in image pixel coordinates)
/// into a 3D polygon (world space, meters) using the captured ARKit data.
///
/// Two strategies are supported:
/// 1. **Mesh ray-casting** — uses the ARMeshAnchor OBJ from the snapshot.
///    Slow but most accurate; falls back when sceneDepth is unavailable.
/// 2. **sceneDepth lookup** — samples `ARFrame.sceneDepth.depthMap` directly.
///    Fast (<10ms) and sub-mm at close range; preferred when LiDAR is available.
///
/// On-device, the simplest accurate approach is to back-project each 2D pixel
/// through the camera intrinsics + pose using the depth value at that pixel.
/// This is exactly what `ARSession.raycast` does internally; we replicate it
/// here so the math is deterministic and doesn't require a live ARSession
/// (we work from the frozen snapshot).
enum RaycastProjection {

    /// Projection error.
    enum Error: Swift.Error {
        case noDepthSource
        case allPointsMissedMesh
    }

    /// Result of projecting a single 2D point.
    struct ProjectionResult {
        let point3D: SIMD3<Float>      // ARKit world-space point in meters
        let validDepth: Bool            // false if depth was missing/clipped at this pixel
    }

    // MARK: - Mesh-based projection (preferred when we have an OBJ mesh)

    /// Parse the snapshot's OBJ mesh into vertices and faces.
    /// Used for ray-mesh intersection.
    static func parseOBJMesh(data: Data) -> (vertices: [SIMD3<Float>], faces: [SIMD3<Int>])? {
        guard let objText = String(data: data, encoding: .utf8) else { return nil }
        var vertices = [SIMD3<Float>]()
        var faces = [SIMD3<Int>]()
        for line in objText.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4 else { continue }
            if parts[0] == "v" {
                if let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3]) {
                    vertices.append(SIMD3<Float>(x, y, z))
                }
            } else if parts[0] == "f" {
                // OBJ is 1-indexed; can have v/vt/vn so split on '/'
                let parseIndex = { (s: Substring) -> Int? in
                    let token = s.split(separator: "/").first ?? s
                    return Int(token).map { $0 - 1 }
                }
                if let i0 = parseIndex(parts[1]),
                   let i1 = parseIndex(parts[2]),
                   let i2 = parseIndex(parts[3]) {
                    faces.append(SIMD3<Int>(i0, i1, i2))
                }
            }
        }
        return (vertices, faces)
    }

    /// Build a unit ray in world space from a 2D image pixel.
    /// ARKit camera convention: -Z is forward.
    static func ray(
        forPixel pixel: CGPoint,
        intrinsics: CameraIntrinsics,
        poseC2W: simd_float4x4
    ) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let fx = intrinsics.fx
        let fy = intrinsics.fy
        let cx = intrinsics.cx
        let cy = intrinsics.cy

        let xCam = (Float(pixel.x) - cx) / fx
        let yCam = (Float(pixel.y) - cy) / fy
        // ARKit -Z forward
        var dirCam = SIMD3<Float>(xCam, yCam, -1)
        dirCam = simd_normalize(dirCam)

        // Transform to world space using the rotation part of the pose
        let R = simd_float3x3(
            SIMD3<Float>(poseC2W.columns.0.x, poseC2W.columns.0.y, poseC2W.columns.0.z),
            SIMD3<Float>(poseC2W.columns.1.x, poseC2W.columns.1.y, poseC2W.columns.1.z),
            SIMD3<Float>(poseC2W.columns.2.x, poseC2W.columns.2.y, poseC2W.columns.2.z)
        )
        let dirWorld = simd_normalize(R * dirCam)

        let origin = SIMD3<Float>(
            poseC2W.columns.3.x,
            poseC2W.columns.3.y,
            poseC2W.columns.3.z
        )
        return (origin, dirWorld)
    }

    /// Möller–Trumbore ray-triangle intersection.
    /// Returns the t parameter (distance along ray) of the closest hit, or nil.
    static func rayTriangleIntersect(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        v0: SIMD3<Float>,
        v1: SIMD3<Float>,
        v2: SIMD3<Float>
    ) -> Float? {
        let edge1 = v1 - v0
        let edge2 = v2 - v0
        let h = simd_cross(direction, edge2)
        let a = simd_dot(edge1, h)
        if abs(a) < 1e-7 { return nil }
        let f = 1 / a
        let s = origin - v0
        let u = f * simd_dot(s, h)
        if u < 0 || u > 1 { return nil }
        let q = simd_cross(s, edge1)
        let v = f * simd_dot(direction, q)
        if v < 0 || (u + v) > 1 { return nil }
        let t = f * simd_dot(edge2, q)
        return t > 1e-6 ? t : nil
    }

    /// Project a 2D polygon onto the snapshot's mesh by ray-casting each vertex.
    /// Returns the resulting 3D world points and the number of misses (vertices that
    /// fell off the mesh — those are dropped).
    static func projectPolygonOntoMesh(
        polygon2D: [CGPoint],
        intrinsics: CameraIntrinsics,
        poseC2W: simd_float4x4,
        meshVertices: [SIMD3<Float>],
        meshFaces: [SIMD3<Int>]
    ) -> (world3D: [SIMD3<Float>], misses: Int) {
        var world3D = [SIMD3<Float>]()
        world3D.reserveCapacity(polygon2D.count)
        var misses = 0

        for pixel in polygon2D {
            let (origin, dir) = ray(forPixel: pixel, intrinsics: intrinsics, poseC2W: poseC2W)

            // Brute-force ray-mesh intersection. For typical cropped meshes
            // (a few thousand triangles), this completes in a few milliseconds.
            // If we ever need to scale, we can add a BVH/KD-tree.
            var bestT: Float = .infinity
            var hit: SIMD3<Float>? = nil

            for face in meshFaces {
                let v0 = meshVertices[face.x]
                let v1 = meshVertices[face.y]
                let v2 = meshVertices[face.z]
                if let t = rayTriangleIntersect(origin: origin, direction: dir, v0: v0, v1: v1, v2: v2) {
                    if t < bestT {
                        bestT = t
                        hit = origin + dir * t
                    }
                }
            }

            if let hit = hit {
                world3D.append(hit)
            } else {
                misses += 1
            }
        }

        return (world3D, misses)
    }

    // MARK: - Plane fallback (when no mesh is available)

    /// Fallback when the mesh is unavailable: assume the wound lies on a plane
    /// at `cameraToWoundDistanceMeters` and back-project all polygon points
    /// through the camera intrinsics into world space at that depth.
    /// This is much less accurate (no actual depth variation) but lets us still
    /// produce a measurement on non-LiDAR fallback.
    static func projectPolygonAtConstantDepth(
        polygon2D: [CGPoint],
        intrinsics: CameraIntrinsics,
        poseC2W: simd_float4x4,
        depthMeters: Float
    ) -> [SIMD3<Float>] {
        var world3D = [SIMD3<Float>]()
        world3D.reserveCapacity(polygon2D.count)
        for pixel in polygon2D {
            let (origin, dir) = ray(forPixel: pixel, intrinsics: intrinsics, poseC2W: poseC2W)
            world3D.append(origin + dir * depthMeters)
        }
        return world3D
    }
}
