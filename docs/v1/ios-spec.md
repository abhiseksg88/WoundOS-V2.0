# WoundOS Pro v1 — iOS Implementation Specification

**Target**: iPhone 12 Pro+ (LiDAR required), iOS 16+
**Branch**: `feature/v1-lidar-ondevice`

---

## 1. Architecture Overview

```
Nurse opens app → ARKit + LiDAR runs silently
    → Nurse taps shutter → SnapshotService freezes ARFrame
    → Frozen frame displayed → Nurse draws boundary (BezierPathEngine)
    → BoundaryProjector3D converts 2D → 3D using LiDAR depth
    → OnDeviceMeasurementEngine computes area/depth/volume/L×W
    → ResultsView displays measurements
    → ScanUploadService syncs to backend (async, when online)
```

**On-device (offline)**: Capture, boundary drawing, 3D projection, all measurements, results display, PDF reports, Core Data persistence.

**Backend (async, when online)**: Scan metadata storage, SAM 2 shadow validation, clinical summary (Claude Haiku).

---

## 2. New Files to Create

### 2a. `Models/WoundCaptureSnapshot.swift`

```swift
import ARKit
import UIKit

struct WoundCaptureSnapshot {
    let rgbImage: UIImage
    let depthMap: CVPixelBuffer       // Float32, typically 256×192
    let confidenceMap: CVPixelBuffer? // ARConfidenceLevel, same dims
    let meshAnchors: [ARMeshAnchor]
    let cameraPose: CameraPose        // Existing model
    let cameraIntrinsics: CameraIntrinsics // Existing model
    let timestamp: TimeInterval
    let depthWidth: Int
    let depthHeight: Int
    let imageWidth: Int
    let imageHeight: Int

    /// Scale factors from image pixel coords to depth map coords
    var depthScaleX: Float { Float(depthWidth) / Float(imageWidth) }
    var depthScaleY: Float { Float(depthHeight) / Float(imageHeight) }
}
```

**Integration**: Created by `SnapshotService`, consumed by `BoundaryProjector3D` and `OnDeviceMeasurementEngine`.

---

### 2b. `Services/SnapshotService.swift`

```swift
import ARKit
import UIKit

final class SnapshotService {

    /// Capture the current ARFrame state as a frozen snapshot.
    /// Returns nil if tracking is not normal or sceneDepth unavailable.
    static func captureSnapshot(from session: ARSession) -> WoundCaptureSnapshot? {
        guard let frame = session.currentFrame else { return nil }
        guard frame.camera.trackingState == .normal else { return nil }
        guard let sceneDepth = frame.sceneDepth else { return nil }

        let depthBuffer = sceneDepth.depthMap
        let confidenceBuffer = sceneDepth.confidenceMap

        let depthW = CVPixelBufferGetWidth(depthBuffer)
        let depthH = CVPixelBufferGetHeight(depthBuffer)

        // Convert ARFrame pixel buffer to UIImage
        let ciImage = CIImage(cvPixelBuffer: frame.capturedImage)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        let rgbImage = UIImage(cgImage: cgImage)

        let imageW = Int(frame.camera.imageResolution.width)
        let imageH = Int(frame.camera.imageResolution.height)

        // Extract pose using existing ARSessionManager helper
        let t = frame.camera.transform
        let matrix: [[Float]] = [
            [t.columns.0.x, t.columns.1.x, t.columns.2.x, t.columns.3.x],
            [t.columns.0.y, t.columns.1.y, t.columns.2.y, t.columns.3.y],
            [t.columns.0.z, t.columns.1.z, t.columns.2.z, t.columns.3.z],
            [t.columns.0.w, t.columns.1.w, t.columns.2.w, t.columns.3.w]
        ]
        let pose = CameraPose(timestamp: frame.timestamp, transform: matrix)

        // Extract intrinsics
        let intr = frame.camera.intrinsics
        let intrinsics = CameraIntrinsics(
            fx: intr[0][0], fy: intr[1][1],
            cx: intr[2][0], cy: intr[2][1],
            width: imageW, height: imageH
        )

        // Collect mesh anchors
        let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }

        return WoundCaptureSnapshot(
            rgbImage: rgbImage,
            depthMap: depthBuffer,
            confidenceMap: confidenceBuffer,
            meshAnchors: meshAnchors,
            cameraPose: pose,
            cameraIntrinsics: intrinsics,
            timestamp: frame.timestamp,
            depthWidth: depthW,
            depthHeight: depthH,
            imageWidth: imageW,
            imageHeight: imageH
        )
    }
}
```

