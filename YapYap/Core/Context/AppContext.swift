// AppContext.swift
// YapYap — Detected app context for adaptive formatting
import Foundation

struct AppContext {
    let bundleId: String
    let appName: String
    let category: AppCategory
    let style: OutputStyle
    let windowTitle: String?
    let focusedFieldText: String?
    let isIDEChatPanel: Bool
}
