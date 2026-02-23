// ContextFactory.swift
// YapYapBench — CLI strings → AppContext / CleanupContext
import Foundation

struct ContextFactory {

    /// All recognized context names for the CLI.
    static let allContextNames: [String] = [
        "email", "slack", "work", "imessage", "messages",
        "code", "ide", "vscode", "chrome", "browser",
        "docs", "notion", "chatgpt", "claude", "other"
    ]

    /// Canonical context names (deduplicated aliases).
    static let canonicalNames: [String] = [
        "email", "slack", "imessage", "code", "browser", "docs", "chatgpt", "other"
    ]

    /// Parse a comma-separated context string, or "all" for all canonical contexts.
    static func parseContexts(_ input: String) -> [String] {
        if input.lowercased() == "all" {
            return canonicalNames
        }
        return input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    }

    /// Parse a comma-separated cleanup-levels string, or "all".
    static func parseCleanupLevels(_ input: String) -> [CleanupContext.CleanupLevel] {
        if input.lowercased() == "all" {
            return [.light, .medium, .heavy]
        }
        return input.split(separator: ",").compactMap { raw in
            CleanupContext.CleanupLevel(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased())
        }
    }

    /// Map a CLI context name to a simulated AppContext.
    static func makeAppContext(for name: String) -> AppContext {
        let lower = name.lowercased()
        switch lower {
        case "email":
            return AppContext(bundleId: "com.apple.mail", appName: "Mail",
                            category: .email, style: .formal,
                            windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        case "slack", "work":
            return AppContext(bundleId: "com.tinyspeck.slackmacgap", appName: "Slack",
                            category: .workMessaging, style: .casual,
                            windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        case "imessage", "messages":
            return AppContext(bundleId: "com.apple.MobileSMS", appName: "Messages",
                            category: .personalMessaging, style: .casual,
                            windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        case "code", "ide", "vscode":
            return AppContext(bundleId: "com.microsoft.VSCode", appName: "VS Code",
                            category: .codeEditor, style: .formal,
                            windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        case "chrome", "browser":
            return AppContext(bundleId: "com.apple.Safari", appName: "Safari",
                            category: .browser, style: .casual,
                            windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        case "docs", "notion":
            return AppContext(bundleId: "md.obsidian", appName: "Obsidian",
                            category: .documents, style: .formal,
                            windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        case "chatgpt", "claude":
            return AppContext(bundleId: "com.openai.chat", appName: "ChatGPT",
                            category: .aiChat, style: .casual,
                            windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        default:
            return AppContext(bundleId: "unknown", appName: "Unknown",
                            category: .other, style: .casual,
                            windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        }
    }

    /// Build a CleanupContext for benchmarking from CLI parameters.
    static func makeCleanupContext(
        appContext: AppContext,
        cleanupLevel: CleanupContext.CleanupLevel,
        experimentalPrompts: Bool
    ) -> CleanupContext {
        let formality: CleanupContext.Formality
        switch appContext.style {
        case .formal: formality = .formal
        case .veryCasual, .casual: formality = .casual
        case .excited: formality = .neutral
        }

        return CleanupContext(
            stylePrompt: "",
            formality: formality,
            language: "en",
            appContext: appContext,
            cleanupLevel: cleanupLevel,
            removeFillers: true,
            experimentalPrompts: experimentalPrompts
        )
    }
}
