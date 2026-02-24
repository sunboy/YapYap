// OutputFormatter.swift
// YapYap — Deterministic post-processing after LLM cleanup
import Foundation

struct OutputFormatter {

    // MARK: - Pre-compiled Regex Patterns

    private static let codeFileExtensions = [
        "swift", "py", "ts", "tsx", "js", "jsx", "rs", "go", "rb",
        "java", "kt", "cpp", "c", "h", "css", "html", "json",
        "yaml", "yml", "toml", "md", "sql", "sh", "vue", "svelte"
    ]

    /// Matches "at filename.ext" — handles STT transcription of "@filename.ext"
    private static let fileTaggingRegex: NSRegularExpression = {
        let extPattern = codeFileExtensions.joined(separator: "|")
        return try! NSRegularExpression(
            pattern: "\\bat\\s+(\\w+\\.(?:\(extPattern)))\\b",
            options: [.caseInsensitive]
        )
    }()

    /// Matches bare filenames like "notes.ts" that aren't already @-prefixed.
    /// Negative lookbehind prevents double-tagging (@file.ext) and dotted paths (com.apple.Mail).
    private static let bareFileTaggingRegex: NSRegularExpression = {
        let extPattern = codeFileExtensions.joined(separator: "|")
        return try! NSRegularExpression(
            pattern: "(?<![@`\\w\\.])(\\w+\\.(?:\(extPattern)))\\b",
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

    // MARK: - Work Messaging Patterns

    /// Common English words that follow "at" but are NOT usernames.
    private static let mentionStopwords: Set<String> = [
        "the", "a", "an", "this", "that", "my", "our", "your", "his", "her", "its", "their",
        "it", "home", "work", "noon", "night", "least", "most", "once", "first", "last",
        "all", "any", "some", "no", "one", "two", "three", "four", "five",
        "am", "pm", "me", "us", "them", "him", "best", "worst"
    ]

    /// Matches "at <username>" where username is lowercase alphanumeric (not a stopword, not a filename).
    private static let mentionRegex = try! NSRegularExpression(
        pattern: "\\bat\\s+([a-z][a-z0-9._-]{1,30})(?=\\s|$|[,.])",
        options: [.caseInsensitive]
    )

    /// Matches "hashtag general" / "hash tag general" / "hash general" → "#general"
    private static let channelRegex = try! NSRegularExpression(
        pattern: "\\b(?:hashtag|hash tag|hash)\\s+([a-z][a-z0-9-]{0,30})\\b",
        options: [.caseInsensitive]
    )

    // MARK: - Email Patterns

    /// Insert paragraph break before transition words that start a new topic.
    private static let emailParagraphRegex = try! NSRegularExpression(
        pattern: "([.!?])\\s+((?:However|Additionally|Also|Furthermore|In addition|Meanwhile|On the other hand|That said|Regarding|As for|Moving on|Finally|Lastly)\\s)",
        options: []
    )

    // MARK: - List Detection Patterns (Ordinal Safety Net)

    /// Matches ordinal markers: "First,", "Second,", "Third,", etc.
    private static let ordinalRegex = try! NSRegularExpression(
        pattern: "(?:^|[.!?]\\s+)(First|Second|Third|Fourth|Fifth|1st|2nd|3rd|4th|5th),?\\s+",
        options: [.caseInsensitive]
    )

    /// Matches "Number one,", "Number two,", etc.
    private static let numberWordRegex = try! NSRegularExpression(
        pattern: "(?:^|[.!?]\\s+)(?:Number\\s+)(one|two|three|four|five),?\\s+",
        options: [.caseInsensitive]
    )

    private static let numberWordMap: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
        "1st": 1, "2nd": 2, "3rd": 3, "4th": 4, "5th": 5
    ]


    // MARK: - Colon-List Detection Patterns

    /// Matches a colon that introduces a list (not time like 3:00, not URL like https:)
    /// Requires: space after colon, NOT preceded by digits (time) or http/https (URL)
    private static let colonListRegex = try! NSRegularExpression(
        pattern: "(?<!\\d)(?<!https?):\\s+",
        options: []
    )

    // MARK: - Terminal Detection

    private static let terminalBundleIds: Set<String> = [
        "com.googlecode.iterm2", "com.apple.Terminal",
        "net.kovidgoyal.kitty", "com.github.wez.wezterm",
        "dev.warp.Warp-Stable", "co.zeit.hyper"
    ]

    // MARK: - Public API

    static func format(_ text: String, for context: AppContext, styleSettings: StyleSettings = StyleSettings()) -> String {
        var result = text

        // Global: detect ordinal list patterns the LLM missed
        result = applyListFormatting(result)

        // Very casual: strip trailing periods, lowercase
        if context.style == .veryCasual {
            result = applyVeryCasual(result)
        }

        // File tagging for IDE chat panels and AI chat apps (respects user toggle)
        if (context.isIDEChatPanel || context.category == .aiChat) && styleSettings.ideFileTagging {
            result = applyFileTagging(result)
        }

        // IDE variable backtick wrapping (respects user toggle)
        if context.category == .codeEditor && styleSettings.ideVariableRecognition {
            result = wrapCodeTokens(result)
        }

        // Work messaging: @mentions and #channels
        if context.category == .workMessaging {
            result = applySlackFormatting(result)
        }

        // Email: paragraph breaks at transition words
        if context.category == .email {
            result = applyEmailFormatting(result)
        }

        // Terminal: strip trailing periods on commands
        if context.category == .terminal {
            result = applyTerminalFormatting(result)
        }

        // Social media: hashtag/mention conversion
        if context.category == .social {
            result = applySocialFormatting(result)
        }

        // Notes: minimal post-processing (markdown handled by LLM via AppRules)

        return result
    }

    // MARK: - File Tagging

    /// Convert filenames to @filename.ext for IDE chat panels.
    /// Handles both "at filename.ext" (STT transcription) and bare "filename.ext" patterns.
    static func applyFileTagging(_ text: String) -> String {
        var result = text

        // First: convert "at filename.ext" → "@filename.ext"
        var range = NSRange(result.startIndex..<result.endIndex, in: result)
        result = fileTaggingRegex.stringByReplacingMatches(in: result, range: range, withTemplate: "@$1")

        // Second: convert bare "filename.ext" → "@filename.ext"
        range = NSRange(result.startIndex..<result.endIndex, in: result)
        result = bareFileTaggingRegex.stringByReplacingMatches(in: result, range: range, withTemplate: "@$1")

        return result
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

    // MARK: - Work Messaging Formatting

    /// Convert "at username" → "@username" and "hashtag channel" → "#channel" for Slack/Teams/Discord.
    static func applySlackFormatting(_ text: String) -> String {
        var result = text

        // Convert "hashtag/hash channel" → "#channel" (do this first, less ambiguous)
        var range = NSRange(result.startIndex..<result.endIndex, in: result)
        result = channelRegex.stringByReplacingMatches(in: result, range: range, withTemplate: "#$1")

        // Convert "at username" → "@username" (skip stopwords and filenames)
        range = NSRange(result.startIndex..<result.endIndex, in: result)
        let matches = mentionRegex.matches(in: result, range: range)

        // Process matches in reverse to preserve indices
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let wordRange = Range(match.range(at: 1), in: result) else { continue }
            let word = String(result[wordRange]).lowercased()

            // Skip common English words
            if mentionStopwords.contains(word) { continue }
            // Skip filenames (has a code extension)
            if word.contains(".") && codeFileExtensions.contains(where: { word.hasSuffix(".\($0)") }) { continue }

            if let fullRange = Range(match.range, in: result) {
                result.replaceSubrange(fullRange, with: "@\(word)")
            }
        }

        return result
    }

    // MARK: - Email Formatting

    /// Matches greeting patterns at the start of text
    private static let greetingRegex = try! NSRegularExpression(
        pattern: "^((?:Hi|Hello|Hey|Dear|Good morning|Good afternoon|Good evening)\\s+[A-Z][a-z]+(?:\\s+[A-Z][a-z]+)?,?)\\s+",
        options: []
    )

    /// Matches sign-off patterns near the end of text
    private static let signOffRegex = try! NSRegularExpression(
        pattern: "\\s+((?:Thanks|Thank you|Best|Best regards|Regards|Cheers|Sincerely|Warm regards|Kind regards|All the best),?\\s+[A-Z][a-z]+\\.?)$",
        options: []
    )

    /// Format email text with greeting/body/sign-off structure and transition paragraph breaks.
    static func applyEmailFormatting(_ text: String) -> String {
        guard !text.contains("\n\n") else { return text }

        var result = text

        // Extract greeting (e.g., "Hi Robert," or "Hello Sarah,")
        let fullRange = NSRange(result.startIndex..<result.endIndex, in: result)
        if let greetingMatch = greetingRegex.firstMatch(in: result, range: fullRange),
           let greetingRange = Range(greetingMatch.range(at: 1), in: result) {
            let greeting = String(result[greetingRange])
            let rest = String(result[greetingRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            result = greeting + "\n\n" + rest
        }

        // Extract sign-off (e.g., "Thanks, Sandeep" or "Best regards, John")
        let currentRange = NSRange(result.startIndex..<result.endIndex, in: result)
        if let signOffMatch = signOffRegex.firstMatch(in: result, range: currentRange),
           let signOffRange = Range(signOffMatch.range(at: 1), in: result) {
            let signOff = String(result[signOffRange])
            let body = String(result[result.startIndex..<signOffRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            // Split sign-off name onto its own line (e.g., "Thanks,\nSandeep")
            let signOffFormatted = signOff.replacingOccurrences(of: ", ", with: ",\n")
            result = body + "\n\n" + signOffFormatted
        }

        // Insert paragraph breaks before transition words in the body
        let sentenceCount = result.components(separatedBy: CharacterSet(charactersIn: ".!?")).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        if sentenceCount >= 3 {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = emailParagraphRegex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1\n\n$2")
        }

        return result
    }

    // MARK: - List Formatting (Ordinal Safety Net + Colon-List Detection)

    /// Detect list patterns and convert to numbered lists.
    /// Layer 1: Ordinal patterns ("First, ... Second, ... Third, ...")
    /// Layer 2: Colon-introduced comma-separated lists ("Things to do: X, Y, and Z")
    static func applyListFormatting(_ text: String) -> String {
        // Try ordinal detection first
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let ordinalMatches = ordinalRegex.numberOfMatches(in: text, range: range)
        let numberWordRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let numberWordMatches = numberWordRegex.numberOfMatches(in: text, range: numberWordRange)
        let totalMarkers = ordinalMatches + numberWordMatches

        if totalMarkers >= 2 {
            return applyOrdinalListFormatting(text)
        }

        // Try colon-list detection
        let colonResult = applyColonListFormatting(text)
        if colonResult != text {
            return colonResult
        }

        return text
    }

    /// Detect ordinal patterns ("First, ... Second, ...") and convert to numbered lists.
    private static func applyOrdinalListFormatting(_ text: String) -> String {
        var result = text

        // Handle "Number one/two/three" patterns first
        let nwRange = NSRange(result.startIndex..<result.endIndex, in: result)
        let nwMatches = numberWordRegex.matches(in: result, range: nwRange)
        for match in nwMatches.reversed() {
            guard match.numberOfRanges >= 2,
                  let wordRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }
            let word = String(result[wordRange]).lowercased()
            if let num = numberWordMap[word] {
                let prefix = result[fullRange].hasPrefix(".") || result[fullRange].hasPrefix("!") || result[fullRange].hasPrefix("?") ? "\n" : ""
                result.replaceSubrange(fullRange, with: "\(prefix)\(num). ")
            }
        }

        // Handle "First/Second/Third" ordinal patterns
        let ordRange = NSRange(result.startIndex..<result.endIndex, in: result)
        let ordMatches = ordinalRegex.matches(in: result, range: ordRange)
        for match in ordMatches.reversed() {
            guard match.numberOfRanges >= 2,
                  let wordRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }
            let word = String(result[wordRange]).lowercased()
            if let num = numberWordMap[word] {
                let prefix = result[fullRange].hasPrefix(".") || result[fullRange].hasPrefix("!") || result[fullRange].hasPrefix("?") ? "\n" : ""
                result.replaceSubrange(fullRange, with: "\(prefix)\(num). ")
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Colon-List Detection

    /// Detect "intro: item1, item2, and item3" and format as numbered list.
    /// Only triggers when there's a colon followed by 2+ comma-separated items.
    static func applyColonListFormatting(_ text: String) -> String {
        // Find a qualifying colon (not time, not URL)
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let colonMatches = colonListRegex.matches(in: text, range: fullRange)
        guard !colonMatches.isEmpty else { return text }

        // Use the last qualifying colon (handles "Note: items: milk, eggs")
        guard let lastColonMatch = colonMatches.last,
              let colonSwiftRange = Range(lastColonMatch.range, in: text) else { return text }

        let intro = String(text[text.startIndex..<colonSwiftRange.lowerBound]) + ":"
        var itemsPart = String(text[colonSwiftRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        // Remove trailing period
        if itemsPart.hasSuffix(".") { itemsPart = String(itemsPart.dropLast()).trimmingCharacters(in: .whitespaces) }

        // Split into list items
        let items = splitListItems(itemsPart)
        guard items.count >= 2 else { return text }

        // Capitalize first letter of each item
        let numbered = items.enumerated().map { index, item in
            let trimmed = item.trimmingCharacters(in: .whitespaces)
            guard let first = trimmed.first else { return "\(index + 1). \(trimmed)" }
            let capitalized = first.uppercased() + trimmed.dropFirst()
            return "\(index + 1). \(capitalized)"
        }

        return intro + "\n" + numbered.joined(separator: "\n")
    }

    /// Split comma-separated items, handling "and"/"or" conjunctions before the last item.
    /// "check Reddit, GitHub Actions job run status, and finish working on the voice app"
    /// → ["check Reddit", "GitHub Actions job run status", "finish working on the voice app"]
    static func splitListItems(_ text: String) -> [String] {
        // Split on ", and ", ", or " first (Oxford comma with conjunction)
        // Then split remaining segments on ", "
        var items: [String] = []
        var remaining = text

        // Handle ", and " / ", or " as a separator (including before the last item)
        // Also handle " and " / " or " without preceding comma for 2-item lists
        // Pattern: split on ", " then check if last segment starts with "and "/"or "
        let segments = remaining.components(separatedBy: ", ")

        for (index, segment) in segments.enumerated() {
            let trimmed = segment.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Check if segment starts with "and " or "or " (conjunction before last item)
            if index > 0 {
                let lower = trimmed.lowercased()
                if lower.hasPrefix("and ") {
                    items.append(String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces))
                    continue
                }
                if lower.hasPrefix("or ") {
                    items.append(String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces))
                    continue
                }
            }

            // Check for " and " / " or " within the segment (2-item list without commas)
            // Only do this if we have no comma-separated items yet (avoids splitting "GitHub Actions and stuff")
            if index == 0 && segments.count == 1 {
                // Try splitting on " and " for 2-item lists like "eat lunch and take a walk"
                if let andRange = remaining.range(of: " and ", options: .caseInsensitive) {
                    let before = String(remaining[remaining.startIndex..<andRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let after = String(remaining[andRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !before.isEmpty && !after.isEmpty {
                        return [before, after]
                    }
                }
                // Try " or "
                if let orRange = remaining.range(of: " or ", options: .caseInsensitive) {
                    let before = String(remaining[remaining.startIndex..<orRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let after = String(remaining[orRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !before.isEmpty && !after.isEmpty {
                        return [before, after]
                    }
                }
                // Single segment with no conjunction — not a list
                return [trimmed]
            }

            items.append(trimmed)
        }

        return items
    }

    // MARK: - Terminal Formatting

    /// Strip trailing periods on commands — terminals don't use sentence punctuation.
    static func applyTerminalFormatting(_ text: String) -> String {
        var result = text
        // Remove trailing period (commands don't end with periods)
        if result.hasSuffix(".") {
            result = String(result.dropLast())
        }
        return result
    }

    // MARK: - Social Media Formatting

    /// Convert "hashtag X" → #X and "at X" / "mention X" → @X for social media.
    static func applySocialFormatting(_ text: String) -> String {
        var result = text

        // Convert "hashtag/hash X" → "#X"
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        result = channelRegex.stringByReplacingMatches(in: result, range: range, withTemplate: "#$1")

        // Convert "at username" → "@username" (reuse mention logic, skip stopwords)
        let mentionRange = NSRange(result.startIndex..<result.endIndex, in: result)
        let matches = mentionRegex.matches(in: result, range: mentionRange)
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let wordRange = Range(match.range(at: 1), in: result) else { continue }
            let word = String(result[wordRange]).lowercased()
            if mentionStopwords.contains(word) { continue }
            if word.contains(".") && codeFileExtensions.contains(where: { word.hasSuffix(".\($0)") }) { continue }
            if let fullRange = Range(match.range, in: result) {
                result.replaceSubrange(fullRange, with: "@\(word)")
            }
        }

        return result
    }
}
