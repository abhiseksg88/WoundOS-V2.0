import SwiftUI
import ARKit

struct LiDARDiagnosticsView: View {
    @State private var isLiDARAvailable = false
    @State private var supportsSceneDepth = false
    @State private var supportsSceneReconstruction = false
    @State private var depthRange: String = "N/A"

    var body: some View {
        List {
            Section("LiDAR Status") {
                statusRow("LiDAR Scanner", isLiDARAvailable)
                statusRow("Scene Depth", supportsSceneDepth)
                statusRow("Scene Reconstruction", supportsSceneReconstruction)
            }

            Section("Capabilities") {
                infoRow("Depth Range", depthRange)
                infoRow("Depth Resolution", supportsSceneDepth ? "256 × 192" : "N/A")
                infoRow("Confidence Map", supportsSceneDepth ? "Available" : "N/A")
            }

            Section("Supported Modes") {
                featureRow("Mesh Reconstruction", ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh))
                featureRow("Mesh Classification", ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification))
                featureRow("Person Occlusion", ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth))
            }

            if !isLiDARAvailable {
                Section {
                    VStack(alignment: .leading, spacing: WOSSpacing.sm) {
                        Text("LiDAR Not Available")
                            .font(WOSTypography.headline)
                            .foregroundColor(WOSColors.textPrimary)
                        Text("LiDAR scanning is available on iPhone 12 Pro and later Pro models. WoundOS will use standard ARKit depth estimation on this device.")
                            .font(WOSTypography.footnote)
                            .foregroundColor(WOSColors.textSecondary)
                    }
                    .padding(.vertical, WOSSpacing.sm)
                }
            }
        }
        .navigationTitle("LiDAR Diagnostics")
        .onAppear { checkCapabilities() }
    }

    private func statusRow(_ label: String, _ available: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(available ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(available ? "Available" : "Not Available")
                    .font(WOSTypography.caption)
                    .foregroundColor(available ? WOSColors.green : WOSColors.red)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(WOSTypography.body)
            Spacer()
            Text(value)
                .font(WOSTypography.footnote)
                .foregroundColor(WOSColors.textSecondary)
        }
    }

    private func featureRow(_ label: String, _ supported: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Image(systemName: supported ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(supported ? WOSColors.green : WOSColors.textTertiary)
        }
    }

    private func checkCapabilities() {
        isLiDARAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        supportsSceneDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        supportsSceneReconstruction = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        depthRange = isLiDARAvailable ? "0.2 – 5.0 m" : "N/A"
    }
}

#if DEBUG
struct LiDARDiagnosticsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            LiDARDiagnosticsView()
        }
    }
}
#endif
