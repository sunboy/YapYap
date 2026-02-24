// UserPromptContextManager.swift
// YapYap — Builds UserPromptContext from PersonalDictionary and edit memory
import Foundation

class UserPromptContextManager {
    static let shared = UserPromptContextManager()

    /// Build a UserPromptContext for the current dictation.
    /// - Parameters:
    ///   - appName: Active app name for per-app filtering (nil = global only)
    ///   - transcript: Raw transcript text for relevance boosting (nil = no boosting)
    func context(for appName: String?, transcript: String? = nil) -> UserPromptContext {
        let dictionary = PersonalDictionary.shared
        let entries = buildDictionaryEntries(
            from: dictionary,
            appName: appName,
            transcript: transcript
        )

        // Edit memory: returns empty for now (Phase 2)
        let editMemory: [(before: String, after: String)] = []

        return UserPromptContext(
            dictionaryEntries: entries,
            editMemoryEntries: editMemory
        )
    }

    /// Convert PersonalDictionary CorrectionEntries into prompt-injectable pairs.
    /// Sorted by hit count descending. Per-app entries matching appName are included.
    private func buildDictionaryEntries(
        from dictionary: PersonalDictionary,
        appName: String?,
        transcript: String?
    ) -> [(spoken: String, corrected: String)] {
        let allEntries = dictionary.entries.values
            .filter { $0.isEnabled }
            .filter { entry in
                // Include global entries (no app) and entries matching the active app
                entry.appName == nil || entry.appName == appName
            }

        // Sort by relevance: entries matching transcript words first, then by hit count
        let sorted = allEntries.sorted { a, b in
            let aRelevant = transcript?.localizedCaseInsensitiveContains(a.spoken) ?? false
            let bRelevant = transcript?.localizedCaseInsensitiveContains(b.spoken) ?? false
            if aRelevant != bRelevant { return aRelevant }
            return a.hitCount > b.hitCount
        }

        return sorted.map { (spoken: $0.spoken, corrected: $0.corrected) }
    }
}
