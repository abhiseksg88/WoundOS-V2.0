import Foundation
import ARKit
import Combine
import simd

struct SelectedFrame {
    let index: Int
    let jpegData: Data
    let pose: CameraPose
    let intrinsics: CameraIntrinsics
    let timestamp: TimeInterval
    /// Sharpness score (Laplacian variance) used for best-frame selection.
    var sharpnessScore: Float = 0
}

/// Capture mode determines how the wound is reconstructed.
enum CaptureMode: String {
    /// LiDAR-native: ARKit scene reconstruction mesh + 1 best frame.
    /// Available on iPhone 12 Pro+, iPad Pro. Total backend time: 3-5s.
    case lidar
    /// Multi-view photogrammetry: 30 frames + Depth Pro + COLMAP MVS.
    /// Fallback for non-LiDAR devices. Total backend time: 30-60s.
    case multiview
}

final class ARSessionManager: NSObject, ObservableObject {
    let session = ARSession()

    @Published var currentTrackingState: ARCamera.TrackingState = .notAvailable
    @Published var detectedPlaneDistance: Float?
    @Published var totalFrameCount: Int = 0
    @Published var selectedFrameCount: Int = 0
    @Published var isLiDARAvailable: Bool = false
    @Published var hasSceneDepth: Bool = false
    @Published var latestCameraTransform: (simd_float4x4, TimeInterval)?

    /// Active capture mode (defaults to LiDAR if available).
    @Published var captureMode: CaptureMode = .multiview

    /// Number of ARMeshAnchor objects collected so far (LiDAR mode only).
    @Published var meshAnchorCount: Int = 0

    /// Best single frame for LiDAR mode (sharpest, captured during session).
    @Published var bestLiDARFrame: SelectedFrame?

    /// Most recent ARFrame.sceneDepth.depthMap (LiDAR mode, optional).
    private(set) var latestDepthMap: CVPixelBuffer?

    /// All ARMeshAnchor objects collected during this session, keyed by identifier.
    /// In .lidar mode, ARKit emits these via session(_:didAdd:) and session(_:didUpdate:).
    private var meshAnchorsByID: [UUID: ARMeshAnchor] = [:]

    private(set) var selectedFrames: [SelectedFrame] = []
    private var frameSelector: FrameSelector?
    private let processingQueue = DispatchQueue(label: "com.careplix.woundos.frameprocessing", qos: .userInitiated)

    override init() {
        super.init()
        session.delegate = self
        isLiDARAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        // Auto-select LiDAR mode if hardware supports it
        captureMode = isLiDARAvailable ? .lidar : .multiview
    }

    func startSession() {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.worldAlignment = .gravity

        if let videoFormat = ARWorldTrackingConfiguration.supportedVideoFormats.first(where: {
            $0.imageResolution.width == 4032 && $0.imageResolution.height == 3024
        }) {
            config.videoFormat = videoFormat
        } else if let bestFormat = ARWorldTrackingConfiguration.supportedVideoFormats.first {
            config.videoFormat = bestFormat
        }

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
            hasSceneDepth = true
        }

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        // Reset all state
        selectedFrames = []
        selectedFrameCount = 0
        totalFrameCount = 0
        meshAnchorsByID = [:]
        meshAnchorCount = 0
        bestLiDARFrame = nil
        latestDepthMap = nil
        frameSelector = FrameSelector()

        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func pauseSession() {
        session.pause()
    }

    func resetSession() {
        selectedFrames = []
        selectedFrameCount = 0
        totalFrameCount = 0
        meshAnchorsByID = [:]
        meshAnchorCount = 0
        bestLiDARFrame = nil
        latestDepthMap = nil
        frameSelector = FrameSelector()
        startSession()
    }

    // MARK: - LiDAR Finalization

