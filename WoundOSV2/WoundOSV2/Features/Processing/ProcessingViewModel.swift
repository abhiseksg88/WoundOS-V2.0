import Foundation
import Combine

enum ProcessingStep: Int, CaseIterable {
    case upload = 0
    case reconstruct
    case segment
    case measure
    case complete

    var label: String {
        switch self {
        case .upload: return "Uploading frames"
        case .reconstruct: return "Reconstructing 3D model"
        case .segment: return "Segmenting wound"
        case .measure: return "Computing measurements"
        case .complete: return "Complete"
        }
    }

    var icon: String {
        switch self {
        case .upload: return "arrow.up.circle"
        case .reconstruct: return "cube"
        case .segment: return "scissors"
        case .measure: return "ruler"
        case .complete: return "checkmark.circle"
        }
    }
}

enum ProcessingStepState {
    case pending
    case active
    case complete
    case failed
}

final class ProcessingViewModel: ObservableObject {
    @Published var currentStep: ProcessingStep = .upload
    @Published var stepStates: [ProcessingStep: ProcessingStepState] = [:]
    @Published var overallProgress: Double = 0
    @Published var isComplete = false
    @Published var hasFailed = false
    @Published var errorMessage: String?
    @Published var serverResponse: ServerResponse?
    @Published var wasQueued = false

    /// Called when Tier 2 gold results arrive in the background
    var onGoldReady: ((ServerResponse) -> Void)?

    private let useMock: Bool
    private var cancellables = Set<AnyCancellable>()
    private var service: ReconstructionServiceProtocol?

    init(useMock: Bool = true) {
        self.useMock = useMock
        for step in ProcessingStep.allCases {
            stepStates[step] = .pending
        }
    }

    func startProcessing(frames: [SelectedFrame]) {
        Task { @MainActor in
            do {
                let svc: ReconstructionServiceProtocol = useMock
                    ? MockReconstructionService()
                    : ReconstructionService()
                self.service = svc

                // Step 1: Upload frames to server
                await advanceToStep(.upload)

                // Listen to progress stream for real-time updates
                let progressStream = svc.progressStream()
                let progressTask = Task {
                    for await progress in progressStream {
                        await MainActor.run {
                            switch progress {
                            case .uploading:
                                // Already on upload step
                                break
                            case .processing(let step):
                                if step.contains("Reconstruct") || step.contains("Queued") {
                                    self.stepStates[.upload] = .complete
                                    self.stepStates[.reconstruct] = .active
                                    self.currentStep = .reconstruct
                                } else if step.contains("Segment") {
                                    self.stepStates[.reconstruct] = .complete
                                    self.stepStates[.segment] = .active
                                    self.currentStep = .segment
                                } else if step.contains("Refin") || step.contains("Measur") {
                                    self.stepStates[.segment] = .complete
                                    self.stepStates[.measure] = .active
                                    self.currentStep = .measure
                                }
                            case .complete, .failed:
                                break // Handled below
                            }
                        }
                    }
                }

                // Step 2: Upload + poll (ReconstructionService handles the async flow)
                let response = try await svc.uploadScan(
                    frames: frames,
                    woundPoint: nil,
                    useWoundAmbit: true,
                    generateSplat: true
                )

                progressTask.cancel()

                await advanceToStep(.complete)

                self.serverResponse = response
                self.isComplete = true

                // Start background polling for Tier 2 gold results
                self.startGoldPolling(service: svc)
            } catch {
                // Check if we should enqueue for offline upload
                if !OfflineScanQueue.shared.isOnline && !useMock {
                    self.wasQueued = true
                    self.errorMessage = "No network connection. Scan has been queued for upload when connectivity is restored."
                    self.hasFailed = true
                    self.stepStates[self.currentStep] = .failed

                    // Save frames to disk and enqueue
                    let scanId = UUID()
                    let scanDir = ScanStore.scanDirectory(for: scanId)
                    let framesDir = scanDir.appendingPathComponent("frames")
                    try? FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)

                    for (index, frame) in frames.enumerated() {
                        let framePath = framesDir.appendingPathComponent("frame_\(index).jpg")
                        try? frame.jpegData.write(to: framePath)
                    }

                    OfflineScanQueue.shared.enqueue(
                        scanId: scanId,
                        patientId: UUID(), // Will be associated later
                        framesDirectory: framesDir.path
                    )
                } else {
                    self.hasFailed = true
                    self.errorMessage = error.localizedDescription
                    self.stepStates[self.currentStep] = .failed
                }
            }
        }
    }

    func retry(frames: [SelectedFrame]) {
        hasFailed = false
        wasQueued = false
        errorMessage = nil
        for step in ProcessingStep.allCases {
            stepStates[step] = .pending
        }
        overallProgress = 0
        startProcessing(frames: frames)
    }

    @MainActor
    private func advanceToStep(_ step: ProcessingStep) async {
        // Complete previous steps
        for s in ProcessingStep.allCases where s.rawValue < step.rawValue {
            stepStates[s] = .complete
        }
        stepStates[step] = .active
        currentStep = step
        overallProgress = Double(step.rawValue + 1) / Double(ProcessingStep.allCases.count)
    }

    private func startGoldPolling(service: ReconstructionServiceProtocol) {
        guard let realService = service as? ReconstructionService,
              let jobId = realService.lastJobId else {
            // For mock: simulate gold arriving
            if let mockService = service as? MockReconstructionService {
                Task {
                    if let gold = try? await mockService.pollForGoldResults(jobId: "") {
                        await MainActor.run {
                            self.onGoldReady?(gold)
                        }
                    }
                }
            }
            return
        }

        Task {
            if let gold = try? await realService.pollForGoldResults(jobId: jobId) {
                await MainActor.run {
                    self.serverResponse = gold
                    self.onGoldReady?(gold)
                }
            }
        }
    }
}
