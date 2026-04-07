import SwiftUI

struct ShimmerModifier: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        if active {
            content
                .redacted(reason: .placeholder)
                .overlay(
                    GeometryReader { geometry in
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .clear,
                                .white.opacity(0.4),
                                .clear
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 0.6)
                        .offset(x: -geometry.size.width * 0.3 + phase * geometry.size.width * 1.6)
                    }
                    .clipped()
                )
                .onAppear {
                    withAnimation(
                        .linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                    ) {
                        phase = 1
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    func shimmer(active: Bool) -> some View {
        modifier(ShimmerModifier(active: active))
    }
}

#if DEBUG
struct WOSShimmer_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            RoundedRectangle(cornerRadius: WOSRadius.lg)
                .fill(WOSColors.cardBackground)
                .frame(height: 100)
                .shimmer(active: true)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
