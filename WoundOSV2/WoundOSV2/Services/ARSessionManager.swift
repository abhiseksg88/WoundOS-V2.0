import Foundation
import ARKit
import Combine

struct SelectedFrame {
    let index: Int
    let jpegData: Data
    let pose: CameraPose
    let intrinsics: CameraIntrinsics
    let timestamp: TimeInterval
}

final class ARSessionManager: NSObject, ObservableObject {
    let session = ARSession()

    @Published var currentTrackingState: ARCamera.TrackingState = .notAvailable
    @Published var detectedPlaneDistance: Float?
    @Published var totalFrameCount: Int = 0
    @Published var selectedFrameCount: Int = 0
    @Published var isLiDARAvailable: Bool = false
    @Published var hasSceneDepth: Bool = false

    private(set) var selectedFrames: [SelectedFrame] = []
    private var frameSelector: FrameSelector?
    private var lastForwardVector: simd_float3?
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        session.delegate = self
        isLiDARAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
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

        selectedFrames = []
        selectedFrameCount = 0
        totalFrameCount = 0
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
        frameSelector = FrameSelector()
        startSession()
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
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.currentTrackingState = frame.camera.trackingState
            self.detectedPlaneDistance = self.distanceToNearestPlane(from: frame)
            self.totalFrameCount += 1

            guard self.selectedFrameCount < ServerConfig.maxFrames else { return }

            guard let selector = self.frameSelector else { return }

            let pose = self.extractPose(from: frame.camera, at: frame.timestamp)

            if selector.shouldSelect(frame: frame, pose: pose) {
                let intrinsics = self.extractIntrinsics(from: frame.camera)
                let pixelBuffer = frame.capturedImage
                if let jpegData = self.compressToJPEG(pixelBuffer: pixelBuffer) {
                    let selected = SelectedFrame(
                        index: self.selectedFrameCount,
                        jpegData: jpegData,
                        pose: pose,
                        intrinsics: intrinsics,
                        timestamp: frame.timestamp
                    )
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