---

### 2c. `Utilities/DepthMapUtils.swift`

```swift
import ARKit
import simd

struct DepthMapUtils {

    /// Read depth value (meters) from LiDAR depth buffer at a given image pixel.
    /// Handles resolution scaling: depth map is 256×192 while image may be 4032×3024.
    static func depthAtPixel(
        _ pixel: CGPoint,
        depthBuffer: CVPixelBuffer,
        imageWidth: Int,
        imageHeight: Int
    ) -> Float? {
        let depthW = CVPixelBufferGetWidth(depthBuffer)
        let depthH = CVPixelBufferGetHeight(depthBuffer)

        // Scale image pixel to depth map pixel
        let dx = Int(Float(pixel.x) * Float(depthW) / Float(imageWidth))
        let dy = Int(Float(pixel.y) * Float(depthH) / Float(imageHeight))

        guard dx >= 0, dx < depthW, dy >= 0, dy < depthH else { return nil }

        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
        let pointer = baseAddress.advanced(by: dy * bytesPerRow)
            .assumingMemoryBound(to: Float32.self)
        let depth = pointer[dx]

        guard depth.isFinite, depth > 0 else { return nil }
        return depth
    }

    /// Unproject a 2D image pixel + depth to 3D world coordinates.
    /// Uses camera intrinsics for unprojection and camera pose for world transform.
    static func unprojectToWorld(
        pixel: CGPoint,
        depth: Float,
        intrinsics: CameraIntrinsics,
        pose: CameraPose
    ) -> simd_float3 {
        // Unproject to camera space
        // ARKit camera: X-right, Y-up, Z-toward-viewer (negative Z is forward)
        let x_cam = (Float(pixel.x) - intrinsics.cx) * depth / intrinsics.fx
        let y_cam = (Float(pixel.y) - intrinsics.cy) * depth / intrinsics.fy
        let z_cam = -depth  // ARKit: negative Z is forward from camera

        let pointCam = simd_float4(x_cam, y_cam, z_cam, 1.0)

        // Camera-to-world transform from pose (4x4 row-major matrix)
        let t = pose.transform
        let c2w = simd_float4x4(
            simd_float4(t[0][0], t[0][1], t[0][2], t[0][3]),
            simd_float4(t[1][0], t[1][1], t[1][2], t[1][3]),
            simd_float4(t[2][0], t[2][1], t[2][2], t[2][3]),
            simd_float4(t[3][0], t[3][1], t[3][2], t[3][3])
        )

        let pointWorld = c2w * pointCam
        return simd_float3(pointWorld.x, pointWorld.y, pointWorld.z)
    }
}
```

---

### 2d. `Services/BoundaryProjector3D.swift`

