import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showCapture = false
    @State private var showProcessing = false
    @State private var showBoundary = false
    @State private var showResults = false
    @State private var capturedFrames: [SelectedFrame] = []
    @State private var capturedLiDARPayload: LiDARScanPayload?
    @State private var capturedWoundPoint: CGPoint?
    @State private var serverResponse: ServerResponse?
    @State private var processingViewModel: ProcessingViewModel?
    @State private var resultsViewModel: ResultsViewModel?
    @AppStorage("useMockServer") private var useMockServer: Bool = true

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "heart.text.square")
                }
                .tag(0)

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
                selectedTab = 0
            }
        }
        .fullScreenCover(isPresented: $showCapture) {
            CaptureContainerView { result in
                switch result {
                case .multiview(let frames, let woundPoint):
                    self.capturedFrames = frames
                    self.capturedLiDARPayload = nil
                    self.capturedWoundPoint = woundPoint
                case .lidar(let payload, let woundPoint):
                    self.capturedFrames = [payload.bestFrame]
                    self.capturedLiDARPayload = payload
                    self.capturedWoundPoint = woundPoint
                }
                showCapture = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    startProcessing()
                }
            }
        }
        .fullScreenCover(isPresented: $showProcessing) {
            NavigationStack {
                if let vm = processingViewModel {
                    ProcessingView(
                        viewModel: vm,
                        frames: capturedFrames,
                        lidarPayload: capturedLiDARPayload,
                        woundPoint: capturedWoundPoint
                    ) { response in
                        self.serverResponse = response
                        showProcessing = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showBoundary = true
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showProcessing = false
                                processingViewModel = nil
                            }
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showBoundary) {
            NavigationStack {
                if let response = serverResponse {
                    let annotatedImage: UIImage? = {
                        guard let d = Data(base64Encoded: response.annotatedImageBase64) else { return nil }
                        return UIImage(data: d)
                    }()
                    let maskImage: UIImage? = {
                        guard let d = Data(base64Encoded: response.woundMaskBase64) else { return nil }
                        return UIImage(data: d)
                    }()
                    BoundaryEditView(viewModel: BoundaryViewModel(woundImage: annotatedImage, maskImage: maskImage))
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Skip") {
                                    showBoundary = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        showResults = true
                                    }
                                }
                            }
                        }
                        .onDisappear {
                            if !showResults {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    showResults = true
                                }
                            }
                        }
                }
            }
        }
        .fullScreenCover(isPresented: $showResults) {
            NavigationStack {
                if let response = serverResponse {
                    let vm = ResultsViewModel(response: response)
                    ResultsView(viewModel: vm)
                        .onAppear {
                            self.resultsViewModel = vm
                        }
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Done") {
                                    showResults = false
                                    serverResponse = nil
                                    capturedFrames = []
                                    capturedLiDARPayload = nil
                                    capturedWoundPoint = nil
                                    processingViewModel = nil
                                    resultsViewModel = nil
                                }
                            }
                        }
                }
            }
        }
    }

    private func startProcessing() {
        let vm = ProcessingViewModel(useMock: useMockServer)
        vm.onGoldReady = { gold in
            DispatchQueue.main.async {
                self.serverResponse = gold
                self.resultsViewModel?.updateWithGoldResults(gold)
            }
        }
        self.processingViewModel = vm
        showProcessing = true
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
