import UIKit
import SceneKit

final class MeshViewerController: UIViewController {
    let sceneView = SCNView()
    private var meshNode: SCNNode?
    private var boundaryNode: SCNNode?
    private var dimensionNodes: [SCNNode] = []
    private var deepestPointNode: SCNNode?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSceneView()
        loadMockMesh()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sceneView.frame = view.bounds
    }

    private func setupSceneView() {
        sceneView.backgroundColor = .black
        sceneView.allowsCameraControl = true
        sceneView.autoenablesDefaultLighting = true
        sceneView.antialiasingMode = .multisampling4X

        let scene = SCNScene()

        // Ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 600
        ambientLight.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambientLight)

        // Directional light
        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.light?.intensity = 800
        directionalLight.light?.color = UIColor.white
        directionalLight.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(directionalLight)

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = false
        cameraNode.camera?.fieldOfView = 60
        cameraNode.position = SCNVector3(0, 0.15, 0.3)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)

        sceneView.scene = scene
        sceneView.pointOfView = cameraNode
        view.addSubview(sceneView)
    }

    // MARK: - Mock Mesh (Bowl Shape)

    func loadMockMesh() {
        let mesh = generateBowlMesh(radius: 0.06, depth: 0.02, segments: 32)
        meshNode = mesh
        sceneView.scene?.rootNode.addChildNode(mesh)
        addDeepestPointMarker(at: SCNVector3(0, -0.02, 0))
        addBoundaryContour(radius: 0.06, segments: 32)
        addDimensionLines(length: 0.12, width: 0.10)
    }

    func loadOBJMesh(data: Data) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("wound.obj")
        try? data.write(to: tempURL)

        guard let scene = try? SCNScene(url: tempURL, options: nil) else { return }
        let node = SCNNode()
        for child in scene.rootNode.childNodes {
            node.addChildNode(child)
        }
        meshNode?.removeFromParentNode()
        meshNode = node
        sceneView.scene?.rootNode.addChildNode(node)
    }

    func takeSnapshot() -> UIImage? {
        sceneView.snapshot()
    }

    // MARK: - Generate Bowl Mesh

    private func generateBowlMesh(radius: Float, depth: Float, segments: Int) -> SCNNode {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var colors: [SCNVector3] = []
        var indices: [Int32] = []

        let rings = segments / 2

        for ring in 0...rings {
            let t = Float(ring) / Float(rings)
            let r = radius * t
            let y = -depth * (1 - t * t) // Parabolic bowl

            for seg in 0..<segments {
                let angle = Float(seg) / Float(segments) * 2 * .pi
                let x = r * cos(angle)
                let z = r * sin(angle)

                vertices.append(SCNVector3(x, y, z))

                // Normal (approximate)
                let nx = cos(angle) * 0.3
                let ny: Float = 0.9
                let nz = sin(angle) * 0.3
                let len = sqrt(nx*nx + ny*ny + nz*nz)
                normals.append(SCNVector3(nx/len, ny/len, nz/len))

                // Color by depth (green=shallow, yellow=mid, red=deep)
                let depthRatio = abs(y) / depth
                let r_color: Float = depthRatio
                let g_color: Float = 1 - depthRatio
                colors.append(SCNVector3(r_color, g_color, 0))
            }
        }

        // Generate triangle indices
        for ring in 0..<rings {
            for seg in 0..<segments {
                let current = Int32(ring * segments + seg)
                let next = Int32(ring * segments + (seg + 1) % segments)
                let below = Int32((ring + 1) * segments + seg)
                let belowNext = Int32((ring + 1) * segments + (seg + 1) % segments)

                indices.append(contentsOf: [current, below, next])
                indices.append(contentsOf: [next, below, belowNext])
            }
        }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)

        let colorData = Data(bytes: colors, count: colors.count * MemoryLayout<SCNVector3>.stride)
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.stride
        )

        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<Int32>.size
        )

        let geometry = SCNGeometry(sources: [vertexSource, normalSource, colorSource], elements: [element])
        geometry.firstMaterial?.lightingModel = .phong
        geometry.firstMaterial?.isDoubleSided = true

        return SCNNode(geometry: geometry)
    }

    // MARK: - Boundary Contour

    private func addBoundaryContour(radius: Float, segments: Int) {
        var points: [SCNVector3] = []
        for i in 0...segments {
            let angle = Float(i) / Float(segments) * 2 * .pi
            points.append(SCNVector3(radius * cos(angle), 0.001, radius * sin(angle)))
        }

        let source = SCNGeometrySource(vertices: points)
        var indices: [Int32] = []
        for i in 0..<segments {
            indices.append(Int32(i))
            indices.append(Int32(i + 1))
        }
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(data: indexData, primitiveType: .line, primitiveCount: segments, bytesPerIndex: MemoryLayout<Int32>.size)

        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial?.diffuse.contents = UIColor.systemGreen
        geometry.firstMaterial?.lightingModel = .constant

        let node = SCNNode(geometry: geometry)
        boundaryNode = node
        sceneView.scene?.rootNode.addChildNode(node)
    }

    // MARK: - Deepest Point Marker

    private func addDeepestPointMarker(at position: SCNVector3) {
        let sphere = SCNSphere(radius: 0.002)
        sphere.firstMaterial?.diffuse.contents = UIColor.systemRed
        sphere.firstMaterial?.lightingModel = .constant

        let node = SCNNode(geometry: sphere)
        node.position = position
        deepestPointNode = node
        sceneView.scene?.rootNode.addChildNode(node)

        // Label
        let text = SCNText(string: "5.2 mm", extrusionDepth: 0.001)
        text.font = UIFont.systemFont(ofSize: 0.008, weight: .bold)
        text.firstMaterial?.diffuse.contents = UIColor.white
        text.firstMaterial?.lightingModel = .constant

        let textNode = SCNNode(geometry: text)
        textNode.position = SCNVector3(position.x + 0.005, position.y - 0.005, position.z)
        textNode.scale = SCNVector3(1, 1, 1)
        sceneView.scene?.rootNode.addChildNode(textNode)
    }

    // MARK: - Dimension Lines

    private func addDimensionLines(length: Float, width: Float) {
        addLine(from: SCNVector3(-length/2, 0.002, 0), to: SCNVector3(length/2, 0.002, 0), color: .systemYellow, label: "45 mm")
        addLine(from: SCNVector3(0, 0.002, -width/2), to: SCNVector3(0, 0.002, width/2), color: .systemYellow, label: "32 mm")
    }

    private func addLine(from: SCNVector3, to: SCNVector3, color: UIColor, label: String) {
        let source = SCNGeometrySource(vertices: [from, to])
        let indexData = Data(bytes: [Int32(0), Int32(1)] as [Int32], count: 2 * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(data: indexData, primitiveType: .line, primitiveCount: 1, bytesPerIndex: MemoryLayout<Int32>.size)

        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial?.diffuse.contents = color
        geometry.firstMaterial?.lightingModel = .constant

        let node = SCNNode(geometry: geometry)
        sceneView.scene?.rootNode.addChildNode(node)
        dimensionNodes.append(node)
    }
}
