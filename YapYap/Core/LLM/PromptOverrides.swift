// PromptOverrides.swift
// YapYap — User-customizable prompt rules per app category
import Foundation

/// Stores user overrides for the per-category prompt rules that CleanupPromptBuilder
/// normally reads from PromptTemplates. When an override exists and is enabled for a
/// category, the builder uses it instead of the hardcoded default.
struct PromptOverrides: Codable {

    /// Per-category overrides. Key is AppCategory.rawValue.
    var categories: [String: CategoryOverride] = [:]

    struct CategoryOverride: Codable, Equatable {
        /// Custom rules text that replaces the built-in AppRules for this category.
        /// For medium/large models these are multi-line rules (prefixed with "-").
        /// For small models a compact 1-2 sentence variant is derived automatically.
        var rules: String

        /// Whether to use the custom rules vs the built-in defaults.
        var isEnabled: Bool = true
    }

    /// Categories that have meaningful prompt rules (browser/other use empty generic defaults).
    static let editableCategories: [AppCategory] = [
        .personalMessaging, .workMessaging, .email, .codeEditor,
        .aiChat, .terminal, .notes, .social, .documents
    ]

    // MARK: - Query

    /// Returns the custom rules for a category if an override exists and is enabled.
    /// Returns nil when the builder should fall back to the hardcoded default.
    func effectiveRules(for category: AppCategory) -> String? {
        guard let override = categories[category.rawValue],
              override.isEnabled,
              !override.rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return override.rules
    }

    /// Returns the default (built-in) rules text for a category.
    /// This is shown in the UI as the starting point for customization.
    static func defaultRules(for category: AppCategory) -> String {
        PromptTemplates.AppRules.medium(for: category)
    }

    /// Returns the default small-model rules text for a category.
    static func defaultSmallRules(for category: AppCategory) -> String {
        PromptTemplates.AppRules.small(for: category)
    }

    // MARK: - Persistence

    static let userDefaultsKey = "yapyap.promptOverrides"

    func saveToUserDefaults() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    static func loadFromUserDefaults() -> PromptOverrides {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return PromptOverrides()
        }
        do {
            return try JSONDecoder().decode(PromptOverrides.self, from: data)
        } catch {
            NSLog("[PromptOverrides] Failed to decode saved overrides, using defaults: \(error)")
            return PromptOverrides()
        }
    }
}
