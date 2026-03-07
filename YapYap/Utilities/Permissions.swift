// Permissions.swift
// YapYap — Permission checking and system settings guidance
//
// App Store sandbox compatible: uses CGPreflightPostEventAccess/CGRequestPostEventAccess
// for paste permission instead of AXIsProcessTrusted (which is blocked in sandbox).
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

    // MARK: - Accessibility (PostEvent permission for synthetic Cmd+V)

    /// Check if we can post synthetic keyboard events (Cmd+V for paste).
    /// Uses the sandbox-compatible CGPreflightPostEventAccess API which checks
    /// the PostEvent TCC service (shown as "Accessibility" in System Settings).
    static var hasAccessibilityPermission: Bool {
        CGPreflightPostEventAccess()
    }

    /// Request permission to post synthetic keyboard events.
    /// Shows the system TCC dialog prompting the user to grant access.
    static func requestAccessibilityPermission() {
        CGRequestPostEventAccess()
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
            message: "YapYap needs accessibility access to paste transcribed text into your apps.\n\nPlease enable YapYap in System Settings → Privacy & Security → Accessibility.",
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
