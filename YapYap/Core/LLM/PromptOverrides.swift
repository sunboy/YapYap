// PromptOverrides.swift
// YapYap — User-customizable prompt overrides for system prompts, few-shot examples, and app rules
import Foundation

/// Stores user overrides for the three prompt layers:
/// 1. System prompts (base instructions per model size / cleanup level)
/// 2. Few-shot examples (input/output pairs in the user message)
/// 3. App-specific rules (per-category formatting rules)
///
/// When an override exists and is enabled, the builder uses it instead of
/// the hardcoded default from PromptTemplates.
struct PromptOverrides: Codable {

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - System Prompt Overrides
    // ═══════════════════════════════════════════════════════════════════

    /// Override for the small-model light cleanup system prompt.
    var systemSmallLight: SystemPromptOverride?

    /// Override for the small-model medium cleanup system prompt.
    var systemSmallMedium: SystemPromptOverride?

    /// Override for the small-model heavy cleanup system prompt.
    var systemSmallHeavy: SystemPromptOverride?

    /// Override for the unified medium/large model system prompt.
    /// When enabled, replaces the dynamically generated `PromptTemplates.System.unified(...)`.
    /// App-specific rules and formality modifiers are still appended automatically.
    var systemUnified: SystemPromptOverride?

    struct SystemPromptOverride: Codable, Equatable {
        var text: String
        var isEnabled: Bool = true
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Few-Shot Example Overrides
    // ═══════════════════════════════════════════════════════════════════

    /// Custom few-shot examples. When non-nil and enabled, replaces the built-in benchmark examples.
    var fewShotOverride: FewShotOverride?

    struct FewShotOverride: Codable, Equatable {
        var isEnabled: Bool = true
        var examples: [FewShotExample] = []
    }

    struct FewShotExample: Codable, Equatable, Identifiable {
        var id: UUID = UUID()
        var input: String
        var output: String
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - App-Specific Rule Overrides (existing)
    // ═══════════════════════════════════════════════════════════════════

    /// Per-category overrides. Key is AppCategory.rawValue.
    var categories: [String: CategoryOverride] = [:]

    struct CategoryOverride: Codable, Equatable {
        /// Custom rules text that replaces the built-in AppRules for this category.
        var rules: String
        var isEnabled: Bool = true
    }

    /// Categories that have meaningful prompt rules (browser/other use empty generic defaults).
    static let editableCategories: [AppCategory] = [
        .personalMessaging, .workMessaging, .email, .codeEditor,
        .aiChat, .terminal, .notes, .social, .documents
    ]

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - System Prompt Variants
    // ═══════════════════════════════════════════════════════════════════

    enum SystemPromptVariant: String, CaseIterable, Identifiable {
        case smallLight
        case smallMedium
        case smallHeavy
        case unified

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .smallLight:  return "Small Model — Light"
            case .smallMedium: return "Small Model — Medium"
            case .smallHeavy:  return "Small Model — Heavy"
            case .unified:     return "Medium / Large Model"
            }
        }

        var description: String {
            switch self {
            case .smallLight:  return "Fix punctuation only, keep all words (≤2B params)"
            case .smallMedium: return "Remove fillers, fix grammar (≤2B params)"
            case .smallHeavy:  return "Full rewrite, remove all hesitations (≤2B params)"
            case .unified:     return "Dynamic prompt for 3B+ models (all cleanup levels)"
            }
        }

