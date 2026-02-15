import SwiftUI
import SwiftData

struct GeneralTab: View {
    @State private var launchAtLogin = true
    @State private var showFloatingBar = true
    @State private var autoPaste = true
    @State private var copyToClipboard = true
    @State private var notifyOnComplete = false
    @State private var selectedMic = "Default"
    @State private var floatingBarPosition = "Bottom center"
    @State private var historyLimit = "Last 100"

    private let micOptions = ["Default", "MacBook Pro Microphone (Built-in)", "AirPods Pro"]
    private let positions = ["Bottom center", "Bottom left", "Bottom right", "Top center"]
    private let historyOptions = ["Last 50", "Last 100", "Last 500", "Keep all", "Don't save"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("General Settings")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.ypText1)
                .padding(.bottom, 4)
            Text("Configure app behavior and appearance.")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)
                .padding(.bottom, 20)

            toggleRow(label: "Launch at login", subtitle: "Start YapYap when you log in", isOn: $launchAtLogin)
            toggleRow(label: "Show floating bar", subtitle: "Display creature bar while recording", isOn: $showFloatingBar)
            toggleRow(label: "Auto-paste after transcription", subtitle: "Paste into active text field", isOn: $autoPaste)
            toggleRow(label: "Copy to clipboard", subtitle: "Also copy result to clipboard", isOn: $copyToClipboard)
            toggleRow(label: "Notification on complete", subtitle: "macOS notification when done", isOn: $notifyOnComplete)

            divider

            dropdownRow(label: "MICROPHONE", options: micOptions, selection: $selectedMic)
            dropdownRow(label: "FLOATING BAR POSITION", options: positions, selection: $floatingBarPosition)
            dropdownRow(label: "TRANSCRIPTION HISTORY", options: historyOptions, selection: $historyLimit)
        }
        .onAppear {
            loadSettings()
        }
        .onChange(of: launchAtLogin) { _, newValue in
            saveSettings { $0.launchAtLogin = newValue }
        }
        .onChange(of: showFloatingBar) { _, newValue in
            saveSettings { $0.showFloatingBar = newValue }
        }
        .onChange(of: autoPaste) { _, newValue in
            saveSettings { $0.autoPaste = newValue }
        }
        .onChange(of: copyToClipboard) { _, newValue in
            saveSettings { $0.copyToClipboard = newValue }
        }
        .onChange(of: notifyOnComplete) { _, newValue in
            saveSettings { $0.notifyOnComplete = newValue }
        }
        .onChange(of: floatingBarPosition) { _, newValue in
            saveSettings { $0.floatingBarPosition = newValue }
        }
        .onChange(of: historyLimit) { _, newValue in
            saveSettings { $0.historyLimit = historyLimitToInt(newValue) }
        }
    }

    private func loadSettings() {
        Task { @MainActor in
            let settings = DataManager.shared.fetchSettings()
            launchAtLogin = settings.launchAtLogin
            showFloatingBar = settings.showFloatingBar
            autoPaste = settings.autoPaste
            copyToClipboard = settings.copyToClipboard
            notifyOnComplete = settings.notifyOnComplete
            floatingBarPosition = settings.floatingBarPosition
            historyLimit = intToHistoryLimit(settings.historyLimit)
        }
    }

    private func saveSettings(_ update: @escaping (AppSettings) -> Void) {
        Task { @MainActor in
            let settings = DataManager.shared.fetchSettings()
            update(settings)
            // Settings are automatically saved by SwiftData context
            try? DataManager.shared.container.mainContext.save()
        }
    }

    private func historyLimitToInt(_ str: String) -> Int {
        switch str {
        case "Last 50": return 50
        case "Last 100": return 100
        case "Last 500": return 500
        case "Keep all": return -1
        case "Don't save": return 0
        default: return 100
        }
    }

    private func intToHistoryLimit(_ int: Int) -> String {
        switch int {
        case 50: return "Last 50"
        case 100: return "Last 100"
        case 500: return "Last 500"
        case -1: return "Keep all"
        case 0: return "Don't save"
        default: return "Last 100"
        }
    }

    private func toggleRow(label: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13)).foregroundColor(.ypText2)
                Text(subtitle).font(.system(size: 11)).foregroundColor(.ypText3)
            }
            Spacer()
            Toggle("", isOn: isOn).toggleStyle(YPToggleStyle())
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.ypBorderLight).frame(height: 1)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.ypBorderLight)
            .frame(height: 1)
            .padding(.vertical, 24)
    }

    private func dropdownRow(label: String, options: [String], selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.ypText2)
                .tracking(0.8)
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { Text($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .padding(.bottom, 24)
    }
}
