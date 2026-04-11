import SwiftUI
import ARKit

/// Single-shot freeze-frame capture screen for the on-device clinical critical path.
///
/// Unlike the multi-view pan flow (`CaptureContainerView`), this view captures
/// **one frozen moment**: the nurse aims, taps the shutter, and we hand back a
/// `WoundCaptureSnapshot` containing the JPEG, intrinsics, pose, and LiDAR mesh.
/// The next screen (`FrozenBoundaryEditView`) lets the nurse draw the wound
/// boundary directly on that frozen image, and `MeasurementEngine` produces the
/// measurement entirely on-device.
struct SnapshotCaptureView: View {
    @StateObject private var viewModel = CaptureViewModel()
    @Environment(\.dismiss) private var dismiss

    /// Called when the nurse has frozen a usable snapshot.
    var onSnapshot: ((WoundCaptureSnapshot) -> Void)?

    @State private var isFreezing: Bool = false
    @State private var freezeError: String?

    var body: some View {
        ZStack {
            if ARWorldTrackingConfiguration.isSupported {
                ARViewRepresentable(sessionManager: viewModel.sessionManager)
                    .ignoresSafeArea()

                overlay
                if isFreezing {
                    freezeOverlay
                }
            } else {
                cameraNotAvailableView
            }
        }
        .statusBarHidden()
        .alert("Couldn't freeze frame", isPresented: Binding(
            get: { freezeError != nil },
            set: { if !$0 { freezeError = nil } }
        )) {
            Button("OK", role: .cancel) { freezeError = nil }
        } message: {
            Text(freezeError ?? "")
        }
        .onAppear {
            viewModel.startCapture()
        }
        .onDisappear {
            viewModel.stopCapture()
        }
    }

    // MARK: - Overlay

    private var overlay: some View {
        VStack {
            topBar
            Spacer()
            instructionPill
            Spacer().frame(height: WOSSpacing.md)
            shutterButton
                .padding(.bottom, WOSSpacing.lg)
        }
        .padding()
    }

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

            DistancePill(
                distance: viewModel.planeDistance,
                status: viewModel.distanceStatus
            )
        }
    }

    private var instructionPill: some View {
        let canFreeze = readyToFreeze
        let label: String = {
            if !viewModel.isLiDAREnhanced {
                return "Hold steady and tap the shutter"
            }
            if viewModel.meshAnchorCount < ServerConfig.lidarMinMeshAnchors {
                return "Slowly move the phone around the wound"
            }
            if viewModel.trackingState != .normal {
                return "Looking around to track..."
            }
            return canFreeze ? "Tap the shutter to freeze the wound"
                             : "Hold the phone 15-30 cm from the wound"
        }()
        return HStack(spacing: WOSSpacing.sm) {
            Image(systemName: canFreeze ? "checkmark.circle.fill" : "viewfinder")
                .font(.system(size: 14))
                .foregroundColor(canFreeze ? WOSColors.green : .white)
            Text(label)
                .font(WOSTypography.footnote)
                .foregroundColor(.white)
        }
        .padding(.horizontal, WOSSpacing.md)
        .padding(.vertical, WOSSpacing.sm)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var shutterButton: some View {
        let ready = readyToFreeze
        return Button(action: handleFreeze) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 84, height: 84)
                Circle()
                    .fill(ready ? WOSColors.accent : Color.gray.opacity(0.6))
                    .frame(width: 70, height: 70)
                Image(systemName: "camera.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .disabled(!ready || isFreezing)
    }

    private var freezeOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: WOSSpacing.md) {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.white)
                Text("Freezing wound...")
                    .font(WOSTypography.headline)
                    .foregroundColor(.white)
            }
        }
    }

    private var cameraNotAvailableView: some View {
        VStack(spacing: WOSSpacing.xl) {
            Image(systemName: "camera.fill")
                .font(.system(size: 64))
                .foregroundColor(WOSColors.textTertiary)
            Text("Camera Required")
                .font(WOSTypography.title2)
                .foregroundColor(WOSColors.textPrimary)
            Text("ARKit with a camera is required for wound capture.")
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

    // MARK: - Freeze logic

    private var readyToFreeze: Bool {
        guard viewModel.trackingState == .normal else { return false }
        if viewModel.isLiDAREnhanced {
            return viewModel.meshAnchorCount >= ServerConfig.lidarMinMeshAnchors
                && viewModel.sessionManager.bestLiDARFrame != nil
        } else {
            return viewModel.planeDistance != nil
        }
    }

    private func handleFreeze() {
        guard !isFreezing else { return }
        isFreezing = true
        WOSHaptics.capture()

        Task {
            let snapshot = await buildSnapshot()
            await MainActor.run {
                isFreezing = false
                if let snapshot = snapshot {
                    onSnapshot?(snapshot)
                } else {
                    freezeError = "We couldn't capture a usable frame. Try moving slowly around the wound for a few seconds."
                }
            }
        }
    }

    private func buildSnapshot() async -> WoundCaptureSnapshot? {
        let distance = viewModel.planeDistance
        if viewModel.isLiDAREnhanced {
            guard let payload = await viewModel.finalizeLiDARCapture() else {
                return nil
            }
            return WoundCaptureSnapshot(
                lidarPayload: payload,
                cameraToWoundDistanceMeters: distance
            )
        } else {
            // Non-LiDAR fallback: take the most recent best frame from the multi-view selector.
            // For the freeze-frame flow we don't actually need 30 frames — one sharp frame is fine.
            viewModel.sessionManager.pauseSession()
            guard let best = viewModel.sessionManager.selectedFrames.last
                ?? viewModel.sessionManager.bestLiDARFrame else {
                return nil
            }
            return WoundCaptureSnapshot(
                bestFrame: best,
                cameraToWoundDistanceMeters: distance ?? 0.20
            )
        }
    }
}

#if DEBUG
struct SnapshotCaptureView_Previews: PreviewProvider {
    static var previews: some View {
        SnapshotCaptureView()
    }
}
#endif
