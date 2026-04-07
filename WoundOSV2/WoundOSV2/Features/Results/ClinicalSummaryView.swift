import SwiftUI

struct ClinicalSummaryView: View {
    let text: String
    @State private var isExpanded = false

    private let lineLimit = 3

    var body: some View {
        WOSCard {
            VStack(alignment: .leading, spacing: WOSSpacing.sm) {
                HStack {
                    Image(systemName: "text.document")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(WOSColors.accent)
                    Text("Clinical Summary")
                        .font(WOSTypography.headline)
                        .foregroundColor(WOSColors.textPrimary)
                }

                Text(text)
                    .font(WOSTypography.body)
                    .foregroundColor(WOSColors.textSecondary)
                    .lineLimit(isExpanded ? nil : lineLimit)
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)

                if text.count > 150 {
                    Button(action: { isExpanded.toggle() }) {
                        Text(isExpanded ? "Show less" : "Read more")
                            .font(WOSTypography.footnote)
                            .fontWeight(.semibold)
                            .foregroundColor(WOSColors.accent)
                    }
                }
            }
        }
    }
}

#if DEBUG
struct ClinicalSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        ClinicalSummaryView(text: "Stage III pressure injury on sacrum measuring 12.4 cm². Wound bed shows 70% granulation tissue with 30% slough. Moderate serous exudate noted. Periwound skin intact with mild erythema extending 1cm from wound edge.")
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
#endif
