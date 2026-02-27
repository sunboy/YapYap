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

        // Terminal
        "com.googlecode.iterm2": .terminal,
        "com.apple.Terminal": .terminal,
        "dev.warp.Warp-Stable": .terminal,
        "net.kovidgoyal.kitty": .terminal,
        "com.github.wez.wezterm": .terminal,

        // Notes
        "com.apple.Notes": .notes,
        "md.obsidian": .notes,

        // Documents
        "com.apple.iWork.Pages": .documents,
        "notion.id": .documents,

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

        // Fetch AX data once — used for classification AND AppContext construction
        let windowTitle = getWindowTitle(pid: pid)
        let focusedText = getFocusedFieldText()

        var category: AppCategory
        var fromHardcodedMap = false

        if let override = settings.appCategoryOverrides[bundleId] {
            category = override
        } else if browserBundleIds.contains(bundleId) {
            // Browser tab classification must run BEFORE bundleMap fallback
            // so Gmail/Outlook/Slack in Chrome get the correct category
            category = classifyBrowserTab(windowTitle: windowTitle)
        } else if let mapped = bundleMap[bundleId] {
            category = mapped
            fromHardcodedMap = true
        } else {
            // Layered auto-classification for unknown apps
            category = categoryFromLSApplicationCategoryType(frontApp.bundleURL)
                ?? categoryFromHeuristics(bundleId: bundleId, appName: appName)
                ?? categoryFromWindowTitle(windowTitle, focusedText: focusedText)
                ?? .other
        }

        // Record seen apps for overrides UI (skip known apps and user overrides)
        if !fromHardcodedMap, settings.appCategoryOverrides[bundleId] == nil, !bundleId.isEmpty {
            recordSeenApp(bundleId: bundleId, appName: appName, category: category)
        }

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

    /// Pre-built browser URL patterns for tab classification (allocated once)
    private static let browserTabPatterns: [(String, AppCategory)] = [
        ("gmail", .email), ("outlook.live", .email), ("mail.google", .email),
        ("proton", .email), ("yahoo.com/mail", .email),
        ("slack.com", .workMessaging), ("teams.microsoft", .workMessaging),
        ("discord.com", .workMessaging), ("linear.app", .workMessaging),
        ("jira", .workMessaging),
        ("chatgpt", .aiChat), ("claude.ai", .aiChat), ("perplexity", .aiChat),
        ("docs.google", .documents), ("notion.so", .documents),
        ("confluence", .documents),
        ("github.com", .codeEditor), ("gitlab.com", .codeEditor),
        ("stackoverflow", .codeEditor),
        ("reddit.com", .social), ("twitter.com", .social), ("x.com", .social),
        ("mastodon", .social),
    ]

    private static func classifyBrowserTab(windowTitle: String?) -> AppCategory {
        guard let title = windowTitle?.lowercased() else { return .browser }

        for (pattern, category) in browserTabPatterns {
            if title.contains(pattern) { return category }
        }
        return .browser
    }

    // MARK: - Auto-Classification Layers

    /// Layer 1: Apple LSApplicationCategoryType from app's Info.plist
    static func categoryFromLSApplicationCategoryType(_ bundleURL: URL?) -> AppCategory? {
        guard let url = bundleURL,
              let bundle = Bundle(url: url),
              let ls = bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        else { return nil }

        switch ls {
        case "public.app-category.social-networking":          return .social
        case "public.app-category.productivity":               return .documents
        case "public.app-category.developer-tools":            return .codeEditor
        case "public.app-category.business":                   return .workMessaging
        case "public.app-category.news", "public.app-category.reference": return .browser
        case "public.app-category.education",
             "public.app-category.finance":                    return .documents
        case _ where ls.hasPrefix("public.app-category.game"),
             "public.app-category.utilities":                  return nil  // too broad
        default:                                               return nil
        }
    }

    /// Layer 2: Bundle ID and app name pattern matching
    static func categoryFromHeuristics(bundleId: String, appName: String) -> AppCategory? {
        let bid  = bundleId.lowercased()
        let name = appName.lowercased()

        if bid.contains("mail") || bid.contains(".email") || name == "mail" { return .email }
        if bid.contains("terminal") || bid.contains("console") || bid.contains(".shell")
            || name.contains("terminal")                                     { return .terminal }
        if (bid.contains("editor") || bid.contains(".code.") || bid.contains("studio")
            || name.contains("studio") || name.contains("editor"))
            && !bid.hasPrefix("com.apple.systempreferences")                 { return .codeEditor }
        if bid.contains("slack") || bid.contains("teams")                    { return .workMessaging }
        if bid.contains("chat") || bid.contains("message") || bid.contains("messenger")
            || name.contains("messenger")                                    { return .personalMessaging }
        if bid.contains("note") || bid.contains("bear") || bid.contains("craft")
            || name.contains("journal")                                      { return .notes }
        return nil
    }

    /// Layer 3: Window title and focused text high-confidence signals
    static func categoryFromWindowTitle(_ title: String?, focusedText: String?) -> AppCategory? {
        if let t = title?.lowercased() {
            if t.contains("inbox") || t.contains("new message")
               || t.contains("compose") || t.contains("reply")      { return .email }
            if t.contains("new note") || t.contains("untitled note"){ return .notes }
            if t.hasSuffix("— slack") || t.hasSuffix("– slack")
               || t.hasSuffix("— teams") || t.hasSuffix("– teams")  { return .workMessaging }
        }
        if let text = focusedText {
            let lastLine = text.components(separatedBy: .newlines).last ?? ""
            let trimmed  = lastLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("$") || trimmed.hasPrefix("%")
               || trimmed.hasPrefix(">>>") || trimmed.hasPrefix(">") { return .terminal }
        }
        return nil
    }

    // MARK: - Seen Apps Recording

    private static let seenAppsQueue = DispatchQueue(label: "dev.yapyap.seenApps", qos: .utility)

    private static func recordSeenApp(bundleId: String, appName: String, category: AppCategory) {
        seenAppsQueue.async {
            var settings = StyleSettings.loadFromUserDefaults()
            // Throttle: skip if seen within last 60s with same category
            if let existing = settings.seenApps[bundleId],
               existing.autoDetectedCategory == category,
               Date().timeIntervalSince(existing.lastSeen) < 60 { return }

            settings.seenApps[bundleId] = SeenAppInfo(
                appName: appName, autoDetectedCategory: category, lastSeen: Date()
            )
            // Cap at 50 most-recently-seen entries
            if settings.seenApps.count > 50 {
                let trimmed = settings.seenApps
                    .sorted { $0.value.lastSeen > $1.value.lastSeen }
                    .prefix(50)
                    .map { ($0.key, $0.value) }
                settings.seenApps = Dictionary(uniqueKeysWithValues: trimmed)
            }
            settings.saveToUserDefaults()
        }
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
