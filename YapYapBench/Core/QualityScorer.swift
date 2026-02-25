// QualityScorer.swift
// YapYapBench — Automated quality checks for LLM cleanup output
import Foundation

struct QualityCheckResult: Codable {
    let name: String
    let passed: Bool
    let detail: String
}

struct QualityScore: Codable {
    let checks: [QualityCheckResult]
    let score: Double        // checks passed / checks applicable
    let passed: Bool         // score > 0.7
    let failedChecks: [String]
}

struct QualityScorer {

    /// Common filler words that medium/heavy cleanup should remove.
    private static let fillerWords: Set<String> = [
        "um", "uh", "like", "you know", "i mean", "basically",
        "right", "kind of", "sort of", "actually", "literally",
        "honestly", "so", "just", "yeah"
    ]

    /// Two-word fillers need special handling.
    private static let twoWordFillers: Set<String> = [
        "you know", "i mean", "kind of", "sort of"
    ]

    /// Preamble patterns that indicate the model didn't follow instructions.
    private static let preamblePatterns: [String] = [
        "here is", "here's the", "cleaned text", "cleaned version",
        "corrected text", "sure,", "sure!", "of course",
        "certainly", "absolutely", "i'd be happy",
        "output:", "result:", "cleaned:", "fixed:",
        "i'm sorry", "i cannot", "i can't provide"
    ]

    /// Run all applicable quality checks for a corpus entry + LLM output.
    static func score(
        entry: CorpusEntry,
        rawInput: String,
        finalOutput: String,
        cleanupLevel: String,
        contextCategory: String
    ) -> QualityScore {
        var checks: [QualityCheckResult] = []

        // 1. Not empty (always applies)
        checks.append(checkNotEmpty(output: finalOutput))

        // 2. No preamble leak (always applies)
        checks.append(checkNoPreamble(output: finalOutput))

        // 3. No hallucination (always applies, unless edge case)
        if !entry.tags.contains(CorpusEntry.isShort) || rawInput.trimmingCharacters(in: .whitespaces).count > 5 {
            checks.append(checkNoHallucination(input: rawInput, output: finalOutput))
        }

        // 4. Fillers removed (if tagged and level >= medium)
        if entry.tags.contains(CorpusEntry.hasFillers) && cleanupLevel != "light" {
            checks.append(checkFillersRemoved(input: rawInput, output: finalOutput))
        }

        // 5. Self-correction applied (if tagged and level >= medium)
        if entry.tags.contains(CorpusEntry.hasSelfCorrection) && cleanupLevel != "light" {
            checks.append(checkSelfCorrectionApplied(input: rawInput, output: finalOutput))
        }

        // 6. Length reasonable (always, unless edge case with near-empty input)
        if rawInput.trimmingCharacters(in: .whitespaces).count > 5 {
            checks.append(checkLengthReasonable(input: rawInput, output: finalOutput))
        }

        // 7. Overlap sufficient (always, unless edge case)
        if rawInput.trimmingCharacters(in: .whitespaces).count > 5 {
            checks.append(checkOverlapSufficient(input: rawInput, output: finalOutput))
        }

        // 8. List format correct (if tagged)
        if entry.tags.contains(CorpusEntry.hasList) && cleanupLevel != "light" {
            checks.append(checkListFormat(output: finalOutput))
        }

        // 9. Context-specific checks
        if entry.tags.contains(CorpusEntry.hasMentions) {
            checks.append(checkMentionsPreserved(input: rawInput, output: finalOutput))
        }

        if entry.tags.contains(CorpusEntry.hasTechnicalTerms) && contextCategory == "codeEditor" {
            checks.append(checkTechnicalTermsPreserved(input: rawInput, output: finalOutput))
        }

        let passedCount = checks.filter(\.passed).count
        let totalScore = checks.isEmpty ? 1.0 : Double(passedCount) / Double(checks.count)
        let failedNames = checks.filter { !$0.passed }.map(\.name)

        return QualityScore(
            checks: checks,
            score: totalScore,
            passed: totalScore > 0.7,
            failedChecks: failedNames
        )
    }

