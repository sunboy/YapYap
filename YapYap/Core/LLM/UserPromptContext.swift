// UserPromptContext.swift
// YapYap — Dictionary and edit memory entries for LLM prompt injection
import Foundation

struct UserPromptContext {
    let dictionaryEntries: [(spoken: String, corrected: String)]
    let editMemoryEntries: [(before: String, after: String)]

    /// Format dictionary entries for injection into the LLM user prompt.
    /// Small models get compact format, medium/large get detailed format.
    func dictionaryBlock(modelSize: LLMModelSize) -> String {
        guard !dictionaryEntries.isEmpty else { return "" }

        let limit = modelSize == .small ? 15 : 30
        let entries = Array(dictionaryEntries.prefix(limit))

        switch modelSize {
        case .small:
            let pairs = entries.map { "\($0.spoken) → \($0.corrected)" }
            return "WORDS: \(pairs.joined(separator: ", "))"
        case .medium, .large:
            let lines = entries.map { "\($0.spoken) → \($0.corrected)" }
            return "DICTIONARY (use these exact spellings):\n\(lines.joined(separator: "\n"))"
        }
    }

    /// Format edit memory entries for injection into the LLM user prompt.
    /// Returns empty for now — Phase 2 feature.
    func editMemoryBlock(modelSize: LLMModelSize) -> String {
        guard !editMemoryEntries.isEmpty else { return "" }

        let limit = modelSize == .small ? 10 : 20
        let entries = Array(editMemoryEntries.prefix(limit))

        switch modelSize {
        case .small:
            let pairs = entries.map { "\($0.before) → \($0.after)" }
            return "STYLE: \(pairs.joined(separator: ", "))"
        case .medium, .large:
            let lines = entries.map { "\"\($0.before)\" → \"\($0.after)\"" }
            return "STYLE RULES (this is how the user writes — apply these):\n\(lines.joined(separator: "\n"))"
        }
    }
}