```swift
import simd
import CoreGraphics

final class BoundaryProjector3D {

    /// Project nurse-drawn 2D boundary to 3D world coordinates using LiDAR depth.
    ///
    /// For each 2D point:
    /// 1. Look up depth from LiDAR depth map (scaling from image to depth resolution)
    /// 2. Unproject to camera space using intrinsics
    /// 3. Transform to world space using camera pose
    ///
    /// Points where depth is unavailable (NaN, 0, out of range) are skipped.
    static func projectBoundaryTo3D(
        boundary2D: [CGPoint],
        snapshot: WoundCaptureSnapshot
    ) -> [simd_float3] {
        var points3D: [simd_float3] = []
        points3D.reserveCapacity(boundary2D.count)

        for point2D in boundary2D {
            guard let depth = DepthMapUtils.depthAtPixel(
                point2D,
                depthBuffer: snapshot.depthMap,
                imageWidth: snapshot.imageWidth,
                imageHeight: snapshot.imageHeight
            ) else {
                continue // Skip points with no valid depth
            }

            let point3D = DepthMapUtils.unprojectToWorld(
                pixel: point2D,
                depth: depth,
                intrinsics: snapshot.cameraIntrinsics,
                pose: snapshot.cameraPose
            )
            points3D.append(point3D)
        }

        return points3D
    }

    /// Extract wound submesh from ARMeshAnchor geometry.
    ///
    /// For each mesh triangle:
    /// 1. Project triangle center to 2D image space
    /// 2. Check if center is inside the nurse boundary polygon
    /// 3. Collect vertices and faces of wound-interior triangles
    static func extractWoundSubmesh(
        meshAnchors: [ARMeshAnchor],
        boundary2D: [CGPoint],
        snapshot: WoundCaptureSnapshot
    ) -> (vertices: [simd_float3], triangleIndices: [Int]) {
        var allVertices: [simd_float3] = []
        var allIndices: [Int] = []

        let intr = snapshot.cameraIntrinsics
        let pose = snapshot.cameraPose

        // Build camera-to-world and world-to-camera matrices
        let t = pose.transform
        let c2w = simd_float4x4(
            simd_float4(t[0][0], t[0][1], t[0][2], t[0][3]),
            simd_float4(t[1][0], t[1][1], t[1][2], t[1][3]),
            simd_float4(t[2][0], t[2][1], t[2][2], t[2][3]),
            simd_float4(t[3][0], t[3][1], t[3][2], t[3][3])
        )
        let w2c = c2w.inverse

        for anchor in meshAnchors {
            let anchorTransform = anchor.transform
            let geometry = anchor.geometry
            let vertexBuffer = geometry.vertices
            let faceBuffer = geometry.faces

            let vertexCount = vertexBuffer.count
            let faceCount = faceBuffer.count

            // Extract vertices in world space
            var meshVertices: [simd_float3] = []
            for i in 0..<vertexCount {
                let localPos = vertexBuffer.asSIMD(index: i)
                let worldPos4 = anchorTransform * simd_float4(localPos, 1.0)
                meshVertices.append(simd_float3(worldPos4.x, worldPos4.y, worldPos4.z))
            }

            // Check each face
            let indexBuffer = faceBuffer.buffer
            let bytesPerIndex = faceBuffer.bytesPerIndex
            let indicesPerFace = faceBuffer.indexCountPerPrimitive

            for f in 0..<faceCount {
                // Read face indices
                var faceIndices: [Int] = []
                for j in 0..<indicesPerFace {
                    let offset = (f * indicesPerFace + j) * bytesPerIndex
                    let index: Int
                    if bytesPerIndex == 4 {
                        index = Int(indexBuffer.contents()
                            .advanced(by: offset)
                            .assumingMemoryBound(to: UInt32.self).pointee)
                    } else {
                        index = Int(indexBuffer.contents()
                            .advanced(by: offset)
                            .assumingMemoryBound(to: UInt16.self).pointee)
                    }
                    faceIndices.append(index)
                }

                guard faceIndices.count == 3 else { continue }

                // Compute triangle center in world space
                let v0 = meshVertices[faceIndices[0]]
                let v1 = meshVertices[faceIndices[1]]
                let v2 = meshVertices[faceIndices[2]]
                let center = (v0 + v1 + v2) / 3.0

                // Project center to 2D image space
                let camPos4 = w2c * simd_float4(center, 1.0)
                let camPos = simd_float3(camPos4.x, camPos4.y, camPos4.z)

                guard camPos.z < 0 else { continue } // Behind camera

                let px = intr.fx * (camPos.x / -camPos.z) + intr.cx
                let py = intr.fy * (camPos.y / -camPos.z) + intr.cy

                let projected = CGPoint(x: CGFloat(px), y: CGFloat(py))

                // Check if inside boundary polygon
                if isPointInsidePolygon(projected, polygon: boundary2D) {
                    let baseIdx = allVertices.count
                    allVertices.append(contentsOf: [v0, v1, v2])
                    allIndices.append(contentsOf: [baseIdx, baseIdx + 1, baseIdx + 2])
                }
            }
        }

        return (allVertices, allIndices)
    }

    /// Ray-casting point-in-polygon test.
    private static func isPointInsidePolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        let n = polygon.count
        var j = n - 1
        for i in 0..<n {
            let pi = polygon[i], pj = polygon[j]
            if (pi.y > point.y) != (pj.y > point.y) {
                let intersectX = (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x
                if point.x < intersectX { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}

// Helper to read ARMeshGeometry vertex data
extension ARGeometrySource {
    func asSIMD(index: Int) -> simd_float3 {
        let ptr = buffer.contents().advanced(by: offset + stride * index)
        let floats = ptr.assumingMemoryBound(to: Float.self)
        return simd_float3(floats[0], floats[1], floats[2])
    }
}
```

---

### 2e. `Services/OnDeviceMeasurementEngine.swift`

