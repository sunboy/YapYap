// PasteManager.swift
// YapYap — Paste text into active app via cascading injection strategies
import AppKit
import Carbon.HIToolbox

class PasteManager {

    /// Terminal emulators that silently accept AX writes but never render them.
    /// For these apps, always use clipboard + Cmd+V.
    private let terminalBundleIds: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable", "dev.warp.Warp",
        "com.github.alacritty",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "com.panic.Prompt",
    ]

    /// Cascading paste: try Accessibility API first (cleanest), then clipboard + Cmd+V
    /// - Parameters:
    ///   - text: The text to paste
    ///   - targetApp: The app to paste into (captured at recording start). Falls back to frontmost app.
    func paste(_ text: String, targetApp: NSRunningApplication? = nil) {
        let resolvedApp = targetApp ?? NSWorkspace.shared.frontmostApplication
        let appName = resolvedApp?.localizedName ?? "unknown"
        NSLog("[PasteManager] Paste requested: \(text.count) chars → \(appName)")

        // Strategy 1: Accessibility API setValue (no clipboard pollution)
        // Skip for terminal apps — they accept AX writes silently but don't render them
        let bundleId = resolvedApp?.bundleIdentifier ?? ""
        let isTerminal = terminalBundleIds.contains(bundleId)
        if !isTerminal, tryAccessibilitySetValue(text, targetApp: resolvedApp) {
            NSLog("[PasteManager] Pasted via Accessibility API")
            return
        }
        if isTerminal {
            NSLog("[PasteManager] Terminal app detected (\(bundleId)), skipping AX paste")
        }

        // Strategy 2: Clipboard + synthetic Cmd+V (most compatible)
        NSLog("[PasteManager] Accessibility API failed, falling back to clipboard paste")
        pasteViaClipboard(text, targetApp: resolvedApp)
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
                // Verify the text actually landed — some apps (terminals, Electron)
                // return .success but silently ignore the write
                var readBack: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &readBack) == .success,
                   let readStr = readBack as? String, readStr.isEmpty {
                    // Text was consumed (selection collapsed) — likely worked
                    return true
                }
                // Can't verify, but AX said success — trust it for non-terminal apps
                // Terminal emulators lie about AX writes, so check the role
                var role: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
                   let roleStr = role as? String, roleStr == "AXTextArea" || roleStr == "AXTextField" {
                    return true
                }
                NSLog("[PasteManager] AX set returned success but element role is suspicious, falling through")
            }
        }

        // Fallback: replace entire value (works for simple single-line fields)
        // Only do this for short text fields to avoid overwriting document content
        var currentValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValue) == .success {
            if let current = currentValue as? String, current.count < 500 {
                let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
                if result == .success {
                    // Verify write took effect
                    var afterValue: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &afterValue) == .success,
                       let afterStr = afterValue as? String, afterStr.contains(text) {
                        return true
                    }
                    NSLog("[PasteManager] AX setValue returned success but verification failed")
                }
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

        // Ensure the target app is ready to receive the paste.
        // Use the pre-captured target app from recording start (prevents pasting into
        // YapYap itself when processing takes a long time and YapYap becomes frontmost).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            // Activate the target app to make sure it can receive key events.
            // Detect self-paste: if target is YapYap itself, fall back to another active app.
            let appToActivate = targetApp ?? NSWorkspace.shared.frontmostApplication
            if let app = appToActivate {
                let isSelf = app.processIdentifier == ProcessInfo.processInfo.processIdentifier
                if isSelf {
                    NSLog("[PasteManager] Target is YapYap itself, looking for previous app")
                    // Fall back to frontmost non-self app
                    if let fallback = NSWorkspace.shared.runningApplications.first(where: {
                        $0.isActive && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                    }) {
                        NSLog("[PasteManager] Activating fallback app: \(fallback.localizedName ?? "unknown") (pid: \(fallback.processIdentifier))")
                        fallback.activate()
                    } else {
                        NSLog("[PasteManager] No suitable target app found")
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