    // MARK: - Individual Checks

    private static func checkNotEmpty(output: String) -> QualityCheckResult {
        let passed = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return QualityCheckResult(name: "not_empty", passed: passed, detail: passed ? "OK" : "Output is empty")
    }

    private static func checkNoPreamble(output: String) -> QualityCheckResult {
        let lower = output.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in preamblePatterns {
            if lower.hasPrefix(pattern) {
                return QualityCheckResult(name: "no_preamble", passed: false, detail: "Starts with: \"\(pattern)\"")
            }
        }
        return QualityCheckResult(name: "no_preamble", passed: true, detail: "OK")
    }

    private static func checkNoHallucination(input: String, output: String) -> QualityCheckResult {
        let allowedAdditions: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been",
            "to", "of", "in", "on", "at", "for", "with", "and", "or",
            "but", "not", "it", "its", "this", "that", "i", "we", "you",
            "my", "our", "your", "he", "she", "they", "them",
            "do", "does", "did", "have", "has", "had", "will", "would",
            "can", "could", "should", "may", "might",
        ]
        let inputWords = Set(input.lowercased().components(separatedBy: .whitespacesAndNewlines)
            .flatMap { $0.components(separatedBy: CharacterSet.alphanumerics.inverted) }
            .filter { !$0.isEmpty })
        let outputWords = output.lowercased().components(separatedBy: .whitespacesAndNewlines)
            .flatMap { $0.components(separatedBy: CharacterSet.alphanumerics.inverted) }
            .filter { !$0.isEmpty }

        let novelWords = outputWords.filter { !inputWords.contains($0) && !allowedAdditions.contains($0) }
        let novelRatio = outputWords.isEmpty ? 0.0 : Double(novelWords.count) / Double(outputWords.count)

