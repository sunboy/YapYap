// PromptOverridesTests.swift
// YapYapTests — Tests for prompt overrides data model, persistence, and integration
import XCTest
@testable import YapYap

final class PromptOverridesTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear any saved overrides before each test
        UserDefaults.standard.removeObject(forKey: PromptOverrides.userDefaultsKey)
    }

    override func tearDown() {
        // Clean up after each test
        UserDefaults.standard.removeObject(forKey: PromptOverrides.userDefaultsKey)
        super.tearDown()
    }

    // MARK: - PromptOverrides Data Model

    func testDefaultOverridesAreEmpty() {
        let overrides = PromptOverrides()
        XCTAssertTrue(overrides.categories.isEmpty)
    }

    func testEffectiveRulesReturnsNilWithoutOverride() {
        let overrides = PromptOverrides()
        for category in AppCategory.allCases {
            XCTAssertNil(overrides.effectiveRules(for: category))
        }
    }

    func testEffectiveRulesReturnsCustomWhenEnabled() {
        var overrides = PromptOverrides()
        let customRules = "- Custom rule for Slack\n- Keep it professional"
        overrides.categories["workMessaging"] = .init(rules: customRules, isEnabled: true)

        XCTAssertEqual(overrides.effectiveRules(for: .workMessaging), customRules)
    }

    func testEffectiveRulesReturnsNilWhenDisabled() {
        var overrides = PromptOverrides()
        overrides.categories["workMessaging"] = .init(
            rules: "- Custom rule", isEnabled: false
        )

        XCTAssertNil(overrides.effectiveRules(for: .workMessaging))
    }

    func testEffectiveRulesReturnsNilForEmptyRules() {
        var overrides = PromptOverrides()
        overrides.categories["email"] = .init(rules: "   ", isEnabled: true)

        XCTAssertNil(overrides.effectiveRules(for: .email))
    }

    func testDefaultRulesExistForAllEditableCategories() {
        for category in PromptOverrides.editableCategories {
            let rules = PromptOverrides.defaultRules(for: category)
            XCTAssertFalse(rules.isEmpty, "Default rules should exist for \(category.rawValue)")
        }
    }

    func testDefaultSmallRulesExistForAllEditableCategories() {
        for category in PromptOverrides.editableCategories {
            let rules = PromptOverrides.defaultSmallRules(for: category)
            XCTAssertFalse(rules.isEmpty, "Default small rules should exist for \(category.rawValue)")
        }
    }

    func testDefaultRulesMatchPromptTemplates() {
        XCTAssertEqual(PromptOverrides.defaultRules(for: .workMessaging),
                       PromptTemplates.AppRules.Medium.slack)
        XCTAssertEqual(PromptOverrides.defaultRules(for: .email),
                       PromptTemplates.AppRules.Medium.mail)
        XCTAssertEqual(PromptOverrides.defaultRules(for: .codeEditor),
                       PromptTemplates.AppRules.Medium.cursor)
        XCTAssertEqual(PromptOverrides.defaultRules(for: .terminal),
                       PromptTemplates.AppRules.Medium.terminal)
    }

    // MARK: - Persistence (UserDefaults)

    func testSaveAndLoadRoundTrip() {
        var overrides = PromptOverrides()
        overrides.categories["email"] = .init(
            rules: "- Format as email\n- Use formal tone", isEnabled: true
        )
        overrides.categories["terminal"] = .init(
            rules: "- No periods on commands", isEnabled: false
        )
        overrides.saveToUserDefaults()

        let loaded = PromptOverrides.loadFromUserDefaults()
        XCTAssertEqual(loaded.categories.count, 2)
        XCTAssertEqual(loaded.categories["email"]?.rules, "- Format as email\n- Use formal tone")
        XCTAssertEqual(loaded.categories["email"]?.isEnabled, true)
        XCTAssertEqual(loaded.categories["terminal"]?.rules, "- No periods on commands")
        XCTAssertEqual(loaded.categories["terminal"]?.isEnabled, false)
    }

    func testLoadReturnsDefaultsWhenNoSavedData() {
        let loaded = PromptOverrides.loadFromUserDefaults()
        XCTAssertTrue(loaded.categories.isEmpty)
    }

    // MARK: - CleanupPromptBuilder Integration: stylePrompt

    func testStylePromptInjectedIntoSmallModelPrompt() {
        let context = makeContext(stylePrompt: "Be concise and direct.")
        let messages = CleanupPromptBuilder.buildMessages(
            rawText: "test", context: context, modelId: "qwen-2.5-1.5b"
        )
        XCTAssertTrue(messages.system.contains("Be concise and direct."),
                       "stylePrompt should appear in small model system prompt")
    }

    func testStylePromptInjectedIntoMediumModelPrompt() {
        let context = makeContext(stylePrompt: "Write like a senior engineer.")
        let messages = CleanupPromptBuilder.buildMessages(
            rawText: "test", context: context, modelId: "qwen-2.5-3b"
        )
        XCTAssertTrue(messages.system.contains("CUSTOM STYLE:"),
                       "Medium model should have CUSTOM STYLE section")
        XCTAssertTrue(messages.system.contains("Write like a senior engineer."),
                       "stylePrompt should appear in medium model system prompt")
    }

    func testStylePromptInjectedIntoLargeModelPrompt() {
        let context = makeContext(stylePrompt: "Technical and precise.")
        let messages = CleanupPromptBuilder.buildMessages(
            rawText: "test", context: context, modelId: "qwen-2.5-7b"
        )
        XCTAssertTrue(messages.system.contains("CUSTOM STYLE:"),
                       "Large model should have CUSTOM STYLE section")
        XCTAssertTrue(messages.system.contains("Technical and precise."),
                       "stylePrompt should appear in large model system prompt")
    }

    func testEmptyStylePromptNotInjected() {
        let context = makeContext(stylePrompt: "")
        let messages = CleanupPromptBuilder.buildMessages(
            rawText: "test", context: context, modelId: "qwen-2.5-3b"
        )
        XCTAssertFalse(messages.system.contains("CUSTOM STYLE:"),
                        "Empty stylePrompt should not add CUSTOM STYLE section")
    }

    // MARK: - CleanupPromptBuilder Integration: PromptOverrides

    func testOverrideReplacesDefaultMediumRules() {
        // Set a custom override for email
        var overrides = PromptOverrides()
        overrides.categories["email"] = .init(
            rules: "- Always start with Dear\n- End with Regards", isEnabled: true
        )
        overrides.saveToUserDefaults()

        let appCtx = AppContext(
            bundleId: "com.apple.mail", appName: "Mail", category: .email,
            style: .formal, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false
        )
        let context = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilder.buildMessages(
            rawText: "test email", context: context, modelId: "qwen-2.5-3b"
        )

        // Custom rules should be present
        XCTAssertTrue(messages.system.contains("Always start with Dear"),
                       "Custom override rules should appear in system prompt")
        XCTAssertTrue(messages.system.contains("End with Regards"),
                       "Custom override rules should appear in system prompt")
        // Default email rules should NOT be present
        XCTAssertFalse(messages.system.contains("Structure as email with explicit blank lines"),
                        "Default email rules should be replaced by override")
    }

    func testDisabledOverrideFallsBackToDefault() {
        var overrides = PromptOverrides()
        overrides.categories["email"] = .init(
            rules: "- Custom email rule", isEnabled: false
        )
        overrides.saveToUserDefaults()

        let appCtx = AppContext(
            bundleId: "com.apple.mail", appName: "Mail", category: .email,
            style: .formal, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false
        )
        let context = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilder.buildMessages(
            rawText: "test email", context: context, modelId: "qwen-2.5-3b"
        )

        // Default rules should be present
        XCTAssertTrue(messages.system.contains("Structure as email"),
                       "Disabled override should fall back to default rules")
        // Custom rule should NOT be present
        XCTAssertFalse(messages.system.contains("Custom email rule"),
                        "Disabled override should not inject custom rules")
    }

    func testOverrideReplacesSmallModelRules() {
        var overrides = PromptOverrides()
        overrides.categories["workMessaging"] = .init(
            rules: "Keep it super casual for Slack.", isEnabled: true
        )
        overrides.saveToUserDefaults()

        let appCtx = AppContext(
            bundleId: "com.tinyspeck.slackmacgap", appName: "Slack", category: .workMessaging,
            style: .casual, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false
        )
        let context = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilder.buildMessages(
            rawText: "test slack", context: context, modelId: "qwen-2.5-1.5b"
        )

        XCTAssertTrue(messages.system.contains("Keep it super casual for Slack."),
                       "Custom override should appear in small model prompt")
    }

    func testNoOverrideKeepsDefaultRules() {
        // No overrides saved
        let appCtx = AppContext(
            bundleId: "com.tinyspeck.slackmacgap", appName: "Slack", category: .workMessaging,
            style: .casual, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false
        )
        let context = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilder.buildMessages(
            rawText: "test slack", context: context, modelId: "qwen-2.5-3b"
        )

        XCTAssertTrue(messages.system.contains("@mentions"),
                       "Default Slack rules should be present when no override exists")
    }

    func testOverrideDoesNotAffectOtherCategories() {
        var overrides = PromptOverrides()
        overrides.categories["email"] = .init(
            rules: "- Custom email rule", isEnabled: true
        )
        overrides.saveToUserDefaults()

        // Test Slack (should still use defaults)
        let slackCtx = AppContext(
            bundleId: "com.tinyspeck.slackmacgap", appName: "Slack", category: .workMessaging,
            style: .casual, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false
        )
        let context = makeContext(appContext: slackCtx)
        let messages = CleanupPromptBuilder.buildMessages(
            rawText: "test", context: context, modelId: "qwen-2.5-3b"
        )

        XCTAssertTrue(messages.system.contains("@mentions"),
                       "Email override should not affect Slack rules")
        XCTAssertFalse(messages.system.contains("Custom email rule"))
    }

    func testIDEChatPanelIgnoresOverride() {
        // IDE chat panel should use its own rules regardless of codeEditor override
        var overrides = PromptOverrides()
        overrides.categories["codeEditor"] = .init(
            rules: "- Custom code editor rule", isEnabled: true
        )
        overrides.saveToUserDefaults()

        let ideCtx = AppContext(
            bundleId: "com.todesktop.230313mzl4w4u92", appName: "Cursor",
            category: .codeEditor, style: .formal, windowTitle: "Composer",
            focusedFieldText: nil, isIDEChatPanel: true
        )
        let context = makeContext(appContext: ideCtx)
        let messages = CleanupPromptBuilder.buildMessages(
            rawText: "test", context: context, modelId: "qwen-2.5-3b"
        )

        // IDE chat panel rules should be used, not the custom override
        XCTAssertTrue(messages.system.contains("Prefix ALL filenames with @"),
                       "IDE chat panel should use its own rules, not category override")
    }

    // MARK: - CategoryOverride Codable

    func testCategoryOverrideCodable() throws {
        let override = PromptOverrides.CategoryOverride(
            rules: "- Test rule\n- Second rule", isEnabled: true
        )
        let data = try JSONEncoder().encode(override)
        let decoded = try JSONDecoder().decode(
            PromptOverrides.CategoryOverride.self, from: data
        )
        XCTAssertEqual(override, decoded)
    }

    // MARK: - Helpers

    private func makeContext(
        stylePrompt: String = "",
        formality: CleanupContext.Formality = .neutral,
        cleanupLevel: CleanupContext.CleanupLevel = .medium,
        appContext: AppContext? = nil
    ) -> CleanupContext {
        CleanupContext(
            stylePrompt: stylePrompt,
            formality: formality,
            language: "en",
            appContext: appContext,
            cleanupLevel: cleanupLevel,
            removeFillers: true,
            experimentalPrompts: false
        )
    }
}
