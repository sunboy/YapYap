import Foundation

enum OutputStyle: String, Codable, CaseIterable, Identifiable {
    case veryCasual
    case casual
    case excited
    case formal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .veryCasual: return "Very Casual"
        case .casual: return "Casual"
        case .excited: return "Excited"
        case .formal: return "Formal"
        }
    }

    var previewText: String {
        switch self {
        case .veryCasual: return "hey yeah that sounds good to me"
        case .casual: return "Hey, yeah that sounds good to me"
        case .excited: return "Hey, yeah that sounds good to me!"
        case .formal: return "Hey, that sounds good to me."
        }
    }
}
