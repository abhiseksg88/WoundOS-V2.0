import Foundation

struct ServerConfig {
    static let defaultBaseURL = "https://wound-ai-api-333499614175.us-central1.run.app"
    static let reconstructEndpoint = "/api/v2/reconstruct"
    static let jobsEndpoint = "/api/v2/jobs"  // GET /api/v2/jobs/{jobId}
    static let segmentEndpoint = "/api/v1/segment"
    static let woundAmbitEndpoint = "/api/v1/woundambit"
    static let uploadTimeout: TimeInterval = 30  // Upload only, not full processing
    static let pollInterval: TimeInterval = 3.0  // Seconds between job polls
    static let maxPollDuration: TimeInterval = 300  // 5 min max poll time
    static let maxRetries = 3
    static let jobStatusEndpoint = "/api/v2/jobs/"
    static let pollIntervalSeconds: TimeInterval = 3.0
    static let pollTimeout: TimeInterval = 10
    static let maxPollAttempts = 40
    static let maxFrames = 50
    static let minFrames = 20
    static let targetFrames = 30
    static let minParallaxDegrees: Float = 3.0
    static let minSharpnessVariance: Float = 100.0
    static let exposureTolerance: Float = 0.15
    static let optimalDistanceRange: ClosedRange<Float> = 0.12...0.35
    static let minArcCoverageDegrees: Float = 120.0

    // MARK: - LiDAR-native pipeline (Tier 1)
    /// Form-field name used to indicate LiDAR mode to the backend.
    static let lidarModeParamName = "lidar"
    /// Minimum capture duration before LiDAR completion is allowed (seconds).
    static let lidarCaptureMinDurationSeconds: TimeInterval = 2.0
    /// Maximum LiDAR capture duration before forced completion (seconds).
    static let lidarCaptureMaxDurationSeconds: TimeInterval = 8.0
    /// On-device sphere crop radius around the camera look-at point (meters).
    /// Larger = more upload bandwidth but more context for plane fitting.
    static let lidarCaptureCropRadius: Float = 0.20
    /// Minimum number of ARMeshAnchor objects required before allowing finalization.
    static let lidarMinMeshAnchors: Int = 3
}
