// SnippetManager.swift
// YapYap — Voice snippet triggers and expansions
import Foundation

struct VoiceSnippet: Codable, Identifiable {
    let id: UUID
    let trigger: String
    let expansion: String
    let isTeamShared: Bool

    init(trigger: String, expansion: String, isTeamShared: Bool = false) {
        self.id = UUID()
        self.trigger = trigger
        self.expansion = expansion
        self.isTeamShared = isTeamShared
    }
}

class SnippetManager: ObservableObject {
    @Published var snippets: [VoiceSnippet] = []

    private let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("YapYap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("snippets.json")
    }()

    init() { load() }

    /// Check if transcribed text matches a snippet trigger
    func matchSnippet(from text: String) -> VoiceSnippet? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return snippets.first {
            lower == $0.trigger.lowercased() ||
            lower == "insert \($0.trigger.lowercased())"
        }
    }

    func addSnippet(trigger: String, expansion: String) {
        let snippet = VoiceSnippet(trigger: trigger, expansion: expansion)
        snippets.append(snippet)
        save()
    }

    func removeSnippet(id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        try? data.write(to: fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([VoiceSnippet].self, from: data)
        else { return }
        snippets = decoded
    }
}
