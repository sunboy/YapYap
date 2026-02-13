// AppContextDetector.swift
// YapYap — Detect active app and classify for adaptive formatting
import AppKit
import ApplicationServices

class AppContextDetector {

    // MARK: - Bundle ID Mapping

    private static let bundleMap: [String: AppCategory] = [
        // Personal Messaging
        "com.apple.MobileSMS": .personalMessaging,
        "net.whatsapp.WhatsApp": .personalMessaging,
        "org.telegram.desktop": .personalMessaging,
        "org.thoughtcrime.securesms": .personalMessaging,
        "com.facebook.archon": .personalMessaging,

        // Work Messaging
        "com.tinyspeck.slackmacgap": .workMessaging,
        "com.microsoft.teams2": .workMessaging,
        "com.hnc.Discord": .workMessaging,
        "us.zoom.xos": .workMessaging,

        // Email
        "com.apple.mail": .email,
        "com.microsoft.Outlook": .email,
        "com.readdle.smartemail-macos": .email,
        "com.superhuman.electron": .email,

        // Code Editors
        "com.todesktop.230313mzl4w4u92": .codeEditor,
        "com.microsoft.VSCode": .codeEditor,
        "com.apple.dt.Xcode": .codeEditor,
        "dev.zed.Zed": .codeEditor,
        "com.codeium.windsurf": .codeEditor,
        "com.googlecode.iterm2": .codeEditor,
        "com.apple.Terminal": .codeEditor,

        // Documents
        "com.apple.iWork.Pages": .documents,
        "notion.id": .documents,
        "md.obsidian": .documents,
        "com.apple.Notes": .documents,

        // AI Chat
        "com.openai.chat": .aiChat,

        // Browsers
        "com.apple.Safari": .browser,
        "com.google.Chrome": .browser,
        "org.mozilla.firefox": .browser,
        "company.thebrowser.Browser": .browser,
        "com.brave.Browser": .browser,
        "com.vivaldi.Vivaldi": .browser,
        "com.operasoftware.Opera": .browser,
    ]

    private static let browserBundleIds: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox",
        "company.thebrowser.Browser", "com.brave.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera"
    ]

    // MARK: - Detection

    static func detect(settings: StyleSettings) -> AppContext {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return AppContext(
                bundleId: "", appName: "Unknown", category: .other,
                style: settings.styleFor(.other), windowTitle: nil,
                focusedFieldText: nil, isIDEChatPanel: false
            )
        }

        let bundleId = frontApp.bundleIdentifier ?? ""
        let appName = frontApp.localizedName ?? "Unknown"
        let pid = frontApp.processIdentifier

        // Check user overrides first
        var category: AppCategory
        if let override = settings.appCategoryOverrides[bundleId] {
            category = override
        } else if let mapped = bundleMap[bundleId] {
            category = mapped
        } else if browserBundleIds.contains(bundleId) {
            category = classifyBrowserTab(pid: pid)
        } else {
            category = .other
        }

        let windowTitle = getWindowTitle(pid: pid)
        let focusedText = getFocusedFieldText()
        let isIDEChat = category == .codeEditor && isAIChatPanel(windowTitle: windowTitle)
        let style = settings.styleFor(category)

        return AppContext(
            bundleId: bundleId, appName: appName, category: category,
            style: style, windowTitle: windowTitle,
            focusedFieldText: focusedText, isIDEChatPanel: isIDEChat
        )
    }

    /// Get the name of the frontmost app (convenience)
    static func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    // MARK: - Browser Tab Classification

    private static func classifyBrowserTab(pid: pid_t) -> AppCategory {
        guard let title = getWindowTitle(pid: pid)?.lowercased() else { return .browser }

        let patterns: [(String, AppCategory)] = [
            ("gmail", .email), ("outlook.live", .email), ("mail.google", .email),
            ("proton", .email), ("yahoo.com/mail", .email),
            ("slack.com", .workMessaging), ("teams.microsoft", .workMessaging),
            ("chatgpt", .aiChat), ("claude.ai", .aiChat), ("perplexity", .aiChat),
            ("docs.google", .documents), ("notion.so", .documents),
            ("github.com", .codeEditor), ("gitlab.com", .codeEditor),
        ]

        for (pattern, category) in patterns {
            if title.contains(pattern) { return category }
        }
        return .browser
    }

    // MARK: - IDE Chat Panel Detection

    private static func isAIChatPanel(windowTitle: String?) -> Bool {
        guard let title = windowTitle?.lowercased() else { return false }
        return title.contains("composer") || title.contains("chat") ||
               title.contains("copilot") || title.contains("ai assistant")
    }

    // MARK: - Accessibility API Helpers

    static func getWindowTitle(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue) == .success else { return nil }

        var titleValue: AnyObject?
        AXUIElementCopyAttributeValue(windowValue as! AXUIElement, kAXTitleAttribute as CFString, &titleValue)
        return titleValue as? String
    }

    static func getFocusedFieldText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success else { return nil }

        var textValue: AnyObject?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXValueAttribute as CFString, &textValue) == .success else { return nil }

        if let text = textValue as? String {
            return String(text.suffix(500))
        }
        return nil
    }

    /// Get selected text from active app (for Command Mode)
    static func getSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success else { return nil }

        var selectedText: AnyObject?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText) == .success else { return nil }
        return selectedText as? String
    }
}
