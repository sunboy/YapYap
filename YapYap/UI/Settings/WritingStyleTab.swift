import SwiftUI
import SwiftData

struct WritingStyleTab: View {
    @State private var language = "English (US)"
    @State private var formality = "Casual — like texting a friend"
    @State private var stylePrompt = "Write like a senior engineer — concise, direct, no fluff. Prefer short sentences. Skip pleasantries."
    @State private var cleanupLevel = "Medium — restructure sentences, improve clarity"
    @State private var availableLanguages: [String] = ["English (US)"]
    @State private var didLoadSettings = false

    private let formalities = [
        "Casual — like texting a friend",
        "Neutral — everyday professional",
        "Formal — polished and precise"
    ]
    private let cleanupLevels = [
        "Light — fix grammar, keep my words",
        "Medium — restructure sentences, improve clarity",
        "Heavy — full rewrite matching my style"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How should YapYap write for you?")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.ypText1)
                .padding(.bottom, 4)

            Text("Configure how your speech gets cleaned up and formatted.")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)
                .padding(.bottom, 20)

            // Language — dynamically filtered by selected STT + LLM model capabilities
            formGroup(label: "WRITING LANGUAGE") {
                Picker("", selection: $language) {
                    ForEach(availableLanguages, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            // Formality
            formGroup(label: "FORMALITY") {
                Picker("", selection: $formality) {
                    ForEach(formalities, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            // Custom Style Prompt
            formGroup(label: "CUSTOM STYLE PROMPT", description: "Give YapYap instructions about your writing voice. Passed to the cleanup model.") {
                TextEditor(text: $stylePrompt)
                    .font(.system(size: 13))
                    .foregroundColor(.ypText1)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 80)
                    .background(Color.white.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.ypBorder, lineWidth: 1))
                    .cornerRadius(6)
            }

            // Cleanup Level
            formGroup(label: "CLEANUP LEVEL") {
                Picker("", selection: $cleanupLevel) {
                    ForEach(cleanupLevels, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            // Preview
            previewCard
        }
        .onAppear {
            loadSettings()
        }
        .onChange(of: language) { _, newValue in
            guard didLoadSettings else { return }
            saveSettings { $0.language = languageToCode(newValue) }
        }
        .onChange(of: formality) { _, newValue in
            guard didLoadSettings else { return }
            saveSettings { $0.formality = formalityToValue(newValue) }
        }
        .onChange(of: stylePrompt) { _, newValue in
            guard didLoadSettings else { return }
            saveSettings { $0.stylePrompt = newValue }
        }
        .onChange(of: cleanupLevel) { _, newValue in
            guard didLoadSettings else { return }
            saveSettings { $0.cleanupLevel = cleanupLevelToValue(newValue) }
        }
    }

    private func loadSettings() {
        let settings = DataManager.shared.fetchSettings()
        formality = valueToFormality(settings.formality)
        stylePrompt = settings.stylePrompt
        cleanupLevel = valueToCleanupLevel(settings.cleanupLevel)

        // Compute available languages from intersection of STT and LLM model capabilities
        availableLanguages = Self.computeAvailableLanguages(
            sttModelId: settings.sttModelId,
            llmModelId: settings.llmModelId
        )

        let currentLang = codeToLanguage(settings.language)
        if availableLanguages.contains(currentLang) {
            language = currentLang
        } else {
            // Current language not supported by model combo — reset to English
            language = "English (US)"
            saveSettings { $0.language = "en" }
        }
        didLoadSettings = true
    }

    private func saveSettings(_ update: @escaping (AppSettings) -> Void) {
        DataManager.shared.updateSettings(update)
    }

    /// Compute available languages as the intersection of the selected STT and LLM models
    static func computeAvailableLanguages(sttModelId: String, llmModelId: String) -> [String] {
        let sttLanguages = STTModelRegistry.model(for: sttModelId)?.languages ?? ["en"]
        let llmLanguages = LLMModelRegistry.model(for: llmModelId)?.languages ?? ["en"]

        let sttSet = Set(sttLanguages)
        let llmSet = Set(llmLanguages)
        let intersection = sttSet.intersection(llmSet)

        // Map codes to display names, preserving a stable order
        let allDisplayLanguages: [(code: String, display: String)] = [
            ("en", "English (US)"),
            ("es", "Spanish"),
            ("fr", "French"),
            ("de", "German"),
            ("it", "Italian"),
            ("pt", "Portuguese"),
            ("zh", "Chinese"),
            ("ja", "Japanese"),
            ("ko", "Korean"),
            ("hi", "Hindi"),
        ]

        let result = allDisplayLanguages
            .filter { intersection.contains($0.code) }
            .map { $0.display }

        return result.isEmpty ? ["English (US)"] : result
    }

    // Language conversion helpers
    private func languageToCode(_ display: String) -> String {
        switch display {
        case "English (US)": return "en"
        case "English (UK)": return "en-GB"
        case "Spanish": return "es"
        case "French": return "fr"
        case "German": return "de"
        case "Italian": return "it"
        case "Portuguese": return "pt"
        case "Chinese": return "zh"
        case "Hindi": return "hi"
        case "Japanese": return "ja"
        case "Korean": return "ko"
        default: return "en"
        }
    }

    private func codeToLanguage(_ code: String) -> String {
        switch code {
        case "en": return "English (US)"
        case "en-GB": return "English (UK)"
        case "es": return "Spanish"
        case "fr": return "French"
        case "de": return "German"
        case "it": return "Italian"
        case "pt": return "Portuguese"
        case "zh": return "Chinese"
        case "hi": return "Hindi"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        default: return "English (US)"
        }
    }

    // Formality conversion helpers
    private func formalityToValue(_ display: String) -> String {
        if display.hasPrefix("Casual") { return "casual" }
        if display.hasPrefix("Neutral") { return "neutral" }
        if display.hasPrefix("Formal") { return "formal" }
        return "neutral"
    }

    private func valueToFormality(_ value: String) -> String {
        switch value {
        case "casual": return "Casual — like texting a friend"
        case "neutral": return "Neutral — everyday professional"
        case "formal": return "Formal — polished and precise"
        default: return "Neutral — everyday professional"
        }
    }

    // Cleanup level conversion helpers
    private func cleanupLevelToValue(_ display: String) -> String {
        if display.hasPrefix("Light") { return "light" }
        if display.hasPrefix("Medium") { return "medium" }
        if display.hasPrefix("Heavy") { return "heavy" }
        return "medium"
    }

    private func valueToCleanupLevel(_ value: String) -> String {
        switch value {
        case "light": return "Light — fix grammar, keep my words"
        case "medium": return "Medium — restructure sentences, improve clarity"
        case "heavy": return "Heavy — full rewrite matching my style"
        default: return "Medium — restructure sentences, improve clarity"
        }
    }

    private func formGroup<Content: View>(label: String, description: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.ypText2)
                .tracking(0.8)

            if let desc = description {
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundColor(.ypText3)
                    .lineSpacing(2)
            }

            content()
        }
        .padding(.bottom, 24)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PREVIEW")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.ypText3)
                .tracking(0.8)

            // Before
            Text("so basically I was thinking that maybe we should like revisit the whole onboarding thing because um the drop off is pretty bad")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)
                .lineSpacing(4)
                .strikethrough(color: Color.ypRed.opacity(0.3))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ypPillRed)
                .overlay(
                    Rectangle().fill(Color.ypRed).frame(width: 2),
                    alignment: .leading
                )
                .cornerRadius(6)

            // Arrow
            Text("↓ YapYap cleanup ↓")
                .font(.system(size: 10))
                .foregroundColor(.ypText4)
                .frame(maxWidth: .infinity)

            // After
            Text("We should revisit the onboarding flow. Drop-off rate is too high — the current setup has too many steps before users reach value.")
                .font(.system(size: 12))
                .foregroundColor(.ypText2)
                .lineSpacing(4)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ypPillMint)
                .overlay(
                    Rectangle().fill(Color.ypMint).frame(width: 2),
                    alignment: .leading
                )
                .cornerRadius(6)
        }
        .padding(14)
        .background(Color.ypCard)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ypBorderLight, lineWidth: 1))
        .cornerRadius(10)
    }
}
