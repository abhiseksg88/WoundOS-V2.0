import SwiftUI

struct RecentScanCard: View {
    let scan: WoundScan
    let patientName: String

    var body: some View {
        WOSCard {
            VStack(alignment: .leading, spacing: WOSSpacing.sm) {
                // Wound image placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: WOSRadius.md)
                        .fill(WOSColors.fill)
                        .frame(width: 140, height: 100)

                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundColor(WOSColors.textTertiary)
                }

                // Patient name
                Text(patientName)
                    .font(WOSTypography.headline)
                    .foregroundColor(WOSColors.textPrimary)
                    .lineLimit(1)

                // Location & date
                VStack(alignment: .leading, spacing: 2) {
                    Text(scan.bodyLocation.displayName)
                        .font(WOSTypography.caption)
                        .foregroundColor(WOSColors.textSecondary)

                    Text(scan.capturedAt, style: .date)
                        .font(WOSTypography.caption)
                        .foregroundColor(WOSColors.textTertiary)
                }

                // Status or measurement
                if let measurements = scan.measurements {
                    Text(String(format: "%.1f cm²", measurements.areaCm2))
                        .font(WOSTypography.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(WOSColors.accent)
                }

                // Healing badge
                if let trend = scan.healingTrend {
                    healingBadge(for: trend)
                } else if scan.status != .complete {
                    statusLabel
                }
            }
            .frame(width: 140)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(patientName), \(scan.bodyLocation.displayName)")
        .accessibilityValue(scan.measurements.map { String(format: "%.1f square centimeters", $0.areaCm2) } ?? scan.status.rawValue)
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

    @ViewBuilder
    private var statusLabel: some View {
        HStack(spacing: WOSSpacing.xs) {
            if scan.status == .processing || scan.status == .uploading {
                ProgressView()
                    .scaleEffect(0.7)
            }
            Text(scan.status.rawValue.capitalized)
                .font(WOSTypography.caption)
                .foregroundColor(WOSColors.textSecondary)
        }
    }
}

#if DEBUG
struct RecentScanCard_Previews: PreviewProvider {
    static var previews: some View {
        let scan = MockDataProvider.allScans.first!
        RecentScanCard(scan: scan, patientName: "Margaret Chen")
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
#endif
