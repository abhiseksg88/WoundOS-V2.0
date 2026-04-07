import SceneKit
import ARKit

final class ArcCaptureGuide {
    let rootNode = SCNNode()

    private var arcSegments: [SCNNode] = []
    private let segmentCount = 12
    private let arcRadius: Float = 0.25
    private var coveredSegments: Set<Int> = []

    init() {
        setupArc()
    }

    private func setupArc() {
        for i in 0..<segmentCount {
            let startAngle = Float(i) * (2 * .pi / Float(segmentCount))
            let endAngle = Float(i + 1) * (2 * .pi / Float(segmentCount))

            let path = UIBezierPath(
                arcCenter: .zero,
                radius: CGFloat(arcRadius),
                startAngle: CGFloat(startAngle),
                endAngle: CGFloat(endAngle),
                clockwise: true
            )

            let shape = SCNShape(path: path, extrusionDepth: 0.002)
            shape.firstMaterial?.diffuse.contents = UIColor.systemGray.withAlphaComponent(0.4)
            shape.firstMaterial?.isDoubleSided = true

            let node = SCNNode(geometry: shape)
            node.eulerAngles.x = -.pi / 2
            rootNode.addChildNode(node)
            arcSegments.append(node)
        }
    }

    func updateCoverage(cameraAngle: Float) {
        let segmentIndex = Int((cameraAngle / (2 * .pi)) * Float(segmentCount)) % segmentCount
        let normalizedIndex = segmentIndex < 0 ? segmentIndex + segmentCount : segmentIndex

        if !coveredSegments.contains(normalizedIndex) {
            coveredSegments.insert(normalizedIndex)
            if normalizedIndex < arcSegments.count {
                let node = arcSegments[normalizedIndex]
                node.geometry?.firstMaterial?.diffuse.contents = UIColor.systemTeal.withAlphaComponent(0.8)

                let fadeIn = SCNAction.fadeIn(duration: 0.2)
                node.runAction(fadeIn)
            }
        }
    }

    func placeAtAnchor(transform: simd_float4x4) {
        rootNode.simdTransform = transform
        rootNode.position.y += 0.01
    }

    var coverageFraction: Float {
        Float(coveredSegments.count) / Float(segmentCount)
    }

    func reset() {
        coveredSegments.removeAll()
        for node in arcSegments {
            node.geometry?.firstMaterial?.diffuse.contents = UIColor.systemGray.withAlphaComponent(0.4)
        }
    }
}
