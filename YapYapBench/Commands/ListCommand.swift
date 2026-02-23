// ListCommand.swift
// YapYapBench — List available models and contexts
import ArgumentParser
import Foundation

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available STT models, LLM models, and context categories."
    )

    func run() async throws {
        printSTTModels()
        print("")
        printLLMModels()
        print("")
        printContexts()
        print("")
        printCleanupLevels()
    }

    private func printSTTModels() {
        print("STT Models:")
        print(String(repeating: "-", count: 70))
        print("  \(pad("ID", 25)) \(pad("Backend", 12)) \(pad("Size", 10)) Languages")
        print(String(repeating: "-", count: 70))
        for model in STTModelRegistry.allModels {
            let rec = model.isRecommended ? " *" : ""
            print("  \(pad(model.id + rec, 25)) \(pad(model.backend.rawValue, 12)) \(pad(model.sizeDescription, 10)) \(model.languages.joined(separator: ","))")
        }
        print("  (* = recommended)")
    }

    private func printLLMModels() {
        print("LLM Models:")
        print(String(repeating: "-", count: 80))
        print("  \(pad("ID", 20)) \(pad("Family", 8)) \(pad("Size", 8)) \(pad("Disk", 10)) Languages")
        print(String(repeating: "-", count: 80))
        for model in LLMModelRegistry.allModels {
            let rec = model.isRecommended ? " *" : ""
            let sizeLabel = model.size == .small ? "small" : "medium"
            print("  \(pad(model.id + rec, 20)) \(pad(model.family.rawValue, 8)) \(pad(sizeLabel, 8)) \(pad(model.sizeDescription, 10)) \(model.languages.prefix(5).joined(separator: ","))")
        }
        print("  (* = recommended)")
    }

    private func printContexts() {
        print("Contexts (--contexts):")
        print(String(repeating: "-", count: 60))
        let contexts: [(name: String, category: String, app: String)] = [
            ("email", "Email", "Mail"),
            ("slack / work", "Work Messaging", "Slack"),
            ("imessage / messages", "Personal Messaging", "Messages"),
            ("code / ide / vscode", "Code Editor", "VS Code"),
            ("chrome / browser", "Browser", "Safari"),
            ("docs / notion", "Documents", "Obsidian"),
            ("chatgpt / claude", "AI Chat", "ChatGPT"),
            ("other", "Other", "Unknown"),
        ]
        for ctx in contexts {
            print("  \(pad(ctx.name, 25)) \(pad(ctx.category, 22)) \(ctx.app)")
        }
        print("  Use 'all' for all canonical contexts")
    }

    private func printCleanupLevels() {
        print("Cleanup Levels (--cleanup-levels):")
        print(String(repeating: "-", count: 60))
        print("  light    Fix punctuation/capitalization only")
        print("  medium   Remove fillers + fix punctuation (default)")
        print("  heavy    Aggressive cleanup + clarity improvement")
        print("  Use 'all' for all levels")
    }

    private func pad(_ text: String, _ width: Int) -> String {
        if text.count >= width { return text }
        return text + String(repeating: " ", count: width - text.count)
    }
}
