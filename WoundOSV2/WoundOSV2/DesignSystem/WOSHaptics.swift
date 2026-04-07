import UIKit

enum WOSHaptics {
    private static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    static func capture() {
        impactMedium.impactOccurred()
    }

    static func complete() {
        notificationGenerator.notificationOccurred(.success)
    }

    static func warning() {
        notificationGenerator.notificationOccurred(.warning)
    }

    static func error() {
        notificationGenerator.notificationOccurred(.error)
    }

    static func selection() {
        selectionGenerator.selectionChanged()
    }
}
