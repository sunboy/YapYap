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
    /// Relies on the category already computed by AppContextDetector, with
    /// browser/social refinement via window title for sub-category keywords.
    static func keyword(from context: AppContext?) -> String {
        guard let ctx = context else { return "General" }

        // IDE (highest priority — includes IDE chat panels)
        if ctx.isIDEChatPanel || ctx.category == .codeEditor {
            return "IDE"
        }

        switch ctx.category {
        case .terminal:          return "Terminal"
        case .email:             return "Email"
        case .workMessaging:     return "Slack"
        case .browser:           return browserKeyword(from: ctx.windowTitle)
        case .social:            return socialKeyword(from: ctx.windowTitle, appName: ctx.appName)
        case .notes:             return "Notes"
        case .personalMessaging: return "Slack"
        case .aiChat:            return "IDE"
        case .documents:         return "Email"
        case .codeEditor:        return "IDE"  // already handled above, but exhaustive
        case .other:             return appNameFallback(ctx.appName)
        }
    }

    /// Last-resort fallback: infer keyword from app name when category is .other.
    private static func appNameFallback(_ name: String) -> String {
        let terminals = ["iTerm", "Terminal", "Hyper", "Warp", "Alacritty", "kitty"]
        if terminals.contains(where: { name.localizedCaseInsensitiveContains($0) }) { return "Terminal" }

        let emailApps = ["Outlook", "Spark", "Superhuman", "Airmail"]
        if emailApps.contains(where: { name.localizedCaseInsensitiveContains($0) }) { return "Email" }

        let chatApps = ["Discord", "Teams"]
        if chatApps.contains(where: { name.localizedCaseInsensitiveContains($0) }) { return "Slack" }

        return "General"
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
        if title.contains("twitter") || name.contains("twitter") || name == "x" { return "Twitter" }

        // Default social → General (no special formatting needed)
        return "General"
    }
}
