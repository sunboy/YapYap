import SwiftUI
import SwiftData

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
            Text("Customize how you interact with YapYap.")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)
                .padding(.bottom, 20)

            hotkeyRow(label: "PUSH-TO-TALK (HOLD)", description: "Hold to record. Release to transcribe and paste.", keys: ["⌥", "Space"])
            hotkeyRow(label: "HANDS-FREE MODE (TOGGLE)", description: "Press once to start, again to stop.", keys: ["⌥", "⇧", "Space"])
            hotkeyRow(label: "COMMAND MODE", description: "Highlight text first, then speak a command to rewrite.", keys: ["⌥", "⌘", "Space"])
            hotkeyRow(label: "CANCEL RECORDING", description: "Abort without pasting.", keys: ["Esc"])

            // Divider
            Rectangle()
                .fill(Color.ypBorderLight)
                .frame(height: 1)
                .padding(.vertical, 24)

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

    private func hotkeyRow(label: String, description: String, keys: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.ypText2)
                .tracking(0.8)
            Text(description)
                .font(.system(size: 12))
                .foregroundColor(.ypText3)

            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    if index > 0 {
                        Text("+")
                            .font(.system(size: 10))
                            .foregroundColor(.ypText3)
                    }
                    Text(key)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.ypText1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.ypInput)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.ypBorder, lineWidth: 1))
            .cornerRadius(6)
        }
        .padding(.bottom, 24)
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
}
