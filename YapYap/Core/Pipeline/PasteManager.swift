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

    /// Cascading paste: try Accessibility API first (cleanest), then clipboard + Cmd+V.
    ///
    /// - Parameters:
    ///   - text: The text to paste.
    ///   - targetApp: The app to paste into (captured at recording start). Falls back to frontmost app.
    ///   - keepOnClipboard: When true (copyToClipboard setting), the clipboard keeps the
    ///     transcription after paste instead of being restored. Also omits the transient marker
    ///     so clipboard managers record the text.
    func paste(_ text: String, targetApp: NSRunningApplication? = nil, keepOnClipboard: Bool = false) {
        let resolvedApp = targetApp ?? NSWorkspace.shared.frontmostApplication
        let appName = resolvedApp?.localizedName ?? "unknown"
        NSLog("[PasteManager] Paste requested: \(text.count) chars → \(appName) (pid: \(resolvedApp?.processIdentifier ?? -1))")

        guard canPostCGEvents() else {
            NSLog("[PasteManager] ❌ CGEvent permission check failed — paste skipped. Showing permission alert.")
            DispatchQueue.main.async { Permissions.showAccessibilityPermissionAlert() }
            return
        }

        // Strategy 1: Accessibility API setValue (no clipboard pollution)
        // Skip for terminal apps — they accept AX writes silently but don't render them
        let bundleId = resolvedApp?.bundleIdentifier ?? ""
        let isTerminal = terminalBundleIds.contains(bundleId)
        if !isTerminal, tryAccessibilitySetValue(text, targetApp: resolvedApp) {
            NSLog("[PasteManager] Pasted via Accessibility API")
            // If user wants text on clipboard too, set it now (AX path doesn't touch clipboard)
            if keepOnClipboard {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
            return
        }
        if isTerminal {
            NSLog("[PasteManager] Terminal app detected (\(bundleId)), skipping AX paste")
        }

        // Strategy 2: Clipboard + synthetic Cmd+V (most compatible)
        NSLog("[PasteManager] Accessibility API failed, falling back to clipboard paste")
        pasteViaClipboard(text, targetApp: resolvedApp, keepOnClipboard: keepOnClipboard)
    }

    // MARK: - Permission Check

    /// Probe whether we can actually post CGEvents by attempting to create an event tap.
    /// `AXIsProcessTrusted()` returns stale `true` after rebuilds when the code signature
    /// changes but the TCC database entry hasn't been refreshed. This is the real check.
    private func canPostCGEvents() -> Bool {
        // Fast path: if AXIsProcessTrusted is false, we definitely can't
        guard AXIsProcessTrusted() else { return false }

        // Real check: try creating a passive event tap — this goes through the kernel
        // TCC check and will fail if the permission is stale
        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        )
        if let tap = tap {
            CFMachPortInvalidate(tap)
            return true
        }
        NSLog("[PasteManager] ⚠️ CGEvent tap creation failed — accessibility permission is stale. Reset with: tccutil reset Accessibility dev.yapyap.app")
        return false
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
                // Verify the text actually landed — some apps (Electron: Slack, VS Code)
                // return .success but silently ignore the write
                var readBack: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &readBack) == .success,
                   let readStr = readBack as? String, readStr.isEmpty {
                    // Text was consumed (selection collapsed after insert) — it worked
                    return true
                }
                // Read the full value to see if our text appears
                var fullValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &fullValue) == .success,
                   let fullStr = fullValue as? String, fullStr.contains(text) {
                    return true
                }
                NSLog("[PasteManager] AX: selectedText set returned success but text not found in field — falling through to clipboard")
                return false
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

    /// Save clipboard, set text, synthetic Cmd+V, optionally restore clipboard.
    private func pasteViaClipboard(_ text: String, targetApp: NSRunningApplication?, keepOnClipboard: Bool) {
        let pasteboard = NSPasteboard.general

        // Save ALL pasteboard items (not just .string) so we can restore rich content
        // (images, RTF, files) the user had copied. Skip if keepOnClipboard — no restore needed.
        let savedItems: [[(NSPasteboard.PasteboardType, Data)]]? = keepOnClipboard ? nil : savePasteboard(pasteboard)

        // Set new content
        pasteboard.clearContents()

        // Mark as transient so clipboard managers (Maccy, Paste.app) don't record
        // this temporary write — unless the user wants it kept on clipboard
        if !keepOnClipboard {
            let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
            let autoGenType = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            item.setData(Data(), forType: transientType)
            item.setData(Data(), forType: autoGenType)
            pasteboard.writeObjects([item])
        } else {
            pasteboard.setString(text, forType: .string)
        }
        NSLog("[PasteManager] Clipboard set: text length: \(text.count), keepOnClipboard: \(keepOnClipboard)")

        // Ensure the target app is ready to receive the paste.
        // Allow 50ms for clipboard write to propagate before activating the app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.activateTargetApp(targetApp)

            // Allow 100ms after activation for the app to become ready to receive input.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                self.simulatePaste()

                // Retry: send a second Cmd+V after a short delay if the first one was
                // silently dropped (common when accessibility permission cache is stale).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    if let app = targetApp, !app.isActive {
                        NSLog("[PasteManager] ⚠️ Target app not active after first paste, retrying activation + Cmd+V")
                        self.activateTargetApp(targetApp)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                            self.simulatePaste()
                        }
                    }
                }

                // Restore previous clipboard content after paste has been processed.
                // Only restore when keepOnClipboard is false — otherwise the user wants
                // the transcription to stay on the clipboard.
                if let savedItems = savedItems, !savedItems.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.restorePasteboard(pasteboard, from: savedItems)
                        NSLog("[PasteManager] Clipboard restored (all types)")
                    }
                }
            }
        }
    }

    // MARK: - App Activation

    private func activateTargetApp(_ targetApp: NSRunningApplication?) {
        let appToActivate = targetApp ?? NSWorkspace.shared.frontmostApplication
        guard let app = appToActivate else {
            NSLog("[PasteManager] ⚠️ No target app found")
            return
        }

        let isSelf = app.processIdentifier == ProcessInfo.processInfo.processIdentifier
        if isSelf {
            NSLog("[PasteManager] Target is YapYap itself, looking for previous app")
            if let fallback = NSWorkspace.shared.frontmostApplication,
               fallback.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                NSLog("[PasteManager] Activating fallback app: \(fallback.localizedName ?? "unknown") (pid: \(fallback.processIdentifier))")
                Self.activateApp(fallback)
            } else {
                NSLog("[PasteManager] ⚠️ No suitable target app found — frontmost is YapYap")
            }
        } else {
            NSLog("[PasteManager] Activating app: \(app.localizedName ?? "unknown") (pid: \(app.processIdentifier))")
            Self.activateApp(app)
        }
    }

    /// Activate using cooperative API on macOS 14+, legacy API otherwise.
    private static func activateApp(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            NSApplication.shared.yieldActivation(to: app)
            app.activate(from: NSRunningApplication.current, options: [])
        } else {
            app.activate()
        }
    }

    // MARK: - Pasteboard Save/Restore

    /// Save all items and their types from the pasteboard so we can do a full restore later.
    private func savePasteboard(_ pasteboard: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
        var saved: [[(NSPasteboard.PasteboardType, Data)]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var pairs: [(NSPasteboard.PasteboardType, Data)] = []
            for type in item.types {
                if let data = item.data(forType: type) {
                    pairs.append((type, data))
                }
            }
            if !pairs.isEmpty {
                saved.append(pairs)
            }
        }
        return saved
    }

    /// Restore pasteboard to its previous state with all types preserved.
    private func restorePasteboard(_ pasteboard: NSPasteboard, from saved: [[(NSPasteboard.PasteboardType, Data)]]) {
        pasteboard.clearContents()
        var items: [NSPasteboardItem] = []
        for pairs in saved {
            let item = NSPasteboardItem()
            for (type, data) in pairs {
                item.setData(data, forType: type)
            }
            items.append(item)
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    // MARK: - CGEvent Helpers

    private func simulatePaste() {
        // Try creating event source; fall back to nil if it fails
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
        guard keyDown != nil else {
            NSLog("[PasteManager] ❌ Failed to create CGEvent keyDown — accessibility permission likely stale. Reset with: tccutil reset Accessibility dev.yapyap.app")
            return
        }
        // Clear inherited modifier flags (e.g. Option from hotkey) then set only Cmd
        keyDown!.flags = []
        keyDown!.flags = .maskCommand
        keyDown!.post(tap: .cghidEventTap)

        // 50ms delay between keyDown and keyUp — Electron apps (Slack, VS Code, Discord)
        // need time between events to register the paste
        usleep(50_000)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = []
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
        NSLog("[PasteManager] Cmd+V posted (keyDown + 50ms + keyUp)")
    }
}
