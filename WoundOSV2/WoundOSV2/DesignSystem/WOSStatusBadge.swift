import SwiftUI

enum WOSHealingStatus {
    case healing
    case stable
    case worsening
    case newWound

    var label: String {
        switch self {
        case .healing: return "Healing"
        case .stable: return "Stable"
        case .worsening: return "Worsening"
        case .newWound: return "New"
        }
    }

    var icon: String {
        switch self {
        case .healing: return "arrow.down.right"
        case .stable: return "arrow.right"
        case .worsening: return "arrow.up.right"
        case .newWound: return "plus"
        }
    }

    var color: Color {
        switch self {
        case .healing: return WOSColors.green
        case .stable: return WOSColors.yellow
        case .worsening: return WOSColors.red
        case .newWound: return WOSColors.teal
        }
    }
}

struct WOSStatusBadge: View {
    let status: WOSHealingStatus

    var body: some View {
        HStack(spacing: WOSSpacing.xs) {
            Image(systemName: status.icon)
                .font(.system(size: 10, weight: .bold))
            Text(status.label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundColor(status.color)
        .padding(.horizontal, WOSSpacing.sm)
        .padding(.vertical, WOSSpacing.xs)
        .background(status.color.opacity(0.15))
        .clipShape(Capsule())
    }
}

#if DEBUG
struct WOSStatusBadge_Previews: PreviewProvider {
    static var previews: some View {
        HStack {
            WOSStatusBadge(status: .healing)
            WOSStatusBadge(status: .stable)
            WOSStatusBadge(status: .worsening)
            WOSStatusBadge(status: .newWound)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
