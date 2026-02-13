import SwiftUI

struct GeneralTab: View {
    @State private var launchAtLogin = true
    @State private var showFloatingBar = true
    @State private var autoPaste = true
    @State private var copyToClipboard = true
    @State private var notifyOnComplete = false
    @State private var selectedMic = "MacBook Pro Microphone (Built-in)"
    @State private var floatingBarPosition = "Bottom center"
    @State private var historyLimit = "Last 100"

    private let micOptions = ["MacBook Pro Microphone (Built-in)", "AirPods Pro"]
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
