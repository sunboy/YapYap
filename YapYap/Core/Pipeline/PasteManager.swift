// PasteManager.swift
// YapYap — Paste text into active app via cascading injection strategies
import AppKit
import Carbon.HIToolbox

class PasteManager {

    /// Cascading paste: try Accessibility API first (cleanest), then clipboard + Cmd+V
    func paste(_ text: String) {
        let targetApp = NSWorkspace.shared.frontmostApplication
        let appName = targetApp?.localizedName ?? "unknown"
        NSLog("[PasteManager] Paste requested: \(text.count) chars → \(appName)")

        // Strategy 1: Accessibility API setValue (no clipboard pollution)
        if tryAccessibilitySetValue(text, targetApp: targetApp) {
            NSLog("[PasteManager] ✅ Pasted via Accessibility API")
            return
        }

        // Strategy 2: Clipboard + synthetic Cmd+V (most compatible)
        NSLog("[PasteManager] Accessibility API failed, falling back to clipboard paste")
        pasteViaClipboard(text, targetApp: targetApp)
    }

    // MARK: - Strategy 1: Accessibility API

    /// Try to set text directly via AXUIElement on the focused text field.
    /// Works in most native macOS text fields without touching the clipboard.
    private func tryAccessibilitySetValue(_ text: String, targetApp: NSRunningApplication?) -> Bool {
        guard let pid = targetApp?.processIdentifier else { return false }

        let app = AXUIElementCreateApplication(pid)
        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            return false
        }

        let element = focusedElement as! AXUIElement

        // Check if the element supports setting a value
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
              settable.boolValue else {
            return false
        }

        // Try to get selected text range to insert at cursor (not replace all)
        var selectedRange: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success {
            // Insert at selection point using selected text attribute
            let setResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            if setResult == .success {
                return true
            }
        }

        // Fallback: replace entire value (works for simple single-line fields)
        // Only do this for short text fields to avoid overwriting document content
        var currentValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValue) == .success {
            if let current = currentValue as? String, current.count < 500 {
                let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
                return result == .success
            }
        }

        return false
    }

    // MARK: - Strategy 2: Clipboard + Cmd+V

    /// Save clipboard, set text, synthetic Cmd+V, restore clipboard
    private func pasteViaClipboard(_ text: String, targetApp: NSRunningApplication?) {
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)

        // Set new content
        pasteboard.clearContents()
        let setOk = pasteboard.setString(text, forType: .string)
        NSLog("[PasteManager] Clipboard set: \(setOk), text length: \(text.count)")

        // Ensure the frontmost app is ready to receive the paste.
        // YapYap's floating bar is a non-activating panel, so the user's app
        // should still be frontmost. Brief delay for pasteboard sync.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            // Activate the target app to make sure it can receive key events
            if let app = targetApp ?? NSWorkspace.shared.frontmostApplication {
                NSLog("[PasteManager] Activating app: \(app.localizedName ?? "unknown") (pid: \(app.processIdentifier))")
                app.activate()
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
