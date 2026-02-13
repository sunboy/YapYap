import SwiftUI

struct PopoverView: View {
    let appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerSection

            // MARK: - Last Transcription
            if let lastText = appState.lastTranscription {
                lastTranscriptionSection(text: lastText)
            }

            // MARK: - Quick Stats
            quickStatsSection

            // MARK: - Quick Settings
            quickSettingsSection

            // MARK: - Footer
            footerSection
        }
        .background(Color.ypBg3)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            CreatureView(state: appState.creatureState, size: 32)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("YapYap")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ypText1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 5, height: 5)
                        .opacity(0.5)

                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundColor(.ypText3)
                }
            }

            Spacer()

            // Master toggle
            Toggle("", isOn: Binding(
                get: { appState.masterToggle },
                set: { appState.masterToggle = $0 }
            ))
            .toggleStyle(YPToggleStyle(width: 36, height: 20))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider().background(Color.ypBorderLight)
        }
    }

    private var statusDotColor: Color {
        switch appState.creatureState {
        case .sleeping: return .ypZzz
        case .recording: return .ypWarm
        case .processing: return .ypLavender
        }
    }

    private var statusText: String {
        switch appState.creatureState {
        case .sleeping: return "Sleeping · ⌥Space to wake"
        case .recording: return "Listening..."
        case .processing: return "Cleaning up..."
        }
    }

    // MARK: - Last Transcription

    private func lastTranscriptionSection(text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LAST TRANSCRIPTION")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.ypText3)
                .tracking(0.8)

            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.ypText2)
                .lineLimit(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ypCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.ypBorderLight, lineWidth: 1)
                )
                .cornerRadius(6)
                .onTapGesture {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().background(Color.ypBorderLight)
        }
    }

    // MARK: - Quick Stats

    private var quickStatsSection: some View {
        HStack(spacing: 8) {
            statColumn(value: "\(appState.todayCount)", label: "TODAY")
            statColumn(value: appState.todayTimeSaved, label: "SAVED")
            statColumn(value: formatWordCount(appState.todayWords), label: "WORDS")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider().background(Color.ypBorderLight)
        }
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.ypText1)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.ypText3)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatWordCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000)
        }
        return "\(count)"
    }

    // MARK: - Quick Settings

    private var quickSettingsSection: some View {
        VStack(spacing: 0) {
            settingsRow(icon: "🎙", label: "STT Model") {
                HStack(spacing: 4) {
                    Text("Whisper")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.ypLavender)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.ypPillLavender)
                        .cornerRadius(4)
                    Text("›")
                        .font(.system(size: 10))
                        .foregroundColor(.ypText3)
                        .opacity(0.3)
                }
            }

            settingsRow(icon: "✨", label: "Cleanup Model") {
                HStack(spacing: 4) {
                    Text("Qwen 2.5")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.ypWarm)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.ypPillWarm)
                        .cornerRadius(4)
                    Text("›")
                        .font(.system(size: 10))
                        .foregroundColor(.ypText3)
                        .opacity(0.3)
                }
            }

            settingsRow(icon: "🌐", label: "Language") {
                HStack(spacing: 4) {
                    Text("English")
                        .font(.system(size: 11))
                        .foregroundColor(.ypText3)
                    Text("›")
                        .font(.system(size: 10))
                        .foregroundColor(.ypText3)
                        .opacity(0.3)
                }
            }

            // Divider
            Rectangle()
                .fill(Color.ypBorderLight)
                .frame(height: 1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)

            settingsRow(icon: "📋", label: "Paste to clipboard") {
                Toggle("", isOn: .constant(true))
                    .toggleStyle(YPToggleStyle(width: 28, height: 16))
            }
        }
        .padding(8)
    }

    private func settingsRow<Content: View>(icon: String, label: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            HStack(spacing: 8) {
                Text(icon)
                    .font(.system(size: 12))
                    .opacity(0.5)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundColor(.ypText2)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 0) {
            Divider().background(Color.ypBorderLight)

            Button(action: { SettingsWindowController.shared.showWindow(nil) }) {
                HStack {
                    HStack(spacing: 8) {
                        Text("⚙️").font(.system(size: 12)).opacity(0.5).frame(width: 16)
                        Text("Settings…").font(.system(size: 12.5)).foregroundColor(.ypText2)
                    }
                    Spacer()
                    Text("⌘ ,")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.ypText4)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .cornerRadius(6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { NSApp.terminate(nil) }) {
                HStack {
                    HStack(spacing: 8) {
                        Text("🚪").font(.system(size: 12)).opacity(0.5).frame(width: 16)
                        Text("Quit YapYap").font(.system(size: 12.5)).foregroundColor(.ypText3)
                    }
                    Spacer()
                    Text("⌘ Q")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.ypText4)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .cornerRadius(6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(8)
    }
}

// MARK: - Custom Toggle Style

struct YPToggleStyle: ToggleStyle {
    var width: CGFloat = 36
    var height: CGFloat = 20

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: height / 2)
                .fill(configuration.isOn ? Color.ypMint : Color.white.opacity(0.12))
                .frame(width: width, height: height)

            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                .frame(width: height - 4, height: height - 4)
                .offset(x: configuration.isOn ? (width / 2 - height / 2) : -(width / 2 - height / 2))
        }
        .animation(.easeInOut(duration: 0.2), value: configuration.isOn)
        .onTapGesture {
            configuration.isOn.toggle()
        }
    }
}
