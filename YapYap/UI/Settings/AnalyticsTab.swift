import SwiftUI

struct AnalyticsTab: View {
    @State private var weeklyData: [(String, Double)] = []
    @State private var totalTranscriptions: Int = 0
    @State private var totalWords: Int = 0
    @State private var totalTimeSaved: String = "0h"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your Yapping Stats")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.ypText1)
                .padding(.bottom, 4)
            Text("All data stays on your Mac. Always.")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)
                .padding(.bottom, 24)

            // Stats grid
            HStack(spacing: 12) {
                statCard(value: formatNumber(totalTranscriptions), label: "TRANSCRIPTIONS", color: .ypLavender)
                statCard(value: formatNumber(totalWords), label: "WORDS", color: .ypWarm)
                statCard(value: totalTimeSaved, label: "TIME SAVED", color: .ypMint)
            }
            .padding(.bottom, 24)

            // Chart
            VStack(alignment: .leading, spacing: 12) {
                Text("Transcriptions This Week")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ypText2)

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(weeklyData.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.ypLavender)
                                .opacity(index == weeklyData.count - 1 ? 0.3 : 0.6)
                                .frame(height: max(4, item.1 * 100))

                            Text(item.0)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.ypText4)
                                .textCase(.uppercase)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 120)
            }
            .padding(16)
            .background(Color.ypCard)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ypBorderLight, lineWidth: 1))
            .cornerRadius(10)
        }
        .onAppear {
            loadAnalytics()
        }
    }

    private func loadAnalytics() {
        let totals = AnalyticsTracker.shared.getTotalStats()
        totalTranscriptions = totals.transcriptions
        totalWords = totals.words
        totalTimeSaved = formatDuration(totals.duration)

        let weekStats = AnalyticsTracker.shared.getStatsForWeek()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Create data for last 7 days
        var dataByDate: [Date: Int] = [:]
        for stat in weekStats {
            dataByDate[stat.date] = stat.transcriptionCount
        }

        // Find max value for normalization
        let maxCount = dataByDate.values.max() ?? 1

        // Generate array for last 7 days
        weeklyData = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -6 + offset, to: today) else { return nil }
            let dayName = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
            let count = dataByDate[date] ?? 0
            let normalized = maxCount > 0 ? Double(count) / Double(maxCount) : 0.0
            return (dayName, normalized)
        }
    }

    private func formatNumber(_ num: Int) -> String {
        if num >= 1000 {
            return String(format: "%.1fk", Double(num) / 1000.0)
        }
        return "\(num)"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        if hours > 0 {
            return "\(hours)h"
        }
        let minutes = Int(seconds) / 60
        return "\(minutes)m"
    }

    private func statCard(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.ypText3)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.ypCard)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ypBorderLight, lineWidth: 1))
        .cornerRadius(10)
    }
}
