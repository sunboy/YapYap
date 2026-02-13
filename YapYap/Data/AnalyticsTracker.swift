import Foundation
import SwiftData

@MainActor
final class AnalyticsTracker {
    static let shared = AnalyticsTracker()

    private init() {}

    func recordTranscription(wordCount: Int, duration: Double) {
        let container = DataManager.shared.container
        let context = ModelContext(container)
        let today = Calendar.current.startOfDay(for: Date())

        let descriptor = FetchDescriptor<DailyStats>(
            predicate: #Predicate { $0.date == today }
        )

        let stats: DailyStats
        if let existing = try? context.fetch(descriptor).first {
            stats = existing
        } else {
            stats = DailyStats(date: today)
            context.insert(stats)
        }

        stats.transcriptionCount += 1
        stats.wordCount += wordCount
        stats.totalDurationSeconds += duration
        try? context.save()
    }

    func getStatsForWeek() -> [DailyStats] {
        let container = DataManager.shared.container
        let context = ModelContext(container)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) else { return [] }

        let descriptor = FetchDescriptor<DailyStats>(
            predicate: #Predicate { $0.date >= weekAgo },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func getTotalStats() -> (transcriptions: Int, words: Int, duration: Double) {
        let container = DataManager.shared.container
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<DailyStats>()
        let allStats = (try? context.fetch(descriptor)) ?? []
        return (
            transcriptions: allStats.reduce(0) { $0 + $1.transcriptionCount },
            words: allStats.reduce(0) { $0 + $1.wordCount },
            duration: allStats.reduce(0) { $0 + $1.totalDurationSeconds }
        )
    }

    func getTodayStats() -> DailyStats {
        let container = DataManager.shared.container
        let context = ModelContext(container)
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<DailyStats>(
            predicate: #Predicate { $0.date == today }
        )
        return (try? context.fetch(descriptor).first) ?? DailyStats(date: today)
    }
}
