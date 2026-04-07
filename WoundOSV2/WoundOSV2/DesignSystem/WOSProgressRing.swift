import SwiftUI

struct WOSProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 8
    var color: Color = WOSColors.accent
    var centerText: String?

    @State private var animatedProgress: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if let centerText = centerText {
                Text(centerText)
                    .font(WOSTypography.headline)
                    .foregroundColor(WOSColors.textPrimary)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animatedProgress = min(max(progress, 0), 1)
            }
        }
        .onChange(of: progress) { newValue in
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animatedProgress = min(max(newValue, 0), 1)
            }
        }
    }
}

#if DEBUG
struct WOSProgressRing_Previews: PreviewProvider {
    static var previews: some View {
        WOSProgressRing(progress: 0.65, centerText: "11")
            .frame(width: 80, height: 80)
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
#endif
