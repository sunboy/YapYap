// StyleSettings.swift
// YapYap — Per-category style preferences
import Foundation

struct StyleSettings: Codable {
    var personalMessaging: OutputStyle = .casual
    var workMessaging: OutputStyle = .casual
    var email: OutputStyle = .formal
    var codeEditor: OutputStyle = .formal
    var documents: OutputStyle = .formal
    var aiChat: OutputStyle = .casual
    var browser: OutputStyle = .casual
    var terminal: OutputStyle = .casual
    var notes: OutputStyle = .casual
    var social: OutputStyle = .casual
    var other: OutputStyle = .casual

    var ideVariableRecognition: Bool = true
    var ideFileTagging: Bool = true

    // Migration-safe: stored as optional, exposed as non-optional with default
    private var _notesTodoConversion: Bool?
    var notesTodoConversion: Bool {
        get { _notesTodoConversion ?? true }
        set { _notesTodoConversion = newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case personalMessaging, workMessaging, email, codeEditor, documents
        case aiChat, browser, terminal, notes, social, other
        case ideVariableRecognition, ideFileTagging
        case appCategoryOverrides
        case _notesTodoConversion = "notesTodoConversion"
    }

    var appCategoryOverrides: [String: AppCategory] = [:]

    func styleFor(_ category: AppCategory) -> OutputStyle {
        switch category {
        case .personalMessaging: return personalMessaging
        case .workMessaging: return workMessaging
        case .email: return email
        case .codeEditor: return codeEditor
        case .documents: return documents
        case .aiChat: return aiChat
        case .browser: return browser
        case .terminal: return terminal
        case .notes: return notes
        case .social: return social
        case .other: return other
        }
    }

    /// Load user-saved style settings from UserDefaults, or return defaults.
    static func loadFromUserDefaults() -> StyleSettings {
        guard let data = UserDefaults.standard.data(forKey: "yapyap.styleSettings") else {
            return StyleSettings()
        }
        do {
            return try JSONDecoder().decode(StyleSettings.self, from: data)
        } catch {
            NSLog("[StyleSettings] ⚠️ Failed to decode saved settings, using defaults: \(error)")
            return StyleSettings()
        }
    }
}
