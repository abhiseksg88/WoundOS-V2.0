import SwiftUI

struct WoundTimelineView: View {
    let scans: [WoundScan]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(scans.enumerated()), id: \.element.id) { index, scan in
                HStack(alignment: .top, spacing: WOSSpacing.lg) {
                    // Timeline line + dot
                    VStack(spacing: 0) {
                        Circle()
                            .fill(scan.status == .complete ? WOSColors.accent : WOSColors.textTertiary)
                            .frame(width: 12, height: 12)

                        if index < scans.count - 1 {
                            Rectangle()
                                .fill(WOSColors.separator)
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 12)

                    // Scan card
                    WOSCard {
                        VStack(alignment: .leading, spacing: WOSSpacing.sm) {
                            HStack {
                                VStack(alignment: .leading, spacing: WOSSpacing.xs) {
                                    Text(scan.bodyLocation.displayName)
                                        .font(WOSTypography.headline)
                                        .foregroundColor(WOSColors.textPrimary)

                                    Text(scan.capturedAt, format: .dateTime.month().day().year().hour().minute())
                                        .font(WOSTypography.caption)
                                        .foregroundColor(WOSColors.textSecondary)
                                }

                                Spacer()

                                if let trend = scan.healingTrend {
                                    healingBadge(for: trend)
                                }
                            }

                            if let measurements = scan.measurements {
                                Divider()

                                HStack(spacing: WOSSpacing.lg) {
                                    metricLabel("Area", String(format: "%.1f cm²", measurements.areaCm2))
                                    metricLabel("Depth", String(format: "%.1f mm", measurements.maxDepthMm))
                                    metricLabel("Volume", String(format: "%.1f mL", measurements.volumeMl))
                                }
                            }

                            if scan.status != .complete {
                                HStack(spacing: WOSSpacing.xs) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text(scan.status.rawValue.capitalized)
                                        .font(WOSTypography.caption)
                                        .foregroundColor(WOSColors.textSecondary)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, WOSSpacing.md)
            }
        }
    }

    private func metricLabel(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(WOSTypography.caption)
                .foregroundColor(WOSColors.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(WOSColors.textPrimary)
        }
    }

    private func healingBadge(for trend: HealingTrend) -> some View {
        let status: WOSHealingStatus = {
            switch trend {
            case .healing: return .healing
            case .stable: return .stable
            case .worsening: return .worsening
            }
        }()
        return WOSStatusBadge(status: status)
    }
}

#if DEBUG
struct WoundTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        WoundTimelineView(scans: MockDataProvider.patients[0].wounds)
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
#endif
