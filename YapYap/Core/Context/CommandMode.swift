// CommandMode.swift
// YapYap — Voice-powered text editing (Command Mode)
import Foundation

struct CommandMode {

    static let commandPrefixes = [
        "make this", "turn this into", "turn into", "rewrite this", "rewrite",
        "shorten this", "shorten", "summarize this", "summarize",
        "expand this", "expand", "make it", "format this as", "format as",
        "translate this to", "translate to", "fix the grammar", "fix grammar",
        "add bullet points", "make more professional", "make more casual",
        "make this more", "make it more", "simplify this", "simplify",
    ]

    static func isCommand(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return commandPrefixes.contains(where: { lower.hasPrefix($0) })
    }

    static func buildPrompt(command: String, selectedText: String) -> String {
        """
        You are a text editor assistant. Apply the user's command to transform the given text.

        RULES:
        - Apply ONLY the requested transformation
        - Preserve the original meaning and intent
        - Output ONLY the transformed text, nothing else
        - No explanations, no preamble

        USER COMMAND: \(command)

        ORIGINAL TEXT:
        \(selectedText)

        TRANSFORMED TEXT:
        """
    }
}
