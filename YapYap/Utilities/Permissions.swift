// Permissions.swift
// YapYap — Permission checking and system settings guidance
//
// Two distribution modes:
//  - DIRECT_DISTRIBUTION: uses AXIsProcessTrusted() — full Accessibility API access.
//  - App Store: uses CGPreflightPostEventAccess() — sandbox-compatible PostEvent check.
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

    /// Check if we have the required permission for paste.
    /// - Direct distribution: checks full Accessibility (AXIsProcessTrusted) — needed for
    ///   AX-based paste strategy and CGEvent posting.
    /// - App Store: checks PostEvent TCC service (CGPreflightPostEventAccess) — the
    ///   sandbox-compatible check for synthetic Cmd+V.
    static var hasAccessibilityPermission: Bool {
        #if DIRECT_DISTRIBUTION
        AXIsProcessTrusted()
        #else
        CGPreflightPostEventAccess()
        #endif
    }

    /// Request the appropriate accessibility permission.
    static func requestAccessibilityPermission() {
        #if DIRECT_DISTRIBUTION
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        #else
        CGRequestPostEventAccess()
        #endif
    }

    // MARK: - Alerts

    static func showPermissionAlert(title: String, message: String, settingsPath: String) {
        // Bring app to foreground so the alert is visible — LSUIElement apps
        // show alerts behind other windows without this.
        NSApp.activate(ignoringOtherApps: true)

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
        #if DIRECT_DISTRIBUTION
        let message = "YapYap needs accessibility access to paste transcribed text into your apps.\n\nIf YapYap is already listed in System Settings → Privacy & Security → Accessibility, toggle it OFF then back ON to refresh the permission."
        #else
        let message = "YapYap needs accessibility access to paste transcribed text into your apps.\n\nPlease enable YapYap in System Settings → Privacy & Security → Accessibility."
        #endif
        showPermissionAlert(
            title: "Accessibility Access Required",
            message: message,
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
