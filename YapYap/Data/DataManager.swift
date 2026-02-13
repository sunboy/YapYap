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
            CustomDictionaryEntry.self,
            DailyStats.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error)")
        }
    }

    func fetchSettings() -> AppSettings {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? context.fetch(descriptor).first {
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
