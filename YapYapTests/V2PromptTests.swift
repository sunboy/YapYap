// V2PromptTests.swift
// YapYapTests — Tests for V2 prompt system: PromptTemplatesV2, AppContextMapper, CleanupPromptBuilderV2
import XCTest
@testable import YapYap

final class PromptTemplatesV2Tests: XCTestCase {

    // MARK: - System Prompt

    func testSystemPromptContainsAppContext() {
        let prompt = PromptTemplatesV2.systemPrompt(appContext: "Slack", cleanupLevel: .medium)
        XCTAssertTrue(prompt.contains("CONTEXT: Slack"))
    }

    func testSystemPromptContainsHardRules() {
        let prompt = PromptTemplatesV2.systemPrompt(appContext: "General", cleanupLevel: .medium)
        XCTAssertTrue(prompt.contains("HARD RULES:"))
        XCTAssertTrue(prompt.contains("1."))
        XCTAssertTrue(prompt.contains("14."))
    }

    func testSystemPromptLightCleanupKeepsFillers() {
        let prompt = PromptTemplatesV2.systemPrompt(appContext: "General", cleanupLevel: .light)
        XCTAssertTrue(prompt.contains("Keep ALL words including fillers"))
    }

    func testSystemPromptMediumCleanupRemovesFillers() {
        let prompt = PromptTemplatesV2.systemPrompt(appContext: "General", cleanupLevel: .medium)
        XCTAssertTrue(prompt.contains("fillers"))
        XCTAssertTrue(prompt.contains("uh"))
    }

    func testSystemPromptHeavyCleanupFixesStructure() {
        let prompt = PromptTemplatesV2.systemPrompt(appContext: "General", cleanupLevel: .heavy)
        XCTAssertTrue(prompt.contains("Fix grammar, punctuation, and sentence structure"))
        XCTAssertTrue(prompt.contains("Remove ALL fillers"))
    }

    func testSystemPromptContainsFileTaggingRule() {
        let prompt = PromptTemplatesV2.systemPrompt(appContext: "IDE", cleanupLevel: .medium)
        XCTAssertTrue(prompt.contains("@main.py"))
        XCTAssertTrue(prompt.contains("File tagging rule"))
    }

    func testSystemPromptContainsLinkedInRule() {
        let prompt = PromptTemplatesV2.systemPrompt(appContext: "LinkedIn", cleanupLevel: .medium)
        XCTAssertTrue(prompt.contains("LinkedIn context"))
        XCTAssertTrue(prompt.contains("punchy paragraphs"))
    }

    // MARK: - Few-Shot Examples

    func testFewShotExamplesArePrefixedWithReformat() {
        for example in PromptTemplatesV2.fewShotExamples {
            XCTAssertTrue(example.user.hasPrefix("Reformat:"), "Example missing Reformat prefix: \(example.user)")
        }
    }

    func testFewShotExamplesNotEmpty() {
        XCTAssertFalse(PromptTemplatesV2.fewShotExamples.isEmpty)
        XCTAssertGreaterThanOrEqual(PromptTemplatesV2.fewShotExamples.count, 3)
    }

    func testFewShotExamplesContainFileTagging() {
        let hasFileTagging = PromptTemplatesV2.fewShotExamples.contains { example in
            example.assistant.contains("@main.py")
        }
        XCTAssertTrue(hasFileTagging, "Few-shot examples should demonstrate file tagging")
    }

    // MARK: - User Input Format

    func testFormatUserInput() {
        let formatted = PromptTemplatesV2.formatUserInput("hello world")
        XCTAssertEqual(formatted, "Reformat: hello world")
    }

    func testFormatUserInputEmpty() {
        let formatted = PromptTemplatesV2.formatUserInput("")
        XCTAssertEqual(formatted, "Reformat: ")
    }
}

// MARK: - AppContextMapper Tests

final class AppContextMapperTests: XCTestCase {

    // MARK: - Nil Context

    func testNilContextReturnsSlack() {
        XCTAssertEqual(AppContextMapper.keyword(from: nil), "Slack")
    }

    // MARK: - IDE Priority

