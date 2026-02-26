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
    case promptTest = "Prompt Test"
    case about = "About"

    var id: String { rawValue }

    var sfIcon: String {
        switch self {
        case .writingStyle: return "pencil.and.outline"
        case .models: return "cpu"
        case .hotkeys: return "keyboard"
        case .general: return "gearshape"
        case .style: return "sparkles"
        case .dictionary: return "text.book.closed"
        case .history: return "clock"
        case .analytics: return "chart.bar"
        case .promptTest: return "testtube.2"
        case .about: return "heart"
        }
    }

    var section: String {
        switch self {
        case .writingStyle, .models, .hotkeys, .general, .style, .dictionary: return "CONFIGURATION"
        case .history, .analytics, .promptTest: return "INSIGHTS"
        case .about: return "APP"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .writingStyle

    var body: some View {
        ZStack {
            AmbientGlowBackground(layers: AmbientGlowBackground.settings)

            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
                tabContent
            }
        }
        .frame(width: 820, height: 560)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Spacer for titlebar traffic lights
            Spacer().frame(height: 44)

            // Brand header
            HStack(spacing: 8) {
                CreatureView(state: .sleeping, size: 24)
                Text("YapYap")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.ypText1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)

            // Navigation
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    sectionHeader("CONFIGURATION")
                    navItem("Writing Style", icon: "pencil.and.outline", tab: .writingStyle)
                    navItem("Models", icon: "cpu", tab: .models)
                    navItem("Hotkeys", icon: "keyboard", tab: .hotkeys)
                    navItem("General", icon: "gearshape", tab: .general)
                    navItem("Style", icon: "sparkles", tab: .style)
                    navItem("Dictionary", icon: "text.book.closed", tab: .dictionary)

                    sectionHeader("INSIGHTS")
                    navItem("History", icon: "clock", tab: .history)
                    navItem("Analytics", icon: "chart.bar", tab: .analytics)
                    navItem("Prompt Test", icon: "testtube.2", tab: .promptTest)

                    sectionHeader("APP")
                    navItem("About", icon: "heart", tab: .about)
                }
                .padding(.horizontal, 8)
            }

            Spacer()

            // Footer
            Text("~ the little one is listening ~")
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(.ypText4)
                .padding(16)
        }
        .frame(width: 200)
        .background(Color(hex: "201C32"))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundColor(.ypText4)
            .tracking(1.2)
            .padding(.horizontal, 10)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    private func navItem(_ label: String, icon: String, tab: SettingsTab) -> some View {
        let isActive = selectedTab == tab
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .ypLavender : .ypText3)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12.5, weight: isActive ? .medium : .regular, design: .rounded))
                .foregroundColor(isActive ? .ypText1 : .ypText2)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.ypLavender.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.ypLavender.opacity(0.25), lineWidth: 1)
                    )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedTab = tab }
    }

    // MARK: - Tab Content

    private var tabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                currentTabView
                    .padding(24)
            }
        }
        .background(Color(hex: "2A2540"))
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var currentTabView: some View {
        switch selectedTab {
        case .writingStyle: WritingStyleTab()
        case .models: ModelsTab()
        case .hotkeys: HotkeysTab()
        case .general: GeneralTab()
        case .style: StyleTab()
        case .dictionary: DictionaryTab()
        case .history: HistoryTab()
        case .analytics: AnalyticsTab()
        case .promptTest: PromptTestTab()
        case .about: AboutTab()
        }
    }
}

