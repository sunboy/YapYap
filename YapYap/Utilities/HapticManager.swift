// HapticManager.swift
// YapYap — Trackpad haptic feedback
import AppKit

class HapticManager {
    static let shared = HapticManager()

    private var isEnabled: Bool = true

    private init() {}

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    func tap() {
        guard isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .default
        )
    }

    func levelChange() {
        guard isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .default
        )
    }
}