```swift
import simd
import CoreGraphics

final class OnDeviceMeasurementEngine {

    /// Compute all wound measurements from a captured snapshot and nurse-drawn boundary.
    ///
    /// Pipeline:
    /// 1. Project 2D boundary to 3D using LiDAR depth
    /// 2. Extract wound submesh from ARMeshAnchors
    /// 3. Fit reference plane (RANSAC on boundary points)
    /// 4. Compute area, depth, volume, length, width, perimeter
    /// 5. Return WoundMeasurement (existing model)
    static func computeMeasurements(
        snapshot: WoundCaptureSnapshot,
        boundary2D: [CGPoint]
    ) -> WoundMeasurement {

        // Step 1: Project boundary to 3D
        let boundary3D = BoundaryProjector3D.projectBoundaryTo3D(
            boundary2D: boundary2D,
            snapshot: snapshot
        )

        guard boundary3D.count >= 3 else {
            return WoundMeasurement() // All zeros
        }

        // Step 2: Extract wound submesh from ARMeshAnchors
        let (woundVertices, woundIndices) = BoundaryProjector3D.extractWoundSubmesh(
            meshAnchors: snapshot.meshAnchors,
            boundary2D: boundary2D,
            snapshot: snapshot
        )

        // Step 3: Fit reference plane on boundary points
        guard let plane = PlaneFitter.fitPlane(to: boundary3D) else {
            return WoundMeasurement()
        }

        // Step 4a: Surface area (m² → cm²)
        let areaCm2: Double
        if woundVertices.count >= 3 && woundIndices.count >= 3 {
            let areaM2 = SurfaceAreaCalculator.calculateArea(
                vertices: woundVertices,
                triangleIndices: woundIndices
            )
            areaCm2 = Double(areaM2) * 10_000.0
        } else {
            // Fallback: projected area from boundary
            let boundary2DFloat = boundary3D.map { p -> simd_float2 in
                let projected = p - plane.point
                let u = projected - simd_dot(projected, plane.normal) * plane.normal
                return simd_float2(u.x, u.y)
            }
            areaCm2 = Double(SurfaceAreaCalculator.projectedArea(
                boundaryPoints: boundary2DFloat
            )) * 10_000.0
        }

        // Step 4b: Depth and volume
        let depthVolume: (volume: Float, maxDepth: Float, avgDepth: Float)
        if woundVertices.count >= 3 && woundIndices.count >= 3 {
            depthVolume = DepthVolumeCalculator.calculateVolume(
                vertices: woundVertices,
                triangleIndices: woundIndices,
                referencePlane: plane
            )
        } else {
            // Fallback: compute from boundary 3D points only
            var maxD: Float = 0
            var sumD: Float = 0
            var countD = 0
            for p in boundary3D {
                let d = abs(plane.distanceTo(p))
                if d > 0.0001 {
                    maxD = max(maxD, d)
                    sumD += d
                    countD += 1
                }
            }
            depthVolume = (0, maxD, countD > 0 ? sumD / Float(countD) : 0)
        }

        // Step 4c: Length, width, perimeter
        // Project boundary3D onto the wound plane for 2D dimension analysis
        let planeX = Self.computePlaneTangent(normal: plane.normal)
        let planeY = simd_cross(plane.normal, planeX)

        let boundary2DOnPlane = boundary3D.map { p -> simd_float2 in
            let rel = p - plane.point
            return simd_float2(simd_dot(rel, planeX), simd_dot(rel, planeY))
        }

        let dims = DimensionCalculator.calculateDimensions(
            boundaryPoints: boundary2DOnPlane
        )

        return WoundMeasurement(
            areaCm2: areaCm2,
            maxDepthMm: Double(depthVolume.maxDepth * 1000),
            avgDepthMm: Double(depthVolume.avgDepth * 1000),
            volumeMl: Double(depthVolume.volume * 1_000_000), // m³ → mL
            lengthMm: Double(dims.length * 1000),
            widthMm: Double(dims.width * 1000),
            perimeterMm: Double(dims.perimeter * 1000)
        )
    }

    /// Compute a tangent vector perpendicular to the given normal.
    private static func computePlaneTangent(normal: simd_float3) -> simd_float3 {
        let candidate = abs(normal.x) < 0.9
            ? simd_float3(1, 0, 0)
            : simd_float3(0, 1, 0)
        return simd_normalize(simd_cross(normal, candidate))
    }
}
```

---

### 2f. `Utilities/DeviceCapabilityChecker.swift`