    func testIDEChatPanelReturnsCursor() {
        let ctx = makeContext(appName: "Cursor", category: .codeEditor, isIDEChatPanel: true)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Cursor")
    }

    func testCodeEditorReturnsIDE() {
        let ctx = makeContext(appName: "VS Code", category: .codeEditor)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "IDE")
    }

    // MARK: - Terminal

    func testTerminalCategoryReturnsTerminal() {
        let ctx = makeContext(appName: "Terminal", category: .terminal)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Terminal")
    }

    func testItermReturnsTerminal() {
        let ctx = makeContext(appName: "iTerm2", category: .other)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Terminal")
    }

    func testWarpReturnsTerminal() {
        let ctx = makeContext(appName: "Warp", category: .other)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Terminal")
    }

    // MARK: - Email

    func testEmailCategoryReturnsEmail() {
        let ctx = makeContext(appName: "Mail", category: .email)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Email")
    }

    func testOutlookReturnsEmail() {
        let ctx = makeContext(appName: "Microsoft Outlook", category: .other)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Email")
    }

    // MARK: - Work Messaging → Slack

    func testWorkMessagingReturnsSlack() {
        let ctx = makeContext(appName: "Slack", category: .workMessaging)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Slack")
    }

    func testDiscordReturnsSlack() {
        let ctx = makeContext(appName: "Discord", category: .other)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Slack")
    }

    // MARK: - Browser (Dynamic)

    func testBrowserLinkedInReturnsLinkedIn() {
        let ctx = makeContext(appName: "Safari", category: .browser, windowTitle: "LinkedIn - Feed")
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "LinkedIn")
    }

    func testBrowserGmailReturnsEmail() {
        let ctx = makeContext(appName: "Chrome", category: .browser, windowTitle: "Inbox - Gmail")
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Email")
    }

    func testBrowserGitHubReturnsGitHub() {
        let ctx = makeContext(appName: "Chrome", category: .browser, windowTitle: "Issues - GitHub")
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "GitHub")
    }

    func testBrowserTwitterReturnsTwitter() {
        let ctx = makeContext(appName: "Safari", category: .browser, windowTitle: "Home / X.com")
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Twitter")
    }

    func testBrowserSlackReturnsSlack() {
        let ctx = makeContext(appName: "Chrome", category: .browser, windowTitle: "Slack | general")
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Slack")
    }

    func testBrowserGenericReturnsSlack() {
        let ctx = makeContext(appName: "Safari", category: .browser, windowTitle: "Google Search")
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Slack")
    }

    func testBrowserNoTitleReturnsSlack() {
        let ctx = makeContext(appName: "Safari", category: .browser, windowTitle: nil)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Slack")
    }

    // MARK: - Social

    func testSocialLinkedInReturnsLinkedIn() {
        let ctx = makeContext(appName: "LinkedIn", category: .social)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "LinkedIn")
    }

    func testSocialTwitterReturnsTwitter() {
        let ctx = makeContext(appName: "Twitter", category: .social)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Twitter")
    }

    // MARK: - Notes

    func testNotesCategoryReturnsNotes() {
        let ctx = makeContext(appName: "Notes", category: .notes)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Notes")
    }

    func testObsidianReturnsObsidian() {
        let ctx = makeContext(appName: "Obsidian", category: .notes)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Obsidian")
    }

    // MARK: - Personal Messaging → Slack

    func testPersonalMessagingReturnsSlack() {
        let ctx = makeContext(appName: "Messages", category: .personalMessaging)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Slack")
    }

    // MARK: - AI Chat → IDE

    func testAIChatReturnsAIPrompt() {
        let ctx = makeContext(appName: "ChatGPT", category: .aiChat)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "AI Prompt")
    }

    // MARK: - Documents → Email

    func testDocumentsReturnsEmail() {
        let ctx = makeContext(appName: "Pages", category: .documents)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Email")
    }

    // MARK: - Priority Order

    func testIDEHasPriorityOverTerminal() {
        // Code editor category should win even if app name contains "Terminal"
        let ctx = makeContext(appName: "Terminal Code Editor", category: .codeEditor)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "IDE")
    }

    // MARK: - Helpers

    private func makeContext(
        appName: String,
        category: AppCategory,
        windowTitle: String? = nil,
        isIDEChatPanel: Bool = false
    ) -> AppContext {
        AppContext(
            bundleId: "com.test.\(appName.lowercased())",
            appName: appName,
            category: category,
            style: .casual,
            windowTitle: windowTitle,
            focusedFieldText: nil,
            isIDEChatPanel: isIDEChatPanel
        )
    }
}

