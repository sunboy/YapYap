// CommandMode.swift
// YapYap — Voice-powered text editing (Command Mode)
import Foundation

struct CommandMode {

    static let commandPrefixes = [
        // Edit mode triggers
        "make this", "turn this into", "turn into", "rewrite this", "rewrite",
        "shorten this", "shorten", "summarize this", "summarize",
        "expand this", "expand", "make it", "format this as", "format as",
        "translate this to", "translate to", "fix the grammar", "fix grammar",
        "add bullet points", "make more professional", "make more casual",
        "make this more", "make it more", "simplify this", "simplify",
        "add emojis", "remove emojis",
        "make shorter", "make longer",
        "fix spelling", "fix punctuation",
        "convert to bullet points", "convert to list",
        // Write mode triggers
        "write", "draft", "compose", "create",
    ]

    static func isCommand(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return commandPrefixes.contains(where: { lower.hasPrefix($0) })
    }

    /// Returns true if the command is a write-mode trigger (generates new content)
    static func isWriteCommand(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let writePrefixes = ["write", "draft", "compose", "create"]
        return writePrefixes.contains(where: { lower.hasPrefix($0) })
    }

    static func buildPrompt(command: String, selectedText: String) -> String {
        """
        You are a text editing assistant. Apply the user's instruction to transform the given text.

        RULES:
        - Apply ONLY the requested transformation
        - Preserve the original meaning, tone, and intent
        - Output ONLY the transformed text — no explanations, no preamble, no quotes
        - If the instruction is ambiguous, prefer the most natural interpretation
        - Preserve formatting (bullet points, line breaks) unless the instruction changes it

        INSTRUCTION: \(command)

        TEXT TO EDIT:
        \(selectedText)
        """
    }

    static func buildWritePrompt(instruction: String) -> String {
        """
        You are a writing assistant. Generate text based on the user's instruction.

        RULES:
        - Write ONLY what was requested — no explanations, no preamble
        - Match the implied tone and formality
        - Be concise unless the user asks for detail

        INSTRUCTION: \(instruction)
        """
    }
}