```swift
import ARKit

enum DeviceCapability {
    case supported
    case unsupported(reason: String)
}

struct DeviceCapabilityChecker {

    static func checkCapability() -> DeviceCapability {
        guard ARWorldTrackingConfiguration.isSupported else {
            return .unsupported(reason: "ARKit world tracking is not supported on this device.")
        }
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            return .unsupported(reason: "LiDAR depth sensing is not available. WoundOS Pro requires iPhone 12 Pro or later.")
        }
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            return .unsupported(reason: "Scene reconstruction is not available on this device.")
        }
        return .supported
    }
}
```

---

### 2g. `Services/ScanUploadService.swift`

```swift
import Foundation
import UIKit

final class ScanUploadService {

    private let baseURL: String
    private let authService: AuthService

    init(baseURL: String = ServerConfig.baseURL, authService: AuthService = .shared) {
        self.baseURL = baseURL
        self.authService = authService
    }

    /// Upload scan metadata and binary files to backend.
    /// 1. POST /api/wound/v1/scans → get scan_id + signed upload URLs
    /// 2. Upload binary files (RGB, depth, mesh) to GCS via signed URLs
    func uploadScan(
        patientId: String,
        nurseId: String,
        snapshot: WoundCaptureSnapshot,
        boundary2D: [CGPoint],
        boundary3D: [simd_float3],
        measurements: WoundMeasurement,
        pushScore: PUSHScore,
        bodyLocation: String,
        woundType: String
    ) async throws {
        // Step 1: Create scan record
        let scanPayload = buildScanPayload(
            patientId: patientId, nurseId: nurseId,
            snapshot: snapshot, boundary2D: boundary2D,
            boundary3D: boundary3D, measurements: measurements,
            pushScore: pushScore, bodyLocation: bodyLocation,
            woundType: woundType
        )

        let url = URL(string: baseURL + ServerConfig.scanEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authService.currentToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(scanPayload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw UploadError.serverError
        }

        let createResponse = try JSONDecoder().decode(CreateScanResponse.self, from: data)
        let scanId = createResponse.scanId

        // Step 2: Request signed upload URLs
        let uploadURLs = try await requestUploadURLs(scanId: scanId)

        // Step 3: Upload binary files
        if let rgbData = snapshot.rgbImage.jpegData(compressionQuality: 0.85),
           let rgbURL = uploadURLs["rgb.jpg"] {
            try await uploadFile(data: rgbData, to: rgbURL, contentType: "image/jpeg")
        }
    }

    private func requestUploadURLs(scanId: String) async throws -> [String: String] {
        let url = URL(string: baseURL + ServerConfig.scanEndpoint + "/\(scanId)/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authService.currentToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let body = ["files": ["rgb.jpg", "annotated.jpg"]]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(UploadURLsResponse.self, from: data)
        return response.uploadURLs
    }

    private func uploadFile(data: Data, to urlString: String, contentType: String) async throws {
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw UploadError.uploadFailed
        }
    }

    private func buildScanPayload(
        patientId: String, nurseId: String,
        snapshot: WoundCaptureSnapshot, boundary2D: [CGPoint],
        boundary3D: [simd_float3], measurements: WoundMeasurement,
        pushScore: PUSHScore, bodyLocation: String, woundType: String
    ) -> ScanUploadPayload {
        ScanUploadPayload(
            patientId: patientId,
            nurseId: nurseId,
            captureMetadata: .init(
                deviceModel: UIDevice.current.model,
                iosVersion: UIDevice.current.systemVersion,
                appVersion: "1.0.0",
                lidarAvailable: true,
                captureDistanceM: 0.25,
                cameraIntrinsics: snapshot.cameraIntrinsics,
                cameraTransform: snapshot.cameraPose.transform,
                imageWidth: snapshot.imageWidth,
                imageHeight: snapshot.imageHeight
            ),
            nurseBoundary: .init(
                boundary2D: boundary2D.map { [$0.x, $0.y] },
                boundary3D: boundary3D.map { [Double($0.x), Double($0.y), Double($0.z)] },
                tapCenter2D: [Double(snapshot.imageWidth) / 2, Double(snapshot.imageHeight) / 2]
            ),
            measurements: measurements,
            woundLocation: bodyLocation,
            woundType: woundType
        )
    }

    enum UploadError: Error {
        case serverError
        case uploadFailed
    }
}

// Codable models for upload
struct ScanUploadPayload: Codable {
    let patientId: String
    let nurseId: String
    let captureMetadata: CaptureMetadataPayload
    let nurseBoundary: NurseBoundaryPayload
    let measurements: WoundMeasurement
    let woundLocation: String
    let woundType: String

    enum CodingKeys: String, CodingKey {
        case patientId = "patient_id"
        case nurseId = "nurse_id"
        case captureMetadata = "capture_metadata"
        case nurseBoundary = "nurse_boundary"
        case measurements
        case woundLocation = "wound_location"
        case woundType = "wound_type"
    }
}

struct CaptureMetadataPayload: Codable {
    let deviceModel: String
    let iosVersion: String
    let appVersion: String
    let lidarAvailable: Bool
    let captureDistanceM: Double
    let cameraIntrinsics: CameraIntrinsics
    let cameraTransform: [[Float]]
    let imageWidth: Int
    let imageHeight: Int

    enum CodingKeys: String, CodingKey {
        case deviceModel = "device_model"
        case iosVersion = "ios_version"
        case appVersion = "app_version"
        case lidarAvailable = "lidar_available"
        case captureDistanceM = "capture_distance_m"
        case cameraIntrinsics = "camera_intrinsics"
        case cameraTransform = "camera_transform"
        case imageWidth = "image_width"
        case imageHeight = "image_height"
    }
}

struct NurseBoundaryPayload: Codable {
    let boundary2D: [[Double]]
    let boundary3D: [[Double]]
    let tapCenter2D: [Double]

    enum CodingKeys: String, CodingKey {
        case boundary2D = "boundary_2d"
        case boundary3D = "boundary_3d"
        case tapCenter2D = "tap_center_2d"
    }
}

struct CreateScanResponse: Codable {
    let scanId: String
    let status: String
    enum CodingKeys: String, CodingKey {
        case scanId = "scan_id"
        case status
    }
}

struct UploadURLsResponse: Codable {
    let scanId: String
    let uploadURLs: [String: String]
    enum CodingKeys: String, CodingKey {
        case scanId = "scan_id"
        case uploadURLs = "upload_urls"
    }
}
```

