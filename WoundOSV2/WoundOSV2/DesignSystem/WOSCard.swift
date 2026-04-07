import SwiftUI

struct WOSCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(WOSSpacing.lg)
            .background(WOSColors.cardBackground)
            .cornerRadius(WOSRadius.lg)
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

#if DEBUG
struct WOSCard_Previews: PreviewProvider {
    static var previews: some View {
        WOSCard {
            Text("Sample Card")
                .font(WOSTypography.headline)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
