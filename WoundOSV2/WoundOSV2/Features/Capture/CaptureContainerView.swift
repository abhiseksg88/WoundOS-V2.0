import SwiftUI
import ARKit

/// Result of a capture session: either multi-view frames (Tier 2) or
/// a LiDAR payload (Tier 1).
enum CaptureResult {
    case multiview(frames: [SelectedFrame], woundPoint: CGPoint?)
    case lidar(payload: LiDARScanPayload, woundPoint: CGPoint?)
}

struct CaptureContainerView: View {
    @StateObject private var viewModel = CaptureViewModel()
    @Environment(\.dismiss) private var dismiss
    var onComplete: ((CaptureResult) -> Void)?

    @State private var isFinalizing: Bool = false

    var body: some View {
        ZStack {
            if ARWorldTrackingConfiguration.isSupported {
                arCameraView
                tapMarkerOverlay
                captureOverlay
                if isFinalizing {
                    finalizingOverlay
                }
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
                handleCaptureComplete()
            }
        }
    }

    private func handleCaptureComplete() {
        switch viewModel.captureMode {
        case .lidar:
            isFinalizing = true
            Task {
                let payload = await viewModel.finalizeLiDARCapture()
                await MainActor.run {
                    isFinalizing = false
                    if let payload = payload {
                        onComplete?(.lidar(
                            payload: payload,
                            woundPoint: viewModel.woundPointNormalized
                        ))
                    } else {
                        // Fallback: treat as failed multiview if LiDAR finalization failed
                        onComplete?(.multiview(
                            frames: viewModel.selectedFrames,
                            woundPoint: viewModel.woundPointNormalized
                        ))
                    }
                }
            }
        case .multiview:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onComplete?(.multiview(
                    frames: viewModel.selectedFrames,
                    woundPoint: viewModel.woundPointNormalized
                ))
            }
        }
    }

    // MARK: - AR Camera
    private var arCameraView: some View {
        ARViewRepresentable(sessionManager: viewModel.sessionManager)
            .ignoresSafeArea()
    }

    // MARK: - Tap-to-mark wound center (Apple Measure-style)
    private var tapMarkerOverlay: some View {
        GeometryReader { geometry in
            ZStack {
                // Capture taps anywhere on screen → normalized [0,1] wound point
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let nx = location.x / geometry.size.width
                        let ny = location.y / geometry.size.height
                        viewModel.setWoundPoint(CGPoint(x: nx, y: ny))
                        WOSHaptics.selection()
                    }

                // Render the marker if a wound point is set
                if let normPoint = viewModel.woundPointNormalized {
                    let x = normPoint.x * geometry.size.width
                    let y = normPoint.y * geometry.size.height
                    ZStack {
                        Circle()
                            .stroke(WOSColors.accent, lineWidth: 3)
                            .frame(width: 44, height: 44)
                        Circle()
                            .fill(WOSColors.accent)
                            .frame(width: 8, height: 8)
                    }
                    .position(x: x, y: y)
                    .shadow(radius: 4)
                }
            }
        }
    }

    // MARK: - Overlay HUD
    private var captureOverlay: some View {
        VStack {
            topBar
            Spacer()
            bottomHUD
            if viewModel.captureMode == .lidar {
                captureButton
            }
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
            if viewModel.captureMode == .lidar {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                Text("\(viewModel.meshAnchorCount)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            } else {
                Text("\(viewModel.selectedFrameCount)/\(viewModel.targetFrames)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

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
            if viewModel.captureMode == .lidar {
                lidarHint
            } else {
                MotionFeedback(status: viewModel.motionStatus)
            }

            HStack {
                if viewModel.captureMode == .multiview {
                    CoverageRadar(
                        coverage: viewModel.arcCoverage,
                        targetCoverage: ServerConfig.minArcCoverageDegrees
                    )
                    .frame(width: 64, height: 64)
                }

                Spacer()

                DistancePill(
                    distance: viewModel.planeDistance,
                    status: viewModel.distanceStatus
                )
            }
        }
    }

    // MARK: - LiDAR Hint
    private var lidarHint: some View {
        HStack(spacing: WOSSpacing.sm) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 14))
            if viewModel.woundPointNormalized == nil {
                Text("Tap the wound to mark its center")
                    .font(WOSTypography.footnote)
            } else if viewModel.meshAnchorCount < ServerConfig.lidarMinMeshAnchors {
                Text("Slowly pan around the wound...")
                    .font(WOSTypography.footnote)
            } else {
                Text("Ready — tap Capture below")
                    .font(WOSTypography.footnote)
                    .foregroundColor(WOSColors.green)
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, WOSSpacing.md)
        .padding(.vertical, WOSSpacing.sm)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    // MARK: - LiDAR Capture Button
    private var captureButton: some View {
        let isReady = viewModel.meshAnchorCount >= ServerConfig.lidarMinMeshAnchors
            && viewModel.woundPointNormalized != nil
            && viewModel.trackingState == .normal

        return Button(action: {
            viewModel.userCompleteCapture()
            WOSHaptics.complete()
        }) {
            ZStack {
                Circle()
                    .fill(isReady ? WOSColors.accent : Color.gray.opacity(0.5))
                    .frame(width: 72, height: 72)
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 80, height: 80)
                Image(systemName: "camera.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .disabled(!isReady)
        .padding(.bottom, WOSSpacing.lg)
    }

    // MARK: - Finalizing overlay
    private var finalizingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: WOSSpacing.lg) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("Building 3D mesh...")
                    .font(WOSTypography.headline)
                    .foregroundColor(.white)
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
