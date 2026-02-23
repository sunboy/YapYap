import Foundation
import SwiftData

@MainActor
final class DataManager {
    static let shared = DataManager()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            Transcription.self,
            AppSettings.self,
            PowerModeRule.self,
            DailyStats.self
        ])

        // Get the app's Application Support directory
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let yapyapDir = appSupportURL.appendingPathComponent("YapYap", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: yapyapDir, withIntermediateDirectories: true)

        let storeURL = yapyapDir.appendingPathComponent("YapYap.store")

        let config = ModelConfiguration(
            schema: schema,
            url: storeURL,
            allowsSave: true
        )

        do {
            container = try ModelContainer(for: schema, configurations: [config])
            print("[DataManager] SwiftData container initialized at: \(storeURL.path)")
        } catch {
            print("[DataManager] Failed to initialize SwiftData: \(error)")
            print("[DataManager] Attempting to delete corrupt store and retry...")

            // Try to delete corrupt database and retry
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))

            do {
                container = try ModelContainer(for: schema, configurations: [config])
                print("[DataManager] SwiftData container initialized after cleanup")
            } catch {
                // Last resort: use in-memory store so app doesn't crash
                print("[DataManager] Using in-memory store as fallback: \(error)")
                let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                // This should never fail, but if it does, we have no choice but to crash
                container = try! ModelContainer(for: schema, configurations: [memoryConfig])
            }
        }
    }

    func fetchSettings() -> AppSettings {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? context.fetch(descriptor).first {
            // Migrate invalid LLM model IDs to recommended default
            if LLMModelRegistry.model(for: settings.llmModelId) == nil {
                let newDefault = LLMModelRegistry.recommendedModel.id
                print("[DataManager] Migrating invalid LLM: \(settings.llmModelId) → \(newDefault)")
                settings.llmModelId = newDefault
                try? context.save()
            }
            return settings
        }
        let defaults = AppSettings.defaults()
        context.insert(defaults)
        try? context.save()
        return defaults
    }

    func saveTranscription(raw: String, cleaned: String, duration: Double, sttModel: String, llmModel: String, sourceApp: String?) {
        let context = ModelContext(container)
        let entry = Transcription(
            rawText: raw,
            cleanedText: cleaned,
            durationSeconds: duration,
            wordCount: cleaned.split(separator: " ").count,
            sttModel: sttModel,
            llmModel: llmModel,
            sourceApp: sourceApp
        )
        context.insert(entry)
        try? context.save()
    }
}
