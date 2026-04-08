import Foundation

struct ServerConfig {
    static let defaultBaseURL = "https://wound-ai-api-333499614175.us-central1.run.app"
    static let reconstructEndpoint = "/api/v2/reconstruct"
    static let segmentEndpoint = "/api/v1/segment"
    static let woundAmbitEndpoint = "/api/v1/woundambit"
    static let uploadTimeout: TimeInterval = 60
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
}
