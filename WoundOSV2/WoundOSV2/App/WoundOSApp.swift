import SwiftUI

@main
struct WoundOSApp: App {
    @StateObject private var scanStore = ScanStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scanStore)
        }
    }
}
