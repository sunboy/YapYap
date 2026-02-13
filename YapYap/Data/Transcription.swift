import Foundation
import SwiftData

@Model
final class Transcription {
    var id: UUID
    var rawText: String
    var cleanedText: String
    var timestamp: Date
    var durationSeconds: Double
    var wordCount: Int
    var sttModel: String
    var llmModel: String
    var sourceApp: String?
    var language: String
    var cleanupLevel: String

    init(
        id: UUID = UUID(),
        rawText: String,
        cleanedText: String,
        timestamp: Date = Date(),
        durationSeconds: Double,
        wordCount: Int,
        sttModel: String,
        llmModel: String,
        sourceApp: String? = nil,
        language: String = "en",
        cleanupLevel: String = "medium"
    ) {
        self.id = id
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
        self.sttModel = sttModel
        self.llmModel = llmModel
        self.sourceApp = sourceApp
        self.language = language
        self.cleanupLevel = cleanupLevel
    }
}
