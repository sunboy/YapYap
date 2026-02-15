// OutputFormatter.swift
// YapYap — Deterministic post-processing after LLM cleanup
import Foundation

struct OutputFormatter {

    // MARK: - Pre-compiled Regex Patterns

    private static let fileTaggingRegex: NSRegularExpression = {
        let extensions = [
            "swift", "py", "ts", "tsx", "js", "jsx", "rs", "go", "rb",
            "java", "kt", "cpp", "c", "h", "css", "html", "json",
            "yaml", "yml", "toml", "md", "sql", "sh", "vue", "svelte"
        ]
        let extPattern = extensions.joined(separator: "|")
        return try! NSRegularExpression(
            pattern: "\\bat\\s+(\\w+\\.(?:\(extPattern)))\\b",
            options: [.caseInsensitive]
        )
    }()

    private static let codeTokenRegex = try! NSRegularExpression(
        pattern: "(?<!`)\\b([a-z]+[A-Z][a-zA-Z]*|[a-z]+_[a-z_]+)\\b(?!`)",
        options: []
    )

    private static let trailingPeriodRegex = try! NSRegularExpression(pattern: "\\.$")
    private static let periodNewlineRegex = try! NSRegularExpression(pattern: "\\.\\n")
    private static let periodSpaceRegex = try! NSRegularExpression(pattern: "\\. ")

    // MARK: - Public API

    static func format(_ text: String, for context: AppContext, styleSettings: StyleSettings = StyleSettings()) -> String {
        var result = text

        // Very casual: strip trailing periods, lowercase
        if context.style == .veryCasual {
            result = applyVeryCasual(result)
        }

        // IDE file tagging (respects user toggle)
        if context.isIDEChatPanel && styleSettings.ideFileTagging {
            result = applyFileTagging(result)
        }

        // IDE variable backtick wrapping (respects user toggle)
        if context.category == .codeEditor && styleSettings.ideVariableRecognition {
            result = wrapCodeTokens(result)
        }

        return result
    }

    // MARK: - File Tagging

    /// Convert "at filename.ext" to "@filename.ext" for IDE chat panels
    static func applyFileTagging(_ text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return fileTaggingRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "@$1")
    }

    // MARK: - Code Token Wrapping

    /// Wrap camelCase and snake_case identifiers in backticks
    static func wrapCodeTokens(_ text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return codeTokenRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "`$0`")
    }

    // MARK: - Very Casual Formatting

    /// Strip trailing periods, lowercase sentence starts
    static func applyVeryCasual(_ text: String) -> String {
        var result = text

        // Remove trailing periods (keep ! and ?)
        var range = NSRange(result.startIndex..<result.endIndex, in: result)
        result = trailingPeriodRegex.stringByReplacingMatches(in: result, range: range, withTemplate: "")

        range = NSRange(result.startIndex..<result.endIndex, in: result)
        result = periodNewlineRegex.stringByReplacingMatches(in: result, range: range, withTemplate: "\n")

        range = NSRange(result.startIndex..<result.endIndex, in: result)
        result = periodSpaceRegex.stringByReplacingMatches(in: result, range: range, withTemplate: " ")

        // Lowercase first character of each line
        let lines = result.components(separatedBy: "\n")
        result = lines.map { line in
            guard let first = line.first, first.isUppercase else { return line }
            return first.lowercased() + line.dropFirst()
        }.joined(separator: "\n")

        return result
    }
}
