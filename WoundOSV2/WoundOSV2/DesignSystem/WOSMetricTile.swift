import SwiftUI

enum MetricTrend {
    case improving(Double)
    case stable
    case worsening(Double)

    var icon: String {
        switch self {
        case .improving: return "arrow.down.right"
        case .stable: return "arrow.right"
        case .worsening: return "arrow.up.right"
        }
    }

    var color: Color {
        switch self {
        case .improving: return WOSColors.green
        case .stable: return WOSColors.yellow
        case .worsening: return WOSColors.red
        }
    }

    var text: String {
        switch self {
        case .improving(let pct): return String(format: "%.0f%% from last scan", pct)
        case .stable: return "Stable from last scan"
        case .worsening(let pct): return String(format: "%.0f%% from last scan", pct)
        }
    }
}

struct WOSMetricTile: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let unit: String
    var trend: MetricTrend?

    var body: some View {
        WOSCard {
            VStack(alignment: .leading, spacing: WOSSpacing.sm) {
                HStack(spacing: WOSSpacing.sm) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(iconColor)
                        .frame(width: 28, height: 28)
                        .background(iconColor.opacity(0.15))
                        .clipShape(Circle())

                    Text(label)
                        .font(WOSTypography.caption)
                        .foregroundColor(WOSColors.textSecondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: WOSSpacing.xs) {
                    Text(value)
                        .font(WOSTypography.metricValueMedium)
                        .foregroundColor(WOSColors.textPrimary)

                    Text(unit)
                        .font(WOSTypography.metricUnit)
                        .foregroundColor(WOSColors.textSecondary)
                }

                if let trend = trend {
                    HStack(spacing: WOSSpacing.xs) {
                        Image(systemName: trend.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(trend.text)
                            .font(WOSTypography.footnote)
                    }
                    .foregroundColor(trend.color)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) \(unit)")
        .accessibilityValue(trend?.text ?? "")
    }
}

#if DEBUG
struct WOSMetricTile_Previews: PreviewProvider {
    static var previews: some View {
        WOSMetricTile(
            icon: "square.dashed",
            iconColor: WOSColors.teal,
            label: "Area",
            value: "12.4",
            unit: "cm²",
            trend: .improving(8)
        )
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
