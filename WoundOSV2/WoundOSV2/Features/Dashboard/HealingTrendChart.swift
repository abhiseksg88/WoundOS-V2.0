import SwiftUI

struct HealingTrendChart: View {
    let scans: [WoundScan]

    var body: some View {
        GeometryReader { geometry in
            if dataPoints.count >= 2 {
                chartContent(in: geometry)
            } else {
                emptyState
            }
        }
    }

    private var dataPoints: [(date: Date, area: Double)] {
        scans
            .filter { $0.measurements != nil }
            .sorted { $0.capturedAt < $1.capturedAt }
            .map { ($0.capturedAt, $0.measurements!.areaCm2) }
    }

    private func chartContent(in geometry: GeometryProxy) -> some View {
        let width = geometry.size.width
        let height = geometry.size.height
        let padding: CGFloat = 32
        let chartWidth = width - padding * 2
        let chartHeight = height - padding * 2

        let areas = dataPoints.map { $0.area }
        let minArea = (areas.min() ?? 0) * 0.9
        let maxArea = (areas.max() ?? 1) * 1.1
        let areaRange = max(maxArea - minArea, 0.1)

        let timeMin = dataPoints.first!.date.timeIntervalSince1970
        let timeMax = dataPoints.last!.date.timeIntervalSince1970
        let timeRange = max(timeMax - timeMin, 1)

        return ZStack(alignment: .topLeading) {
            // Y-axis labels
            VStack {
                Text(String(format: "%.0f", maxArea))
                    .font(WOSTypography.caption)
                    .foregroundColor(WOSColors.textTertiary)
                Spacer()
                Text(String(format: "%.0f", minArea))
                    .font(WOSTypography.caption)
                    .foregroundColor(WOSColors.textTertiary)
            }
            .frame(width: padding - 4)
            .padding(.top, padding)
            .frame(height: height - padding)

            // Chart area
            Path { path in
                for (index, point) in dataPoints.enumerated() {
                    let x = padding + CGFloat((point.date.timeIntervalSince1970 - timeMin) / timeRange) * chartWidth
                    let y = padding + chartHeight - CGFloat((point.area - minArea) / areaRange) * chartHeight
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(WOSColors.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            // Data points
            ForEach(Array(dataPoints.enumerated()), id: \.offset) { index, point in
                let x = padding + CGFloat((point.date.timeIntervalSince1970 - timeMin) / timeRange) * chartWidth
                let y = padding + chartHeight - CGFloat((point.area - minArea) / areaRange) * chartHeight
                Circle()
                    .fill(WOSColors.accent)
                    .frame(width: 8, height: 8)
                    .position(x: x, y: y)
            }

            // Area label
            Text("Area (cm²)")
                .font(WOSTypography.caption)
                .foregroundColor(WOSColors.textSecondary)
                .position(x: width / 2, y: height - 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: WOSSpacing.sm) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 32))
                .foregroundColor(WOSColors.textTertiary)
            Text("Not enough data for trends")
                .font(WOSTypography.footnote)
                .foregroundColor(WOSColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
struct HealingTrendChart_Previews: PreviewProvider {
    static var previews: some View {
        HealingTrendChart(scans: MockDataProvider.allScans)
            .frame(height: 180)
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
#endif
