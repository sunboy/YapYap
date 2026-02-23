// CorrectionDiffer.swift
// YapYap — LCS-based word diff for learning corrections
import Foundation

struct CorrectionCandidate {
    let original: String
    let corrected: String
}

struct CorrectionDiffer {

    // MARK: - Common English Words (used to filter rephrasing vs STT errors)

    private static let commonWords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could",
        "should", "may", "might", "shall", "can", "must", "to", "of", "in",
        "for", "on", "with", "at", "by", "from", "it", "its", "this", "that",
        "and", "or", "but", "not", "no", "so", "if", "as", "he", "she", "we",
        "they", "them", "their", "there", "here", "where", "when", "what",
        "which", "who", "how", "all", "each", "every", "both", "few", "more",
        "most", "other", "some", "such", "than", "too", "very", "just", "also",
        "about", "after", "before", "between", "into", "through", "during",
        "above", "below", "up", "down", "out", "off", "over", "under", "again",
        "then", "once", "here", "there", "why", "how", "any", "many", "much",
        "own", "same", "still", "well", "back", "even", "also", "new", "now",
        "way", "use", "her", "him", "his", "my", "your", "our", "i", "me",
        "you", "get", "got", "go", "went", "gone", "come", "came", "make",
        "made", "take", "took", "give", "gave", "say", "said", "tell", "told",
        "think", "thought", "know", "knew", "see", "saw", "want", "need",
        "like", "look", "find", "found", "put", "set", "run", "let", "keep",
        "begin", "show", "try", "ask", "work", "call", "turn", "move", "live",
        "play", "feel", "felt", "leave", "left", "mean", "meant", "end",
        "while", "right", "write", "wrote", "read", "really", "thing",
        "because", "people", "time", "year", "day", "man", "woman", "child",
        "world", "life", "hand", "part", "place", "case", "week", "company",
        "system", "program", "question", "home", "point", "number", "night",
        "long", "great", "little", "good", "bad", "big", "small", "old",
        "high", "low", "first", "last", "next", "young", "important", "large",
        "early", "those", "these", "since", "only", "been", "going", "being"
    ]

    /// Diff two strings and return substitution candidates suitable for dictionary learning.
    /// Only returns word-for-word substitutions, not insertions or deletions.
    static func diff(original: String, corrected: String) -> [CorrectionCandidate] {
        let origWords = tokenize(original)
        let corrWords = tokenize(corrected)

        guard !origWords.isEmpty, !corrWords.isEmpty else { return [] }

        // Compute LCS
        let lcs = longestCommonSubsequence(origWords, corrWords)

        // Walk both arrays, extracting substitutions via LCS alignment
        let candidates = extractSubstitutions(
            origWords: origWords,
            corrWords: corrWords,
            lcs: lcs
        )

        // Filter unlikely corrections
        return candidates.filter { isLikelyCorrection($0) }
    }

    // MARK: - Tokenization

    private static func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    // MARK: - LCS

    private static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count
        let n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        // Case-sensitive comparison so capitalization changes are detected as substitutions
        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to find the LCS words
        var result: [String] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                result.append(a[i - 1])
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return result.reversed()
    }

    // MARK: - Substitution Extraction

    private static func extractSubstitutions(
        origWords: [String],
        corrWords: [String],
        lcs: [String]
    ) -> [CorrectionCandidate] {
        var candidates: [CorrectionCandidate] = []
        var oi = 0, ci = 0, li = 0

        while oi < origWords.count && ci < corrWords.count {
            let origWord = origWords[oi]
            let corrWord = corrWords[ci]

            if li < lcs.count && origWord == lcs[li] && corrWord == lcs[li] {
                // Both match LCS exactly — skip (unchanged word)
                oi += 1
                ci += 1
                li += 1
            } else if li < lcs.count && origWord == lcs[li] {
                // Original matches next LCS but corrected doesn't — insertion in corrected, skip
                ci += 1
            } else if li < lcs.count && corrWord == lcs[li] {
                // Corrected matches next LCS but original doesn't — deletion from original, skip
                oi += 1
            } else {
                // Neither matches LCS — this is a substitution
                candidates.append(CorrectionCandidate(
                    original: origWords[oi],
                    corrected: corrWords[ci]
                ))
                oi += 1
                ci += 1
            }
        }

        return candidates
    }

    // MARK: - Filtering

    private static func isLikelyCorrection(_ candidate: CorrectionCandidate) -> Bool {
        let orig = candidate.original
        let corr = candidate.corrected

        // Strip punctuation for comparison
        let origClean = orig.trimmingCharacters(in: .punctuationCharacters).lowercased()
        let corrClean = corr.trimmingCharacters(in: .punctuationCharacters).lowercased()

        // If identical after lowercasing, the only change is capitalization.
        // Accept if it's a proper noun correction (lowercase → Uppercase).
        if origClean == corrClean {
            return orig.first?.isLowercase == true && corr.first?.isUppercase == true
        }

        // Accept apostrophe additions: "cant" → "can't", "dont" → "don't"
        let origNoPunct = orig.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "").lowercased()
        let corrNoPunct = corr.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "").lowercased()
        if origNoPunct == corrNoPunct {
            return true
        }

        // Skip if both words are common English words (likely rephrasing, not STT error)
        if commonWords.contains(origClean) && commonWords.contains(corrClean) {
            return false
        }

        // Skip if Levenshtein distance > 60% of max word length (too different to be STT error)
        // This check runs before proper noun acceptance to prevent accepting wildly different words
        let maxLen = max(origClean.count, corrClean.count)
        let distance = levenshteinDistance(origClean, corrClean)
        if maxLen > 0 && Double(distance) / Double(maxLen) > 0.6 {
            return false
        }

        // Accept proper noun corrections (corrected starts uppercase, original doesn't)
        let isProperNounFix = corr.first?.isUppercase == true && orig.first?.isLowercase == true
        if isProperNounFix {
            return true
        }

        return true
    }

    // MARK: - Levenshtein Distance

    static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    curr[j] = prev[j - 1]
                } else {
                    curr[j] = min(prev[j - 1], prev[j], curr[j - 1]) + 1
                }
            }
            prev = curr
        }

        return prev[n]
    }
}
