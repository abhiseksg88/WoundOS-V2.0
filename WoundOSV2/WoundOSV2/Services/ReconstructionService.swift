import Foundation
import UIKit
import Combine

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
}

enum UploadProgress {
    case uploading(fractionCompleted: Double)
    case processing(step: String)
    case complete(ServerResponse)
    case failed(Error)
}

protocol ReconstructionServiceProtocol {
    func uploadScan(
        frames: [SelectedFrame],
        woundPoint: CGPoint?,
        useWoundAmbit: Bool,
        generateSplat: Bool
    ) async throws -> ServerResponse

    func progressStream() -> AsyncStream<UploadProgress>

    /// Continue polling for Tier 2 gold results after Tier 1 was returned.
    /// Returns nil if already complete, or the gold ServerResponse when available.
    func pollForGoldResults(jobId: String) async throws -> ServerResponse?
}

// MARK: - Real Server Implementation (Async Job Polling)

final class ReconstructionService: ReconstructionServiceProtocol {
    private let baseURL: String
    private let authService: AuthService
    private var progressContinuation: AsyncStream<UploadProgress>.Continuation?
    private(set) var lastJobId: String?

    init(baseURL: String = ServerConfig.defaultBaseURL, authService: AuthService = .shared) {
        self.baseURL = baseURL
        self.authService = authService
    }

    func progressStream() -> AsyncStream<UploadProgress> {
        AsyncStream { continuation in
            self.progressContinuation = continuation
        }
    }

    func uploadScan(
        frames: [SelectedFrame],
        woundPoint: CGPoint?,
        useWoundAmbit: Bool,
        generateSplat: Bool
    ) async throws -> ServerResponse {
        // Step 1: Submit the scan — receive jobId
        let jobId = try await submitScan(
            frames: frames,
            woundPoint: woundPoint,
            useWoundAmbit: useWoundAmbit,
            generateSplat: generateSplat
        )

        // Step 2: Poll for results
        return try await pollForResults(jobId: jobId)
    }

    // MARK: - Submit Scan

    private func submitScan(
        frames: [SelectedFrame],
        woundPoint: CGPoint?,
        useWoundAmbit: Bool,
        generateSplat: Bool
    ) async throws -> String {
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

        // Add frames as JPEG
        for (index, frame) in frames.enumerated() {
            body.appendMultipart(boundary: boundary, name: "frames", filename: "frame_\(index).jpg",
                                 mimeType: "image/jpeg", data: frame.jpegData)
        }

        // Add poses as JSON
        let poses = frames.map { $0.pose }
        if let posesData = try? JSONEncoder().encode(poses) {
            body.appendMultipart(boundary: boundary, name: "poses", filename: "poses.json",
                                 mimeType: "application/json", data: posesData)
        }

        // Add intrinsics
        if let firstFrame = frames.first {
            if let intrinsicsData = try? JSONEncoder().encode(firstFrame.intrinsics) {
                body.appendMultipart(boundary: boundary, name: "intrinsics", filename: "intrinsics.json",
                                     mimeType: "application/json", data: intrinsicsData)
            }
        }

        // Add form fields
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

        progressContinuation?.yield(.uploading(fractionCompleted: 0.3))

        // Retry upload with exponential backoff
        var lastError: Error?
        for attempt in 0..<ServerConfig.maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                let submitResponse = try JSONDecoder().decode(JobSubmitResponse.self, from: data)
                progressContinuation?.yield(.uploading(fractionCompleted: 1.0))
                self.lastJobId = submitResponse.jobId
                return submitResponse.jobId
            } catch {
                lastError = error
                if attempt < ServerConfig.maxRetries - 1 {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }

        let error = lastError ?? URLError(.unknown)
        progressContinuation?.yield(.failed(error))
        throw error
    }

    // MARK: - Poll for Results

