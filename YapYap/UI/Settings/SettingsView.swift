import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case writingStyle = "Writing Style"
    case models = "Models"
    case hotkeys = "Hotkeys"
    case general = "General"
    case style = "Style"
    case dictionary = "Dictionary"
    case history = "History"
    case analytics = "Analytics"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .writingStyle: return "✍️"
        case .models: return "🧠"
        case .hotkeys: return "⌨️"
        case .general: return "⚙️"
        case .style: return "✨"
        case .dictionary: return "📖"
        case .history: return "📜"
        case .analytics: return "📊"
        case .about: return "💜"
        }
    }

    var section: String {
        switch self {
        case .writingStyle, .models, .hotkeys, .general, .style, .dictionary: return "CONFIGURATION"
        case .history, .analytics: return "INSIGHTS"
        case .about: return "APP"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .writingStyle

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar
                .frame(width: 200)
                .background(Color.ypBg4)

            // Divider
            Rectangle()
                .fill(Color.ypBorderLight)
                .frame(width: 1)

            // Content
            VStack(spacing: 0) {
                // Title bar
                HStack {
                    Text(selectedTab.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.ypText1)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .frame(height: 52)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.ypBorderLight).frame(height: 1)
                }

                // Tab content
                ScrollView {
                    tabContent
                        .padding(24)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 780, height: 540)
        .background(Color.ypBg.opacity(0.96))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Spacer for titlebar traffic lights
            Spacer().frame(height: 52)

            // Brand
            HStack(spacing: 8) {
                CreatureView(state: .recording, size: 28, showSmile: false)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text("yapyap")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.ypText1)
                        Text("v0.1.0")
                            .font(.system(size: 10))
                            .foregroundColor(.ypText3)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            // Navigation
            VStack(alignment: .leading, spacing: 0) {
                navSection("CONFIGURATION", tabs: [.writingStyle, .models, .hotkeys, .general, .style, .dictionary])
                navSection("INSIGHTS", tabs: [.history, .analytics])
                navSection("APP", tabs: [.about])
            }
            .padding(.horizontal, 8)

            Spacer()

            // Footer
            Text("~ the little one is listening ~")
                .font(.custom("Caveat", size: 13))
                .foregroundColor(.ypText4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.ypBorderLight).frame(height: 1)
                }
        }
    }

    private func navSection(_ title: String, tabs: [SettingsTab]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.ypText3)
                .tracking(1)
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 6)

            ForEach(tabs) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 8) {
                        Text(tab.icon)
                            .font(.system(size: 13))
                            .opacity(selectedTab == tab ? 1 : 0.6)
                            .frame(width: 16)
                        Text(tab.rawValue)
                            .font(.system(size: 12.5, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundColor(selectedTab == tab ? .ypText1 : .ypText2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectedTab == tab ? Color.ypPillLavender : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .writingStyle: WritingStyleTab()
        case .models: ModelsTab()
        case .hotkeys: HotkeysTab()
        case .general: GeneralTab()
        case .style: StyleTab()
        case .dictionary: DictionaryTab()
        case .history: HistoryTab()
        case .analytics: AnalyticsTab()
        case .about: AboutTab()
        }
    }
}
