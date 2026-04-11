import Foundation
import Combine
import ARKit

enum CaptureState {
    case ready
    case positioning
    case capturing
    case complete
}

final class CaptureViewModel: ObservableObject {
    @Published var state: CaptureState = .ready
    @Published var selectedFrameCount: Int = 0
    @Published var trackingState: ARCamera.TrackingState = .notAvailable
    @Published var planeDistance: Float?
    @Published var angularVelocity: Float = 0
    @Published var arcCoverage: Float = 0
    @Published var isLiDAREnhanced: Bool = false
    @Published var meshAnchorCount: Int = 0
    /// User-tappable wound center in normalized image coordinates [0,1].
    @Published var woundPointNormalized: CGPoint?

    let sessionManager = ARSessionManager()
    private var cancellables = Set<AnyCancellable>()
    private var lastPoseTimestamp: TimeInterval = 0
    private var lastForwardVector: simd_float3?
    private var captureStartTime: Date?

    var captureMode: CaptureMode { sessionManager.captureMode }
    var targetFrames: Int { ServerConfig.targetFrames }
    var progress: Double {
        if captureMode == .lidar {
            // For LiDAR mode, progress is based on time + mesh anchor count
            guard let start = captureStartTime else { return 0 }
            let elapsed = Date().timeIntervalSince(start)
            let timeFraction = min(elapsed / ServerConfig.lidarCaptureMinDurationSeconds, 1.0)
            let anchorFraction = min(Double(meshAnchorCount) / Double(ServerConfig.lidarMinMeshAnchors), 1.0)
            return min(timeFraction, anchorFraction)
        }
        return Double(selectedFrameCount) / Double(targetFrames)
    }

    var distanceStatus: DistanceStatus {
        guard let dist = planeDistance else { return .unknown }
        if ServerConfig.optimalDistanceRange.contains(dist) { return .optimal }
        if dist < ServerConfig.optimalDistanceRange.lowerBound { return .tooClose }
        return .tooFar
    }

    var motionStatus: MotionStatus {
        if angularVelocity < 1 { return .tooSlow }
        if angularVelocity > 15 { return .tooFast }
        return .good
    }

    enum DistanceStatus {
        case optimal, tooClose, tooFar, unknown
    }

    enum MotionStatus {
        case good, tooFast, tooSlow
    }

    init() {
        setupBindings()
    }

    func startCapture() {
        state = .positioning
        captureStartTime = Date()
        sessionManager.startSession()
        isLiDAREnhanced = sessionManager.isLiDARAvailable
    }

    func stopCapture() {
        sessionManager.pauseSession()
    }

    func resetCapture() {
        state = .ready
        lastPoseTimestamp = 0
        lastForwardVector = nil
        captureStartTime = nil
        woundPointNormalized = nil
        sessionManager.resetSession()
    }

    var selectedFrames: [SelectedFrame] {
        sessionManager.selectedFrames
    }

    /// For LiDAR mode: finalize capture and produce a payload ready for upload.
    /// **Pauses the session before serialization** so anchors are stable.
    func finalizeLiDARCapture() async -> LiDARScanPayload? {
        // Pause first so the anchor list is stable for OBJ serialization
        sessionManager.pauseSession()
        return await sessionManager.finalizeLiDARPayload(
            cropRadius: ServerConfig.lidarCaptureCropRadius
        )
    }

    /// User taps the screen at this normalized position to mark the wound center.
    func setWoundPoint(_ point: CGPoint) {
        woundPointNormalized = point
    }

    private func setupBindings() {
        sessionManager.$currentTrackingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.trackingState = state
                if case .normal = state, self?.state == .positioning {
                    self?.state = .capturing
                }
            }
            .store(in: &cancellables)

        sessionManager.$selectedFrameCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                guard let self = self else { return }
                self.selectedFrameCount = count
                self.arcCoverage = Float(count) * ServerConfig.minParallaxDegrees

                // Multi-view auto-complete (Tier 2)
                if self.captureMode == .multiview {
                    if count >= ServerConfig.targetFrames && self.arcCoverage >= ServerConfig.minArcCoverageDegrees {
                        self.completeCapture()
                    }
                }
            }
            .store(in: &cancellables)

        sessionManager.$meshAnchorCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                guard let self = self else { return }
                self.meshAnchorCount = count
                self.checkLiDARCompletion()
            }
            .store(in: &cancellables)

        sessionManager.$detectedPlaneDistance
            .receive(on: DispatchQueue.main)
            .assign(to: &$planeDistance)

        // Update angular velocity from ARKit frame updates
        sessionManager.$latestCameraTransform
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transformData in
                guard let self = self, let (transform, timestamp) = transformData else { return }
                self.updateAngularVelocity(transform: transform, timestamp: timestamp)
                self.checkLiDARCompletion()
            }
            .store(in: &cancellables)
    }

    private func checkLiDARCompletion() {
        guard captureMode == .lidar, state == .capturing else { return }
        guard let start = captureStartTime else { return }

        let elapsed = Date().timeIntervalSince(start)

        // Forced completion if we've been capturing too long
        if elapsed > ServerConfig.lidarCaptureMaxDurationSeconds {
            completeCapture()
            return
        }

        // Normal completion: minimum time + minimum mesh anchors + best frame available
        let hasMinTime = elapsed >= ServerConfig.lidarCaptureMinDurationSeconds
        let hasMinAnchors = meshAnchorCount >= ServerConfig.lidarMinMeshAnchors
        let hasBestFrame = sessionManager.bestLiDARFrame != nil
        let isTracking = trackingState == .normal

        if hasMinTime && hasMinAnchors && hasBestFrame && isTracking {
            // Auto-complete after minimum criteria met. The user can also tap manually.
            // For now we let the user tap "Capture" — see CaptureContainerView.
        }
    }

    /// Manual completion trigger from the user tapping "Capture" in LiDAR mode.
    func userCompleteCapture() {
        completeCapture()
    }

    private func updateAngularVelocity(transform: simd_float4x4, timestamp: TimeInterval) {
        let forward = -simd_normalize(simd_float3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))

        if let lastForward = lastForwardVector, lastPoseTimestamp > 0 {
            let dt = timestamp - lastPoseTimestamp
            if dt > 0.01 {
                let dot = simd_clamp(simd_dot(forward, lastForward), -1.0, 1.0)
                let angleDeg = acos(dot) * 180.0 / .pi
                angularVelocity = angleDeg / Float(dt)
            }
        }

        lastForwardVector = forward
        lastPoseTimestamp = timestamp
    }

    private func completeCapture() {
        guard state == .capturing else { return }
        state = .complete
        sessionManager.pauseSession()
        WOSHaptics.complete()
    }
}