    private func pollForResults(jobId: String) async throws -> ServerResponse {
        let pollURL = URL(string: baseURL + ServerConfig.jobsEndpoint + "/\(jobId)")!
        let startTime = Date()

        progressContinuation?.yield(.processing(step: "Processing scan"))

        while true {
            // Check timeout
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > ServerConfig.maxPollDuration {
                let error = URLError(.timedOut)
                progressContinuation?.yield(.failed(error))
                throw error
            }

            // Wait before polling
            try await Task.sleep(nanoseconds: UInt64(ServerConfig.pollInterval * 1_000_000_000))

            // Poll
            var request = URLRequest(url: pollURL)
            request.timeoutInterval = 10

            if let token = authService.currentToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    continue // Retry on server error
                }

                let jobResponse = try JSONDecoder().decode(JobResponse.self, from: data)

                switch jobResponse.status {
                case .queued:
                    progressContinuation?.yield(.processing(step: "Queued"))

                case .tier1_processing:
                    progressContinuation?.yield(.processing(step: "Reconstructing 3D model"))

                case .tier1_complete:
                    // Tier 1 results available — return immediately
                    // iOS can show these while Tier 2 continues in background
                    if let result = jobResponse.result ?? jobResponse.preliminaryResult {
                        progressContinuation?.yield(.complete(result))
                        return result
                    }
                    progressContinuation?.yield(.processing(step: "Refining measurements"))

                case .tier2_processing:
                    // If we have preliminary results, return those
                    if let preliminary = jobResponse.preliminaryResult {
                        progressContinuation?.yield(.complete(preliminary))
                        return preliminary
                    }
                    progressContinuation?.yield(.processing(step: "Refining measurements"))

                case .complete:
                    if let result = jobResponse.result {
                        progressContinuation?.yield(.complete(result))
                        return result
                    }
                    if let preliminary = jobResponse.preliminaryResult {
                        progressContinuation?.yield(.complete(preliminary))
                        return preliminary
                    }

                case .failed:
                    let errorMessage = jobResponse.error ?? "Processing failed"
                    let error = NSError(domain: "WoundOS", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: errorMessage])
                    progressContinuation?.yield(.failed(error))
                    throw error
                }
            } catch let error as NSError where error.domain == "WoundOS" {
                throw error // Re-throw our own errors
            } catch {
                // Network error during poll — keep trying
                continue
            }
        }
    }
}

    // MARK: - Background Gold Polling

    func pollForGoldResults(jobId: String) async throws -> ServerResponse? {
        let pollURL = URL(string: baseURL + ServerConfig.jobsEndpoint + "/\(jobId)")!
        let startTime = Date()

        while true {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > ServerConfig.maxPollDuration { return nil }

            try await Task.sleep(nanoseconds: UInt64(ServerConfig.pollInterval * 1_000_000_000))

            var request = URLRequest(url: pollURL)
            request.timeoutInterval = 10
            if let token = authService.currentToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else { continue }

                let jobResponse = try JSONDecoder().decode(JobResponse.self, from: data)

                if jobResponse.status == .complete, let result = jobResponse.result {
                    return result
                }
                if jobResponse.status == .failed { return nil }
            } catch {
                continue
            }
        }
    }
}

// MARK: - Mock Server Implementation

final class MockReconstructionService: ReconstructionServiceProtocol {
    private var progressContinuation: AsyncStream<UploadProgress>.Continuation?

    func progressStream() -> AsyncStream<UploadProgress> {
        AsyncStream { continuation in
            self.progressContinuation = continuation
        }
    }

