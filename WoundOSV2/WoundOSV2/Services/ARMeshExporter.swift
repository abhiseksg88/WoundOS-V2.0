import Foundation
import ARKit
import Metal
import simd

/// Serializes ARKit scene reconstruction mesh anchors to Wavefront OBJ format.
///
/// ARKit provides per-anchor `ARMeshGeometry` containing:
/// - `vertices`: MTLBuffer of `simd_float3` in the anchor's local space
/// - `faces`: MTLBuffer of triangle indices (typically `UInt32`)
/// - `anchor.transform`: 4x4 local-to-world transform
///
/// We transform every vertex into world space, then merge all anchors into
/// a single OBJ document with 1-indexed face references.
///
/// **Threading**: This must run on a background queue, and the ARSession
/// should be paused before calling, so the anchor list is stable and Metal
/// buffer access is safe.
enum ARMeshExporter {

    /// Serialize all provided mesh anchors into a single Wavefront OBJ.
    ///
    /// - Parameters:
    ///   - anchors: Snapshot of `ARMeshAnchor` objects collected during capture.
    ///   - cropCenterWorld: Optional world-space center for sphere cropping.
    ///   - cropRadius: Optional crop radius in meters. Triangles whose centroid
    ///     falls outside the sphere are skipped. Use ~0.20m to limit the upload
    ///     to the wound region only (HIPAA + bandwidth).
    /// - Returns: UTF-8 encoded OBJ bytes, or nil if all anchors empty.
    static func serializeToOBJ(
        anchors: [ARMeshAnchor],
        cropCenterWorld: SIMD3<Float>? = nil,
        cropRadius: Float? = nil
    ) -> Data? {
        guard !anchors.isEmpty else { return nil }

        var output = String()
        output.reserveCapacity(1024 * 1024)  // 1 MB initial

        output += "# WoundOS V2 — ARKit LiDAR mesh export\n"
        output += "# Anchors: \(anchors.count)\n"
        if let center = cropCenterWorld, let radius = cropRadius {
            output += "# Crop sphere: center=(\(center.x),\(center.y),\(center.z)) radius=\(radius)m\n"
        }

        var globalVertexBase: Int = 0  // 1-indexed running total

        for (anchorIdx, anchor) in anchors.enumerated() {
            let geometry = anchor.geometry
            let transform = anchor.transform

            // Extract vertices into world space
            let worldVertices = extractWorldVertices(geometry: geometry, transform: transform)
            if worldVertices.isEmpty {
                continue
            }

            // Extract triangle indices (local to this anchor)
            let localFaces = extractFaces(geometry: geometry)
            if localFaces.isEmpty {
                continue
            }

            // Optional sphere cropping: keep only triangles with centroid inside sphere
            // Build a remap from original local index → new local index for kept vertices
            var keptVertexIndices: [Int] = []
            var oldToNewIndex: [Int: Int] = [:]
            var keptFaces: [(Int, Int, Int)] = []

            for (i0, i1, i2) in localFaces {
                guard i0 < worldVertices.count,
                      i1 < worldVertices.count,
                      i2 < worldVertices.count else { continue }

                let v0 = worldVertices[i0]
                let v1 = worldVertices[i1]
                let v2 = worldVertices[i2]

                if let center = cropCenterWorld, let radius = cropRadius {
                    let centroid = (v0 + v1 + v2) / 3.0
                    let distance = simd_length(centroid - center)
                    if distance > radius { continue }
                }

                // Add the 3 vertices to the kept set if not already present
                let newIdxs: [Int] = [i0, i1, i2].map { oldIdx in
                    if let existing = oldToNewIndex[oldIdx] {
                        return existing
                    }
                    let newIdx = keptVertexIndices.count
                    oldToNewIndex[oldIdx] = newIdx
                    keptVertexIndices.append(oldIdx)
                    return newIdx
                }
                keptFaces.append((newIdxs[0], newIdxs[1], newIdxs[2]))
            }

            if keptFaces.isEmpty { continue }

            output += "\n# Anchor \(anchorIdx) — \(keptVertexIndices.count) vertices, \(keptFaces.count) faces\n"

            // Emit vertices (1-indexed in OBJ)
            for localIdx in keptVertexIndices {
                let v = worldVertices[localIdx]
                output += "v \(v.x) \(v.y) \(v.z)\n"
            }

            // Emit faces (1-indexed and offset by globalVertexBase)
            for (a, b, c) in keptFaces {
                let i1 = globalVertexBase + a + 1
                let i2 = globalVertexBase + b + 1
                let i3 = globalVertexBase + c + 1
                output += "f \(i1) \(i2) \(i3)\n"
            }

            globalVertexBase += keptVertexIndices.count
        }

        if globalVertexBase == 0 {
            // No vertices survived the crop
            return nil
        }

        return output.data(using: .utf8)
    }

