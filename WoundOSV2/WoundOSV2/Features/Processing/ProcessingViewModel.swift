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

    private let useMock: Bool
    private var cancellables = Set<AnyCancellable>()

    init(useMock: Bool = true) {
        self.useMock = useMock
        for step in ProcessingStep.allCases {
            stepStates[step] = .pending
        }
    }

    func startProcessing(frames: [SelectedFrame]) {
        Task { @MainActor in
            do {
                let service: ReconstructionServiceProtocol = useMock
                    ? MockReconstructionService()
                    : ReconstructionService()

                // Animate through steps
                await advanceToStep(.upload)
                try await Task.sleep(nanoseconds: 300_000_000)

                await advanceToStep(.reconstruct)

                let response = try await service.uploadScan(
                    frames: frames,
                    woundPoint: nil,
                    useWoundAmbit: true,
                    generateSplat: true
                )

                await advanceToStep(.segment)
                try await Task.sleep(nanoseconds: 400_000_000)

                await advanceToStep(.measure)
                try await Task.sleep(nanoseconds: 300_000_000)

                await advanceToStep(.complete)

                self.serverResponse = response
                self.isComplete = true
            } catch {
                self.hasFailed = true
                self.errorMessage = error.localizedDescription
                self.stepStates[self.currentStep] = .failed
            }
        }
    }

    func retry(frames: [SelectedFrame]) {
        hasFailed = false
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
}
