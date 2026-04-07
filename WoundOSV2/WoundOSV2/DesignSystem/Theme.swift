import SwiftUI

// MARK: - Colors
struct WOSColors {
    static let accent = Color("AccentColor")
    static let red = Color(.systemRed)
    static let green = Color(.systemGreen)
    static let yellow = Color(.systemYellow)
    static let orange = Color(.systemOrange)
    static let purple = Color(.systemPurple)
    static let blue = Color(.systemBlue)
    static let teal = Color(.systemTeal)
    static let background = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)
    static let separator = Color(.separator)
    static let fill = Color(.tertiarySystemFill)
}

// MARK: - Typography
struct WOSTypography {
    static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    static let title = Font.system(size: 28, weight: .bold, design: .rounded)
    static let title2 = Font.system(size: 22, weight: .bold, design: .rounded)
    static let title3 = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 17, weight: .regular, design: .default)
    static let callout = Font.system(size: 16, weight: .regular, design: .default)
    static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
    static let footnote = Font.system(size: 13, weight: .regular, design: .default)
    static let caption = Font.system(size: 12, weight: .regular, design: .default)

    static let metricValue = Font.system(size: 48, weight: .bold, design: .rounded)
    static let metricValueMedium = Font.system(size: 36, weight: .bold, design: .rounded)
    static let metricUnit = Font.system(size: 20, weight: .medium, design: .rounded)
}

// MARK: - Spacing
struct WOSSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

// MARK: - Radii
struct WOSRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let full: CGFloat = 100
}
