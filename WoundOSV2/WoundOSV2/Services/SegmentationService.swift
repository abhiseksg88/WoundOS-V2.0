import UIKit

protocol SegmentationServiceProtocol {
    func segmentWound(image: UIImage) async throws -> UIImage
}

final class SegmentationService: SegmentationServiceProtocol {
    private let baseURL: String
    private let authService: AuthService

    init(baseURL: String = ServerConfig.defaultBaseURL, authService: AuthService = .shared) {
        self.baseURL = baseURL
        self.authService = authService
    }

    func segmentWound(image: UIImage) async throws -> UIImage {
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw SegmentationError.invalidImage
        }

        let url = URL(string: baseURL + ServerConfig.segmentEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = ServerConfig.uploadTimeout

        if let token = authService.currentToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendMultipart(boundary: boundary, name: "image", filename: "wound.jpg",
                             mimeType: "image/jpeg", data: imageData)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw SegmentationError.serverError
        }

        guard let maskImage = UIImage(data: data) else {
            throw SegmentationError.invalidResponse
        }

        return maskImage
    }
}

final class MockSegmentationService: SegmentationServiceProtocol {
    func segmentWound(image: UIImage) async throws -> UIImage {
        try await Task.sleep(nanoseconds: 500_000_000)

        let size = image.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            let inset = min(size.width, size.height) * 0.2
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)).fill()
        }
    }
}

enum SegmentationError: LocalizedError {
    case invalidImage
    case serverError
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Failed to encode image for segmentation"
        case .serverError: return "Segmentation server returned an error"
        case .invalidResponse: return "Invalid mask image in server response"
        }
    }
}
