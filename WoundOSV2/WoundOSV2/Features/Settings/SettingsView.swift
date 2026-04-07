import SwiftUI
import ARKit

struct SettingsView: View {
    @AppStorage("serverBaseURL") private var serverBaseURL: String = ServerConfig.defaultBaseURL
    @AppStorage("useMockServer") private var useMockServer: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                serverSection
                deviceSection
                lidarDiagnosticsSection
                aboutSection
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Server
    private var serverSection: some View {
        Section {
            Toggle("Use Mock Server", isOn: $useMockServer)

            if !useMockServer {
                VStack(alignment: .leading, spacing: WOSSpacing.xs) {
                    Text("Server URL")
                        .font(WOSTypography.caption)
                        .foregroundColor(WOSColors.textSecondary)
                    TextField("https://...", text: $serverBaseURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(WOSTypography.body)
                }
            }
        } header: {
            Text("Server")
        } footer: {
            Text("Mock server returns sample data for testing. Disable to use a live reconstruction server.")
        }
    }

    // MARK: - Device
    private var deviceSection: some View {
        Section("Device Capabilities") {
            HStack {
                Label("ARKit", systemImage: "arkit")
                Spacer()
                Text(ARWorldTrackingConfiguration.isSupported ? "Supported" : "Not Supported")
                    .foregroundColor(ARWorldTrackingConfiguration.isSupported ? WOSColors.green : WOSColors.red)
                    .font(WOSTypography.footnote)
            }

            HStack {
                Label("LiDAR Scanner", systemImage: "sensor.tag.radiowaves.forward")
                Spacer()
                Text(lidarAvailable ? "Available" : "Not Available")
                    .foregroundColor(lidarAvailable ? WOSColors.green : WOSColors.textTertiary)
                    .font(WOSTypography.footnote)
            }

            HStack {
                Label("Scene Depth", systemImage: "cube.transparent")
                Spacer()
                Text(sceneDepthAvailable ? "Supported" : "Not Supported")
                    .foregroundColor(sceneDepthAvailable ? WOSColors.green : WOSColors.textTertiary)
                    .font(WOSTypography.footnote)
            }
        }
    }

    // MARK: - LiDAR Diagnostics Link
    private var lidarDiagnosticsSection: some View {
        Section {
            NavigationLink(destination: LiDARDiagnosticsView()) {
                Label("LiDAR Diagnostics", systemImage: "waveform.badge.magnifyingglass")
            }
        }
    }

    // MARK: - About
    private var aboutSection: some View {
        Section("About") {
            infoRow("App Version", "1.0.0 (1)")
            infoRow("Bundle ID", "com.careplix.woundos-v2")
            infoRow("Platform", "iOS \(UIDevice.current.systemVersion)")
            infoRow("Device", UIDevice.current.name)
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

    private var lidarAvailable: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    private var sceneDepthAvailable: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
#endif
