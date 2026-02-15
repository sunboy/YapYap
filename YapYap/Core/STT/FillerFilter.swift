// FillerFilter.swift
// YapYap — Post-LLM regex guard for remaining filler words
import Foundation

struct FillerFilter {
    /// Regex pattern for isolated hesitation sounds
    /// Only catches standalone fillers, NOT parts of words ("um" in "umbrella" is safe)
    private static let hesitationPattern = try! NSRegularExpression(
        pattern: "\\b(u[hm]+|a[hm]+|e[hr]+|hmm+)\\b[,.]?\\s?",
        options: [.caseInsensitive]
    )

    /// Pre-compiled double-space cleanup regex
    private static let doubleSpacePattern = try! NSRegularExpression(pattern: "  +")

    /// Extended fillers (used when aggressive mode is ON)
    static let extendedFillers = [
        "you know", "I mean", "sort of", "kind of",
        "basically", "literally", "actually", "right",
        "so yeah", "yeah so", "like I said"
    ]

    /// Pre-compiled regexes for extended fillers (compiled once, reused)
    private static let extendedFillerRegexes: [NSRegularExpression] = {
        extendedFillers.compactMap { filler in
            let escaped = NSRegularExpression.escapedPattern(for: filler)
            return try? NSRegularExpression(
                pattern: "\\b\(escaped)\\b[,.]?\\s?",
                options: [.caseInsensitive]
            )
        }
    }()

    static func removeFillers(from text: String, aggressive: Bool = false) -> String {
        var cleaned = text

        // Always remove hesitation sounds
        var range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
        cleaned = hesitationPattern.stringByReplacingMatches(
            in: cleaned, range: range, withTemplate: ""
        )

        if aggressive {
            for regex in extendedFillerRegexes {
                range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
            }
        }

        // Clean up double spaces and leading/trailing whitespace
        range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
        cleaned = doubleSpacePattern.stringByReplacingMatches(in: cleaned, range: range, withTemplate: " ")

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
