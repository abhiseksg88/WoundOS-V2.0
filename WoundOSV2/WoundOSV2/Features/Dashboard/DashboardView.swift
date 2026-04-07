import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var offlineQueue = OfflineScanQueue.shared
    @AppStorage("useMockServer") private var useMockServer: Bool = true

    @State private var showCapture = false
    @State private var showProcessing = false
    @State private var showBoundary = false
    @State private var showResults = false
    @State private var capturedFrames: [SelectedFrame] = []
    @State private var serverResponse: ServerResponse?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WOSSpacing.xxl) {
                    headerSection
                    if offlineQueue.pendingCount > 0 {
                        offlineBanner
                    }
                    quickScanSection
                    recentScansSection
                    healingTrendSection
                }
                .padding(.horizontal, WOSSpacing.lg)
                .padding(.bottom, WOSSpacing.xxxl)
            }
            .background(WOSColors.background.ignoresSafeArea())
            .navigationTitle("Dashboard")
            .refreshable {
                viewModel.loadMockData()
            }
        }
        .fullScreenCover(isPresented: $showCapture) {
            CaptureContainerView { selectedFrames in
                self.capturedFrames = selectedFrames
                showCapture = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showProcessing = true
                }
            }
        }
        .fullScreenCover(isPresented: $showProcessing) {
            NavigationStack {
                ProcessingView(
                    viewModel: ProcessingViewModel(useMock: useMockServer),
                    frames: capturedFrames
                ) { response in
                    self.serverResponse = response
                    showProcessing = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showBoundary = true
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { showProcessing = false }
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
                    ResultsView(viewModel: ResultsViewModel(response: response))
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Done") {
                                    showResults = false
                                    serverResponse = nil
                                    capturedFrames = []
                                    viewModel.loadMockData()
                                }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: WOSSpacing.xs) {
            Text(viewModel.greeting)
                .font(WOSTypography.largeTitle)
                .foregroundColor(WOSColors.textPrimary)

            Text("\(viewModel.recentScans.filter { $0.status == .complete }.count) scans this week")
                .font(WOSTypography.subheadline)
                .foregroundColor(WOSColors.textSecondary)
        }
        .padding(.top, WOSSpacing.sm)
    }

    // MARK: - Offline Banner
    private var offlineBanner: some View {
        WOSCard {
            HStack(spacing: WOSSpacing.md) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 20))
                    .foregroundColor(WOSColors.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(offlineQueue.pendingCount) scan\(offlineQueue.pendingCount == 1 ? "" : "s") waiting to upload")
                        .font(WOSTypography.headline)
                        .foregroundColor(WOSColors.textPrimary)
                    Text(offlineQueue.isOnline ? "Will upload shortly" : "Waiting for network connection")
                        .font(WOSTypography.caption)
                        .foregroundColor(WOSColors.textSecondary)
                }
                Spacer()
                if offlineQueue.isUploading {
                    ProgressView()
                }
            }
        }
    }

    // MARK: - Quick Scan CTA
    private var quickScanSection: some View {
        WOSButton(title: "Quick Scan", icon: "camera.fill", style: .primary) {
            showCapture = true
        }
    }

    // MARK: - Recent Scans
    private var recentScansSection: some View {
        VStack(alignment: .leading, spacing: WOSSpacing.md) {
            HStack {
                Text("Recent Scans")
                    .font(WOSTypography.title3)
                    .foregroundColor(WOSColors.textPrimary)
                Spacer()
                Button("See All") {}
                    .font(WOSTypography.subheadline)
                    .foregroundColor(WOSColors.accent)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WOSSpacing.md) {
                    ForEach(viewModel.recentScans.prefix(5)) { scan in
                        RecentScanCard(
                            scan: scan,
                            patientName: viewModel.patientForScan(scan)?.fullName ?? "Unknown"
                        )
                    }
                }
            }
            .shimmer(active: viewModel.isLoading)
        }
    }

    // MARK: - Healing Trend
    private var healingTrendSection: some View {
        VStack(alignment: .leading, spacing: WOSSpacing.md) {
            Text("Healing Trends")
                .font(WOSTypography.title3)
                .foregroundColor(WOSColors.textPrimary)

            WOSCard {
                HealingTrendChart(scans: viewModel.recentScans.filter { $0.measurements != nil })
                    .frame(height: 180)
            }
        }
    }
}

#if DEBUG
struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
#endif
