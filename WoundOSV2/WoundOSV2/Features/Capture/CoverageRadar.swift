import SwiftUI

struct CoverageRadar: View {
    let coverage: Float
    let targetCoverage: Float

    private var normalizedCoverage: Double {
        min(Double(coverage / 360.0), 1.0)
    }

    private var segments: [(start: Double, isCovered: Bool)] {
        let totalSegments = 12
        let coveredCount = Int(normalizedCoverage * Double(totalSegments))

        return (0..<totalSegments).map { i in
            let start = Double(i) / Double(totalSegments)
            return (start, i < coveredCount)
        }
    }

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(.ultraThinMaterial)

            // Segment arcs
            ForEach(0..<12, id: \.self) { index in
                let startAngle = Angle(degrees: Double(index) * 30 - 90)
                let endAngle = Angle(degrees: Double(index + 1) * 30 - 90)
                let isCovered = index < Int(normalizedCoverage * 12)

                ArcSegment(startAngle: startAngle, endAngle: endAngle)
                    .stroke(
                        isCovered ? Color.white : Color.white.opacity(0.3),
                        lineWidth: 3
                    )
                    .padding(6)
            }

            // Center dot
            Circle()
                .fill(.white)
                .frame(width: 6, height: 6)

            // Coverage label
            VStack(spacing: 0) {
                Spacer()
                Text("\(Int(coverage))°")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.bottom, 2)
            }
        }
    }
}

struct ArcSegment: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle + .degrees(1),
            endAngle: endAngle - .degrees(1),
            clockwise: false
        )
        return path
    }
}

#if DEBUG
struct CoverageRadar_Previews: PreviewProvider {
    static var previews: some View {
        CoverageRadar(coverage: 90, targetCoverage: 120)
            .frame(width: 64, height: 64)
            .padding()
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
#endif
