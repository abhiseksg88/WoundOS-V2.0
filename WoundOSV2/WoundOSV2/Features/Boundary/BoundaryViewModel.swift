import SwiftUI
import Combine

enum BoundaryEditMode: String, CaseIterable {
    case auto = "Auto"
    case adjust = "Adjust"
    case draw = "Draw"
}

final class BoundaryViewModel: ObservableObject {
    @Published var mode: BoundaryEditMode = .auto
    @Published var boundaryPoints: [CGPoint] = []
    @Published var drawingPoints: [CGPoint] = []
    @Published var selectedHandleIndex: Int?
    @Published var imageSize: CGSize = .zero
    @Published var isLoadingBoundary: Bool = false

    let woundImage: UIImage?
    let maskImage: UIImage?
    var onAccept: (([CGPoint]) -> Void)?

    init(woundImage: UIImage?, maskImage: UIImage?) {
        self.woundImage = woundImage
        self.maskImage = maskImage
        generateInitialBoundary()
    }

    func acceptBoundary() {
        let normalizedPoints = BezierPathEngine.normalizePoints(boundaryPoints, imageSize: imageSize)
        onAccept?(normalizedPoints)
    }

    func handleDrag(index: Int, location: CGPoint) {
        guard index < boundaryPoints.count else { return }
        boundaryPoints[index] = location
    }

    func addDrawingPoint(_ point: CGPoint) {
        drawingPoints.append(point)
    }

    func finishDrawing() {
        guard drawingPoints.count > 3 else { return }
        let simplified = BezierPathEngine.simplify(points: drawingPoints, tolerance: 4.0)
        boundaryPoints = simplified
        drawingPoints = []
        mode = .adjust
    }

    func bezierPath() -> UIBezierPath {
        BezierPathEngine.catmullRomToBezierPath(points: boundaryPoints, closed: true)
    }

    private func generateInitialBoundary() {
        // Try to extract boundary from the server-provided wound mask
        if let mask = maskImage, let contourPoints = extractContourFromMask(mask) {
            boundaryPoints = contourPoints
            return
        }

        // Fallback: generate elliptical boundary centered in the image
        let width = woundImage?.size.width ?? 400
        let height = woundImage?.size.height ?? 300
        let cx = width / 2
        let cy = height / 2
        let rx = width * 0.2
        let ry = height * 0.23
        let count = 24

        boundaryPoints = (0..<count).map { i in
            let angle = (2 * .pi / CGFloat(count)) * CGFloat(i)
            return CGPoint(x: cx + rx * cos(angle), y: cy + ry * sin(angle))
        }
    }

    private func extractContourFromMask(_ mask: UIImage) -> [CGPoint]? {
        guard let cgImage = mask.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0 && height > 0 else { return nil }

        // Render mask to grayscale pixel buffer
        let bytesPerRow = width
        var pixelData = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Find boundary pixels (white pixels adjacent to black pixels)
        var boundaryPixels: [CGPoint] = []
        let threshold: UInt8 = 127

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                guard pixelData[idx] > threshold else { continue }

                // Check if any 4-connected neighbor is below threshold
                let up = pixelData[(y - 1) * width + x]
                let down = pixelData[(y + 1) * width + x]
                let left = pixelData[y * width + (x - 1)]
                let right = pixelData[y * width + (x + 1)]

                if up <= threshold || down <= threshold || left <= threshold || right <= threshold {
                    boundaryPixels.append(CGPoint(x: CGFloat(x), y: CGFloat(y)))
                }
            }
        }

        guard boundaryPixels.count >= 10 else { return nil }

        // Subsample to ~48 points for smooth editing
        let targetCount = 48
        let step = max(1, boundaryPixels.count / targetCount)

        // Order boundary points by angle from centroid
        let cx = boundaryPixels.reduce(0.0) { $0 + $1.x } / CGFloat(boundaryPixels.count)
        let cy = boundaryPixels.reduce(0.0) { $0 + $1.y } / CGFloat(boundaryPixels.count)

        let sorted = boundaryPixels.sorted { a, b in
            atan2(a.y - cy, a.x - cx) < atan2(b.y - cy, b.x - cx)
        }

        var sampled: [CGPoint] = []
        for i in stride(from: 0, to: sorted.count, by: step) {
            sampled.append(sorted[i])
        }

        guard sampled.count >= 6 else { return nil }

        // Simplify with Douglas-Peucker
        return BezierPathEngine.simplify(points: sampled, tolerance: 3.0)
    }
}
