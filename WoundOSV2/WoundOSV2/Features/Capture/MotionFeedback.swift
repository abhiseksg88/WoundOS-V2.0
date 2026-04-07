import SwiftUI

struct MotionFeedback: View {
    let status: CaptureViewModel.MotionStatus

    var body: some View {
        HStack(spacing: WOSSpacing.sm) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .foregroundColor(foregroundColor)
        .padding(.horizontal, WOSSpacing.md)
        .padding(.vertical, WOSSpacing.sm)
        .background(backgroundColor)
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.3), value: status.rawValue)
    }

    private var iconName: String {
        switch status {
        case .good: return "checkmark.circle.fill"
        case .tooFast: return "exclamationmark.triangle.fill"
        case .tooSlow: return "hand.raised.fill"
        }
    }

    private var label: String {
        switch status {
        case .good: return "Good pace"
        case .tooFast: return "Too fast"
        case .tooSlow: return "Hold steady"
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .good: return .white
        case .tooFast: return .black
        case .tooSlow: return .white
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .good: return Color.green.opacity(0.85)
        case .tooFast: return Color.yellow.opacity(0.85)
        case .tooSlow: return Color.red.opacity(0.85)
        }
    }
}

extension CaptureViewModel.MotionStatus {
    var rawValue: Int {
        switch self {
        case .good: return 0
        case .tooFast: return 1
        case .tooSlow: return 2
        }
    }
}

#if DEBUG
struct MotionFeedback_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 10) {
            MotionFeedback(status: .good)
            MotionFeedback(status: .tooFast)
            MotionFeedback(status: .tooSlow)
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
#endif
