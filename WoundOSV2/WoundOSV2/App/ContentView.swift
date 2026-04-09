import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showCapture = false
    @State private var showProcessing = false
    @State private var showBoundary = false
    @State private var showResults = false
    @State private var capturedFrames: [SelectedFrame] = []
    @State private var serverResponse: ServerResponse?
    @State private var processingVM: ProcessingViewModel?
    @State private var resultsVM: ResultsViewModel?
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
            CaptureContainerView { selectedFrames in
                self.capturedFrames = selectedFrames
                showCapture = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let vm = ProcessingViewModel(useMock: useMockServer)
                    vm.onGoldReady = { gold in
                        DispatchQueue.main.async {
                            self.serverResponse = gold
                            self.resultsVM?.updateWithGoldResults(gold)
                        }
                    }
                    self.processingVM = vm
                    showProcessing = true
                }
            }
        }
        .fullScreenCover(isPresented: $showProcessing) {
            NavigationStack {
                if let vm = processingVM {
                    ProcessingView(viewModel: vm, frames: capturedFrames) { response in
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
                                processingVM = nil
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
                        guard let data = Data(base64Encoded: response.annotatedImageBase64) else { return nil }
                        return UIImage(data: data)
                    }()
                    let maskImage: UIImage? = {
                        guard let data = Data(base64Encoded: response.woundMaskBase64) else { return nil }
                        return UIImage(data: data)
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
                } else {
                    Text("No data available")
                }
            }
        }
        .fullScreenCover(isPresented: $showResults) {
            NavigationStack {
                if let response = serverResponse {
                    let vm = ResultsViewModel(response: response)
                    ResultsView(viewModel: vm)
                        .onAppear { self.resultsVM = vm }
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Done") {
                                    showResults = false
                                    serverResponse = nil
                                    capturedFrames = []
                                    processingVM = nil
                                    resultsVM = nil
                                }
                            }
                        }
                }
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
