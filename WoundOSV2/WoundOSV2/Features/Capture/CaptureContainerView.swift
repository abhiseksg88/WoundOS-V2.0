import SwiftUI
import ARKit

struct CaptureContainerView: View {
    @StateObject private var viewModel = CaptureViewModel()
    @Environment(\.dismiss) private var dismiss
    var onComplete: (([SelectedFrame]) -> Void)?

    var body: some View {
        ZStack {
            if ARWorldTrackingConfiguration.isSupported {
                arCameraView
                captureOverlay
            } else {
                cameraNotAvailableView
            }
        }
        .statusBarHidden()
        .onAppear {
            viewModel.startCapture()
        }
        .onDisappear {
            viewModel.stopCapture()
        }
        .onChange(of: viewModel.state) { newState in
            if newState == .complete {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onComplete?(viewModel.selectedFrames)
                }
            }
        }
    }

    // MARK: - AR Camera
    private var arCameraView: some View {
        ARViewRepresentable(sessionManager: viewModel.sessionManager)
            .ignoresSafeArea()
    }

    // MARK: - Overlay HUD
    private var captureOverlay: some View {
        VStack {
            topBar
            Spacer()
            bottomHUD
        }
        .padding()
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            Spacer()

            if viewModel.isLiDAREnhanced {
                HStack(spacing: 4) {
                    Image(systemName: "sensor.tag.radiowaves.forward")
                        .font(.system(size: 11))
                    Text("LiDAR")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(WOSColors.accent.opacity(0.8))
                .clipShape(Capsule())
            }

            Spacer()

            frameCounter
        }
    }

    private var frameCounter: some View {
        HStack(spacing: 6) {
            Text("\(viewModel.selectedFrameCount)/\(viewModel.targetFrames)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            WOSProgressRing(
                progress: viewModel.progress,
                lineWidth: 3,
                color: .white
            )
            .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    // MARK: - Bottom HUD
    private var bottomHUD: some View {
        VStack(spacing: WOSSpacing.md) {
            MotionFeedback(status: viewModel.motionStatus)

            HStack {
                CoverageRadar(
                    coverage: viewModel.arcCoverage,
                    targetCoverage: ServerConfig.minArcCoverageDegrees
                )
                .frame(width: 64, height: 64)

                Spacer()

                DistancePill(
                    distance: viewModel.planeDistance,
                    status: viewModel.distanceStatus
                )
            }
        }
    }

    // MARK: - No Camera View
    private var cameraNotAvailableView: some View {
        VStack(spacing: WOSSpacing.xl) {
            Image(systemName: "camera.fill")
                .font(.system(size: 64))
                .foregroundColor(WOSColors.textTertiary)

            Text("Camera Required")
                .font(WOSTypography.title2)
                .foregroundColor(WOSColors.textPrimary)

            Text("ARKit with a camera is required for wound capture. Please use a physical device.")
                .font(WOSTypography.body)
                .foregroundColor(WOSColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, WOSSpacing.xxxl)

            WOSButton(title: "Go Back", icon: "chevron.left", style: .secondary) {
                dismiss()
            }
            .padding(.horizontal, WOSSpacing.xxxl)
        }
    }
}

// MARK: - ARView UIViewControllerRepresentable

struct ARViewRepresentable: UIViewControllerRepresentable {
    let sessionManager: ARSessionManager

    func makeUIViewController(context: Context) -> ARCaptureViewController {
        let vc = ARCaptureViewController()
        vc.configure(with: sessionManager)
        return vc
    }

    func updateUIViewController(_ uiViewController: ARCaptureViewController, context: Context) {}
}

#if DEBUG
struct CaptureContainerView_Previews: PreviewProvider {
    static var previews: some View {
        CaptureContainerView()
    }
}
#endif
