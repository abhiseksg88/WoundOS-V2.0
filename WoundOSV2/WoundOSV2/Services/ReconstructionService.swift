import Foundation
import UIKit
import Combine

// MARK: - Response Types

struct ServerResponse: Codable {
    let measurements: WoundMeasurement
    let annotatedImageBase64: String
    let depthHeatmapBase64: String
    let woundMaskBase64: String
    let meshOBJData: Data?
    let splatURL: String?
    let clinicalSummary: String
    let pushScore: PUSHScore?
    let processingTimeMs: Int
    let quality: ResultQuality

    enum ResultQuality: String, Codable {
        case preliminary
        case gold
    }

    init(measurements: WoundMeasurement, annotatedImageBase64: String, depthHeatmapBase64: String,
         woundMaskBase64: String, meshOBJData: Data?, splatURL: String?, clinicalSummary: String,
         pushScore: PUSHScore?, processingTimeMs: Int, quality: ResultQuality = .gold) {
        self.measurements = measurements
        self.annotatedImageBase64 = annotatedImageBase64
        self.depthHeatmapBase64 = depthHeatmapBase64
        self.woundMaskBase64 = woundMaskBase64
        self.meshOBJData = meshOBJData
        self.splatURL = splatURL
        self.clinicalSummary = clinicalSummary
        self.pushScore = pushScore
        self.processingTimeMs = processingTimeMs
        self.quality = quality
    }

    // Backward-compatible decoding — defaults quality to .gold when absent
    enum CodingKeys: String, CodingKey {
        case measurements, annotatedImageBase64, depthHeatmapBase64, woundMaskBase64
        case meshOBJData, splatURL, clinicalSummary, pushScore, processingTimeMs, quality
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        measurements = try c.decode(WoundMeasurement.self, forKey: .measurements)
        annotatedImageBase64 = try c.decode(String.self, forKey: .annotatedImageBase64)
        depthHeatmapBase64 = try c.decode(String.self, forKey: .depthHeatmapBase64)
        woundMaskBase64 = try c.decode(String.self, forKey: .woundMaskBase64)
        meshOBJData = try c.decodeIfPresent(Data.self, forKey: .meshOBJData)
        splatURL = try c.decodeIfPresent(String.self, forKey: .splatURL)
        clinicalSummary = try c.decode(String.self, forKey: .clinicalSummary)
        pushScore = try c.decodeIfPresent(PUSHScore.self, forKey: .pushScore)
        processingTimeMs = try c.decode(Int.self, forKey: .processingTimeMs)
        quality = try c.decodeIfPresent(ResultQuality.self, forKey: .quality) ?? .gold
    }
}

struct JobSubmission: Codable {
    let jobId: String
    let status: String
    let estimatedDurationSeconds: Int
}

struct JobStatus: Codable {
    let jobId: String
    let status: JobStatusValue
    let step: String?
    let progress: Double?
    let elapsedMs: Int?
    let preliminaryResult: ServerResponse?
    let result: ServerResponse?
    let errorMessage: String?

    enum JobStatusValue: String, Codable {
        case queued, processing, complete, failed
    }
}

enum ReconstructionError: Error, LocalizedError {
    case serverJobFailed(String)
    case pollTimeout

    var errorDescription: String? {
        switch self {
        case .serverJobFailed(let msg): return "Server error: \(msg)"
        case .pollTimeout: return "Processing timed out. Please try again."
        }
    }
}

// MARK: - Protocol

protocol ReconstructionServiceProtocol {
    /// Multi-view (Tier 2) submission: 30 frames + Depth Pro + COLMAP MVS.
    /// Used as fallback for non-LiDAR devices.
    func submitScan(
        frames: [SelectedFrame],
        woundPoint: CGPoint?,
        useWoundAmbit: Bool,
        generateSplat: Bool
    ) async throws -> JobSubmission

