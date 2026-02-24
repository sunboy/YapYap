// PasteManager.swift
// YapYap — Paste text into active app via clipboard + CGEvent or AX API
import AppKit
import Carbon.HIToolbox

class PasteManager {

    /// Primary paste strategy: clipboard + synthetic Cmd+V
    /// - Parameters:
    ///   - text: The text to paste
    ///   - targetApp: The app to paste into (captured at recording start). Falls back to frontmost app.
    func paste(_ text: String, targetApp: NSRunningApplication? = nil) {
        pasteViaClipboard(text, targetApp: targetApp)
    }

    /// Strategy 1: Save clipboard, set text, synthetic Cmd+V, restore clipboard
    func pasteViaClipboard(_ text: String, targetApp: NSRunningApplication? = nil) {
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)

        // Set new content
        pasteboard.clearContents()
        let setOk = pasteboard.setString(text, forType: .string)
        NSLog("[PasteManager] Clipboard set: \(setOk), text length: \(text.count)")

        // Ensure the target app is ready to receive the paste.
        // Use the pre-captured target app from recording start (prevents pasting into
        // YapYap itself when processing takes a long time and YapYap becomes frontmost).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            let appToActivate = targetApp ?? NSWorkspace.shared.frontmostApplication
            if let app = appToActivate {
                let isSelf = app.processIdentifier == ProcessInfo.processInfo.processIdentifier
                if isSelf {
                    NSLog("[PasteManager] ⚠️ Target is YapYap itself, looking for previous app")
                    // Fall back to frontmost non-self app
                    if let fallback = NSWorkspace.shared.runningApplications.first(where: {
                        $0.isActive && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                    }) {
                        NSLog("[PasteManager] Activating fallback app: \(fallback.localizedName ?? "unknown") (pid: \(fallback.processIdentifier))")
                        fallback.activate()
                    } else {
                        NSLog("[PasteManager] ⚠️ No suitable target app found")
                    }
                } else {
                    NSLog("[PasteManager] Activating app: \(app.localizedName ?? "unknown") (pid: \(app.processIdentifier))")
                    app.activate()
                }
            } else {
                NSLog("[PasteManager] ⚠️ No target app found")
            }

            // Small additional delay after activation to ensure the app is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
                NSLog("[PasteManager] Sending synthetic Cmd+V")
                self.simulatePaste()

                // Restore previous clipboard content after paste has been processed
                if let previous = previousContent {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        pasteboard.clearContents()
                        pasteboard.setString(previous, forType: .string)
                        NSLog("[PasteManager] Clipboard restored")
                    }
                }
            }
        }
    }

    /// Strategy 2: Paste via Accessibility API (fallback)
    func pasteViaAccessibility(_ text: String) {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard result == .success else {
            // Fall back to clipboard paste
            pasteViaClipboard(text)
            return
        }

        let axElement = focusedElement as! AXUIElement

        // Try to get existing text and append, or set directly
        var existingValue: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &existingValue)

        // Set the value
        AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, text as CFTypeRef)
    }

    // MARK: - CGEvent Helpers

    private func simulatePaste() {
        // CGEvent requires accessibility permission — check first
        let trusted = AXIsProcessTrusted()
        NSLog("[PasteManager] AXIsProcessTrusted: \(trusted)")

        let source = CGEventSource(stateID: .hidSystemState)
        NSLog("[PasteManager] CGEventSource created: \(source != nil)")

        // Key code for 'V' is 0x09
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        NSLog("[PasteManager] Cmd+V keyDown posted: \(keyDown != nil)")

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
        NSLog("[PasteManager] Cmd+V keyUp posted: \(keyUp != nil)")
    }
}
