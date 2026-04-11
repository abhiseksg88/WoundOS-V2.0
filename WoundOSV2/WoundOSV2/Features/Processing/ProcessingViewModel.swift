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
    @Published var wasQueued = false

    // Async polling state
    @Published var jobId: String?
    @Published var isPreliminaryReady = false
    @Published var preliminaryResponse: ServerResponse?
    @Published var goldResponse: ServerResponse?
    @Published var serverProgress: Double = 0

    var onGoldReady: ((ServerResponse) -> Void)?

    var serverResponse: ServerResponse? {
        goldResponse ?? preliminaryResponse
    }

    private let useMock: Bool

    init(useMock: Bool = true) {
        self.useMock = useMock
        for step in ProcessingStep.allCases {
            stepStates[step] = .pending
        }
    }

    /// LiDAR-native processing: 1 frame + ARKit mesh, ~3-5 second backend.
    /// Uses the same polling pipeline as multiview but with the LiDAR submission method.
    func startLiDARProcessing(payload: LiDARScanPayload, woundPoint: CGPoint?) {
        Task { @MainActor in
            do {
                let service: ReconstructionServiceProtocol = useMock
                    ? MockReconstructionService()
                    : ReconstructionService()

                await advanceToStep(.upload)
                let submission = try await service.submitLiDARScan(
                    payload: payload,
                    woundPoint: woundPoint,
                    useWoundAmbit: true
                )
                self.jobId = submission.jobId

                await advanceToStep(.reconstruct)

                // Poll for results — LiDAR completes in ~3-5 seconds, no Tier 1/2 split
                for _ in 0..<ServerConfig.maxPollAttempts {
                    try await Task.sleep(nanoseconds: UInt64(ServerConfig.pollIntervalSeconds * 1_000_000_000))

                    let status = try await service.pollJobStatus(jobId: submission.jobId)

                    if let progress = status.progress {
                        self.serverProgress = progress
                        self.overallProgress = max(self.overallProgress, 0.2 + progress * 0.8)
                    }

                    if let step = status.step {
                        let mapped = mapServerStep(step)
                        if mapped.rawValue > currentStep.rawValue {
                            await advanceToStep(mapped)
                        }
                    }

                    if status.status == .complete, let result = status.result {
                        self.goldResponse = result
                        self.preliminaryResponse = result
                        self.isPreliminaryReady = true
                        await advanceToStep(.complete)
                        self.isComplete = true
                        self.onGoldReady?(result)
                        return
                    }

                    if status.status == .failed {
                        throw ReconstructionError.serverJobFailed(
                            status.errorMessage ?? "Unknown server error"
                        )
                    }
                }
                throw ReconstructionError.pollTimeout
            } catch {
                self.hasFailed = true
                self.errorMessage = error.localizedDescription
                self.stepStates[self.currentStep] = .failed
            }
        }
    }

    func startProcessing(frames: [SelectedFrame]) {
        Task { @MainActor in
            do {
                let service: ReconstructionServiceProtocol = useMock
                    ? MockReconstructionService()
                    : ReconstructionService()

                // Phase 1: Submit scan
                await advanceToStep(.upload)
                let submission = try await service.submitScan(
                    frames: frames,
                    woundPoint: nil,
                    useWoundAmbit: true,
                    generateSplat: true
                )
                self.jobId = submission.jobId

                // Phase 2: Poll for results
                await advanceToStep(.reconstruct)
                var hasPreliminary = false

                for _ in 0..<ServerConfig.maxPollAttempts {
                    try await Task.sleep(nanoseconds: UInt64(ServerConfig.pollIntervalSeconds * 1_000_000_000))

                    let status = try await service.pollJobStatus(jobId: submission.jobId)

                    // Update progress from server
                    if let progress = status.progress {
                        self.serverProgress = progress
                        self.overallProgress = max(self.overallProgress, 0.2 + progress * 0.8)
                    }

                    // Map server step to UI step
                    if let step = status.step {
                        let mapped = mapServerStep(step)
                        if mapped.rawValue > currentStep.rawValue {
                            await advanceToStep(mapped)
                        }
                    }

                    // Tier 1 preliminary results arrived?
                    if let preliminary = status.preliminaryResult, !hasPreliminary {
                        hasPreliminary = true
                        self.preliminaryResponse = preliminary
                        await advanceToStep(.segment)
                        self.isPreliminaryReady = true
                    }

                    // Tier 2 gold / complete?
                    if status.status == .complete, let result = status.result {
                        self.goldResponse = result
                        await advanceToStep(.complete)
                        self.isComplete = true
                        self.onGoldReady?(result)
                        return
                    }

                    // Server-side failure?
                    if status.status == .failed {
                        throw ReconstructionError.serverJobFailed(
                            status.errorMessage ?? "Unknown server error"
                        )
                    }
                }

                // Poll loop exhausted without completion
                throw ReconstructionError.pollTimeout

            } catch {
                // Offline queue integration
                if !OfflineScanQueue.shared.isOnline && !useMock {
                    self.wasQueued = true
                    self.errorMessage = "No network connection. Scan has been queued for upload when connectivity is restored."
                    self.hasFailed = true
                    self.stepStates[self.currentStep] = .failed

                    let scanId = UUID()
                    let scanDir = ScanStore.scanDirectory(for: scanId)
                    let framesDir = scanDir.appendingPathComponent("frames")
                    try? FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
                    for (index, frame) in frames.enumerated() {
                        let framePath = framesDir.appendingPathComponent("frame_\(index).jpg")
                        try? frame.jpegData.write(to: framePath)
                    }
                    OfflineScanQueue.shared.enqueue(scanId: scanId, patientId: UUID(), framesDirectory: framesDir.path)
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
        jobId = nil
        isPreliminaryReady = false
        preliminaryResponse = nil
        goldResponse = nil
        serverProgress = 0
        for step in ProcessingStep.allCases {
            stepStates[step] = .pending
        }
        overallProgress = 0
        startProcessing(frames: frames)
    }

    @MainActor
    private func advanceToStep(_ step: ProcessingStep) async {
        for s in ProcessingStep.allCases where s.rawValue < step.rawValue {
            stepStates[s] = .complete
        }
        stepStates[step] = .active
        currentStep = step
        overallProgress = max(overallProgress, Double(step.rawValue + 1) / Double(ProcessingStep.allCases.count))
    }

    private func mapServerStep(_ serverStep: String) -> ProcessingStep {
        switch serverStep {
        case "uploading": return .upload
        case "reconstructing", "patch_match_stereo", "dense_reconstruction", "refining": return .reconstruct
        case "segmentation", "wound_segmentation", "segmenting": return .segment
        case "measurement", "mesh_generation", "measuring": return .measure
        default: return currentStep
        }
    }
}
