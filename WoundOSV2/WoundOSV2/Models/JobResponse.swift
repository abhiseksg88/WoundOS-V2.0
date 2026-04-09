import Foundation

/// Response from POST /api/v2/reconstruct — job submission
struct JobSubmitResponse: Codable {
    let jobId: String
    let status: String
    let estimatedDurationSeconds: Int?
}

/// Response from GET /api/v2/jobs/{jobId} — job polling
struct JobResponse: Codable {
    let jobId: String
    let status: JobStatus
    let tier: Int?
    let progress: Double?
    let elapsedMs: Int?
    let result: ServerResponse?
    let preliminaryResult: ServerResponse?
    let measurementDelta: MeasurementDelta?
    let error: String?

    enum JobStatus: String, Codable {
        case queued
        case tier1_processing
        case tier1_complete
        case tier2_processing
        case complete
        case failed
    }
}

struct MeasurementDelta: Codable {
    let areaDiffPercent: Double
    let depthDiffPercent: Double
    let note: String
}
