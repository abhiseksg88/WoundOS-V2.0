import SwiftUI
import SceneKit

struct MeshViewerView: View {
    var meshData: Data?
    @State private var viewerMode: ViewerMode = .clinical

    enum ViewerMode: String, CaseIterable {
        case clinical = "Clinical"
        case photorealistic = "Photorealistic"
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewerToggle(mode: $viewerMode)
                .padding()

            ZStack {
                MeshViewerRepresentable(meshData: meshData)
                    .ignoresSafeArea(edges: .bottom)

                if viewerMode == .photorealistic {
                    splatPlaceholder
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("3D Viewer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var splatPlaceholder: some View {
        VStack(spacing: WOSSpacing.lg) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.5))
            Text("Photorealistic view")
                .font(WOSTypography.title3)
                .foregroundColor(.white.opacity(0.7))
            Text("Download .splat file from results to enable")
                .font(WOSTypography.caption)
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.7))
    }
}

struct MeshViewerRepresentable: UIViewControllerRepresentable {
    var meshData: Data?

    func makeUIViewController(context: Context) -> MeshViewerController {
        let vc = MeshViewerController()
        if let data = meshData {
            vc.loadOBJMesh(data: data)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MeshViewerController, context: Context) {}
}

#if DEBUG
struct MeshViewerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MeshViewerView()
        }
    }
}
#endif
