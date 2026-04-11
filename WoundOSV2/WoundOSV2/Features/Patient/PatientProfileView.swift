import SwiftUI

struct PatientProfileView: View {
    let patient: Patient
    @AppStorage("useMockServer") private var useMockServer: Bool = true

    @State private var showCapture = false
    @State private var showProcessing = false
    @State private var showBoundary = false
    @State private var showResults = false
    @State private var capturedFrames: [SelectedFrame] = []
    @State private var capturedLiDARPayload: LiDARScanPayload?
    @State private var capturedWoundPoint: CGPoint?
    @State private var serverResponse: ServerResponse?
    @State private var processingVM: ProcessingViewModel?
    @State private var resultsVM: ResultsViewModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WOSSpacing.xxl) {
                patientInfoCard
                actionsSection
                woundTimelineSection
            }
            .padding(.horizontal, WOSSpacing.lg)
            .padding(.bottom, WOSSpacing.xxxl)
        }
        .background(WOSColors.background.ignoresSafeArea())
        .navigationTitle(patient.fullName)
        .navigationBarTitleDisplayMode(.large)
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
                            Button("Cancel") { showProcessing = false; processingVM = nil }
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
                    let vm = ResultsViewModel(response: response, patient: patient)
                    ResultsView(viewModel: vm)
                        .onAppear { self.resultsVM = vm }
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Done") {
                                    showResults = false
                                    serverResponse = nil
                                    processingVM = nil
                                    resultsVM = nil
                                    capturedFrames = []
                                    capturedLiDARPayload = nil
                                    capturedWoundPoint = nil
                                }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Patient Info Card
    private var patientInfoCard: some View {
        WOSCard {
            VStack(alignment: .leading, spacing: WOSSpacing.md) {
                HStack(spacing: WOSSpacing.lg) {
                    ZStack {
                        Circle()
                            .fill(WOSColors.accent.opacity(0.15))
                            .frame(width: 64, height: 64)
                        Text(patient.initials)
                            .font(WOSTypography.title2)
                            .foregroundColor(WOSColors.accent)
                    }

                    VStack(alignment: .leading, spacing: WOSSpacing.xs) {
                        Text(patient.fullName)
                            .font(WOSTypography.title3)
                            .foregroundColor(WOSColors.textPrimary)

                        if let dob = patient.dateOfBirth {
                            Text("DOB: \(dob, format: .dateTime.month().day().year())")
                                .font(WOSTypography.footnote)
                                .foregroundColor(WOSColors.textSecondary)
                        }
                    }
                }

                Divider()

                infoRow(icon: "number", label: "MRN", value: patient.mrn ?? "—")
                infoRow(icon: "building.2", label: "Facility", value: patient.facilityName ?? "—")
                infoRow(icon: "door.left.hand.open", label: "Room", value: patient.roomNumber ?? "—")
                infoRow(icon: "bandage", label: "Active Wounds", value: "\(patient.wounds.count)")
            }
        }
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: WOSSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(WOSColors.accent)
                .frame(width: 24)
            Text(label)
                .font(WOSTypography.footnote)
                .foregroundColor(WOSColors.textSecondary)
            Spacer()
            Text(value)
                .font(WOSTypography.footnote)
                .fontWeight(.medium)
                .foregroundColor(WOSColors.textPrimary)
        }
    }

    // MARK: - Actions
    private var actionsSection: some View {
        WOSButton(title: "New Scan", icon: "camera.fill", style: .primary) {
            showCapture = true
        }
    }

    // MARK: - Wound Timeline
    private var woundTimelineSection: some View {
        VStack(alignment: .leading, spacing: WOSSpacing.md) {
            Text("Wound History")
                .font(WOSTypography.title3)
                .foregroundColor(WOSColors.textPrimary)

            WoundTimelineView(scans: patient.wounds.sorted { $0.capturedAt > $1.capturedAt })
        }
    }
}

#if DEBUG
struct PatientProfileView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PatientProfileView(patient: MockDataProvider.patients[0])
        }
    }
}
#endif