    // MARK: - Private helpers

    /// Extract every vertex from ARMeshGeometry and transform into world space.
    /// Reads MTLBuffer using `vertices.stride` (do NOT assume 12-byte stride).
    private static func extractWorldVertices(
        geometry: ARMeshGeometry,
        transform: simd_float4x4
    ) -> [SIMD3<Float>] {
        let vertices = geometry.vertices
        let count = vertices.count
        let stride = vertices.stride
        let offset = vertices.offset
        let buffer = vertices.buffer
        let pointer = buffer.contents().advanced(by: offset)

        guard count > 0 else { return [] }

        var result: [SIMD3<Float>] = []
        result.reserveCapacity(count)

        for i in 0..<count {
            let vertexPointer = pointer.advanced(by: i * stride)
            let local = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            // Transform to world space: anchor.transform * (vec4(local, 1))
            let worldVec4 = transform * SIMD4<Float>(local.x, local.y, local.z, 1.0)
            result.append(SIMD3<Float>(worldVec4.x, worldVec4.y, worldVec4.z))
        }
        return result
    }

    /// Extract triangle face indices from ARMeshGeometry.
    /// Handles both UInt16 and UInt32 index buffers.
    private static func extractFaces(geometry: ARMeshGeometry) -> [(Int, Int, Int)] {
        let faces = geometry.faces
        let primCount = faces.count
        let bytesPerIndex = faces.bytesPerIndex
        let buffer = faces.buffer
        let pointer = buffer.contents()

        guard primCount > 0, faces.indexCountPerPrimitive == 3 else { return [] }

        var result: [(Int, Int, Int)] = []
        result.reserveCapacity(primCount)

        if bytesPerIndex == 2 {
            // UInt16 indices
            for prim in 0..<primCount {
                let base = prim * 3 * 2
                let i0 = Int(pointer.load(fromByteOffset: base, as: UInt16.self))
                let i1 = Int(pointer.load(fromByteOffset: base + 2, as: UInt16.self))
                let i2 = Int(pointer.load(fromByteOffset: base + 4, as: UInt16.self))
                result.append((i0, i1, i2))
            }
        } else if bytesPerIndex == 4 {
            // UInt32 indices
            for prim in 0..<primCount {
                let base = prim * 3 * 4
                let i0 = Int(pointer.load(fromByteOffset: base, as: UInt32.self))
                let i1 = Int(pointer.load(fromByteOffset: base + 4, as: UInt32.self))
                let i2 = Int(pointer.load(fromByteOffset: base + 8, as: UInt32.self))
                result.append((i0, i1, i2))
            }
        } else {
            // Unsupported index size
            return []
        }

        return result
    }

    /// Compute the axis-aligned bounding box of an OBJ-like vertex set.
    /// Used for telemetry / payload diagnostics.
    static func computeBounds(anchors: [ARMeshAnchor]) -> SIMD3<Float> {
        var minPt = SIMD3<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude)
        var maxPt = SIMD3<Float>(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
        for anchor in anchors {
            let verts = extractWorldVertices(geometry: anchor.geometry, transform: anchor.transform)
            for v in verts {
                minPt = simd_min(minPt, v)
                maxPt = simd_max(maxPt, v)
            }
        }
        return maxPt - minPt
    }
}
