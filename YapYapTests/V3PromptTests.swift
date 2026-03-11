// V3PromptTests.swift
// YapYapTests — Tests for DSPy-optimized V3 prompt system
import XCTest
@testable import YapYap

// MARK: - PromptTemplatesV3 Tests

final class PromptTemplatesV3Tests: XCTestCase {

    // MARK: - System Prompt Selection

    func testGemma4BUsesFullGemmaPrompt() {
        let prompt = PromptTemplatesV3.systemPrompt(family: .gemma, size: .medium)
        XCTAssertTrue(prompt.contains("transcription cleanup engine"))
        XCTAssertTrue(prompt.contains("[Context: <app>]"))
        XCTAssertTrue(prompt.contains("Claude Code"))
    }

    func testGemma1BUsesMinimalPrompt() {
        let prompt = PromptTemplatesV3.systemPrompt(family: .gemma, size: .small)
        XCTAssertTrue(prompt.contains("Clean up the dictation"))
        // Must be short — full prompt overwhelms 1B model (8.9% vs 72% pass rate)
        let wordCount = prompt.split(separator: " ").count
        XCTAssertLessThan(wordCount, 100, "Gemma 1B prompt must be minimal")
    }

    func testGemma1BPromptDoesNotContainFullRules() {
        let prompt = PromptTemplatesV3.systemPrompt(family: .gemma, size: .small)
        XCTAssertFalse(prompt.contains("Multi-section content"), "Full rules would overwhelm 1B model")
        XCTAssertFalse(prompt.contains("numbered lists"), "Full list rules would overwhelm 1B model")
    }

    func testQwenUsesQwenPrompt() {
        let prompt = PromptTemplatesV3.systemPrompt(family: .qwen, size: .small)
        XCTAssertTrue(prompt.contains("CRITICAL RULES"))
        XCTAssertTrue(prompt.contains("NEVER refuse"))
    }

    func testLlamaUsesLlamaPrompt() {
        let prompt = PromptTemplatesV3.systemPrompt(family: .llama, size: .large)
        XCTAssertTrue(prompt.contains("deterministic STT"))
        XCTAssertTrue(prompt.contains("HARD RULES"))
    }

    func testVocabularyBlockAppended() {
        let prompt = PromptTemplatesV3.systemPrompt(
            family: .qwen, size: .small,
            vocabularyBlock: "VOCABULARY:\n- yapyap → YapYap"
        )
        XCTAssertTrue(prompt.contains("VOCABULARY:"))
        XCTAssertTrue(prompt.contains("yapyap → YapYap"))
    }

    // MARK: - Few-Shot Selection

    func testGemma4BHas12FewShots() {
        let shots = PromptTemplatesV3.fewShots(family: .gemma, size: .medium)
        XCTAssertEqual(shots.count, 12)
    }

    func testGemma1BHas4FewShots() {
        let shots = PromptTemplatesV3.fewShots(family: .gemma, size: .small)
        XCTAssertEqual(shots.count, 4)
    }

    func testQwenHas7FewShots() {
        let shots = PromptTemplatesV3.fewShots(family: .qwen, size: .small)
        XCTAssertEqual(shots.count, 7)
    }

    func testLlamaHas7FewShots() {
        let shots = PromptTemplatesV3.fewShots(family: .llama, size: .large)
        XCTAssertEqual(shots.count, 7)
    }

    // MARK: - Few-Shot Format

    func testFewShotsHaveContextPrefix() {
        // All V3 few-shots must have [Context: X] prefix — this is the key architectural feature
        for family in [LLMModelFamily.gemma, .qwen, .llama] {
            for size in [LLMModelSize.small, .medium, .large] {
                let shots = PromptTemplatesV3.fewShots(family: family, size: size)
                for (i, shot) in shots.enumerated() {
                    XCTAssertTrue(
                        shot.user.hasPrefix("[Context:"),
                        "Few-shot \(i) for \(family)/\(size) missing [Context:] prefix: \(shot.user.prefix(40))"
                    )
                }
            }
        }
    }