    /// LiDAR-native (Tier 1) submission: 1 frame + ARKit scene mesh + intrinsics.
    /// Used on iPhone Pro / iPad Pro. ~10x faster than multi-view.
    func submitLiDARScan(
        payload: LiDARScanPayload,
        woundPoint: CGPoint?,
        useWoundAmbit: Bool
    ) async throws -> JobSubmission

    func pollJobStatus(jobId: String) async throws -> JobStatus
}

// MARK: - Real Server Implementation

final class ReconstructionService: ReconstructionServiceProtocol {
    private let baseURL: String
    private let authService: AuthService

    init(baseURL: String = ServerConfig.defaultBaseURL, authService: AuthService = .shared) {
        self.baseURL = baseURL
        self.authService = authService
    }

    func submitScan(
        frames: [SelectedFrame],
        woundPoint: CGPoint?,
        useWoundAmbit: Bool,
        generateSplat: Bool
    ) async throws -> JobSubmission {
        let url = URL(string: baseURL + ServerConfig.reconstructEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = ServerConfig.uploadTimeout

        if let token = authService.currentToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        for (index, frame) in frames.enumerated() {
            body.appendMultipart(boundary: boundary, name: "frames", filename: "frame_\(index).jpg",
                                 mimeType: "image/jpeg", data: frame.jpegData)
        }

        let poses = frames.map { $0.pose }
        if let posesData = try? JSONEncoder().encode(poses) {
            body.appendMultipart(boundary: boundary, name: "poses", filename: "poses.json",
                                 mimeType: "application/json", data: posesData)
        }

        if let firstFrame = frames.first,
           let intrinsicsData = try? JSONEncoder().encode(firstFrame.intrinsics) {
            body.appendMultipart(boundary: boundary, name: "intrinsics", filename: "intrinsics.json",
                                 mimeType: "application/json", data: intrinsicsData)
        }

        if let woundPoint = woundPoint {
            body.appendMultipartField(boundary: boundary, name: "wound_point",
                                       value: "\(woundPoint.x),\(woundPoint.y)")
        }
        body.appendMultipartField(boundary: boundary, name: "use_woundambit", value: useWoundAmbit ? "true" : "false")
        body.appendMultipartField(boundary: boundary, name: "generate_splat", value: generateSplat ? "true" : "false")
        body.appendMultipartField(boundary: boundary, name: "source_platform", value: "ios")
        body.appendMultipartField(boundary: boundary, name: "device_model", value: UIDevice.current.model)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        // Retry logic for submission
        var lastError: Error?
        for attempt in 0..<ServerConfig.maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                return try JSONDecoder().decode(JobSubmission.self, from: data)
            } catch {
                lastError = error
                if attempt < ServerConfig.maxRetries - 1 {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    // MARK: - LiDAR-native submission (Tier 1)

    func submitLiDARScan(
        payload: LiDARScanPayload,
        woundPoint: CGPoint?,
        useWoundAmbit: Bool
    ) async throws -> JobSubmission {
        let url = URL(string: baseURL + ServerConfig.reconstructEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = ServerConfig.uploadTimeout

        if let token = authService.currentToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Single best frame
        body.appendMultipart(
            boundary: boundary, name: "frames", filename: "frame_0.jpg",
            mimeType: "image/jpeg", data: payload.bestFrame.jpegData
        )

        // Single-element poses array
        let posesArray = [payload.bestFrame.pose]
        if let posesData = try? JSONEncoder().encode(posesArray) {
            body.appendMultipart(
                boundary: boundary, name: "poses", filename: "poses.json",
                mimeType: "application/json", data: posesData
            )
        }

        // Intrinsics
        if let intrinsicsData = try? JSONEncoder().encode(payload.bestFrame.intrinsics) {
            body.appendMultipart(
                boundary: boundary, name: "intrinsics", filename: "intrinsics.json",
                mimeType: "application/json", data: intrinsicsData
            )
        }

        // ARKit scene reconstruction OBJ mesh — the key payload
        body.appendMultipart(
            boundary: boundary, name: "mesh", filename: "scene.obj",
            mimeType: "application/x-tgif", data: payload.meshOBJData
        )

        // Optional 16-bit depth PNG
        if let depthData = payload.depthPNG {
            body.appendMultipart(
                boundary: boundary, name: "depth", filename: "depth.png",
                mimeType: "image/png", data: depthData
            )
        }

        // Mode and form fields
        body.appendMultipartField(boundary: boundary, name: "mode", value: ServerConfig.lidarModeParamName)
        if let woundPoint = woundPoint {
            body.appendMultipartField(
                boundary: boundary, name: "wound_point",
                value: "\(woundPoint.x),\(woundPoint.y)"
            )
        }
        body.appendMultipartField(boundary: boundary, name: "use_woundambit", value: useWoundAmbit ? "true" : "false")
        body.appendMultipartField(boundary: boundary, name: "generate_splat", value: "false")
        body.appendMultipartField(boundary: boundary, name: "source_platform", value: "ios")
        body.appendMultipartField(boundary: boundary, name: "device_model", value: UIDevice.current.model)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        // Retry logic for upload
        var lastError: Error?
        for attempt in 0..<ServerConfig.maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                return try JSONDecoder().decode(JobSubmission.self, from: data)
            } catch {
                lastError = error
                if attempt < ServerConfig.maxRetries - 1 {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    func pollJobStatus(jobId: String) async throws -> JobStatus {
        let url = URL(string: baseURL + ServerConfig.jobStatusEndpoint + jobId)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = ServerConfig.pollTimeout

        if let token = authService.currentToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(JobStatus.self, from: data)
    }
}

// MARK: - Mock Server Implementation

final class MockReconstructionService: ReconstructionServiceProtocol {
    private var mockStartTime: Date?

    func submitScan(
        frames: [SelectedFrame],
        woundPoint: CGPoint?,
        useWoundAmbit: Bool,
        generateSplat: Bool
    ) async throws -> JobSubmission {
        try await Task.sleep(nanoseconds: 500_000_000) // simulate upload
        mockStartTime = Date()
        return JobSubmission(jobId: UUID().uuidString, status: "queued", estimatedDurationSeconds: 6)
    }

    func submitLiDARScan(
        payload: LiDARScanPayload,
        woundPoint: CGPoint?,
        useWoundAmbit: Bool
    ) async throws -> JobSubmission {
        // Simulate fast LiDAR upload (~0.5s vs ~5s for multiview)
        try await Task.sleep(nanoseconds: 300_000_000)
        mockStartTime = Date()
        // LiDAR jobs complete much faster
        return JobSubmission(jobId: UUID().uuidString, status: "queued", estimatedDurationSeconds: 4)
    }

    func pollJobStatus(jobId: String) async throws -> JobStatus {
        let elapsed = Date().timeIntervalSince(mockStartTime ?? Date())

        if elapsed < 3.0 {
            return JobStatus(jobId: jobId, status: .processing, step: "reconstructing",
                             progress: elapsed / 6.0, elapsedMs: Int(elapsed * 1000),
                             preliminaryResult: nil, result: nil, errorMessage: nil)
        } else if elapsed < 6.0 {
            return JobStatus(jobId: jobId, status: .processing, step: "refining",
                             progress: elapsed / 6.0, elapsedMs: Int(elapsed * 1000),
                             preliminaryResult: makePreliminaryResponse(), result: nil, errorMessage: nil)
        } else {
            return JobStatus(jobId: jobId, status: .complete, step: nil,
                             progress: 1.0, elapsedMs: Int(elapsed * 1000),
                             preliminaryResult: nil, result: makeGoldResponse(), errorMessage: nil)
        }
    }

    private func makePreliminaryResponse() -> ServerResponse {
        ServerResponse(
            measurements: WoundMeasurement(areaCm2: 12.1, maxDepthMm: 4.9, avgDepthMm: 2.6,
                                           volumeMl: 2.9, lengthMm: 44.0, widthMm: 31.0, perimeterMm: 126.0),
            annotatedImageBase64: generateMockAnnotatedImage(),
            depthHeatmapBase64: generateMockHeatmap(),
            woundMaskBase64: generateMockMask(),
            meshOBJData: nil, splatURL: nil,
            clinicalSummary: "Stage III pressure injury on sacrum. Preliminary assessment: wound bed shows granulation tissue with moderate exudate. Periwound skin intact.",
            pushScore: PUSHScore(areaScore: 9, exudateScore: 2, surfaceTypeScore: 3),
            processingTimeMs: 3000, quality: .preliminary
        )
    }

    private func makeGoldResponse() -> ServerResponse {
        ServerResponse(
            measurements: WoundMeasurement(areaCm2: 12.4, maxDepthMm: 5.2, avgDepthMm: 2.8,
                                           volumeMl: 3.1, lengthMm: 45.0, widthMm: 32.0, perimeterMm: 128.5),
            annotatedImageBase64: generateMockAnnotatedImage(),
            depthHeatmapBase64: generateMockHeatmap(),
            woundMaskBase64: generateMockMask(),
            meshOBJData: nil, splatURL: nil,
            clinicalSummary: "Stage III pressure injury on sacrum measuring 12.4 cm\u{00B2}. Wound bed shows 70% granulation tissue with 30% slough. Moderate serous exudate noted. Periwound skin intact with mild erythema extending 1cm from wound edge. Undermining detected at 2 o'clock position extending 8mm. Recommend continued offloading protocol, moisture-retentive dressing change every 48 hours, and nutritional optimization.",
            pushScore: PUSHScore(areaScore: 9, exudateScore: 2, surfaceTypeScore: 3),
            processingTimeMs: 6000, quality: .gold
        )
    }

    private func generateMockAnnotatedImage() -> String {
        let size = CGSize(width: 400, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.systemGray5.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let woundRect = CGRect(x: 120, y: 80, width: 160, height: 140)
            UIColor.systemRed.withAlphaComponent(0.3).setFill()
            UIBezierPath(ovalIn: woundRect).fill()
            UIColor.systemGreen.setStroke()
            let path = UIBezierPath(ovalIn: woundRect)
            path.lineWidth = 2
            path.stroke()
            UIColor.systemYellow.setStroke()
            let hLine = UIBezierPath()
            hLine.move(to: CGPoint(x: 120, y: 150))
            hLine.addLine(to: CGPoint(x: 280, y: 150))
            hLine.lineWidth = 1.5
            hLine.stroke()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: UIColor.white
            ]
            "45.0 mm".draw(at: CGPoint(x: 170, y: 130), withAttributes: attrs)
        }
        return image.jpegData(compressionQuality: 0.8)?.base64EncodedString() ?? ""
    }

    private func generateMockHeatmap() -> String {
        let size = CGSize(width: 400, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let colors = [UIColor.systemGreen.cgColor, UIColor.systemYellow.cgColor, UIColor.systemRed.cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: colors as CFArray, locations: [0, 0.5, 1])!
            ctx.cgContext.drawRadialGradient(gradient,
                startCenter: CGPoint(x: 200, y: 150), startRadius: 0,
                endCenter: CGPoint(x: 200, y: 150), endRadius: 120,
                options: .drawsAfterEndLocation)
        }
        return image.jpegData(compressionQuality: 0.8)?.base64EncodedString() ?? ""
    }

    private func generateMockMask() -> String {
        let size = CGSize(width: 400, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 120, y: 80, width: 160, height: 140)).fill()
        }
        return image.jpegData(compressionQuality: 0.8)?.base64EncodedString() ?? ""
    }
}

// MARK: - Data Helpers

extension Data {
    mutating func appendMultipart(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartField(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}
