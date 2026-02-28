import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case writing = "Writing"
    case models = "Models"
    case dictionary = "Dictionary"
    case shortcuts = "Shortcuts"
    case general = "General"
    case activity = "Activity"
    case about = "About"

    var id: String { rawValue }

    var sfIcon: String {
        switch self {
        case .writing: return "textformat"
        case .models: return "cpu"
        case .dictionary: return "text.book.closed"
        case .shortcuts: return "keyboard"
        case .general: return "gearshape"
        case .activity: return "chart.bar"
        case .about: return "info.circle"
        }
    }

    var section: String {
        switch self {
        case .writing, .models, .dictionary: return "CORE"
        case .shortcuts, .general: return "PREFERENCES"
        case .activity, .about: return "INFO"
        }
    }
}

struct SettingsView: View {
    let appState: AppState?
    @State private var selectedTab: SettingsTab = .writing
    @State private var hoveredTab: SettingsTab? = nil

    var body: some View {
        ZStack {
            AmbientGlowBackground(layers: glowForTab(selectedTab))

            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
                tabContent
            }
        }
        .frame(width: 860, height: 580)
        .animation(.easeInOut(duration: 0.5), value: selectedTab)
    }

    // MARK: - Per-tab ambient glow

    private func glowForTab(_ tab: SettingsTab) -> [AmbientGlowBackground.GlowLayer] {
        switch tab {
        case .writing:
            return [
                .init(color: .ypLavender, x: 0.3, y: 0.4, radius: 350),
                .init(color: .ypZzz, x: 0.8, y: 0.2, radius: 220)
            ]
        case .models:
            return [
                .init(color: .ypWarm, x: 0.2, y: 0.3, radius: 300),
                .init(color: .ypLavender, x: 0.75, y: 0.7, radius: 250)
            ]
        case .dictionary:
            return [
                .init(color: .ypMint, x: 0.4, y: 0.4, radius: 320),
                .init(color: .ypZzz, x: 0.8, y: 0.8, radius: 200)
            ]
        case .shortcuts:
            return [
                .init(color: .ypZzz, x: 0.3, y: 0.5, radius: 300),
                .init(color: .ypLavender, x: 0.7, y: 0.3, radius: 220)
            ]
        case .general:
            return [
                .init(color: .ypLavender, x: 0.5, y: 0.5, radius: 350)
            ]
        case .activity:
            return [
                .init(color: .ypMint, x: 0.2, y: 0.3, radius: 280),
                .init(color: .ypWarm, x: 0.8, y: 0.6, radius: 250)
            ]
        case .about:
            return [
                .init(color: .ypLavender, x: 0.5, y: 0.3, radius: 300),
                .init(color: .ypMint, x: 0.3, y: 0.7, radius: 200)
            ]
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 44)

            // Brand header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.ypLavender.opacity(0.1))
                        .frame(width: 38, height: 38)
                    CreatureView(state: .sleeping, size: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("YapYap")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.ypText1)
                    Text("Settings")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.ypText3)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 28)

            // Navigation
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach([SettingsTab.writing, .models, .dictionary], id: \.id) { tab in
                        navItem(tab)
                    }

                    sectionDivider

                    ForEach([SettingsTab.shortcuts, .general], id: \.id) { tab in
                        navItem(tab)
                    }

                    sectionDivider

                    ForEach([SettingsTab.activity, .about], id: \.id) { tab in
                        navItem(tab)
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer()

            // Footer
            VStack(spacing: 6) {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .padding(.horizontal, 18)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.ypMint)
                        .frame(width: 5, height: 5)
                    Text("100% offline")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.ypText4)
                }
                .padding(.top, 8)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("v\(version)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.ypText4)
                }
            }
            .padding(.bottom, 16)
        }
        .frame(width: 220)
        .background(Color(hex: "1E1A30"))
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.05))
            .frame(height: 1)
            .padding(.horizontal, 6)
            .padding(.vertical, 12)
    }

    private func navItem(_ tab: SettingsTab) -> some View {
        let isActive = selectedTab == tab
        let isHovered = hoveredTab == tab

        return HStack(spacing: 10) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isActive ? Color.ypLavender : Color.clear)
                .frame(width: 3, height: 16)

            Image(systemName: tab.sfIcon)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .ypLavender : .ypText3)
                .frame(width: 16)

            Text(tab.rawValue)
                .font(.system(size: 13, weight: isActive ? .medium : .regular, design: .rounded))
                .foregroundColor(isActive ? .ypText1 : (isHovered ? .ypText2 : .ypText3))

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.ypLavender.opacity(0.08))
            } else if isHovered {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.03))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab } }
        .onHover { hovering in hoveredTab = hovering ? tab : nil }
    }

    // MARK: - Tab Content

    private var tabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Tab header
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedTab.rawValue)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.ypText1)

                    Text(tabSubtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.ypText3)
                }
                .padding(.bottom, 28)

                currentTabView
            }
            .padding(32)
        }
        .background(Color(hex: "262140"))
        .frame(maxWidth: .infinity)
    }

    private var tabSubtitle: String {
        switch selectedTab {
        case .writing: return "Control how your voice becomes text"
        case .models: return "Choose your speech and cleanup models"
        case .dictionary: return "Teach YapYap your vocabulary"
        case .shortcuts: return "Customize your keyboard shortcuts"
        case .general: return "App behavior and preferences"
        case .activity: return "Your transcription history and stats"
        case .about: return "About YapYap"
        }
    }

    @ViewBuilder
    private var currentTabView: some View {
        switch selectedTab {
        case .writing: WritingTab()
        case .models: ModelsTab(appState: appState)
        case .dictionary: DictionaryTab()
        case .shortcuts: HotkeysTab()
        case .general: GeneralTab()
        case .activity: ActivityTab()
        case .about: AboutTab()
        }
    }
}