// MARK: - CleanupPromptBuilderV2 Tests

final class CleanupPromptBuilderV2Tests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: PromptOverrides.userDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: PromptOverrides.userDefaultsKey)
        super.tearDown()
    }

    // MARK: - Message Structure

    func testBuildMessagesStartsWithSystem() {
        let messages = CleanupPromptBuilderV2.buildMessages(
            rawText: "hello world",
            context: makeContext()
        )
        XCTAssertFalse(messages.isEmpty)
        XCTAssertEqual(messages.first?.role, .system)
    }

    func testBuildMessagesEndsWithUserInput() {
        let messages = CleanupPromptBuilderV2.buildMessages(
            rawText: "test input",
            context: makeContext()
        )
        let lastMessage = messages.last!
        XCTAssertEqual(lastMessage.role, .user)
        XCTAssertEqual(lastMessage.content, "Reformat: test input")
    }

    func testBuildMessagesHasFewShotPairs() {
        let messages = CleanupPromptBuilderV2.buildMessages(
            rawText: "test",
            context: makeContext()
        )

        // Expected: system + (5 user/assistant pairs) + final user = 12 messages
        let expectedCount = 1 + (PromptTemplatesV2.fewShotExamples.count * 2) + 1
        XCTAssertEqual(messages.count, expectedCount)

        // Verify alternating user/assistant pattern in few-shot section
        for i in stride(from: 1, to: messages.count - 1, by: 2) {
            XCTAssertEqual(messages[i].role, .user, "Message \(i) should be user")
            XCTAssertEqual(messages[i + 1].role, .assistant, "Message \(i+1) should be assistant")
        }
    }

    func testSystemPromptContainsAppContextKeyword() {
        let ctx = makeContext(appContext: makeAppContext(category: .codeEditor))
        let messages = CleanupPromptBuilderV2.buildMessages(rawText: "test", context: ctx)
        let systemContent = messages.first!.content
        XCTAssertTrue(systemContent.contains("CONTEXT: IDE"))
    }

    func testSystemPromptContainsCleanupLevel() {
        let ctx = makeContext(cleanupLevel: .heavy)
        let messages = CleanupPromptBuilderV2.buildMessages(rawText: "test", context: ctx)
        let systemContent = messages.first!.content
        XCTAssertTrue(systemContent.contains("Remove ALL fillers"))
    }

    func testBuildMessagePartsPrefix() {
        let parts = CleanupPromptBuilderV2.buildMessageParts(
            rawText: "hello world",
            context: makeContext()
        )

        // Prefix should include system + all few-shot pairs
        let expectedPrefixCount = 1 + (PromptTemplatesV2.fewShotExamples.count * 2)
        XCTAssertEqual(parts.prefix.count, expectedPrefixCount)

        // Suffix should be the final user message
        XCTAssertEqual(parts.suffix.role, .user)
        XCTAssertEqual(parts.suffix.content, "Reformat: hello world")
    }

    // MARK: - Custom Overrides

    func testCustomSystemPromptOverride() {
        var overrides = PromptOverrides()
        overrides.setSystemPrompt("Custom system prompt", for: .unified)
        overrides.saveToUserDefaults()

        let messages = CleanupPromptBuilderV2.buildMessages(
            rawText: "test",
            context: makeContext()
        )

        XCTAssertEqual(messages.first?.content, "Custom system prompt")
    }

    func testCustomFewShotOverride() {
        var overrides = PromptOverrides()
        overrides.fewShotOverride = .init(
            isEnabled: true,
            examples: [
                .init(input: "hello", output: "Hello."),
                .init(input: "goodbye", output: "Goodbye."),
            ]
        )
        overrides.saveToUserDefaults()

        let messages = CleanupPromptBuilderV2.buildMessages(
            rawText: "test",
            context: makeContext()
        )

        // system + 2 custom pairs + final user = 6
        XCTAssertEqual(messages.count, 6)

        // Custom examples should be wrapped with "Reformat:" prefix
        XCTAssertEqual(messages[1].content, "Reformat: hello")
        XCTAssertEqual(messages[2].content, "Hello.")
    }

    func testDisabledFewShotOverrideFallsBackToDefaults() {
        var overrides = PromptOverrides()
        overrides.fewShotOverride = .init(isEnabled: false, examples: [
            .init(input: "custom", output: "Custom."),
        ])
        overrides.saveToUserDefaults()

        let messages = CleanupPromptBuilderV2.buildMessages(
            rawText: "test",
            context: makeContext()
        )

        // Should use default examples count
        let expectedCount = 1 + (PromptTemplatesV2.fewShotExamples.count * 2) + 1
        XCTAssertEqual(messages.count, expectedCount)
    }

    // MARK: - App Context Integration

    func testIDEContextSetsContextKeyword() {
        let appCtx = makeAppContext(category: .codeEditor, appName: "VS Code")
        let ctx = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilderV2.buildMessages(rawText: "test", context: ctx)
        XCTAssertTrue(messages.first!.content.contains("CONTEXT: IDE"))
    }

    func testSlackContextSetsContextKeyword() {
        let appCtx = makeAppContext(category: .workMessaging, appName: "Slack")
        let ctx = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilderV2.buildMessages(rawText: "test", context: ctx)
        XCTAssertTrue(messages.first!.content.contains("CONTEXT: Slack"))
    }

    func testEmailContextSetsContextKeyword() {
        let appCtx = makeAppContext(category: .email, appName: "Mail")
        let ctx = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilderV2.buildMessages(rawText: "test", context: ctx)
        XCTAssertTrue(messages.first!.content.contains("CONTEXT: Email"))
    }

    func testNoAppContextSetsSlack() {
        let messages = CleanupPromptBuilderV2.buildMessages(
            rawText: "test",
            context: makeContext(appContext: nil)
        )
        XCTAssertTrue(messages.first!.content.contains("CONTEXT: Slack"))
    }

    // MARK: - V2 Defaults in PromptOverrides

    func testDefaultV2SystemPrompt() {
        let prompt = PromptOverrides.defaultV2SystemPrompt()
        XCTAssertTrue(prompt.contains("HARD RULES:"))
        // Default V2 system prompt uses "General" as placeholder app context
        XCTAssertTrue(prompt.contains("CONTEXT: General"))
    }

    func testDefaultV2FewShotExamples() {
        let examples = PromptOverrides.defaultV2FewShotExamples()
        XCTAssertEqual(examples.count, PromptTemplatesV2.fewShotExamples.count)
        // V2 examples use "Reformat:" prefix in input
        for example in examples {
            XCTAssertTrue(example.input.hasPrefix("Reformat:"), "V2 example should have Reformat prefix")
        }
    }

    // MARK: - Helpers

    private func makeContext(
        cleanupLevel: CleanupContext.CleanupLevel = .medium,
        appContext: AppContext? = nil
    ) -> CleanupContext {
        CleanupContext(
            stylePrompt: "",
            formality: .neutral,
            language: "en",
            appContext: appContext,
            cleanupLevel: cleanupLevel,
            removeFillers: true,
            experimentalPrompts: false,
            useV2Prompts: true
        )
    }

    private func makeAppContext(
        category: AppCategory,
        appName: String = "TestApp",
        windowTitle: String? = nil,
        isIDEChatPanel: Bool = false
    ) -> AppContext {
        AppContext(
            bundleId: "com.test.\(appName.lowercased())",
            appName: appName,
            category: category,
            style: .casual,
            windowTitle: windowTitle,
            focusedFieldText: nil,
            isIDEChatPanel: isIDEChatPanel
        )
    }
}