    func uploadScan(
        frames: [SelectedFrame],
        woundPoint: CGPoint?,
        useWoundAmbit: Bool,
        generateSplat: Bool
    ) async throws -> ServerResponse {
        // Simulate upload
        progressContinuation?.yield(.uploading(fractionCompleted: 0.3))
        try await Task.sleep(nanoseconds: 500_000_000)

        progressContinuation?.yield(.uploading(fractionCompleted: 0.7))
        try await Task.sleep(nanoseconds: 300_000_000)

        progressContinuation?.yield(.processing(step: "Reconstructing 3D model"))
        try await Task.sleep(nanoseconds: 600_000_000)

        progressContinuation?.yield(.processing(step: "Segmenting wound"))
        try await Task.sleep(nanoseconds: 400_000_000)

        progressContinuation?.yield(.processing(step: "Computing measurements"))
        try await Task.sleep(nanoseconds: 300_000_000)

        let response = ServerResponse(
            measurements: WoundMeasurement(
                areaCm2: 12.4, maxDepthMm: 5.2, avgDepthMm: 2.8,
                volumeMl: 3.1, lengthMm: 45.0, widthMm: 32.0, perimeterMm: 128.5
            ),
            annotatedImageBase64: generateMockAnnotatedImage(),
            depthHeatmapBase64: generateMockHeatmap(),
            woundMaskBase64: generateMockMask(),
            meshOBJData: nil,
            splatURL: nil,
            clinicalSummary: "Stage III pressure injury on sacrum measuring 12.4 cm². Wound bed shows 70% granulation tissue with 30% slough. Moderate serous exudate noted. Periwound skin intact with mild erythema extending 1cm from wound edge. Undermining detected at 2 o'clock position extending 8mm. Recommend continued offloading protocol, moisture-retentive dressing change every 48 hours, and nutritional optimization.",
            pushScore: PUSHScore(areaScore: 9, exudateScore: 2, surfaceTypeScore: 3),
            processingTimeMs: 2100
        )

        progressContinuation?.yield(.complete(response))
        return response
    }

    private func generateMockAnnotatedImage() -> String {
        let size = CGSize(width: 400, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            // Background
            UIColor.systemGray5.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Simulate wound area
            let woundRect = CGRect(x: 120, y: 80, width: 160, height: 140)
            UIColor.systemRed.withAlphaComponent(0.3).setFill()
            UIBezierPath(ovalIn: woundRect).fill()

            // Boundary
            UIColor.systemGreen.setStroke()
            let path = UIBezierPath(ovalIn: woundRect)
            path.lineWidth = 2
            path.stroke()

            // Dimension lines
            UIColor.systemYellow.setStroke()
            let hLine = UIBezierPath()
            hLine.move(to: CGPoint(x: 120, y: 150))
            hLine.addLine(to: CGPoint(x: 280, y: 150))
            hLine.lineWidth = 1.5
            hLine.stroke()

            // Label
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            "45.0 mm".draw(at: CGPoint(x: 170, y: 130), withAttributes: attrs)
        }
        return image.jpegData(compressionQuality: 0.8)?.base64EncodedString() ?? ""
    }

    private func generateMockHeatmap() -> String {
        let size = CGSize(width: 400, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            // Gradient heatmap
            let colors = [UIColor.systemGreen.cgColor, UIColor.systemYellow.cgColor, UIColor.systemRed.cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: colors as CFArray, locations: [0, 0.5, 1])!
            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: 200, y: 150), startRadius: 0,
                endCenter: CGPoint(x: 200, y: 150), endRadius: 120,
                options: .drawsAfterEndLocation
            )
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

    func pollForGoldResults(jobId: String) async throws -> ServerResponse? {
        // Mock: simulate gold results arriving 4 seconds after Tier 1
        try await Task.sleep(nanoseconds: 4_000_000_000)
        return ServerResponse(
            measurements: WoundMeasurement(
                areaCm2: 12.4, maxDepthMm: 5.2, avgDepthMm: 2.8,
                volumeMl: 3.1, lengthMm: 45.0, widthMm: 32.0, perimeterMm: 128.5
            ),
            annotatedImageBase64: generateMockAnnotatedImage(),
            depthHeatmapBase64: generateMockHeatmap(),
            woundMaskBase64: generateMockMask(),
            meshOBJData: nil,
            splatURL: nil,
            clinicalSummary: "Stage III pressure injury on sacrum measuring 12.4 cm\u{00B2}. Wound bed shows 70% granulation tissue with 30% slough. Moderate serous exudate noted. Periwound skin intact with mild erythema. Undermining detected at 2 o'clock extending 8mm. Gold-standard COLMAP reconstruction confirms measurements within 3% of preliminary.",
            pushScore: PUSHScore(areaScore: 9, exudateScore: 2, surfaceTypeScore: 3),
            processingTimeMs: 58400
        )
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
