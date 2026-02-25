import SwiftUI

struct PopoverView: View {
    let appState: AppState

    @State private var currentSTTModelName: String = ""
    @State private var currentLLMModelName: String = ""
    @State private var currentLanguage: String = "English"
    @State private var copyToClipboard: Bool = true

    // Correction editing state
    @State private var isEditingTranscription = false
    @State private var editableTranscription = ""
    @State private var learnedMessage: String?

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
        .onAppear {
            appState.updateStats()
            refreshSettingsState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .yapSettingsChanged)) { _ in
            refreshSettingsState()
        }
    }

    private func refreshSettingsState() {
        let settings = DataManager.shared.fetchSettings()
        currentSTTModelName = STTModelRegistry.model(for: settings.sttModelId)?.name ?? settings.sttModelId
        // Only show the LLM model name if it's actually loaded and active
        if let activeId = appState.activeLLMModelId {
            currentLLMModelName = LLMModelRegistry.model(for: activeId)?.name ?? activeId
        } else {
            currentLLMModelName = "Not loaded"
        }
        currentLanguage = Self.languageDisplayName(for: settings.language)
        copyToClipboard = settings.copyToClipboard
    }

    private static func languageDisplayName(for code: String) -> String {
        switch code {
        case "en", "en-GB": return "English"
        case "es": return "Spanish"
        case "fr": return "French"
        case "de": return "German"
        case "it": return "Italian"
        case "pt": return "Portuguese"
        case "zh": return "Chinese"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case "hi": return "Hindi"
        default: return "English"
        }
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
            .toggleStyle(YPToggleStyle())
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
            HStack {
                Text("LAST TRANSCRIPTION")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.ypText3)
                    .tracking(0.8)

                Spacer()

                if !isEditingTranscription {
                    Button(action: {
                        editableTranscription = text
                        isEditingTranscription = true
                        learnedMessage = nil
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(.ypText3)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isEditingTranscription {
                // Editing mode
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $editableTranscription)
                        .font(.system(size: 12))
                        .foregroundColor(.ypText2)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 50, maxHeight: 80)
                        .background(Color.ypCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.ypLavender.opacity(0.5), lineWidth: 1)
                        )
                        .cornerRadius(6)

                    HStack(spacing: 8) {
                        Button(action: learnCorrections) {
                            Text("Learn Corrections")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.ypLavender)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            isEditingTranscription = false
                            learnedMessage = nil
                        }) {
                            Text("Cancel")
                                .font(.system(size: 11))
                                .foregroundColor(.ypText3)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let message = learnedMessage {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundColor(.ypLavender)
                        .transition(.opacity)
                }
            } else {
                // Display mode
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().background(Color.ypBorderLight)
        }
    }

    private func learnCorrections() {
        guard let originalText = appState.lastTranscription else { return }
        let edited = editableTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !edited.isEmpty, edited != originalText else {
            isEditingTranscription = false
            return
        }

        // Diff cleaned text against edited version
        var candidates = CorrectionDiffer.diff(original: originalText, corrected: edited)

        // Also try to map corrections back to raw STT output for better learning
        if let rawText = appState.lastRawTranscription {
            let rawCandidates = CorrectionDiffer.diff(original: rawText, corrected: edited)
            // Add raw-based candidates that aren't duplicates
            let existingOriginals = Set(candidates.map { $0.original.lowercased() })
            for rc in rawCandidates where !existingOriginals.contains(rc.original.lowercased()) {
                candidates.append(rc)
            }
        }

        let dict = PersonalDictionary.shared
        var learned: [String] = []
        for candidate in candidates {
            dict.learnCorrection(
                spoken: candidate.original,
                corrected: candidate.corrected,
                source: .manual
            )
            learned.append("\(candidate.original) \u{2192} \(candidate.corrected)")
        }

        if learned.isEmpty {
            learnedMessage = "No corrections detected"
        } else {
            learnedMessage = "Learned: " + learned.joined(separator: ", ")
        }

        // Update the displayed transcription
        appState.lastTranscription = edited

        // Copy corrected text to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(edited, forType: .string)

        // Dismiss editing after a brief moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isEditingTranscription = false
            learnedMessage = nil
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
                    Text(currentSTTModelName)
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
            .onTapGesture {
                SettingsWindowController.shared.showWindow(nil)
            }

            settingsRow(icon: "✨", label: "Cleanup Model") {
                HStack(spacing: 4) {
                    Text(currentLLMModelName)
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
            .onTapGesture {
                SettingsWindowController.shared.showWindow(nil)
            }

            settingsRow(icon: "🌐", label: "Language") {
                HStack(spacing: 4) {
                    Text(currentLanguage)
                        .font(.system(size: 11))
                        .foregroundColor(.ypText3)
                    Text("›")
                        .font(.system(size: 10))
                        .foregroundColor(.ypText3)
                        .opacity(0.3)
                }
            }
            .onTapGesture {
                SettingsWindowController.shared.showWindow(nil)
            }

            // Divider
            Rectangle()
                .fill(Color.ypBorderLight)
                .frame(height: 1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)

            settingsRow(icon: "📋", label: "Copy to clipboard") {
                Toggle("", isOn: Binding(
                    get: { copyToClipboard },
                    set: { newValue in
                        copyToClipboard = newValue
                        let settings = DataManager.shared.fetchSettings()
                        settings.copyToClipboard = newValue
                        DataManager.shared.saveSettings()
                    }
                ))
                .toggleStyle(YPToggleStyle())
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

// YPToggleStyle is now defined in DesignTokens.swift
