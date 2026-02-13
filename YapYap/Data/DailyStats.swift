import Foundation
import SwiftData

@Model
final class DailyStats {
    var date: Date
    var transcriptionCount: Int
    var wordCount: Int
    var totalDurationSeconds: Double

    init(
        date: Date = Date(),
        transcriptionCount: Int = 0,
        wordCount: Int = 0,
        totalDurationSeconds: Double = 0
    ) {
        self.date = date
        self.transcriptionCount = transcriptionCount
        self.wordCount = wordCount
        self.totalDurationSeconds = totalDurationSeconds
    }
}
