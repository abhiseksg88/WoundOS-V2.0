import SwiftUI

struct DistancePill: View {
    let distance: Float?
    let status: CaptureViewModel.DistanceStatus

    var body: some View {
        HStack(spacing: WOSSpacing.sm) {
            Image(systemName: "ruler")
                .font(.system(size: 12, weight: .semibold))

            if let distance = distance {
                Text(String(format: "%.0f cm", distance * 100))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            } else {
                Text("—")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }

            if distance != nil {
                Image(systemName: statusIcon)
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, WOSSpacing.md)
        .padding(.vertical, WOSSpacing.sm)
        .background(statusColor.opacity(0.85))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch status {
        case .optimal: return .green
        case .tooClose: return .orange
        case .tooFar: return .orange
        case .unknown: return .gray
        }
    }

    private var statusIcon: String {
        switch status {
        case .optimal: return "checkmark"
        case .tooClose: return "arrow.up"
        case .tooFar: return "arrow.down"
        case .unknown: return "questionmark"
        }
    }
}

#if DEBUG
struct DistancePill_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 10) {
            DistancePill(distance: 0.22, status: .optimal)
            DistancePill(distance: 0.08, status: .tooClose)
            DistancePill(distance: 0.45, status: .tooFar)
            DistancePill(distance: nil, status: .unknown)
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
#endif
