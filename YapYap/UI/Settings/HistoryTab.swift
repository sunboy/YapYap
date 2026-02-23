import SwiftUI
import SwiftData

struct HistoryTab: View {
    @State private var transcriptions: [Transcription] = []
    @State private var selectedApp: String? = nil
    @State private var availableApps: [String] = []

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Transcription History")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.ypText1)
                .padding(.bottom, 4)
            Text("Your transcriptions tagged by source app.")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)
                .padding(.bottom, 16)

            // App filter
            if !availableApps.isEmpty {
                appFilterBar
                    .padding(.bottom, 12)
            }

            // Timeline
            if filteredTranscriptions.isEmpty {
                emptyState
            } else {
                timelineList
            }
        }
        .onAppear { loadTranscriptions() }
    }

    private var filteredTranscriptions: [Transcription] {
        guard let app = selectedApp else { return transcriptions }
        return transcriptions.filter { $0.sourceApp == app }
    }

    // MARK: - App Filter Bar

    private var appFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(label: "All", isSelected: selectedApp == nil) {
                    selectedApp = nil
                }
                ForEach(availableApps, id: \.self) { app in
                    filterChip(label: app, isSelected: selectedApp == app) {
                        selectedApp = app
                    }
                }
            }
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .ypText2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.ypLavender : Color.ypCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.clear : Color.ypBorderLight, lineWidth: 1)
                )
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No transcriptions yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.ypText2)
            Text("Your transcription history will appear here after you start using YapYap.")
                .font(.system(size: 11))
                .foregroundColor(.ypText3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.ypCard)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.ypBorderLight, lineWidth: 1)
        )
        .cornerRadius(8)
    }

    // MARK: - Timeline List

    private var timelineList: some View {
        let grouped = groupedByDate(filteredTranscriptions)
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(grouped, id: \.date) { group in
                VStack(alignment: .leading, spacing: 0) {
                    // Date header
                    Text(dateFormatter.string(from: group.date))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.ypText3)
                        .tracking(0.8)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                            transcriptionRow(item)

                            if index < group.items.count - 1 {
                                Divider()
                                    .background(Color.ypBorderLight)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                    .background(Color.ypCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.ypBorderLight, lineWidth: 1)
                    )
                    .cornerRadius(8)
                }
            }
        }
    }

    private func transcriptionRow(_ item: Transcription) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // App badge
            VStack(spacing: 2) {
                Text(appEmoji(for: item.sourceApp))
                    .font(.system(size: 14))
                Text(timeFormatter.string(from: item.timestamp))
                    .font(.system(size: 9))
                    .foregroundColor(.ypText4)
            }
            .frame(width: 44)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.sourceApp ?? "Unknown")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.ypText1)

                    Text("\(item.wordCount) words")
                        .font(.system(size: 10))
                        .foregroundColor(.ypText4)

                    if item.durationSeconds > 0 {
                        Text(formatDuration(item.durationSeconds))
                            .font(.system(size: 10))
                            .foregroundColor(.ypText4)
                    }
                }

                Text(item.cleanedText)
                    .font(.system(size: 11))
                    .foregroundColor(.ypText2)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private struct DateGroup {
        let date: Date
        let items: [Transcription]
    }

    private func groupedByDate(_ items: [Transcription]) -> [DateGroup] {
        let calendar = Calendar.current
        var groups: [Date: [Transcription]] = [:]
        for item in items {
            let day = calendar.startOfDay(for: item.timestamp)
            groups[day, default: []].append(item)
        }
        return groups.keys.sorted(by: >).map { date in
            DateGroup(date: date, items: groups[date]!.sorted { $0.timestamp > $1.timestamp })
        }
    }

    private func appEmoji(for appName: String?) -> String {
        guard let name = appName?.lowercased() else { return "⚙️" }
        // Map common app names to emojis
        if name.contains("message") || name.contains("imessage") || name.contains("whatsapp") || name.contains("telegram") || name.contains("signal") {
            return "💬"
        } else if name.contains("slack") || name.contains("teams") || name.contains("discord") {
            return "💼"
        } else if name.contains("mail") || name.contains("gmail") || name.contains("outlook") {
            return "✉️"
        } else if name.contains("xcode") || name.contains("code") || name.contains("cursor") || name.contains("windsurf") || name.contains("vim") {
            return "🖥️"
        } else if name.contains("safari") || name.contains("chrome") || name.contains("firefox") || name.contains("arc") {
            return "🌐"
        } else if name.contains("notion") || name.contains("obsidian") || name.contains("notes") || name.contains("pages") {
            return "📄"
        } else if name.contains("chatgpt") || name.contains("claude") || name.contains("perplexity") {
            return "🤖"
        }
        return "⚙️"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s >= 60 {
            return "\(s / 60)m \(s % 60)s"
        }
        return "\(s)s"
    }

    private func loadTranscriptions() {
        // Defer to next run loop so settings window renders immediately
        Task { @MainActor in
            let container = DataManager.shared.container
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<Transcription>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = 200
            transcriptions = (try? context.fetch(descriptor)) ?? []

            // Build unique app list
            let apps = Set(transcriptions.compactMap { $0.sourceApp })
            availableApps = apps.sorted()
        }
    }
}
