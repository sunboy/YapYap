// LLMOutputSanitizer.swift
// YapYap — Shared output sanitization for all LLM engines
import Foundation

/// Strips LLM artifacts from cleanup output: special tokens, meta-commentary,
/// preamble labels, code fences, and wrapping quotes/backticks.
/// Used by MLXEngine, OllamaEngine, and BenchmarkLLMRunner.
enum LLMOutputSanitizer {

    // MARK: - Public API

    static func sanitize(_ text: String) -> String {
        var cleaned = text

        // Remove special tokens
        for token in regexes.specialTokens {
            cleaned = cleaned.replacingOccurrences(of: token, with: "")
        }

        // Remove common LLM preambles/labels
        for regex in regexes.preambleRegexes {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }

        // Remove trailing meta-commentary
        for regex in regexes.trailingRegexes {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }

        // Remove markdown code fences if the LLM wrapped its output
        if cleaned.contains("```") {
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        }

        // Remove leading code language identifiers
        if let regex = regexes.codeLanguageRegex {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }

        // Strip lines that are just code comments if output looks like generated code
        let lines = cleaned.components(separatedBy: "\n")
        let commentLines = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        if commentLines.count > lines.count / 2 && lines.count > 2 {
            // More than half the lines are comments — LLM generated code, not cleanup
            return ""
        }

        // Remove wrapping single backticks
        cleaned = cleaned.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if cleaned.hasPrefix("`") && cleaned.hasSuffix("`") && cleaned.count > 2 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }

        // Remove quotes if the LLM quoted the entire output
        cleaned = cleaned.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count > 2 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }

        // Collapse newlines into spaces, EXCEPT when the LLM produced an intentional
        // list (2+ lines starting with numbered/bulleted markers like "1.", "-", "*").
        let splitLines = cleaned.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let listLineCount = splitLines.filter { line in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            return listMarkerRegex.firstMatch(in: line, range: range) != nil
        }.count

        if listLineCount >= 2 {
            // Preserve newlines — this is an intentional list from the LLM
            cleaned = splitLines.joined(separator: "\n")
        } else {
            // Collapse newlines — prose that the LLM split unnecessarily
            cleaned = splitLines.joined(separator: " ")
        }

        return cleaned.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    // MARK: - Pre-compiled Regexes (compiled once at first access)

    private static let regexes = Regexes()

    /// Matches lines starting with list markers: "1. ", "2) ", "- ", "* ", "• "
    private static let listMarkerRegex = try! NSRegularExpression(pattern: "^(\\d+[.)]\\s|[-•*]\\s)")

    private struct Regexes {
        let specialTokens = [
            "<|endoftext|>", "<|im_end|>", "<|im_start|>",
            "<|eot_id|>", "<|end|>", "</s>", "<s>",
            "<|assistant|>", "<|user|>", "<|system|>",
            "</output>", "<output>", "<input>", "</input>"
        ]

        let preambleRegexes: [NSRegularExpression]
        let trailingRegexes: [NSRegularExpression]
        let codeLanguageRegex: NSRegularExpression?

        init() {
            let preamblePatterns = [
                "(?i)^\\s*(the\\s+)?cleaned\\s+(text|version)\\s*(is)?\\s*:?\\s*",
                "(?i)^\\s*here\\s+(is|are)\\s+(the\\s+)?.*?:\\s*",
                "(?i)^\\s*here'?s\\s+the\\s+.*?:\\s*",
                "(?i)^\\s*(cleaned|corrected|fixed)\\s+(text|version)\\s*:?\\s*",
                "(?i)^\\s*output\\s*:\\s*",
                "(?i)^\\s*result\\s*:\\s*",
                "(?i)^\\s*(I'?d\\s+love\\s+to|sure[,!.]?|of\\s+course[,!.]?|certainly[,!.]?|absolutely[,!.]?)\\s+.*?[:\\.!]\\s*",
                "(?i)^\\s*I'?m\\s+sorry.*$",
                "(?i)^\\s*I\\s+cannot\\s+.*$",
                "(?i)^\\s*I\\s+can'?t\\s+provide.*$",
                // Echo patterns: model emits few-shot example structure instead of cleaned text
                "(?i)^\\s*EXAMPLE\\s+\\d+\\s*:?\\s*",
                "(?i)^\\s*Input\\s*:\\s*",
                "(?i)^\\s*<example>\\s*",
                "(?i)^\\s*in\\s*:\\s*",
                "(?i)^\\s*out\\s*:\\s*",
            ]

            let trailingPatterns = [
                "(?i)\\s*no\\s+further\\s+(changes|edits|modifications)\\s+(are\\s+)?(required|needed|necessary).*$",
                "(?i)\\s*\\(no\\s+changes.*?\\)\\s*$",
                "(?i)\\s*I('ve|\\s+have)\\s+cleaned\\s+up.*$",
                "(?i)\\s*note:.*$",
            ]

            let codeLanguages = ["python", "swift", "javascript", "typescript", "bash", "shell", "ruby", "java", "go", "rust", "cpp", "c\\+\\+", "html", "css", "sql"]
            let langPattern = "(?i)^\\s*(" + codeLanguages.joined(separator: "|") + ")\\s*\\n"

            preambleRegexes = preamblePatterns.compactMap { try? NSRegularExpression(pattern: $0) }
            trailingRegexes = trailingPatterns.compactMap { try? NSRegularExpression(pattern: $0) }
            codeLanguageRegex = try? NSRegularExpression(pattern: langPattern)
        }
    }
}
