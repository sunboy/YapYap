import Foundation

enum AppCategory: String, Codable, CaseIterable, Identifiable {
    case personalMessaging
    case workMessaging
    case email
    case codeEditor
    case browser
    case documents
    case aiChat
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .personalMessaging: return "Personal Messaging"
        case .workMessaging: return "Work Messaging"
        case .email: return "Email"
        case .codeEditor: return "Code Editor"
        case .browser: return "Browser"
        case .documents: return "Documents"
        case .aiChat: return "AI Chat"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .personalMessaging: return "bubble.left.fill"
        case .workMessaging: return "briefcase.fill"
        case .email: return "envelope.fill"
        case .codeEditor: return "desktopcomputer"
        case .browser: return "globe"
        case .documents: return "doc.fill"
        case .aiChat: return "cpu"
        case .other: return "gearshape.fill"
        }
    }
    
    var emoji: String {
        switch self {
        case .personalMessaging: return "💬"
        case .workMessaging: return "💼"
        case .email: return "✉️"
        case .codeEditor: return "🖥️"
        case .browser: return "🌐"
        case .documents: return "📄"
        case .aiChat: return "🤖"
        case .other: return "⚙️"
        }
    }

    var exampleApps: String {
        switch self {
        case .personalMessaging: return "iMessage, WhatsApp, Telegram, Signal"
        case .workMessaging: return "Slack, Teams, Discord"
        case .email: return "Mail, Gmail, Outlook, Superhuman"
        case .codeEditor: return "Cursor, VS Code, Xcode, Windsurf"
        case .browser: return "Safari, Chrome, Firefox, Arc"
        case .documents: return "Pages, Notion, Obsidian, Notes"
        case .aiChat: return "ChatGPT, Claude, Perplexity"
        case .other: return "Other applications"
        }
    }

    var availableStyles: [OutputStyle] {
        switch self {
        case .personalMessaging: return [.veryCasual, .casual, .excited, .formal]
        case .workMessaging: return [.casual, .excited, .formal]
        case .email: return [.casual, .excited, .formal]
        case .codeEditor: return [.casual, .formal]
        case .documents: return [.casual, .formal]
        case .aiChat: return [.casual, .formal]
        case .browser: return [.casual, .excited, .formal]
        case .other: return [.casual, .formal]
        }
    }

    var defaultStyle: OutputStyle {
        switch self {
        case .personalMessaging: return .casual
        case .workMessaging: return .casual
        case .email: return .formal
        case .codeEditor: return .formal
        case .documents: return .formal
        case .aiChat: return .casual
        case .browser: return .casual
        case .other: return .casual
        }
    }
}