    func testFewShotsContainReformatKeyword() {
        let shots = PromptTemplatesV3.fewShots(family: .gemma, size: .medium)
        for (i, shot) in shots.enumerated() {
            XCTAssertTrue(
                shot.user.contains("Reformat:"),
                "Few-shot \(i) missing 'Reformat:' keyword"
            )
        }
    }

    // MARK: - User Input Format

    func testFormatUserInputIncludesContext() {
        let result = PromptTemplatesV3.formatUserInput("hello world", appContext: "Slack")
        XCTAssertEqual(result, "[Context: Slack] Reformat: hello world")
    }

    func testFormatUserInputWithTerminal() {
        let result = PromptTemplatesV3.formatUserInput("git status", appContext: "Terminal")
        XCTAssertEqual(result, "[Context: Terminal] Reformat: git status")
    }
}

// MARK: - CleanupPromptBuilderV3 Tests

final class CleanupPromptBuilderV3Tests: XCTestCase {

    // MARK: - Message Structure

    func testBuildMessagesHasCorrectStructure() {
        let context = makeCleanupContext()
        let messages = CleanupPromptBuilderV3.buildMessages(
            rawText: "hello world", context: context, modelId: "gemma-3-4b"
        )
        // First message is system
        XCTAssertEqual(messages.first?.role, .system)
        // Last message is user
        XCTAssertEqual(messages.last?.role, .user)
        // Last user message has context prefix
        XCTAssertTrue(messages.last!.content.hasPrefix("[Context:"))
    }

    func testSystemPromptIsConstantAcrossAppSwitches() {
        let slackCtx = makeCleanupContext(appCategory: .workMessaging, appName: "Slack")
        let emailCtx = makeCleanupContext(appCategory: .email, appName: "Mail")
        let ideCtx = makeCleanupContext(appCategory: .codeEditor, appName: "VS Code")

        let slackMsgs = CleanupPromptBuilderV3.buildMessages(
            rawText: "test", context: slackCtx, modelId: "gemma-3-4b"
        )
        let emailMsgs = CleanupPromptBuilderV3.buildMessages(
            rawText: "test", context: emailCtx, modelId: "gemma-3-4b"
        )
        let ideMsgs = CleanupPromptBuilderV3.buildMessages(
            rawText: "test", context: ideCtx, modelId: "gemma-3-4b"
        )

        // System prompt must be identical regardless of app context
        let slackSystem = slackMsgs.first!.content
        let emailSystem = emailMsgs.first!.content
        let ideSystem = ideMsgs.first!.content
        XCTAssertEqual(slackSystem, emailSystem, "System prompt must not change across apps")
        XCTAssertEqual(emailSystem, ideSystem, "System prompt must not change across apps")
    }

    func testPrefixIsConstantAcrossAppSwitches() {
        let slackCtx = makeCleanupContext(appCategory: .workMessaging, appName: "Slack")
        let emailCtx = makeCleanupContext(appCategory: .email, appName: "Mail")

        let slackParts = CleanupPromptBuilderV3.buildMessageParts(
            rawText: "test", context: slackCtx, modelId: "gemma-3-4b"
        )
        let emailParts = CleanupPromptBuilderV3.buildMessageParts(
            rawText: "test", context: emailCtx, modelId: "gemma-3-4b"
        )

        // Prefix (system + few-shots) must be identical — this is the KV cache invariant
        XCTAssertEqual(slackParts.prefix.count, emailParts.prefix.count)
        for (s, e) in zip(slackParts.prefix, emailParts.prefix) {
            XCTAssertEqual(s.role, e.role)
            XCTAssertEqual(s.content, e.content, "Prefix message content must not vary by app context")
        }
    }

    func testSuffixContainsAppContext() {
        let slackCtx = makeCleanupContext(appCategory: .workMessaging, appName: "Slack")
        let parts = CleanupPromptBuilderV3.buildMessageParts(
            rawText: "check the logs", context: slackCtx, modelId: "gemma-3-4b"
        )
        XCTAssertTrue(parts.suffix.content.contains("[Context: Slack]"))
        XCTAssertTrue(parts.suffix.content.contains("check the logs"))
    }

