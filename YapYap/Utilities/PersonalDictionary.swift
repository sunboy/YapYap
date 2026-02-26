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

    /// Poll the focused text field after pasting and auto-learn any corrections the user makes.
    ///
    /// Strategy:
    /// - Poll every second for up to 60 seconds
    /// - Each poll, find the pasted text (or an edited version of it) within the field
    /// - When the region containing the paste differs from what we pasted, diff it and learn
    /// - Stop as soon as corrections are learned, or when the window/field changes
    func monitorAndLearn(pastedText: String, appName: String? = nil) {
        guard !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let pollInterval: TimeInterval = 1.0
        let maxPolls = 60
        var pollCount = 0

        // Snapshot the field immediately after paste so we have a baseline.
        // This lets us detect the exact location of our paste in the field.
        let baselineFieldText = AppContextDetector.getFocusedFieldText() ?? ""

        NSLog("[PersonalDictionary] monitorAndLearn started — watching for edits to \(pastedText.count)-char paste")

        func poll() {
            guard pollCount < maxPolls else {
                NSLog("[PersonalDictionary] monitorAndLearn: timeout after \(pollCount)s, no corrections detected")
                return
            }
            pollCount += 1

            DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) { [weak self] in
                guard let self else { return }

                guard let currentFieldText = AppContextDetector.getFocusedFieldText() else {
                    // Field gone or focus moved away — stop watching
                    NSLog("[PersonalDictionary] monitorAndLearn: field no longer readable, stopping after \(pollCount)s")
                    return
                }

                // Extract the region of the field that corresponds to our paste.
                // We anchor on the baseline: find where the paste sat, then read that window.
                guard let editedRegion = Self.extractEditedRegion(
                    pastedText: pastedText,
                    baselineField: baselineFieldText,
                    currentField: currentFieldText
                ) else {
                    // Paste region not found — user may have deleted it entirely, stop
                    if pollCount > 3 {
                        NSLog("[PersonalDictionary] monitorAndLearn: paste region gone after \(pollCount)s, stopping")
                        return
                    }
                    poll()
                    return
                }

                // No change yet — keep polling
                guard editedRegion != pastedText else {
                    poll()
                    return
                }

                // Region changed — diff and learn
                let candidates = CorrectionDiffer.diff(original: pastedText, corrected: editedRegion)
                guard !candidates.isEmpty else {
                    // Changed but diff found nothing learnable (e.g. user added new sentences)
                    // Keep polling in case they fix more words
                    poll()
                    return
                }

                NSLog("[PersonalDictionary] monitorAndLearn: learned \(candidates.count) correction(s) after \(pollCount)s")
                for candidate in candidates {
                    NSLog("[PersonalDictionary]   \"\(candidate.original)\" → \"\(candidate.corrected)\"")
                    self.learnCorrection(
                        spoken: candidate.original,
                        corrected: candidate.corrected,
                        source: .autoLearned,
                        appName: appName
                    )
                }
                // Continue polling — user may correct more words in the same paste
                poll()
            }
        }

        poll()
    }

    /// Find the portion of `currentField` that corresponds to where `pastedText` was pasted.
    ///
    /// Uses the baseline field snapshot to locate the paste offset, then reads that
    /// same window from the current field — capturing only user edits to the pasted region,
    /// not text typed before or after the paste.
    ///
    /// Returns nil if the paste region can't be located (e.g. user deleted it).
    static func extractEditedRegion(pastedText: String, baselineField: String, currentField: String) -> String? {
        // Find where the paste starts in the baseline field
        guard let pasteRange = baselineField.range(of: pastedText) else {
            // Exact match not found — try fuzzy: find the first word of the paste
            let firstWords = pastedText.split(separator: " ").prefix(3).joined(separator: " ")
            guard !firstWords.isEmpty,
                  let approxStart = baselineField.range(of: firstWords, options: .caseInsensitive) else {
                return nil
            }
            // Calculate offset from start of baseline field
            let offset = baselineField.distance(from: baselineField.startIndex, to: approxStart.lowerBound)
            return extractWindow(from: currentField, offset: offset, approximateLength: pastedText.count)
        }

        let offset = baselineField.distance(from: baselineField.startIndex, to: pasteRange.lowerBound)
        return extractWindow(from: currentField, offset: offset, approximateLength: pastedText.count)
    }

    /// Extract a window of `approximateLength` characters from `text` starting at `offset`.
    /// Extends to the nearest sentence/word boundary to avoid cutting mid-word.
    private static func extractWindow(from text: String, offset: Int, approximateLength: Int) -> String? {
        guard offset < text.count else { return nil }
        let startIndex = text.index(text.startIndex, offsetBy: min(offset, text.count))
        // Give a 50% length buffer for cases where editing added words
        let endOffset = min(offset + Int(Double(approximateLength) * 1.5), text.count)
        let endIndex = text.index(text.startIndex, offsetBy: endOffset)
        let window = String(text[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return window.isEmpty ? nil : window
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
