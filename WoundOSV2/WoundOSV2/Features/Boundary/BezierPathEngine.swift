import UIKit

final class BezierPathEngine {
    // MARK: - Douglas-Peucker Simplification

    static func simplify(points: [CGPoint], tolerance: CGFloat = 2.0) -> [CGPoint] {
        guard points.count > 2 else { return points }

        var maxDist: CGFloat = 0
        var maxIndex = 0

        let first = points.first!
        let last = points.last!

        for i in 1..<(points.count - 1) {
            let dist = perpendicularDistance(point: points[i], lineStart: first, lineEnd: last)
            if dist > maxDist {
                maxDist = dist
                maxIndex = i
            }
        }

        if maxDist > tolerance {
            let left = simplify(points: Array(points[0...maxIndex]), tolerance: tolerance)
            let right = simplify(points: Array(points[maxIndex...]), tolerance: tolerance)
            return Array(left.dropLast()) + right
        } else {
            return [first, last]
        }
    }

    // MARK: - Catmull-Rom to Cubic Bezier

    static func catmullRomToBezierPath(points: [CGPoint], closed: Bool = true, alpha: CGFloat = 0.5) -> UIBezierPath {
        let path = UIBezierPath()
        guard points.count >= 3 else {
            if let first = points.first {
                path.move(to: first)
                for p in points.dropFirst() { path.addLine(to: p) }
            }
            return path
        }

        let pts: [CGPoint]
        if closed {
            pts = [points.last!] + points + [points.first!, points[1]]
        } else {
            pts = [points.first!] + points + [points.last!]
        }

        path.move(to: pts[1])

        for i in 1..<(pts.count - 2) {
            let p0 = pts[i - 1]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[i + 2]

            let d1 = distance(p0, p1)
            let d2 = distance(p1, p2)
            let d3 = distance(p2, p3)

            let b1: CGPoint
            let b2: CGPoint

            if d1 > 0.001 && d2 > 0.001 {
                let a = pow(d1, 2 * alpha)
                let b = pow(d2, 2 * alpha)
                b1 = CGPoint(
                    x: (b * p0.x - a * p2.x + (2 * a + 3 * sqrt(a * b) + b) * p1.x) / (3 * sqrt(a * b) * (1 + sqrt(a / max(b, 0.001)))),
                    y: (b * p0.y - a * p2.y + (2 * a + 3 * sqrt(a * b) + b) * p1.y) / (3 * sqrt(a * b) * (1 + sqrt(a / max(b, 0.001))))
                )
            } else {
                b1 = p1
            }

            if d3 > 0.001 && d2 > 0.001 {
                let a = pow(d3, 2 * alpha)
                let b = pow(d2, 2 * alpha)
                b2 = CGPoint(
                    x: (b * p3.x - a * p1.x + (2 * a + 3 * sqrt(a * b) + b) * p2.x) / (3 * sqrt(a * b) * (1 + sqrt(a / max(b, 0.001)))),
                    y: (b * p3.y - a * p1.y + (2 * a + 3 * sqrt(a * b) + b) * p2.y) / (3 * sqrt(a * b) * (1 + sqrt(a / max(b, 0.001))))
                )
            } else {
                b2 = p2
            }

            path.addCurve(to: p2, controlPoint1: b1, controlPoint2: b2)
        }

        if closed { path.close() }
        return path
    }

    // MARK: - Control Point Handles

    static func controlHandles(for points: [CGPoint]) -> [(point: CGPoint, handleIn: CGPoint, handleOut: CGPoint)] {
        guard points.count >= 3 else {
            return points.map { ($0, $0, $0) }
        }

        return points.enumerated().map { index, point in
            let prev = points[(index - 1 + points.count) % points.count]
            let next = points[(index + 1) % points.count]

            let handleIn = CGPoint(
                x: point.x + (prev.x - next.x) * 0.2,
                y: point.y + (prev.y - next.y) * 0.2
            )
            let handleOut = CGPoint(
                x: point.x - (prev.x - next.x) * 0.2,
                y: point.y - (prev.y - next.y) * 0.2
            )

            return (point, handleIn, handleOut)
        }
    }

    // MARK: - Normalize to [0,1] coordinates

    static func normalizePoints(_ points: [CGPoint], imageSize: CGSize) -> [CGPoint] {
        points.map { CGPoint(x: $0.x / imageSize.width, y: $0.y / imageSize.height) }
    }

    static func denormalizePoints(_ points: [CGPoint], imageSize: CGSize) -> [CGPoint] {
        points.map { CGPoint(x: $0.x * imageSize.width, y: $0.y * imageSize.height) }
    }

    // MARK: - Helpers

    private static func perpendicularDistance(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lineLength = sqrt(dx * dx + dy * dy)
        guard lineLength > 0.001 else { return distance(point, lineStart) }

        return abs(dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x) / lineLength
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
    }
}
