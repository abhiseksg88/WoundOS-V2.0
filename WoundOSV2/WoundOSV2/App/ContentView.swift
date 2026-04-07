import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showCapture = false

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "heart.text.square")
                }
                .tag(0)

            // Scan tab — acts as a button to open capture
            Color.clear
                .tabItem {
                    Label("Scan", systemImage: "camera.viewfinder")
                }
                .tag(1)

            PatientListView()
                .tabItem {
                    Label("Patients", systemImage: "person.2")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .tint(WOSColors.accent)
        .onChange(of: selectedTab) { newValue in
            if newValue == 1 {
                showCapture = true
                // Reset to dashboard so the tab bar doesn't stay on Scan
                selectedTab = 0
            }
        }
        .fullScreenCover(isPresented: $showCapture) {
            CaptureContainerView { selectedFrames in
                showCapture = false
                // In Phase 3, this will navigate to ProcessingView
            }
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
