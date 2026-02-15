// PasteManager.swift
// YapYap — Paste text into active app via clipboard + CGEvent or AX API
import AppKit
import Carbon.HIToolbox

class PasteManager {

    /// Primary paste strategy: clipboard + synthetic Cmd+V
    func paste(_ text: String) {
        pasteViaClipboard(text)
    }

    /// Strategy 1: Save clipboard, set text, synthetic Cmd+V, restore clipboard
    func pasteViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)

        // Set new content
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Ensure the frontmost app is ready to receive the paste.
        // YapYap's floating bar is a non-activating panel, so the user's app
        // should still be frontmost. We give a tiny delay for pasteboard sync.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Activate the frontmost app to make sure it can receive key events
            if let frontApp = NSWorkspace.shared.frontmostApplication {
                frontApp.activate()
            }

            // Small additional delay after activation to ensure the app is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                self.simulatePaste()

                // Restore previous clipboard content after paste has been processed
                if let previous = previousContent {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        pasteboard.clearContents()
                        pasteboard.setString(previous, forType: .string)
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
        let source = CGEventSource(stateID: .hidSystemState)

        // Key code for 'V' is 0x09
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}
