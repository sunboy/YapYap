// SoundManager.swift
// YapYap — Audio feedback for recording start/stop
import AppKit

class SoundManager {
    static let shared = SoundManager()

    private var isEnabled: Bool = true

    private init() {}

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    func playStart() {
        guard isEnabled else { return }
        // Try to play custom sound, fall back to system sound
        if let sound = NSSound(named: "start") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    func playStop() {
        guard isEnabled else { return }
        if let sound = NSSound(named: "stop") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    func playError() {
        guard isEnabled else { return }
        NSSound.beep()
    }
}
