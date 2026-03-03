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
        NSLog("[PasteManager] Paste requested: \(text.count) chars → \(appName) (pid: \(resolvedApp?.processIdentifier ?? -1))")

        guard AXIsProcessTrusted() else {
            NSLog("[PasteManager] ❌ Accessibility not granted — paste skipped. Showing permission alert.")
            DispatchQueue.main.async { Permissions.showAccessibilityPermissionAlert() }
            return
        }

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
            NSLog("[PasteManager] AX: could not get focused element from pid \(pid)")
            return false
        }

        let element = focusedElement as! AXUIElement

        // Check if the element supports setting a value
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
              settable.boolValue else {
            NSLog("[PasteManager] AX: focused element is not settable")
            return false
        }

        // Check element role — only trust text-input roles
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
           let roleStr = role as? String,
           roleStr != "AXTextArea" && roleStr != "AXTextField" {
            NSLog("[PasteManager] AX: element role is '\(roleStr)', not a text field — skipping AX paste")
            return false
        }

        // Try to get selected text range to insert at cursor (not replace all)
        var selectedRange: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success {
            // Insert at selection point using selected text attribute
            let setResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            if setResult == .success {
                // Role was already validated above — trust AX success for text fields
                return true
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
        // Allow 50ms for clipboard write to propagate before activating the app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Activate the target app to make sure it can receive key events.
            // Detect self-paste: if target is YapYap itself, fall back to another active app.
            let appToActivate = targetApp ?? NSWorkspace.shared.frontmostApplication
            if let app = appToActivate {
                let isSelf = app.processIdentifier == ProcessInfo.processInfo.processIdentifier
                if isSelf {
                    NSLog("[PasteManager] Target is YapYap itself, looking for previous app")
                    // Fall back to frontmost non-self app
                    if let fallback = NSWorkspace.shared.frontmostApplication,
                       fallback.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                        NSLog("[PasteManager] Activating fallback app: \(fallback.localizedName ?? "unknown") (pid: \(fallback.processIdentifier))")
                        fallback.activate()
                    } else {
                        NSLog("[PasteManager] ⚠️ No suitable target app found — frontmost is YapYap")
                    }
                } else {
                    NSLog("[PasteManager] Activating app: \(app.localizedName ?? "unknown") (pid: \(app.processIdentifier))")
                    app.activate()
                }
            } else {
                NSLog("[PasteManager] ⚠️ No target app found")
            }

            // Allow 100ms after activation for the app to become ready to receive input.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                self.simulatePaste()

                // Retry: send a second Cmd+V after a short delay if the first one was
                // silently dropped (common on fresh installs where accessibility permission
                // cache is stale). The clipboard still holds our text so this is safe.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    // Check if the target app is now frontmost — if not, the first paste
                    // likely failed so retry
                    if let app = appToActivate, !app.isActive {
                        NSLog("[PasteManager] ⚠️ Target app not active after first paste, retrying activation + Cmd+V")
                        app.activate()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                            self.simulatePaste()
                        }
                    }
                }

                // Restore previous clipboard content after paste has been processed
                if let previous = previousContent {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
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
        if !trusted {
            NSLog("[PasteManager] ⚠️ AXIsProcessTrusted returned FALSE — CGEvent paste will fail. Reset accessibility: tccutil reset Accessibility dev.yapyap.app")
        }

        // Try creating a named event source; fall back to nil source if it fails
        // (nil source uses the default HID system state and may work even when
        // the named source fails due to stale accessibility permission cache)
        var source = CGEventSource(stateID: .hidSystemState)
        if source == nil {
            NSLog("[PasteManager] ⚠️ Named CGEventSource failed, trying with combinedSessionState")
            source = CGEventSource(stateID: .combinedSessionState)
        }
        if source == nil {
            NSLog("[PasteManager] ⚠️ All CGEventSource creation failed — attempting paste with nil source")
        }

        // Key code for 'V' is 0x09
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        guard keyDown != nil else {
            NSLog("[PasteManager] ❌ Failed to create CGEvent keyDown — accessibility permission likely stale. Reset with: tccutil reset Accessibility dev.yapyap.app")
            return
        }
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
        NSLog("[PasteManager] Cmd+V posted (keyDown + keyUp)")
    }
}