        let passed = novelRatio <= 0.20
        let detail = passed ? "OK (\(Int(novelRatio * 100))% novel)" : "Too many novel words: \(Int(novelRatio * 100))% [\(novelWords.prefix(5).joined(separator: ", "))]"
        return QualityCheckResult(name: "no_hallucination", passed: passed, detail: detail)
    }

    private static func checkFillersRemoved(input: String, output: String) -> QualityCheckResult {
        let inputLower = input.lowercased()
        let outputLower = output.lowercased()

        var inputFillerCount = 0
        var outputFillerCount = 0

        for filler in twoWordFillers {
            inputFillerCount += inputLower.components(separatedBy: filler).count - 1
            outputFillerCount += outputLower.components(separatedBy: filler).count - 1
        }

        let singleFillers = fillerWords.subtracting(twoWordFillers.flatMap { $0.components(separatedBy: " ") })
        let inputTokens = inputLower.components(separatedBy: .whitespacesAndNewlines)
        let outputTokens = outputLower.components(separatedBy: .whitespacesAndNewlines)

        for filler in singleFillers {
            inputFillerCount += inputTokens.filter { $0 == filler }.count
            outputFillerCount += outputTokens.filter { $0 == filler }.count
        }

        let passed = inputFillerCount == 0 || outputFillerCount < inputFillerCount
        let detail = "Input fillers: \(inputFillerCount), Output fillers: \(outputFillerCount)"
        return QualityCheckResult(name: "fillers_removed", passed: passed, detail: detail)
    }

    private static func checkSelfCorrectionApplied(input: String, output: String) -> QualityCheckResult {
        let correctionMarkers = ["no wait", "i mean", "actually no", "or not", "scratch that", "sorry"]
        let inputLower = input.lowercased()
        let hasCorrection = correctionMarkers.contains { inputLower.contains($0) }

        if !hasCorrection {
            return QualityCheckResult(name: "self_correction", passed: true, detail: "No correction markers found")
        }

        let outputLower = output.lowercased()
        let markerRemoved = correctionMarkers.filter { inputLower.contains($0) }.allSatisfy { !outputLower.contains($0) }
        let detail = markerRemoved ? "Correction markers removed" : "Correction markers still present in output"
        return QualityCheckResult(name: "self_correction", passed: markerRemoved, detail: detail)
    }

    private static func checkLengthReasonable(input: String, output: String) -> QualityCheckResult {
        let inputLen = input.trimmingCharacters(in: .whitespacesAndNewlines).count
        let outputLen = output.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard inputLen > 0 else {
            return QualityCheckResult(name: "length_reasonable", passed: true, detail: "Empty input")
        }
        let ratio = Double(outputLen) / Double(inputLen)
        let passed = ratio >= 0.2 && ratio <= 1.8
        let detail = String(format: "Ratio: %.2f (input: %d, output: %d)", ratio, inputLen, outputLen)
        return QualityCheckResult(name: "length_reasonable", passed: passed, detail: detail)
    }

    private static func checkOverlapSufficient(input: String, output: String) -> QualityCheckResult {
        let inputWords = Set(input.lowercased().split(separator: " ").map(String.init))
        let outputWords = Set(output.lowercased().split(separator: " ").map(String.init))
        guard !inputWords.isEmpty else {
            return QualityCheckResult(name: "overlap_sufficient", passed: true, detail: "Empty input")
        }
        let overlap = Double(inputWords.intersection(outputWords).count) / Double(inputWords.count)
        let passed = overlap > 0.2
        let detail = String(format: "Overlap: %.0f%%", overlap * 100)
        return QualityCheckResult(name: "overlap_sufficient", passed: passed, detail: detail)
    }

    private static func checkListFormat(output: String) -> QualityCheckResult {
        let lines = output.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let listPattern = try! NSRegularExpression(pattern: "^(\\d+[.)]\\s|[-•*]\\s)")
        let listLines = lines.filter { line in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            return listPattern.firstMatch(in: line, range: range) != nil
        }
        let passed = listLines.count >= 2
        let detail = "Found \(listLines.count) list-formatted lines out of \(lines.count)"
        return QualityCheckResult(name: "list_format", passed: passed, detail: detail)
    }

    private static func checkMentionsPreserved(input: String, output: String) -> QualityCheckResult {
        let mentionPattern = try! NSRegularExpression(pattern: "[@#]\\w+")
        let inputRange = NSRange(input.startIndex..<input.endIndex, in: input)
        let inputMentions = mentionPattern.matches(in: input, range: inputRange).compactMap { match in
            Range(match.range, in: input).map { String(input[$0]) }
        }
        let outputLower = output.lowercased()
        let preserved = inputMentions.filter { outputLower.contains($0.lowercased()) }
        let passed = inputMentions.isEmpty || preserved.count == inputMentions.count
        let detail = "Preserved \(preserved.count)/\(inputMentions.count) mentions"
        return QualityCheckResult(name: "mentions_preserved", passed: passed, detail: detail)
    }

    private static func checkTechnicalTermsPreserved(input: String, output: String) -> QualityCheckResult {
        let techPattern = try! NSRegularExpression(pattern: "[a-z]+[A-Z][a-zA-Z]*|[a-z]+_[a-z]+|[A-Z]{2,}|/[a-z]+")
        let inputRange = NSRange(input.startIndex..<input.endIndex, in: input)
        let techTerms = techPattern.matches(in: input, range: inputRange).compactMap { match in
            Range(match.range, in: input).map { String(input[$0]) }
        }

        guard !techTerms.isEmpty else {
            return QualityCheckResult(name: "tech_terms_preserved", passed: true, detail: "No tech terms detected")
        }

        let outputLower = output.lowercased()
        let preserved = techTerms.filter { outputLower.contains($0.lowercased()) }
        let ratio = Double(preserved.count) / Double(techTerms.count)
        let passed = ratio >= 0.5
        let detail = "Preserved \(preserved.count)/\(techTerms.count) tech terms"
        return QualityCheckResult(name: "tech_terms_preserved", passed: passed, detail: detail)
    }
}
