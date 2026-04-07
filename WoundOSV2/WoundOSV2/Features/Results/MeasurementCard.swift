import SwiftUI

struct MeasurementCard: View {
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
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

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
    }
}
