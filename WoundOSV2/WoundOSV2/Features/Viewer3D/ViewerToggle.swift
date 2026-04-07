import SwiftUI

struct ViewerToggle: View {
    @Binding var mode: MeshViewerView.ViewerMode

    var body: some View {
        Picker("View Mode", selection: $mode) {
            ForEach(MeshViewerView.ViewerMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .background(.ultraThinMaterial)
        .cornerRadius(WOSRadius.sm)
    }
}
