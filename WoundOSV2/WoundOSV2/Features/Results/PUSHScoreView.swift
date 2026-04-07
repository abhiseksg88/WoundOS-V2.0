import SwiftUI

struct PUSHScoreView: View {
    let score: PUSHScore

    var body: some View {
        WOSCard {
            VStack(alignment: .leading, spacing: WOSSpacing.sm) {
                HStack(spacing: WOSSpacing.sm) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(WOSColors.yellow)
                        .frame(width: 28, height: 28)
                        .background(WOSColors.yellow.opacity(0.15))
                        .clipShape(Circle())

                    Text("PUSH Score")
                        .font(WOSTypography.caption)
                        .foregroundColor(WOSColors.textSecondary)
                }

                HStack(alignment: .center, spacing: WOSSpacing.md) {
                    WOSProgressRing(
                        progress: score.normalizedScore,
                        lineWidth: 5,
                        color: scoreColor,
                        centerText: "\(score.totalScore)"
                    )
                    .frame(width: 48, height: 48)

                    Text("/\(score.maxPossible)")
                        .font(WOSTypography.metricUnit)
                        .foregroundColor(WOSColors.textSecondary)
                }

                Text(score.interpretation)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(scoreColor)
            }
        }
    }

    private var scoreColor: Color {
        switch score.totalScore {
        case 0...5: return WOSColors.green
        case 6...10: return WOSColors.yellow
        case 11...14: return WOSColors.orange
        default: return WOSColors.red
        }
    }
}

#if DEBUG
struct PUSHScoreView_Previews: PreviewProvider {
    static var previews: some View {
        PUSHScoreView(score: PUSHScore(areaScore: 9, exudateScore: 2, surfaceTypeScore: 3))
            .frame(width: 180)
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
#endif
