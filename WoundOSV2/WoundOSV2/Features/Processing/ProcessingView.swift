import SwiftUI

struct ProcessingView: View {
    @StateObject var viewModel: ProcessingViewModel
    let frames: [SelectedFrame]
    var onComplete: ((ServerResponse) -> Void)?

    var body: some View {
        VStack(spacing: WOSSpacing.xxxl) {
            Spacer()

            progressRing

            stepsList

            if viewModel.hasFailed {
                errorSection
            } else {
                caption
            }

            Spacer()
        }
        .padding(WOSSpacing.xxl)
        .background(WOSColors.background.ignoresSafeArea())
        .onAppear {
            viewModel.startProcessing(frames: frames)
        }
        .onChange(of: viewModel.isComplete) { complete in
            if complete, let response = viewModel.serverResponse {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onComplete?(response)
                }
            }
        }
    }

    // MARK: - Progress Ring
    private var progressRing: some View {
        WOSProgressRing(
            progress: viewModel.overallProgress,
            lineWidth: 10,
            color: viewModel.hasFailed ? WOSColors.red : WOSColors.accent,
            centerText: viewModel.hasFailed ? "!" : "\(Int(viewModel.overallProgress * 100))%"
        )
        .frame(width: 100, height: 100)
    }

    // MARK: - Steps List
    private var stepsList: some View {
        VStack(alignment: .leading, spacing: WOSSpacing.lg) {
            ForEach(ProcessingStep.allCases, id: \.rawValue) { step in
                stepRow(step)
            }
        }
        .padding(.horizontal, WOSSpacing.xxxl)
    }

    private func stepRow(_ step: ProcessingStep) -> some View {
        let state = viewModel.stepStates[step] ?? .pending

        return HStack(spacing: WOSSpacing.md) {
            stepIcon(state: state, step: step)
                .frame(width: 28, height: 28)

            Text(step.label)
                .font(WOSTypography.body)
                .foregroundColor(state == .pending ? WOSColors.textTertiary : WOSColors.textPrimary)

            Spacer()

            if state == .complete {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(WOSColors.green)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: state == .complete)
    }

    @ViewBuilder
    private func stepIcon(state: ProcessingStepState, step: ProcessingStep) -> some View {
        switch state {
        case .pending:
            Image(systemName: step.icon)
                .font(.system(size: 16))
                .foregroundColor(WOSColors.textTertiary)
        case .active:
            ProgressView()
                .scaleEffect(0.8)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(WOSColors.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(WOSColors.red)
        }
    }

    // MARK: - Caption
    private var caption: some View {
        Text("This usually takes 5–10 seconds")
            .font(WOSTypography.footnote)
            .foregroundColor(WOSColors.textTertiary)
    }

    // MARK: - Error
    private var errorSection: some View {
        VStack(spacing: WOSSpacing.md) {
            Text(viewModel.errorMessage ?? "An error occurred")
                .font(WOSTypography.footnote)
                .foregroundColor(WOSColors.red)
                .multilineTextAlignment(.center)

            WOSButton(title: "Retry", icon: "arrow.clockwise", style: .secondary) {
                viewModel.retry(frames: frames)
            }
            .frame(width: 200)
        }
    }
}

#if DEBUG
struct ProcessingView_Previews: PreviewProvider {
    static var previews: some View {
        ProcessingView(viewModel: ProcessingViewModel(useMock: true), frames: [])
    }
}
#endif
