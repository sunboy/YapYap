// OutputFormatter.swift
// YapYap — Deterministic post-processing after LLM cleanup
import Foundation

struct OutputFormatter {

    static func format(_ text: String, for context: AppContext) -> String {
        var result = text

        // Very casual: strip trailing periods, lowercase
        if context.style == .veryCasual {
            result = applyVeryCasual(result)
        }

        // IDE file tagging
        if context.isIDEChatPanel {
            result = applyFileTagging(result)
        }

        // IDE variable backtick wrapping
        if context.category == .codeEditor {
            result = wrapCodeTokens(result)
        }

        return result
    }

    // MARK: - File Tagging

    /// Convert "at filename.ext" to "@filename.ext" for IDE chat panels
    static func applyFileTagging(_ text: String) -> String {
        let extensions = [
            "swift", "py", "ts", "tsx", "js", "jsx", "rs", "go", "rb",
            "java", "kt", "cpp", "c", "h", "css", "html", "json",
            "yaml", "yml", "toml", "md", "sql", "sh", "vue", "svelte"
        ]
        let extPattern = extensions.joined(separator: "|")
        guard let regex = try? NSRegularExpression(
            pattern: "\\bat\\s+(\\w+\\.(?:\(extPattern)))\\b",
            options: [.caseInsensitive]
        ) else { return text }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "@$1")
    }

    // MARK: - Code Token Wrapping

    /// Wrap camelCase and snake_case identifiers in backticks
    static func wrapCodeTokens(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "(?<!`)\\b([a-z]+[A-Z][a-zA-Z]*|[a-z]+_[a-z_]+)\\b(?!`)",
            options: []
        ) else { return text }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "`$0`")
    }

    // MARK: - Very Casual Formatting

    /// Strip trailing periods, lowercase sentence starts
    static func applyVeryCasual(_ text: String) -> String {
        var result = text

        // Remove trailing periods (keep ! and ?)
        if let regex = try? NSRegularExpression(pattern: "\\.$") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        if let regex = try? NSRegularExpression(pattern: "\\.\\n") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "\n")
        }
        if let regex = try? NSRegularExpression(pattern: "\\. ") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: " ")
        }

        // Lowercase first character of each line
        let lines = result.components(separatedBy: "\n")
        result = lines.map { line in
            guard let first = line.first, first.isUppercase else { return line }
            return first.lowercased() + line.dropFirst()
        }.joined(separator: "\n")

        return result
    }
}
