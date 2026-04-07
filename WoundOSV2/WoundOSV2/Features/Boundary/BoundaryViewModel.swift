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
        // Generate elliptical boundary as default (would come from server mask in real usage)
        let cx: CGFloat = 200
        let cy: CGFloat = 150
        let rx: CGFloat = 80
        let ry: CGFloat = 70
        let count = 24

        boundaryPoints = (0..<count).map { i in
            let angle = (2 * .pi / CGFloat(count)) * CGFloat(i)
            return CGPoint(
                x: cx + rx * cos(angle),
                y: cy + ry * sin(angle)
            )
        }
    }
}