---

## 3. Files to Modify

### 3a. `Services/ARSessionManager.swift`

**Add** this method:

```swift
/// Freeze current ARKit state as a WoundCaptureSnapshot.
func captureSnapshot() -> WoundCaptureSnapshot? {
    return SnapshotService.captureSnapshot(from: session)
}
```

### 3b. `Features/Capture/CaptureViewModel.swift`

**Add** snapshot capture mode:

```swift
@Published var capturedSnapshot: WoundCaptureSnapshot?
@Published var isFrozen: Bool = false

func captureShutter() {
    guard let snapshot = arSessionManager.captureSnapshot() else {
        errorMessage = "Failed to capture. Ensure tracking is stable."
        return
    }
    capturedSnapshot = snapshot
    isFrozen = true
    arSessionManager.pauseSession()
}
```

### 3c. `Features/Processing/ProcessingViewModel.swift`

**Add** on-device processing path:

```swift
func processOnDevice(snapshot: WoundCaptureSnapshot, boundary: [CGPoint]) {
    currentStep = .measure

    let measurements = OnDeviceMeasurementEngine.computeMeasurements(
        snapshot: snapshot,
        boundary2D: boundary
    )

    self.serverResponse = ServerResponse(
        measurements: measurements,
        annotatedImageBase64: "",  // Generate locally
        depthHeatmapBase64: "",
        woundMaskBase64: "",
        meshOBJData: nil,
        splatURL: nil,
        clinicalSummary: "Measurements computed on-device. Clinical summary pending.",
        pushScore: PUSHScore(areaScore: PUSHScore.areaScore(forAreaCm2: measurements.areaCm2)),
        processingTimeMs: 0
    )

    isComplete = true

    // Background upload
    Task.detached {
        let uploader = ScanUploadService()
        try? await uploader.uploadScan(
            patientId: self.patientId,
            nurseId: self.nurseId,
            snapshot: snapshot,
            boundary2D: boundary,
            boundary3D: BoundaryProjector3D.projectBoundaryTo3D(
                boundary2D: boundary, snapshot: snapshot
            ),
            measurements: measurements,
            pushScore: self.serverResponse!.pushScore!,
            bodyLocation: self.bodyLocation,
            woundType: self.woundType
        )
    }
}
```

