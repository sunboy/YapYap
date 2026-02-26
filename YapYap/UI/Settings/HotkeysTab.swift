import SwiftUI
import SwiftData
import KeyboardShortcuts

struct HotkeysTab: View {
    @State private var doubleTap = false
    @State private var soundFeedback = true
    @State private var hapticFeedback = true
    @State private var didLoadSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Keyboard Shortcuts")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.ypText1)
                .padding(.bottom, 4)
            Text("Click a shortcut to record a new key combination.")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)
                .padding(.bottom, 20)

            hotkeyRow(name: .pushToTalk, label: "PUSH-TO-TALK (HOLD)", description: "Hold to record. Release to transcribe and paste.")
            hotkeyRow(name: .handsFreeMode, label: "HANDS-FREE MODE (TOGGLE)", description: "Press once to start, again to stop.")
            hotkeyRow(name: .commandMode, label: "COMMAND MODE", description: "Highlight text first, then speak a command to rewrite.")
            hotkeyRow(name: .cancelRecording, label: "CANCEL RECORDING", description: "Abort without pasting.")

            Button("Reset to Defaults") {
                KeyboardShortcuts.reset(.pushToTalk, .handsFreeMode, .commandMode, .cancelRecording)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, design: .rounded))
            .foregroundColor(.ypText3)
            .padding(.bottom, 20)

            toggleRow(label: "Double-tap activation", subtitle: "Double-tap ⌥ for hands-free", isOn: $doubleTap)
            toggleRow(label: "Sound feedback", subtitle: "Subtle sound on start/stop", isOn: $soundFeedback)
            toggleRow(label: "Haptic feedback", subtitle: "Trackpad vibration (MacBook only)", isOn: $hapticFeedback)
        }
        .onAppear {
            loadSettings()
        }
        .onChange(of: doubleTap) { _, newValue in
            guard didLoadSettings else { return }
            saveSettings { $0.doubleTapActivation = newValue }
        }
        .onChange(of: soundFeedback) { _, newValue in
            guard didLoadSettings else { return }
            saveSettings { $0.soundFeedback = newValue }
            SoundManager.shared.setEnabled(newValue)
        }
        .onChange(of: hapticFeedback) { _, newValue in
            guard didLoadSettings else { return }
            saveSettings { $0.hapticFeedback = newValue }
            HapticManager.shared.setEnabled(newValue)
        }
    }

    private func loadSettings() {
        Task { @MainActor in
            let settings = DataManager.shared.fetchSettings()
            doubleTap = settings.doubleTapActivation
            soundFeedback = settings.soundFeedback
            hapticFeedback = settings.hapticFeedback
            didLoadSettings = true
        }
    }

    private func saveSettings(_ update: @escaping (AppSettings) -> Void) {
        Task { @MainActor in
            let settings = DataManager.shared.fetchSettings()
            update(settings)
            DataManager.shared.saveSettings()
        }
    }

    private func hotkeyRow(name: KeyboardShortcuts.Name, label: String, description: String) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.ypText2)
                    .tracking(0.8)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.ypText3)
            }
            Spacer()
            KeyboardShortcuts.Recorder(for: name)
        }
        .glassRow()
        .padding(.bottom, 6)
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
        .glassRow()
        .padding(.bottom, 6)
    }
}
