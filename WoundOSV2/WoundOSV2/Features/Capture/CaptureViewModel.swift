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

    let sessionManager = ARSessionManager()
    private var cancellables = Set<AnyCancellable>()
    private var lastPoseTime: TimeInterval = 0
    private var lastForward: simd_float3?

    var targetFrames: Int { ServerConfig.targetFrames }
    var progress: Double { Double(selectedFrameCount) / Double(targetFrames) }

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
        sessionManager.startSession()
        isLiDAREnhanced = sessionManager.isLiDARAvailable
    }

    func stopCapture() {
        sessionManager.pauseSession()
    }

    func resetCapture() {
        state = .ready
        sessionManager.resetSession()
    }

    var selectedFrames: [SelectedFrame] {
        sessionManager.selectedFrames
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
                self.arcCoverage = self.sessionManager.frameSelector(coverage: count)

                if count >= ServerConfig.targetFrames && self.arcCoverage >= ServerConfig.minArcCoverageDegrees {
                    self.completeCapture()
                }
            }
            .store(in: &cancellables)

        sessionManager.$detectedPlaneDistance
            .receive(on: DispatchQueue.main)
            .assign(to: &$planeDistance)
    }

    private func completeCapture() {
        guard state == .capturing else { return }
        state = .complete
        sessionManager.pauseSession()
        WOSHaptics.complete()
    }
}

// Extension to expose arc coverage from session manager
extension ARSessionManager {
    func frameSelector(coverage count: Int) -> Float {
        return Float(count) * ServerConfig.minParallaxDegrees
    }
}
