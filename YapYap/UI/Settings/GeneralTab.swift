import SwiftUI
import SwiftData
import AVFoundation

struct GeneralTab: View {
    @State private var launchAtLogin = true
    @State private var showFloatingBar = true
    @State private var autoPaste = true
    @State private var copyToClipboard = true
    @State private var notifyOnComplete = false
    @State private var experimentalPrompts = false
    @State private var selectedMic = "Default"
    @State private var floatingBarPosition = "Bottom center"
    @State private var historyLimit = "Last 100"
    @State private var micOptions: [String] = ["Default"]

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

            Text("EXPERIMENTAL")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.ypText2)
                .tracking(0.8)
                .padding(.bottom, 8)

            toggleRow(label: "Detailed prompts for small models", subtitle: "Use 3B+ model prompts on ≤1B models (may reduce accuracy)", isOn: $experimentalPrompts)

            divider

            dropdownRow(label: "MICROPHONE", options: micOptions, selection: $selectedMic)
            dropdownRow(label: "FLOATING BAR POSITION", options: positions, selection: $floatingBarPosition)
            dropdownRow(label: "TRANSCRIPTION HISTORY", options: historyOptions, selection: $historyLimit)
        }
        .onAppear {
            enumerateMicrophones()
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
        .onChange(of: experimentalPrompts) { _, newValue in
            saveSettings { $0.experimentalPrompts = newValue }
        }
        .onChange(of: floatingBarPosition) { _, newValue in
            saveSettings { $0.floatingBarPosition = newValue }
        }
        .onChange(of: historyLimit) { _, newValue in
            saveSettings { $0.historyLimit = historyLimitToInt(newValue) }
        }
        .onChange(of: selectedMic) { _, newValue in
            let micId = newValue == "Default" ? nil : newValue
            saveSettings { $0.microphoneId = micId }
        }
    }

    private func enumerateMicrophones() {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices

        var options = ["Default"]
        for device in devices {
            options.append(device.localizedName)
        }
        micOptions = options
    }

    private func loadSettings() {
        let settings = DataManager.shared.fetchSettings()
        launchAtLogin = settings.launchAtLogin
        showFloatingBar = settings.showFloatingBar
        autoPaste = settings.autoPaste
        copyToClipboard = settings.copyToClipboard
        notifyOnComplete = settings.notifyOnComplete
        experimentalPrompts = settings.experimentalPrompts
        floatingBarPosition = settings.floatingBarPosition
        historyLimit = intToHistoryLimit(settings.historyLimit)

        // Load saved mic selection
        if let micId = settings.microphoneId, micOptions.contains(micId) {
            selectedMic = micId
        } else {
            selectedMic = "Default"
        }
    }

    private func saveSettings(_ update: (AppSettings) -> Void) {
        let settings = DataManager.shared.fetchSettings()
        update(settings)
        try? DataManager.shared.container.mainContext.save()
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
