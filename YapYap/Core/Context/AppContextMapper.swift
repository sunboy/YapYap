// AppContextMapper.swift
// YapYap — Maps AppContext to a keyword string for V2 prompt injection
import Foundation

/// Maps the full AppContext struct to a single keyword string for injection
/// into the V2 system prompt's {app_context} placeholder.
///
/// The keywords ("IDE", "Slack", "Email", "LinkedIn", etc.) are specifically
/// trained prompt triggers:
/// - "Slack" → professional-but-casual tone, short paragraphs
/// - "IDE" → backtick code formatting, @ file prefixes
/// - "LinkedIn" → punchy short paragraphs (1-2 sentences)
/// - "Email" → greeting/body/sign-off paragraph structure
/// - "Terminal" → preserve shell commands literally
/// - "Notes" → markdown-style formatting
/// - "General" → default, no special formatting
enum AppContextMapper {

    /// Derives the prompt keyword from the app context.
    /// Priority order ensures the most specific match wins.
    static func keyword(from context: AppContext?) -> String {
        guard let ctx = context else { return "General" }

        // 1. IDE (highest priority)
        if ctx.isIDEChatPanel || ctx.category == .codeEditor {
            return "IDE"
        }

        // 2. Terminal
        if ctx.category == .terminal || isTerminalApp(ctx.appName) {
            return "Terminal"
        }

        // 3. Email
        if ctx.category == .email || isEmailApp(ctx.appName) {
            return "Email"
        }

        // 4. Work Messaging → "Slack" (triggers professional-casual tone)
        if ctx.category == .workMessaging || isWorkMessagingApp(ctx.appName) {
            return "Slack"
        }

        // 5. Browser / Social (dynamic — check window title)
        if ctx.category == .browser {
            return browserKeyword(from: ctx.windowTitle)
        }

        // 6. Social media
        if ctx.category == .social {
            return socialKeyword(from: ctx.windowTitle, appName: ctx.appName)
        }

        // 7. Notes
        if ctx.category == .notes || isNotesApp(ctx.appName) {
            return "Notes"
        }

        // 8. Personal messaging → "Slack" (close enough for tone)
        if ctx.category == .personalMessaging {
            return "Slack"
        }

        // 9. AI Chat
        if ctx.category == .aiChat {
            return "IDE"  // AI chat benefits from code formatting rules
        }

        // 10. Documents
        if ctx.category == .documents {
            return "Email"  // Documents use similar paragraph structure
        }

        // Default
        return "General"
    }

    // MARK: - Private Helpers

    private static func isTerminalApp(_ name: String) -> Bool {
        let terminals = ["iTerm2", "Terminal", "Hyper", "Warp", "Alacritty", "kitty"]
        return terminals.contains(where: { name.localizedCaseInsensitiveContains($0) })
    }

    private static func isEmailApp(_ name: String) -> Bool {
        let emailApps = ["Mail", "Outlook", "Spark", "Superhuman", "Airmail"]
        return emailApps.contains(where: { name.localizedCaseInsensitiveContains($0) })
    }

    private static func isWorkMessagingApp(_ name: String) -> Bool {
        let chatApps = ["Slack", "Teams", "Discord"]
        return chatApps.contains(where: { name.localizedCaseInsensitiveContains($0) })
    }

    private static func isNotesApp(_ name: String) -> Bool {
        let notesApps = ["Notion", "Obsidian", "Notes", "Bear", "Craft"]
        return notesApps.contains(where: { name.localizedCaseInsensitiveContains($0) })
    }

    /// Derives keyword from browser window title.
    private static func browserKeyword(from windowTitle: String?) -> String {
        guard let title = windowTitle?.lowercased() else { return "General" }

        if title.contains("linkedin") { return "LinkedIn" }
        if title.contains("twitter") || title.contains("x.com") { return "Twitter" }
        if title.contains("gmail") || title.contains("outlook") || title.contains("mail") { return "Email" }
        if title.contains("github") || title.contains("gitlab") { return "IDE" }
        if title.contains("slack") || title.contains("discord") || title.contains("teams") { return "Slack" }
        if title.contains("notion") || title.contains("obsidian") { return "Notes" }

        return "General"
    }

    /// Derives keyword from social media context.
    private static func socialKeyword(from windowTitle: String?, appName: String) -> String {
        let title = windowTitle?.lowercased() ?? ""
        let name = appName.lowercased()

        if title.contains("linkedin") || name.contains("linkedin") { return "LinkedIn" }
        if title.contains("twitter") || name.contains("twitter") || name.contains("x") { return "Twitter" }

        // Default social → General (no special formatting needed)
        return "General"
    }
}
