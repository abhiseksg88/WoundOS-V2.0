import UIKit
import ARKit
import SceneKit

final class ARCaptureViewController: UIViewController {
    let sceneView = ARSCNView()
    var sessionManager: ARSessionManager?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSceneView()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sceneView.frame = view.bounds
    }

    private func setupSceneView() {
        sceneView.autoenablesDefaultLighting = true
        sceneView.automaticallyUpdatesLighting = true
        sceneView.rendersCameraGrain = true
        sceneView.rendersMotionBlur = false

        view.addSubview(sceneView)
    }

    func configure(with manager: ARSessionManager) {
        self.sessionManager = manager
        sceneView.session = manager.session
        sceneView.delegate = self
    }
}

extension ARCaptureViewController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // SceneKit overlay updates happen here if needed
    }

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }

        let planeGeometry = SCNPlane(
            width: CGFloat(planeAnchor.planeExtent.width),
            height: CGFloat(planeAnchor.planeExtent.height)
        )
        planeGeometry.firstMaterial?.diffuse.contents = UIColor.systemTeal.withAlphaComponent(0.1)
        planeGeometry.firstMaterial?.isDoubleSided = true

        let planeNode = SCNNode(geometry: planeGeometry)
        planeNode.eulerAngles.x = -.pi / 2
        planeNode.opacity = 0.5
        node.addChildNode(planeNode)
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        guard let planeNode = node.childNodes.first,
              let planeGeometry = planeNode.geometry as? SCNPlane else { return }

        planeGeometry.width = CGFloat(planeAnchor.planeExtent.width)
        planeGeometry.height = CGFloat(planeAnchor.planeExtent.height)
    }
}
