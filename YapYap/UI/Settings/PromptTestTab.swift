// PromptTestTab.swift
// YapYap — Debug view to inspect LLM prompts without recording
import SwiftUI
import SwiftData

struct PromptTestTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var inputText = "so um I was thinking we should like have a meeting tomorrow to uh discuss the project timeline"
    @State private var systemPrompt = ""
    @State private var userPrompt = ""
    @State private var selectedCategory: AppCategory = .other
    @State private var selectedLevel = "medium"
    @State private var selectedFormality = "neutral"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Test what prompt the LLM receives for a given transcription.")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)

            // Input
            VStack(alignment: .leading, spacing: 4) {
                Text("Raw Transcription")
                    .font(.system(size: 11, weight: .semibold))
                TextEditor(text: $inputText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.ypText1)
                    .scrollContentBackground(.hidden)
                    .frame(height: 60)
                    .padding(4)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(6)
            }

            // Controls
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("App Category").font(.system(size: 10, weight: .medium))
                    Picker("", selection: $selectedCategory) {
                        ForEach(AppCategory.allCases) { cat in
                            Text(cat.displayName).tag(cat)
                        }
                    }
                    .frame(width: 150)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cleanup Level").font(.system(size: 10, weight: .medium))
                    Picker("", selection: $selectedLevel) {
                        Text("Light").tag("light")
                        Text("Medium").tag("medium")
                        Text("Heavy").tag("heavy")
                    }
                    .frame(width: 100)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Formality").font(.system(size: 10, weight: .medium))
                    Picker("", selection: $selectedFormality) {
                        Text("Casual").tag("casual")
                        Text("Neutral").tag("neutral")
                        Text("Formal").tag("formal")
                    }
                    .frame(width: 100)
                }
                Spacer()
                Button("Generate Prompt") { generatePrompt() }
                    .buttonStyle(.borderedProminent)
            }

            if !systemPrompt.isEmpty {
                // System prompt
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("System Prompt")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text("\(systemPrompt.count) chars")
                            .font(.system(size: 10))
                            .foregroundColor(.ypText3)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(systemPrompt, forType: .string)
                        }
                        .font(.system(size: 10))
                    }
                    ScrollView {
                        Text(systemPrompt)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 120)
                    .padding(6)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(6)
                }

                // User prompt
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("User Prompt")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text("\(userPrompt.count) chars")
                            .font(.system(size: 10))
                            .foregroundColor(.ypText3)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(userPrompt, forType: .string)
                        }
                        .font(.system(size: 10))
                    }
                    ScrollView {
                        Text(userPrompt)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 120)
                    .padding(6)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(6)
                }
            }
        }
    }

    private func generatePrompt() {
        let settings = fetchSettings()
        let appContext = AppContext(
            bundleId: "com.test.app",
            appName: "TestApp",
            category: selectedCategory,
            style: .casual,
            windowTitle: nil,
            focusedFieldText: nil,
            isIDEChatPanel: false
        )

        let context = CleanupContext(
            stylePrompt: settings.stylePrompt,
            formality: CleanupContext.Formality(rawValue: selectedFormality) ?? .neutral,
            language: settings.language,
            appContext: appContext,
            cleanupLevel: CleanupContext.CleanupLevel(rawValue: selectedLevel) ?? .medium,
            removeFillers: true,
            experimentalPrompts: settings.experimentalPrompts
        )

        let messages = CleanupPromptBuilder.buildMessages(
            rawText: inputText,
            context: context,
            modelId: settings.llmModelId
        )

        systemPrompt = messages.system
        userPrompt = messages.user
    }

    private func fetchSettings() -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        return (try? modelContext.fetch(descriptor).first) ?? AppSettings()
    }
}
