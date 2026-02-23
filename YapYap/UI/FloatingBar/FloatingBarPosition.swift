// FloatingBarPosition.swift
// YapYap — Floating bar screen position options
import Foundation

enum FloatingBarPosition: String, Codable, CaseIterable {
    case bottomCenter
    case bottomLeft
    case bottomRight
    case topCenter

    var displayName: String {
        switch self {
        case .bottomCenter: return "Bottom Center"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .topCenter: return "Top Center"
        }
    }

    /// Map the settings string (e.g. "Bottom center") to enum value
    init(fromSettingsString str: String) {
        switch str.lowercased() {
        case "bottom center": self = .bottomCenter
        case "bottom left": self = .bottomLeft
        case "bottom right": self = .bottomRight
        case "top center": self = .topCenter
        default: self = .bottomCenter
        }
    }
}