    func testSuffixChangesWithDifferentApps() {
        let slackCtx = makeCleanupContext(appCategory: .workMessaging, appName: "Slack")
        let emailCtx = makeCleanupContext(appCategory: .email, appName: "Mail")

        let slackParts = CleanupPromptBuilderV3.buildMessageParts(
            rawText: "test", context: slackCtx, modelId: "gemma-3-4b"
        )
        let emailParts = CleanupPromptBuilderV3.buildMessageParts(
            rawText: "test", context: emailCtx, modelId: "gemma-3-4b"
        )

        XCTAssertTrue(slackParts.suffix.content.contains("[Context: Slack]"))
        XCTAssertTrue(emailParts.suffix.content.contains("[Context: Email]"))
        XCTAssertNotEqual(slackParts.suffix.content, emailParts.suffix.content)
    }

    // MARK: - Model Family Routing

    func testGemma4BUsesGemmaPrompt() {
        let context = makeCleanupContext()
        let messages = CleanupPromptBuilderV3.buildMessages(
            rawText: "test", context: context, modelId: "gemma-3-4b"
        )
        XCTAssertTrue(messages.first!.content.contains("transcription cleanup engine"))
    }

    func testQwen1_5BUsesQwenPrompt() {
        let context = makeCleanupContext()
        let messages = CleanupPromptBuilderV3.buildMessages(
            rawText: "test", context: context, modelId: "qwen-2.5-1.5b"
        )
        XCTAssertTrue(messages.first!.content.contains("CRITICAL RULES"))
    }

    func testLlama8BUsesLlamaPrompt() {
        let context = makeCleanupContext()
        let messages = CleanupPromptBuilderV3.buildMessages(
            rawText: "test", context: context, modelId: "llama-3.1-8b"
        )
        XCTAssertTrue(messages.first!.content.contains("deterministic STT"))
    }

    func testGemma1BUsesMinimalPrompt() {
        let context = makeCleanupContext()
        let messages = CleanupPromptBuilderV3.buildMessages(
            rawText: "test", context: context, modelId: "gemma-3-1b"
        )
        XCTAssertTrue(messages.first!.content.contains("Clean up the dictation"))
        // Gemma 1B should have fewer few-shots (4 vs 12)
        let fewShotPairs = messages.filter { $0.role == .user }.count - 1 // minus the real input
        XCTAssertEqual(fewShotPairs, 4, "Gemma 1B should have 4 few-shot pairs")
    }

    // MARK: - Prefix Messages (for startup caching)

    func testBuildPrefixMessagesDoesNotContainAppContext() {
        let prefix = CleanupPromptBuilderV3.buildPrefixMessages(modelId: "gemma-3-4b")
        for msg in prefix {
            // No message should reference a specific app context like "CONTEXT: Slack"
            XCTAssertFalse(
                msg.content.contains("CONTEXT: Slack"),
                "Prefix should not contain app-specific context"
            )
            XCTAssertFalse(
                msg.content.contains("CONTEXT: Email"),
                "Prefix should not contain app-specific context"
            )
        }
    }

    func testBuildPrefixMessagesMatchesBuildMessagePartsPrefix() {
        let context = makeCleanupContext(appCategory: .workMessaging, appName: "Slack")
        let prefix = CleanupPromptBuilderV3.buildPrefixMessages(modelId: "gemma-3-4b")
        let parts = CleanupPromptBuilderV3.buildMessageParts(
            rawText: "test", context: context, modelId: "gemma-3-4b"
        )
        XCTAssertEqual(prefix.count, parts.prefix.count)
        for (p, pp) in zip(prefix, parts.prefix) {
            XCTAssertEqual(p.role, pp.role)
            XCTAssertEqual(p.content, pp.content)
        }
    }

    // MARK: - PromptVersion Enum

