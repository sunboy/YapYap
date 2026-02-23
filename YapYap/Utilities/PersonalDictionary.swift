// PersonalDictionary.swift
// YapYap — Auto-learning word corrections
import Foundation

enum CorrectionSource: String, Codable {
    case autoLearned
    case manual
}

struct CorrectionEntry: Codable {
    let spoken: String
    let corrected: String
    let dateAdded: Date
    var hitCount: Int
    var isEnabled: Bool
    var source: CorrectionSource
    /// When set, this correction only applies in the specified app
    var appName: String?

    /// Storage key: "spoken" for global, "spoken::AppName" for per-app
    var storageKey: String {
        if let app = appName {
            return "\(spoken)::\(app)"
        }
        return spoken
    }
}

class PersonalDictionary: ObservableObject {
    static let shared = PersonalDictionary()

    @Published var entries: [String: CorrectionEntry] = [:] {
        didSet { rebuildRegexCache() }
    }

    /// Cached compiled regexes for each enabled dictionary entry (rebuilt when entries change)
    /// Tuple: (regex, replacement, key, appName?)
    private var cachedRegexes: [(NSRegularExpression, String, String, String?)] = []

    private let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("YapYap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dictionary.json")
    }()

    init() { load() }

    // MARK: - Corrections

    /// Apply dictionary corrections to text (before LLM cleanup).
    /// Pass activeAppName to also apply per-app corrections.
    func applyCorrections(to text: String, activeAppName: String? = nil) -> String {
        guard !cachedRegexes.isEmpty else { return text }
        var result = text
        for (regex, replacement, key, entryApp) in cachedRegexes {
            // Skip per-app entries that don't match the active app
            if let entryApp = entryApp, entryApp != activeAppName {
                continue
            }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            let before = result
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
            // Increment hit count if a replacement actually happened
            if result != before, var entry = entries[key] {
                entry.hitCount += 1
                entries[key] = entry
                saveWithoutRebuild()
            }
        }
        return result
    }

    /// Learn a new correction (e.g., "anthropick" → "Anthropic")
    func learnCorrection(spoken: String, corrected: String, source: CorrectionSource = .manual, appName: String? = nil) {
        let entry = CorrectionEntry(
            spoken: spoken.lowercased(),
            corrected: corrected,
            dateAdded: Date(),
            hitCount: 0,
            isEnabled: true,
            source: source,
            appName: appName
        )
        let key = entry.storageKey
        if var existing = entries[key] {
            existing.source = source
            entries[key] = existing
        } else {
            entries[key] = entry
        }
        save()
    }

    /// Remove a learned correction
    func removeCorrection(key: String) {
        entries.removeValue(forKey: key)
        save()
    }

    /// Toggle enabled state for a correction
    func toggleCorrection(key: String, enabled: Bool) {
        guard var entry = entries[key] else { return }
        entry.isEnabled = enabled
        entries[key] = entry
        save()
    }

    /// All entries sorted by dateAdded descending (newest first)
    var allEntries: [CorrectionEntry] {
        entries.values.sorted { $0.dateAdded > $1.dateAdded }
    }

    /// Global entries (not scoped to any app)
    var globalEntries: [CorrectionEntry] {
        allEntries.filter { $0.appName == nil }
    }

    /// Entries for a specific app
    func entriesFor(app: String) -> [CorrectionEntry] {
        allEntries.filter { $0.appName == app }
    }

    /// Unique app names that have per-app entries
    var appsWithEntries: [String] {
        Array(Set(entries.values.compactMap { $0.appName })).sorted()
    }

    // MARK: - Auto-Detect Corrections

    /// Monitor the focused text field after pasting and auto-learn corrections
    func monitorAndLearn(pastedText: String, afterDelay: TimeInterval = 5.0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + afterDelay) { [weak self] in
            guard let currentText = AppContextDetector.getFocusedFieldText() else { return }
            let candidates = CorrectionDiffer.diff(original: pastedText, corrected: currentText)
            for candidate in candidates {
                self?.learnCorrection(
                    spoken: candidate.original,
                    corrected: candidate.corrected,
                    source: .autoLearned
                )
            }
        }
    }

    // MARK: - Regex Cache

    /// Rebuild the compiled regex cache from current entries (only enabled entries)
    private func rebuildRegexCache() {
        cachedRegexes = entries.compactMap { (key, entry) in
            guard entry.isEnabled else { return nil }
            let escaped = NSRegularExpression.escapedPattern(for: entry.spoken)
            guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: [.caseInsensitive]) else {
                return nil
            }
            return (regex, entry.corrected, key, entry.appName)
        }
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL)
    }

    /// Save without triggering didSet (used for hit count updates during applyCorrections)
    private func saveWithoutRebuild() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }

        // Try new format first
        if let decoded = try? JSONDecoder().decode([String: CorrectionEntry].self, from: data) {
            entries = decoded
            return
        }

        // Migrate from old flat [String: String] format
        if let legacy = try? JSONDecoder().decode([String: String].self, from: data) {
            var migrated: [String: CorrectionEntry] = [:]
            for (spoken, corrected) in legacy {
                migrated[spoken] = CorrectionEntry(
                    spoken: spoken,
                    corrected: corrected,
                    dateAdded: Date(),
                    hitCount: 0,
                    isEnabled: true,
                    source: .manual,
                    appName: nil
                )
            }
            entries = migrated
            save()
            NSLog("[PersonalDictionary] Migrated \(migrated.count) entries from legacy format")
        }
    }
}