    /// Finalize the LiDAR capture and produce a payload ready for upload.
    ///
    /// **Must be called after `pauseSession()`** so the mesh anchor list is stable.
    /// Runs OBJ serialization on a background queue.
    ///
    /// - Parameters:
    ///   - cropRadius: Sphere crop radius in meters around the camera's look-at point.
    ///     Use ~0.20m to limit upload to the wound region (HIPAA + bandwidth).
    /// - Returns: A LiDARScanPayload, or nil if no mesh / no best frame available.
    func finalizeLiDARPayload(cropRadius: Float) async -> LiDARScanPayload? {
        guard let bestFrame = bestLiDARFrame else { return nil }
        let anchorsSnapshot = Array(meshAnchorsByID.values)
        guard !anchorsSnapshot.isEmpty else { return nil }

        // Compute crop center: camera position + look-at × planeDistance
        let poseRows = bestFrame.pose.transform
        let camPos = SIMD3<Float>(poseRows[0][3], poseRows[1][3], poseRows[2][3])
        let forward = SIMD3<Float>(-poseRows[0][2], -poseRows[1][2], -poseRows[2][2])  // ARKit -Z forward
        let distance = detectedPlaneDistance ?? 0.20
        let cropCenter = camPos + forward * distance

        // Run OBJ serialization off the main thread
        let objData: Data? = await withCheckedContinuation { continuation in
            processingQueue.async {
                let data = ARMeshExporter.serializeToOBJ(
                    anchors: anchorsSnapshot,
                    cropCenterWorld: cropCenter,
                    cropRadius: cropRadius
                )
                continuation.resume(returning: data)
            }
        }

        guard let meshOBJ = objData else { return nil }

        // Optional: encode the latest depth map as 16-bit PNG
        var depthPNG: Data? = nil
        if let depthMap = latestDepthMap {
            depthPNG = DepthMapExporter.encodePNG16(depthMap: depthMap, maxMeters: 5.0)
        }

        let bounds = ARMeshExporter.computeBounds(anchors: anchorsSnapshot)

        return LiDARScanPayload(
            bestFrame: bestFrame,
            meshOBJData: meshOBJ,
            depthPNG: depthPNG,
            anchorCount: anchorsSnapshot.count,
            worldBoundsMeters: bounds
        )
    }

    func extractIntrinsics(from camera: ARCamera) -> CameraIntrinsics {
        let intrinsics = camera.intrinsics
        let resolution = camera.imageResolution
        return CameraIntrinsics(
            fx: intrinsics[0][0],
            fy: intrinsics[1][1],
            cx: intrinsics[2][0],
            cy: intrinsics[2][1],
            width: Int(resolution.width),
            height: Int(resolution.height)
        )
    }

    func extractPose(from camera: ARCamera, at timestamp: TimeInterval) -> CameraPose {
        let t = camera.transform
        let matrix: [[Float]] = [
            [t.columns.0.x, t.columns.1.x, t.columns.2.x, t.columns.3.x],
            [t.columns.0.y, t.columns.1.y, t.columns.2.y, t.columns.3.y],
            [t.columns.0.z, t.columns.1.z, t.columns.2.z, t.columns.3.z],
            [t.columns.0.w, t.columns.1.w, t.columns.2.w, t.columns.3.w]
        ]
        let state: CameraPose.TrackingState = {
            switch camera.trackingState {
            case .normal: return .normal
            case .limited: return .limited
            case .notAvailable: return .notAvailable
            }
        }()
        return CameraPose(timestamp: timestamp, transform: matrix, trackingState: state)
    }

    func distanceToNearestPlane(from frame: ARFrame) -> Float? {
        let cameraPosition = frame.camera.transform.columns.3
        var minDist: Float = .greatestFiniteMagnitude

        for anchor in frame.anchors {
            guard let planeAnchor = anchor as? ARPlaneAnchor else { continue }
            let planePos = planeAnchor.transform.columns.3
            let dist = simd_distance(
                simd_float3(cameraPosition.x, cameraPosition.y, cameraPosition.z),
                simd_float3(planePos.x, planePos.y, planePos.z)
            )
            if dist < minDist {
                minDist = dist
            }
        }

        return minDist < .greatestFiniteMagnitude ? minDist : nil
    }
}

extension ARSessionManager: ARSessionDelegate {

