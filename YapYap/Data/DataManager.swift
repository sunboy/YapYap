import Foundation
import SwiftData

extension Notification.Name {
    static let yapSettingsChanged = Notification.Name("dev.yapyap.settingsChanged")
    static let yapModelSelected = Notification.Name("dev.yapyap.modelSelected")
}

@MainActor
final class DataManager {
    static let shared = DataManager()

    let container: ModelContainer
    private var _cachedSettings: AppSettings?

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

    /// Returns the single AppSettings instance, cached after first fetch.
    /// All callers get the same object so mutations + save always work on mainContext.
    func fetchSettings() -> AppSettings {
        if let cached = _cachedSettings {
            return cached
        }
        let context = container.mainContext
        let descriptor = FetchDescriptor<AppSettings>()
        if let allSettings = try? context.fetch(descriptor), let settings = allSettings.first {
            // Delete duplicate rows (bug from earlier code creating new contexts)
            if allSettings.count > 1 {
                for duplicate in allSettings.dropFirst() {
                    context.delete(duplicate)
                }
                try? context.save()
            }

            // Migrate invalid LLM model IDs to recommended default
            if LLMModelRegistry.model(for: settings.llmModelId) == nil {
                let newDefault = LLMModelRegistry.recommendedModel.id
                settings.llmModelId = newDefault
                try? context.save()
            }
            _cachedSettings = settings
            return settings
        }
        let defaults = AppSettings.defaults()
        context.insert(defaults)
        try? context.save()
        _cachedSettings = defaults
        return defaults
    }

    /// Marks a model ID as successfully downloaded/loaded.
    func markModelDownloaded(_ modelId: String) {
        let settings = fetchSettings()
        var ids = settings.downloadedModelIds.flatMap { $0.isEmpty ? nil : $0.components(separatedBy: ",") } ?? []
        if !ids.contains(modelId) {
            ids.append(modelId)
            settings.downloadedModelIds = ids.joined(separator: ",")
            saveSettings()
        }
    }

    /// Returns the set of model IDs that have been successfully downloaded.
    func downloadedModelIds() -> Set<String> {
        let settings = fetchSettings()
        guard let raw = settings.downloadedModelIds, !raw.isEmpty else { return [] }
        return Set(raw.components(separatedBy: ","))
    }

    /// Persists any pending changes on the cached AppSettings to disk.
    func saveSettings() {
        try? container.mainContext.save()
        NotificationCenter.default.post(name: .yapSettingsChanged, object: nil)
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