### 3d. `Utilities/ServerConfig.swift`

**Add** v1 API endpoints:

```swift
// v1 API (on-device primary, cloud for sync)
static let baseURL = "https://woundos-wound-api-333499614175.us-central1.run.app"
static let scanEndpoint = "/api/wound/v1/scans"
static let clinicalSummaryEndpoint = "/api/wound/v1/clinical-summary"
static let healthEndpoint = "/api/wound/v1/health"
```

---

## 4. Data Flow (Step by Step)

```
1. App launch
   → DeviceCapabilityChecker.checkCapability()
   → If .unsupported: show "LiDAR required" screen, exit
   → If .supported: proceed to dashboard

2. Nurse taps "New Scan" → CaptureContainerView
   → ARSessionManager.startSession() (LiDAR + sceneDepth + sceneReconstruction)
   → Live camera preview with DistancePill, ArcCaptureGuide

3. Nurse taps shutter button
   → CaptureViewModel.captureShutter()
   → SnapshotService.captureSnapshot(from: session)
   → ARSession paused, snapshot stored in memory
   → Transition to BoundaryEditView with frozen frame

4. Nurse draws boundary on frozen frame
   → BezierPathEngine smooths touch points
   → BoundaryViewModel manages boundary state
   → Output: [CGPoint] array of boundary pixels

5. Nurse taps "Measure"
   → OnDeviceMeasurementEngine.computeMeasurements(snapshot, boundary2D)
     → BoundaryProjector3D.projectBoundaryTo3D() [2D→3D via LiDAR]
     → BoundaryProjector3D.extractWoundSubmesh() [mesh triangles inside boundary]
     → PlaneFitter.fitPlane(to: boundary3D)
     → SurfaceAreaCalculator.calculateArea(vertices, indices)
     → DepthVolumeCalculator.calculateVolume(vertices, indices, plane)
     → DimensionCalculator.calculateDimensions(boundary2DOnPlane)
   → Returns WoundMeasurement (all values in clinical units)

6. Results displayed
   → ResultsView shows area, depth, volume, L×W, perimeter, PUSH
   → PDFReportGenerator creates clinical document
   → ScanStore saves to Core Data

7. Background sync (when network available)
   → OfflineScanQueue picks up saved scan
   → ScanUploadService.uploadScan() posts to /api/wound/v1/scans
   → Backend creates Firestore doc, returns signed URLs
   → iOS uploads RGB + depth + mesh to GCS
   → Backend publishes to Pub/Sub → SAM 2 shadow validation runs
```

---

## 5. Edge Cases and Error Handling

| Edge Case | Handling |
|-----------|----------|
| LiDAR depth returns NaN at boundary point | `DepthMapUtils.depthAtPixel` returns nil, point is skipped |
| <3 valid 3D boundary points after projection | `OnDeviceMeasurementEngine` returns zeroed WoundMeasurement |
| No ARMeshAnchor near wound | Fallback to projected area from boundary3D points |
| PlaneFitter returns nil (degenerate geometry) | Return zeroed WoundMeasurement |
| Network unavailable at upload time | OfflineScanQueue retries with exponential backoff |
| Very large boundary (>500 points) | BezierPathEngine simplifies via Ramer-Douglas-Peucker |
| Camera tracking lost during capture | SnapshotService returns nil, user shown "Try again" |
| Depth map resolution differs from expected | Scale factors computed dynamically from CVPixelBuffer dims |

---

## 6. Unit Test Requirements

### DepthMapUtils Tests
- Known depth buffer with uniform values → correct depth at any pixel
- Out-of-bounds pixel → returns nil
- Unproject center pixel with identity pose → correct 3D point
- Unproject with known intrinsics and depth → matches analytical result

### BoundaryProjector3D Tests
- Flat surface with uniform depth → all 3D points at same Z
- Empty boundary → returns empty array
- Point-in-polygon test: inside → true, outside → false, on edge → true

### OnDeviceMeasurementEngine Tests
- Circular boundary on flat plane → area ≈ πr², depth ≈ 0
- Known rectangular wound → L×W matches
- Empty boundary → zeroed measurements
- <3 points → zeroed measurements

### DeviceCapabilityChecker Tests
- Mock LiDAR available → .supported
- Mock LiDAR unavailable → .unsupported with reason

### ScanUploadService Tests
- Valid payload → correct JSON encoding
- Network error → throws UploadError
- Missing auth token → request still sent (backend handles auth)
