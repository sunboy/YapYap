// Permissions.swift
// YapYap — Permission checking and system settings guidance
import AppKit
import AVFoundation

struct Permissions {

    // MARK: - Microphone

    static var hasMicrophonePermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Accessibility

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Alerts

    static func showPermissionAlert(title: String, message: String, settingsPath: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            openSystemSettings(path: settingsPath)
        }
    }

    static func showMicrophonePermissionAlert() {
        showPermissionAlert(
            title: "Microphone Access Required",
            message: "YapYap needs microphone access to transcribe your voice into text.\n\nPlease enable microphone access in System Settings.",
            settingsPath: "Privacy_Microphone"
        )
    }

    static func showAccessibilityPermissionAlert() {
        showPermissionAlert(
            title: "Accessibility Access Required",
            message: "YapYap needs accessibility access to paste transcribed text into your apps and detect the active application.\n\nPlease enable YapYap in System Settings → Privacy & Security → Accessibility.",
            settingsPath: "Privacy_Accessibility"
        )
    }

    // MARK: - System Settings

    private static func openSystemSettings(path: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(path)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Check All

    static func checkAllPermissions() -> (microphone: Bool, accessibility: Bool) {
        return (hasMicrophonePermission, hasAccessibilityPermission)
    }
}
