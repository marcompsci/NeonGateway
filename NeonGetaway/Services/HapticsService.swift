import UIKit

/// Thin wrapper so every haptic respects the Settings toggle.
@MainActor
final class HapticsService {
    var enabled = true

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    /// A wall or block hit. `strength` 0...1 picks the generator and intensity.
    func impact(strength: Double) {
        guard enabled else { return }
        let s = CGFloat(min(max(strength, 0), 1))
        if s > 0.6 {
            heavy.impactOccurred(intensity: s)
        } else {
            light.impactOccurred(intensity: max(0.3, s))
        }
    }

    func tick() {
        guard enabled else { return }
        selection.selectionChanged()
    }

    func success() {
        guard enabled else { return }
        notification.notificationOccurred(.success)
    }

    func failure() {
        guard enabled else { return }
        notification.notificationOccurred(.warning)
    }
}
