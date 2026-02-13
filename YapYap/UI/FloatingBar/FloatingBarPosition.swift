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
}
