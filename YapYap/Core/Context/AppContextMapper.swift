// AppContextMapper.swift
// YapYap — Maps AppContext to a keyword string for V2 prompt injection
import Foundation

/// Maps the full AppContext struct to a single keyword string for prompt injection.
///
/// V2 keywords (8): IDE, Slack, Email, LinkedIn, Twitter, Terminal, Notes, General
/// V3 keywords (18): adds Notion, Obsidian, Jira, GitHub, AI Prompt, Claude Code,
///                    Cursor, AI Chat, SSH, Python — derived from DSPy optimization
///                    across 282 test cases showing context-specific formatting improves quality.
///
/// Keywords are prompt triggers:
/// - "Slack" → professional-but-casual tone, short paragraphs
/// - "IDE" → backtick code formatting, @ file prefixes
/// - "Claude Code" → AI tool prompt formatting with lists and structure
/// - "Terminal" → preserve shell commands literally
/// - "SSH" → remote shell session, preserve commands
/// - "Python" → Python REPL/Jupyter, preserve expressions
/// - "Notion" → structured notes with bullets
/// - "Obsidian" → vault/journal formatting
/// - "GitHub" → PR/issue comment formatting
/// - "Jira" → ticket/comment formatting
/// - "AI Prompt" → prompt engineering for ChatGPT/Gemini
/// - "AI Chat" → generic AI assistant interface
/// - "Cursor" → AI chat or inline edit in Cursor IDE
enum AppContextMapper {

    /// Derives the prompt keyword from the app context.
    /// Relies on the category already computed by AppContextDetector, with
    /// browser/social refinement via window title for sub-category keywords.
    static func keyword(from context: AppContext?) -> String {
        guard let ctx = context else { return "Slack" }

        // IDE chat panels → specific AI context keywords
        if ctx.isIDEChatPanel {
            return ideChatKeyword(from: ctx)
        }

        // Code editors → IDE (or Cursor for Cursor app)
        if ctx.category == .codeEditor {
            return codeEditorKeyword(from: ctx)
        }

        switch ctx.category {
        case .terminal:          return terminalKeyword(from: ctx)
        case .email:             return "Email"
        case .workMessaging:     return "Slack"
        case .browser:           return browserKeyword(from: ctx.windowTitle)
        case .social:            return socialKeyword(from: ctx.windowTitle, appName: ctx.appName)
        case .notes:             return notesKeyword(from: ctx)
        case .personalMessaging: return "Slack"
        case .aiChat:            return aiChatKeyword(from: ctx)
        case .documents:         return documentsKeyword(from: ctx)
        case .codeEditor:        return "IDE"  // already handled above, but exhaustive
        case .other:             return appNameFallback(ctx.appName)
        }
    }

    // MARK: - Refined Sub-Keyword Derivation

    /// IDE chat panels → Claude Code, Cursor, or AI Chat
    private static func ideChatKeyword(from ctx: AppContext) -> String {
        let name = ctx.appName.lowercased()
        let title = ctx.windowTitle?.lowercased() ?? ""

        if name.contains("cursor") || title.contains("cursor") { return "Cursor" }
        if title.contains("claude") { return "Claude Code" }
        if title.contains("copilot") { return "AI Chat" }
        return "AI Chat"
    }

    /// Code editors → IDE or Cursor
    private static func codeEditorKeyword(from ctx: AppContext) -> String {
        let name = ctx.appName.lowercased()
        if name.contains("cursor") { return "Cursor" }
        return "IDE"
    }

    /// Terminal → Terminal, SSH, or Python
    private static func terminalKeyword(from ctx: AppContext) -> String {
        let title = ctx.windowTitle?.lowercased() ?? ""
        let focused = ctx.focusedFieldText?.lowercased() ?? ""

        // SSH detection: window title often shows "user@host" or "ssh"
        if title.contains("ssh") || title.contains("@") && title.contains(":") { return "SSH" }

        // Python REPL detection
        if title.contains("python") || title.contains("ipython") || title.contains("jupyter") { return "Python" }
        if focused.hasPrefix(">>>") || focused.hasPrefix("in [") { return "Python" }

        return "Terminal"
    }

    /// Notes → Notes, Obsidian, or Notion
    private static func notesKeyword(from ctx: AppContext) -> String {
        let name = ctx.appName.lowercased()
        let bundleId = ctx.bundleId.lowercased()

        if name.contains("obsidian") || bundleId.contains("obsidian") { return "Obsidian" }
        return "Notes"
    }

    /// Documents → Notion or Email (general document formatting)
    private static func documentsKeyword(from ctx: AppContext) -> String {
        let name = ctx.appName.lowercased()
        let bundleId = ctx.bundleId.lowercased()

        if name.contains("notion") || bundleId.contains("notion") { return "Notion" }
        return "Email"
    }

    /// AI chat apps → Claude Code, AI Prompt, or AI Chat
    private static func aiChatKeyword(from ctx: AppContext) -> String {
        let name = ctx.appName.lowercased()
        let title = ctx.windowTitle?.lowercased() ?? ""

        if name.contains("claude") || title.contains("claude") { return "Claude Code" }
        if name.contains("chatgpt") || title.contains("chatgpt") { return "AI Prompt" }
        if name.contains("gemini") || title.contains("gemini") { return "AI Prompt" }
        if name.contains("perplexity") || title.contains("perplexity") { return "AI Prompt" }
        return "AI Chat"
    }

    /// Last-resort fallback: infer keyword from app name when category is .other.
    private static func appNameFallback(_ name: String) -> String {
        let terminals = ["iTerm", "Terminal", "Hyper", "Warp", "Alacritty", "kitty"]
        if terminals.contains(where: { name.localizedCaseInsensitiveContains($0) }) { return "Terminal" }

        let emailApps = ["Outlook", "Spark", "Superhuman", "Airmail"]
        if emailApps.contains(where: { name.localizedCaseInsensitiveContains($0) }) { return "Email" }

        let chatApps = ["Discord", "Teams"]
        if chatApps.contains(where: { name.localizedCaseInsensitiveContains($0) }) { return "Slack" }

        return "Slack"
    }

    /// Derives keyword from browser window title.
    private static func browserKeyword(from windowTitle: String?) -> String {
        guard let title = windowTitle?.lowercased() else { return "Slack" }

        // AI tools in browser
        if title.contains("chatgpt") || title.contains("chat.openai") { return "AI Prompt" }
        if title.contains("claude.ai") { return "Claude Code" }
        if title.contains("gemini") { return "AI Prompt" }

        // Dev tools in browser
        if title.contains("github") || title.contains("gitlab") { return "GitHub" }
        if title.contains("jira") || title.contains("atlassian") { return "Jira" }

        // Social
        if title.contains("linkedin") { return "LinkedIn" }
        if title.contains("twitter") || title.contains("x.com") { return "Twitter" }

        // Productivity
        if title.contains("gmail") || title.contains("outlook") || title.contains("mail") { return "Email" }
        if title.contains("notion") { return "Notion" }
        if title.contains("obsidian") { return "Obsidian" }
        if title.contains("slack") || title.contains("discord") || title.contains("teams") { return "Slack" }

        return "Slack"
    }

    /// Derives keyword from social media context.
    private static func socialKeyword(from windowTitle: String?, appName: String) -> String {
        let title = windowTitle?.lowercased() ?? ""
        let name = appName.lowercased()

        if title.contains("linkedin") || name.contains("linkedin") { return "LinkedIn" }
        if title.contains("twitter") || name.contains("twitter") || name == "x" { return "Twitter" }

        // Default social → Slack (casual messaging formatting)
        return "Slack"
    }
}