    // MARK: - Mesh anchor lifecycle (LiDAR mode)

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard captureMode == .lidar else { return }
        var added = 0
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                meshAnchorsByID[meshAnchor.identifier] = meshAnchor
                added += 1
            }
        }
        if added > 0 {
            DispatchQueue.main.async { [weak self] in
                self?.meshAnchorCount = self?.meshAnchorsByID.count ?? 0
            }
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard captureMode == .lidar else { return }
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                meshAnchorsByID[meshAnchor.identifier] = meshAnchor
            }
        }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        guard captureMode == .lidar else { return }
        for anchor in anchors {
            if anchor is ARMeshAnchor {
                meshAnchorsByID.removeValue(forKey: anchor.identifier)
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.meshAnchorCount = self?.meshAnchorsByID.count ?? 0
        }
    }

    // MARK: - Frame updates

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Lightweight updates on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentTrackingState = frame.camera.trackingState
            self.detectedPlaneDistance = self.distanceToNearestPlane(from: frame)
            self.totalFrameCount += 1
            self.latestCameraTransform = (frame.camera.transform, frame.timestamp)
        }

        // Cache the latest depth map for LiDAR mode
        if captureMode == .lidar, let sceneDepth = frame.sceneDepth {
            latestDepthMap = sceneDepth.depthMap
        }

        let camera = frame.camera

        if captureMode == .lidar {
            // LiDAR mode: just track the single best frontal frame.
            // Frame must be normal tracking and reasonably frontal to a plane.
            guard case .normal = camera.trackingState else { return }
            guard let selector = frameSelector else { return }

            let pose = extractPose(from: camera, at: frame.timestamp)
            let pixelBuffer = frame.capturedImage

            // Compute sharpness; only update if better than current best
            let sharpness = selector.computeSharpness(pixelBuffer: pixelBuffer)
            if let current = bestLiDARFrame, current.sharpnessScore >= sharpness {
                return
            }

            // Compress to JPEG on background queue
            CVPixelBufferRetain(pixelBuffer)
            let intrinsics = extractIntrinsics(from: camera)

            processingQueue.async { [weak self] in
                guard let self = self else {
                    CVPixelBufferRelease(pixelBuffer)
                    return
                }
                let jpegData = self.compressToJPEG(pixelBuffer: pixelBuffer)
                CVPixelBufferRelease(pixelBuffer)

                guard let data = jpegData else { return }

                var selected = SelectedFrame(
                    index: 0,
                    jpegData: data,
                    pose: pose,
                    intrinsics: intrinsics,
                    timestamp: frame.timestamp
                )
                selected.sharpnessScore = sharpness

                DispatchQueue.main.async {
                    self.bestLiDARFrame = selected
                    self.selectedFrameCount = 1
                }
            }
            return
        }

        // MULTIVIEW MODE: Heavy processing (JPEG compression) on background queue
        guard selectedFrameCount < ServerConfig.maxFrames else { return }
        guard let selector = frameSelector else { return }

        let pose = extractPose(from: camera, at: frame.timestamp)

        if selector.shouldSelect(frame: frame, pose: pose) {
            let intrinsics = extractIntrinsics(from: camera)
            let pixelBuffer = frame.capturedImage
            CVPixelBufferRetain(pixelBuffer)

            processingQueue.async { [weak self] in
                guard let self = self else {
                    CVPixelBufferRelease(pixelBuffer)
                    return
                }
                let jpegData = self.compressToJPEG(pixelBuffer: pixelBuffer)
                CVPixelBufferRelease(pixelBuffer)

                guard let data = jpegData else { return }

                let selected = SelectedFrame(
                    index: self.selectedFrameCount,
                    jpegData: data,
                    pose: pose,
                    intrinsics: intrinsics,
                    timestamp: frame.timestamp
                )

                DispatchQueue.main.async {
                    self.selectedFrames.append(selected)
                    self.selectedFrameCount = self.selectedFrames.count
                    WOSHaptics.capture()
                }
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("ARSession failed: \(error.localizedDescription)")
    }

    func sessionWasInterrupted(_ session: ARSession) {
        print("ARSession interrupted")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        print("ARSession interruption ended")
    }

    private func compressToJPEG(pixelBuffer: CVPixelBuffer, quality: CGFloat = 0.85) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: quality)
    }
}
