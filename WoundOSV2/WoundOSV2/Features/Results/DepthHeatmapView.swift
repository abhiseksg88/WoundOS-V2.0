import SwiftUI

struct DepthHeatmapView: View {
    let image: UIImage?
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .bottom) {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(WOSRadius.md)
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(value, 1.0), 3.0)
                            }
                            .onEnded { _ in
                                withAnimation(.spring()) {
                                    scale = 1.0
                                }
                            }
                    )
            } else {
                RoundedRectangle(cornerRadius: WOSRadius.md)
                    .fill(WOSColors.fill)
                    .overlay(
                        Image(systemName: "map")
                            .font(.system(size: 32))
                            .foregroundColor(WOSColors.textTertiary)
                    )
            }

            // Color legend
            legendBar
                .padding(.bottom, WOSSpacing.sm)
                .padding(.horizontal, WOSSpacing.lg)
        }
    }

    private var legendBar: some View {
        VStack(spacing: 2) {
            LinearGradient(
                colors: [.green, .yellow, .red],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 8)
            .cornerRadius(4)

            HStack {
                Text("0 mm")
                    .font(.system(size: 9, weight: .medium))
                Spacer()
                Text("3 mm")
                    .font(.system(size: 9, weight: .medium))
                Spacer()
                Text("6+ mm")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.white)
        }
        .padding(.horizontal, WOSSpacing.sm)
        .padding(.vertical, WOSSpacing.xs)
        .background(.ultraThinMaterial)
        .cornerRadius(WOSRadius.sm)
    }
}
