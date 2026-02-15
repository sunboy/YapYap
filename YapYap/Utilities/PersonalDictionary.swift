// PersonalDictionary.swift
// YapYap — Auto-learning word corrections
import Foundation

class PersonalDictionary: ObservableObject {
    @Published var entries: [String: String] = [:] {
        didSet { rebuildRegexCache() }
    }

    /// Cached compiled regexes for each dictionary entry (rebuilt when entries change)
    private var cachedRegexes: [(NSRegularExpression, String)] = []

    private let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("YapYap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dictionary.json")
    }()

    init() { load() }

    /// Apply dictionary corrections to text (before LLM cleanup)
    func applyCorrections(to text: String) -> String {
        guard !cachedRegexes.isEmpty else { return text }
        var result = text
        for (regex, replacement) in cachedRegexes {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }
        return result
    }

    /// Learn a new correction (e.g., "anthropick" → "Anthropic")
    func learnCorrection(spoken: String, corrected: String) {
        entries[spoken.lowercased()] = corrected
        save()
    }

    /// Remove a learned correction
    func removeCorrection(spoken: String) {
        entries.removeValue(forKey: spoken.lowercased())
        save()
    }

    /// Rebuild the compiled regex cache from current entries
    private func rebuildRegexCache() {
        cachedRegexes = entries.compactMap { (spoken, corrected) in
            let escaped = NSRegularExpression.escapedPattern(for: spoken)
            guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: [.caseInsensitive]) else {
                return nil
            }
            return (regex, corrected)
        }
    }

    /// Monitor for user corrections after pasting (auto-learn)
    func monitorCorrections(pastedText: String, afterDelay: TimeInterval = 5.0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + afterDelay) { [weak self] in
            guard let currentText = AppContextDetector.getFocusedFieldText() else { return }
            let corrections = self?.diffWords(original: pastedText, edited: currentText) ?? []
            for (original, corrected) in corrections {
                self?.learnCorrection(spoken: original, corrected: corrected)
            }
        }
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        entries = decoded
    }

    // MARK: - Diff

    private func diffWords(original: String, edited: String) -> [(String, String)] {
        let origWords = original.split(separator: " ").map(String.init)
        let editWords = edited.split(separator: " ").map(String.init)

        var corrections: [(String, String)] = []

        // Simple word-by-word comparison
        let minCount = min(origWords.count, editWords.count)
        for i in 0..<minCount {
            if origWords[i].lowercased() != editWords[i].lowercased() {
                corrections.append((origWords[i], editWords[i]))
            }
        }

        return corrections
    }
}
