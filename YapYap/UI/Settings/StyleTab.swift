import SwiftUI

struct StyleTab: View {
    @State private var styleSettings = StyleSettingsData()
    @State private var ideVariableRecognition = true
    @State private var ideFileTagging = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Context-Aware Formatting")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.ypText1)
                .padding(.bottom, 4)
            Text("YapYap adjusts formatting based on which app you're using.")
                .font(.system(size: 12))
                .foregroundColor(.ypText3)
                .padding(.bottom, 20)

            ForEach(AppCategory.allCases) { category in
                categoryRow(category: category)
            }

            // IDE section
            Rectangle()
                .fill(Color.ypBorderLight)
                .frame(height: 1)
                .padding(.vertical, 16)

            Text("IDE FEATURES")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.ypText3)
                .tracking(1)
                .padding(.bottom, 12)

            toggleRow(label: "Variable recognition", subtitle: "Wrap camelCase and snake_case in backticks", isOn: $ideVariableRecognition)
            toggleRow(label: "File tagging in chat", subtitle: "Say 'at main.py' → types @main.py in Cursor/Windsurf", isOn: $ideFileTagging)

            Text("These features work in Cursor, Windsurf, VS Code, and Xcode")
                .font(.system(size: 11))
                .foregroundColor(.ypText3)
                .padding(.top, 8)
        }
    }

    private func categoryRow(category: AppCategory) -> some View {
        HStack(spacing: 12) {
            Text(category.emoji)
                .font(.system(size: 16))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.displayName)
                    .font(.system(size: 13))
                    .foregroundColor(.ypText2)
                Text(category.exampleApps)
                    .font(.system(size: 11))
                    .foregroundColor(.ypText3)
            }

            Spacer()

            Picker("", selection: binding(for: category)) {
                ForEach(category.availableStyles) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.ypBorderLight).frame(height: 1)
        }
    }

    private func binding(for category: AppCategory) -> Binding<OutputStyle> {
        Binding(
            get: { styleSettings.style(for: category) },
            set: { styleSettings.setStyle($0, for: category) }
        )
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

// Helper for tab-local state
struct StyleSettingsData {
    var personalMessaging: OutputStyle = .casual
    var workMessaging: OutputStyle = .casual
    var email: OutputStyle = .formal
    var codeEditor: OutputStyle = .formal
    var documents: OutputStyle = .formal
    var aiChat: OutputStyle = .casual
    var browser: OutputStyle = .casual
    var other: OutputStyle = .casual

    func style(for category: AppCategory) -> OutputStyle {
        switch category {
        case .personalMessaging: return personalMessaging
        case .workMessaging: return workMessaging
        case .email: return email
        case .codeEditor: return codeEditor
        case .documents: return documents
        case .aiChat: return aiChat
        case .browser: return browser
        case .other: return other
        }
    }

    mutating func setStyle(_ style: OutputStyle, for category: AppCategory) {
        switch category {
        case .personalMessaging: personalMessaging = style
        case .workMessaging: workMessaging = style
        case .email: email = style
        case .codeEditor: codeEditor = style
        case .documents: documents = style
        case .aiChat: aiChat = style
        case .browser: browser = style
        case .other: other = style
        }
    }
}
