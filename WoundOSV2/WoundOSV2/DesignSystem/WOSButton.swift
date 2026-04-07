import SwiftUI

enum WOSButtonStyle {
    case primary
    case secondary
    case ghost
}

struct WOSButton: View {
    let title: String
    var icon: String?
    var style: WOSButtonStyle = .primary
    let action: () -> Void

    var body: some View {
        Button(action: {
            WOSHaptics.selection()
            action()
        }) {
            HStack(spacing: WOSSpacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(WOSTypography.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundColor(foregroundColor)
            .background(backgroundColor)
            .cornerRadius(WOSRadius.lg)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return WOSColors.accent
        case .ghost: return WOSColors.accent
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return WOSColors.accent
        case .secondary: return WOSColors.accent.opacity(0.15)
        case .ghost: return .clear
        }
    }
}

#if DEBUG
struct WOSButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            WOSButton(title: "Quick Scan", icon: "camera.fill", style: .primary) {}
            WOSButton(title: "View Report", icon: "doc.text", style: .secondary) {}
            WOSButton(title: "Share", icon: "square.and.arrow.up", style: .ghost) {}
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
