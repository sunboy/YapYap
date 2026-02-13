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
    var other: OutputStyle = .casual

    var ideVariableRecognition: Bool = true
    var ideFileTagging: Bool = true

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
        case .other: return other
        }
    }
}