    func testPromptVersionV3IsDefault() {
        let context = CleanupContext(
            stylePrompt: "", formality: .neutral, language: "en",
            appContext: nil, cleanupLevel: .medium,
            removeFillers: true, experimentalPrompts: false
        )
        XCTAssertEqual(context.promptVersion, .v3)
    }

    func testUseV2PromptsBackwardCompat() {
        var context = CleanupContext(
            stylePrompt: "", formality: .neutral, language: "en",
            appContext: nil, cleanupLevel: .medium,
            removeFillers: true, experimentalPrompts: false,
            promptVersion: .v2
        )
        XCTAssertTrue(context.useV2Prompts)
        context.useV2Prompts = false
        XCTAssertEqual(context.promptVersion, .v1)
    }

    // MARK: - New AppContextMapper Keywords

    func testCursorIDEReturnsCursor() {
        let ctx = makeAppContext(appName: "Cursor", category: .codeEditor)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Cursor")
    }

    func testIDEChatPanelWithClaudeReturnsClaudeCode() {
        let ctx = makeAppContext(appName: "VS Code", category: .codeEditor,
                                windowTitle: "Claude Chat", isIDEChatPanel: true)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Claude Code")
    }

    func testTerminalSSHReturnsSSH() {
        let ctx = makeAppContext(appName: "Terminal", category: .terminal,
                                windowTitle: "ssh user@server:~/project")
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "SSH")
    }

    func testTerminalPythonReturnsPython() {
        let ctx = makeAppContext(appName: "iTerm2", category: .terminal,
                                windowTitle: "python3 — IPython")
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Python")
    }

    func testNotesObsidianReturnsObsidian() {
        let ctx = makeAppContext(appName: "Obsidian", category: .notes)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Obsidian")
    }

    func testDocumentsNotionReturnsNotion() {
        let ctx = makeAppContext(appName: "Notion", category: .documents)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Notion")
    }

    func testAIChatChatGPTReturnsAIPrompt() {
        let ctx = makeAppContext(appName: "ChatGPT", category: .aiChat)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "AI Prompt")
    }

    func testAIChatClaudeReturnsClaudeCode() {
        let ctx = makeAppContext(appName: "Claude", category: .aiChat)
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Claude Code")
    }

    func testBrowserChatGPTReturnsAIPrompt() {
        let ctx = makeAppContext(appName: "Chrome", category: .browser,
                                windowTitle: "ChatGPT - New conversation")
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "AI Prompt")
    }

    func testBrowserGitHubReturnsGitHub() {
        let ctx = makeAppContext(appName: "Chrome", category: .browser,
                                windowTitle: "Pull Request #42 - GitHub")
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "GitHub")
    }

    func testBrowserJiraReturnsJira() {
        let ctx = makeAppContext(appName: "Chrome", category: .browser,
                                windowTitle: "PROJ-123 - Jira")
        XCTAssertEqual(AppContextMapper.keyword(from: ctx), "Jira")
    }

    // MARK: - Helpers

    private func makeCleanupContext(
        appCategory: AppCategory = .workMessaging,
        appName: String = "Slack"
    ) -> CleanupContext {
        let appCtx = AppContext(
            bundleId: "com.test.\(appName.lowercased())",
            appName: appName,
            category: appCategory,
            style: .casual,
            windowTitle: nil,
            focusedFieldText: nil,
            isIDEChatPanel: false
        )
        return CleanupContext(
            stylePrompt: "",
            formality: .neutral,
            language: "en",
            appContext: appCtx,
            cleanupLevel: .medium,
            removeFillers: true,
            experimentalPrompts: false,
            promptVersion: .v3
        )
    }

    private func makeAppContext(
        appName: String,
        category: AppCategory,
        windowTitle: String? = nil,
        focusedFieldText: String? = nil,
        isIDEChatPanel: Bool = false
    ) -> AppContext {
        AppContext(
            bundleId: "com.test.\(appName.lowercased())",
            appName: appName,
            category: category,
            style: .casual,
            windowTitle: windowTitle,
            focusedFieldText: focusedFieldText,
            isIDEChatPanel: isIDEChatPanel
        )
    }
}