        var icon: String {
            switch self {
            case .smallLight, .smallMedium, .smallHeavy: return "cpu"
            case .unified: return "cpu.fill"
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Query
    // ═══════════════════════════════════════════════════════════════════

    /// Returns the custom system prompt for a variant if override exists and is enabled.
    func effectiveSystemPrompt(variant: SystemPromptVariant) -> String? {
        let override: SystemPromptOverride?
        switch variant {
        case .smallLight:  override = systemSmallLight
        case .smallMedium: override = systemSmallMedium
        case .smallHeavy:  override = systemSmallHeavy
        case .unified:     override = systemUnified
        }
        guard let o = override, o.isEnabled, !o.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return o.text
    }

    /// Returns the custom few-shot examples if override exists and is enabled.
    func effectiveExamples() -> [FewShotExample]? {
        guard let o = fewShotOverride, o.isEnabled, !o.examples.isEmpty else {
            return nil
        }
        return o.examples
    }

    /// Returns the custom rules for a category if an override exists and is enabled.
    func effectiveRules(for category: AppCategory) -> String? {
        guard let override = categories[category.rawValue],
              override.isEnabled,
              !override.rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return override.rules
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Defaults
    // ═══════════════════════════════════════════════════════════════════

    /// Returns the default (built-in) system prompt text for a variant.
    static func defaultSystemPrompt(for variant: SystemPromptVariant) -> String {
        switch variant {
        case .smallLight:  return PromptTemplates.System.smallLight
        case .smallMedium: return PromptTemplates.System.smallMedium
        case .smallHeavy:  return PromptTemplates.System.smallHeavy
        case .unified:
            return PromptTemplates.System.unified(
                cleanupLevel: "medium",
                contextLine: "",
                richRules: "",
                numberRule: true
            )
        }
    }

    /// Returns the default (built-in) few-shot examples.
    static func defaultFewShotExamples() -> [FewShotExample] {
        PromptTemplates.Examples.benchmark.map {
            FewShotExample(input: $0.input, output: $0.output)
        }
    }

    /// Returns the default (built-in) rules text for a category.
    static func defaultRules(for category: AppCategory) -> String {
        PromptTemplates.AppRules.medium(for: category)
    }

    /// Returns the default small-model rules text for a category.
    static func defaultSmallRules(for category: AppCategory) -> String {
        PromptTemplates.AppRules.small(for: category)
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Mutating Helpers
    // ═══════════════════════════════════════════════════════════════════

    /// Sets the system prompt override for a variant.
    mutating func setSystemPrompt(_ text: String, for variant: SystemPromptVariant, isEnabled: Bool = true) {
        let override = SystemPromptOverride(text: text, isEnabled: isEnabled)
        switch variant {
        case .smallLight:  systemSmallLight = override
        case .smallMedium: systemSmallMedium = override
        case .smallHeavy:  systemSmallHeavy = override
        case .unified:     systemUnified = override
        }
    }

    /// Clears the system prompt override for a variant (revert to default).
    mutating func resetSystemPrompt(for variant: SystemPromptVariant) {
        switch variant {
        case .smallLight:  systemSmallLight = nil
        case .smallMedium: systemSmallMedium = nil
        case .smallHeavy:  systemSmallHeavy = nil
        case .unified:     systemUnified = nil
        }
    }

    /// Returns the override for a system prompt variant.
    func systemPromptOverride(for variant: SystemPromptVariant) -> SystemPromptOverride? {
        switch variant {
        case .smallLight:  return systemSmallLight
        case .smallMedium: return systemSmallMedium
        case .smallHeavy:  return systemSmallHeavy
        case .unified:     return systemUnified
        }
    }

    /// Sets the enabled state for a system prompt override.
    mutating func setSystemPromptEnabled(_ enabled: Bool, for variant: SystemPromptVariant) {
        switch variant {
        case .smallLight:  systemSmallLight?.isEnabled = enabled
        case .smallMedium: systemSmallMedium?.isEnabled = enabled
        case .smallHeavy:  systemSmallHeavy?.isEnabled = enabled
        case .unified:     systemUnified?.isEnabled = enabled
        }
    }

    /// Updates the text of a system prompt override.
    mutating func setSystemPromptText(_ text: String, for variant: SystemPromptVariant) {
        switch variant {
        case .smallLight:  systemSmallLight?.text = text
        case .smallMedium: systemSmallMedium?.text = text
        case .smallHeavy:  systemSmallHeavy?.text = text
        case .unified:     systemUnified?.text = text
        }
    }

    /// Returns true if any section has custom overrides.
    var hasAnyOverrides: Bool {
        systemSmallLight != nil || systemSmallMedium != nil ||
        systemSmallHeavy != nil || systemUnified != nil ||
        fewShotOverride != nil || !categories.isEmpty
    }

    // ═══════════════════════════════════════════════════════════════════
    // MARK: - Persistence
    // ═══════════════════════════════════════════════════════════════════

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
