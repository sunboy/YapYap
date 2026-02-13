import SwiftUI

struct WritingStyleTab: View {
    @State private var language = "English (US)"
    @State private var formality = "Casual — like texting a friend"
    @State private var stylePrompt = "Write like a senior engineer — concise, direct, no fluff. Prefer short sentences. Skip pleasantries."
    @State private var cleanupLevel = "Medium — restructure sentences, improve clarity"

    private let languages = ["English (US)", "English (UK)", "Spanish", "French", "German", "Hindi", "Japanese"]
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

            // Language
            formGroup(label: "WRITING LANGUAGE") {
                Picker("", selection: $language) {
                    ForEach(languages, id: \.self) { Text($0) }
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
                    .background(Color.ypInput)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.ypBorder, lineWidth: 1))
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
