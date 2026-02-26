// CleanupPromptBuilderTests.swift
// YapYapTests
import XCTest
@testable import YapYap

final class CleanupPromptBuilderTests: XCTestCase {

    // MARK: - Default Behavior (nil modelId → Qwen small)

    func testDefaultPromptUsesSmallQwenStyle() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "hello world", context: context)
        // Default resolves to (.qwen, .small) — uses smallMedium template
        XCTAssertTrue(messages.system.contains("Clean dictated speech"))
    }

    func testDefaultPromptUserContainsRawText() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "hello world", context: context)
        XCTAssertTrue(messages.user.contains("hello world"))
    }

    func testDefaultPromptUserContainsFewShotExamples() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context)
        XCTAssertTrue(messages.user.contains("IN:"))
        XCTAssertTrue(messages.user.contains("OUT:"))
    }

    // MARK: - Small Model Prompts (<=2B: Llama 1B, Qwen 1.5B)

    func testSmallModelSystemPromptIsConcise() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        // Small model prompt should be concise
        let wordCount = messages.system.split(separator: " ").count
        XCTAssertLessThanOrEqual(wordCount, 65, "Small model system prompt should be concise")
        XCTAssertTrue(messages.system.contains("Clean dictated speech"))
    }

    func testSmallModelUserMessageHasCompactExamples() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test input", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.user.contains("IN:"))
        XCTAssertTrue(messages.user.contains("OUT:"))
        XCTAssertTrue(messages.user.contains("Output only the cleaned text"))
    }

    func testSmallModelUserMessageEndsWithRawText() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "my test input", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.user.hasSuffix("my test input"))
    }

    func testQwen1_5BAlsoUsesSmallPrompt() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-1.5b")
        XCTAssertTrue(messages.system.contains("Clean dictated speech"))
    }

    func testSmallModelLightCleanupPrompt() {
        let context = makeContext(cleanupLevel: .light)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.contains("Fix punctuation"))
        XCTAssertTrue(messages.system.contains("Keep ALL words"))
        XCTAssertTrue(messages.system.contains("including fillers"))
    }

    func testSmallModelIncludesAppContextHint() {
        let appContext = AppContext(
            bundleId: "com.tinyspeck.slackmacgap",
            appName: "Slack",
            category: .workMessaging,
            style: .casual,
            windowTitle: nil,
            focusedFieldText: nil,
            isIDEChatPanel: false
        )
        let context = makeContext(appContext: appContext)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.contains("@mentions"), "Small models should get app-specific rules")
        XCTAssertTrue(messages.system.contains("#channels"))
    }

    func testSmallModelOmitsStylePrompt() {
        let context = makeContext(stylePrompt: "Be concise and direct")
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-1.5b")
        // Small models don't get custom stylePrompt (it's not wired through)
        XCTAssertFalse(messages.system.contains("Be concise and direct"))
    }

    // MARK: - Medium Model Prompts (3B-4B: Llama 3B, Qwen 3B)

    func testMediumModelUsesUnifiedPrompt() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        // All medium models now use unified mediumMedium prompt
        XCTAssertTrue(messages.system.contains("You clean up dictated speech into readable text"))
    }

    func testMediumModelUserHasDetailedExamples() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertTrue(messages.user.contains("<example>"))
        XCTAssertTrue(messages.user.contains("in:"))
        XCTAssertTrue(messages.user.contains("out:"))
        XCTAssertTrue(messages.user.contains("Transcript:"))
    }

    // MARK: - Qwen Medium Model Prompts

    func testQwenMediumSystemPromptHasRules() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.contains("You clean up dictated speech into readable text."))
    }

    func testQwenMediumUserMessageHasExamples() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.user.contains("<example>"))
        XCTAssertTrue(messages.user.contains("in:"))
        XCTAssertTrue(messages.user.contains("out:"))
        XCTAssertTrue(messages.user.contains("Transcript:"))
    }

    // MARK: - Large Model Prompts (7B+: Qwen 7B, Llama 8B)

    func testLargeModelGetsMediumLevelPromptWithMetaCommands() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-7b")
        XCTAssertTrue(messages.system.contains("speech-to-text post-processor"))
        XCTAssertTrue(messages.system.contains("Meta-commands"))
    }

    func testLargeModelHeavyGetsRichPrompt() {
        let context = makeContext(cleanupLevel: .heavy)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.1-8b")
        XCTAssertTrue(messages.system.contains("CORE BEHAVIOR"))
        XCTAssertTrue(messages.system.contains("META-COMMANDS"))
    }

    func testLargeModelLightSameAsMediumLight() {
        let context = makeContext(cleanupLevel: .light)
        let largeMsgs = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-7b")
        let mediumMsgs = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        // Large light uses the exact same base prompt as medium light
        XCTAssertTrue(largeMsgs.system.contains("punctuation and capitalization"))
        XCTAssertTrue(largeMsgs.system.contains("Do NOT remove ANY words"))
        // Same base system prompt (formality/app rules may differ only if context differs)
        XCTAssertEqual(largeMsgs.system, mediumMsgs.system)
    }

    func testLargeModelsGetMediumAppRules() {
        let appContext = AppContext(
            bundleId: "com.tinyspeck.slackmacgap",
            appName: "Slack",
            category: .workMessaging,
            style: .casual,
            windowTitle: nil,
            focusedFieldText: nil,
            isIDEChatPanel: false
        )
        let context = makeContext(appContext: appContext)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-7b")
        XCTAssertTrue(messages.system.contains("Preserve @mentions and #channels exactly"))
    }

    // MARK: - Cleanup Levels (Medium Models)

    func testLightCleanupMentionsPunctuation() {
        let context = makeContext(cleanupLevel: .light)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.lowercased().contains("punctuation"))
    }

    func testMediumCleanupMentionsFillers() {
        let context = makeContext(cleanupLevel: .medium)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.lowercased().contains("um, uh"))
    }

    func testHeavyCleanupMentionsClarityOnMediumModel() {
        let context = makeContext(cleanupLevel: .heavy)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        // Heavy prompt mentions "polished, clear text"
        XCTAssertTrue(messages.system.lowercased().contains("polished"))
    }

    // MARK: - Cleanup Levels (Small Models)

    func testSmallModelLightCleanupKeepsAllWords() {
        let context = makeContext(cleanupLevel: .light)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.contains("Fix punctuation"))
        XCTAssertTrue(messages.system.contains("Keep ALL words"), "Light cleanup should instruct keeping all words")
    }

    func testSmallModelMediumCleanupMentionsFillers() {
        let context = makeContext(cleanupLevel: .medium)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.lowercased().contains("filler"))
    }

    func testSmallModelHeavyCleanupMentionsPolished() {
        let context = makeContext(cleanupLevel: .heavy)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.lowercased().contains("polished"))
    }

    // MARK: - Formality (Medium Models)

    func testCasualFormalityInMediumModel() {
        let context = makeContext(formality: .casual)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.lowercased().contains("casual"))
    }

    func testFormalFormalityInMediumModel() {
        let context = makeContext(formality: .formal)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.contains("Expand contractions"))
        XCTAssertTrue(messages.system.contains("Professional vocabulary"))
    }

    func testNeutralFormalityOmitsExtraInstruction() {
        let context = makeContext(formality: .neutral)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertFalse(messages.system.contains("contractions"))
    }

    func testSmallModelCasualFormality() {
        let context = makeContext(formality: .casual)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.contains("Use contractions"))
    }

    func testSmallModelFormalFormality() {
        let context = makeContext(formality: .formal)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.contains("Expand contractions"))
    }

    // MARK: - App Context (Medium Models)

    func testAppContextInjectedInMediumModel() {
        let appContext = AppContext(
            bundleId: "com.tinyspeck.slackmacgap",
            appName: "Slack",
            category: .workMessaging,
            style: .casual,
            windowTitle: nil,
            focusedFieldText: nil,
            isIDEChatPanel: false
        )
        let context = makeContext(appContext: appContext)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertTrue(messages.system.contains("@mentions"))
        XCTAssertTrue(messages.system.contains("#channels"))
    }

    func testEmailAppContextInMediumModel() {
        let appContext = AppContext(
            bundleId: "com.apple.mail",
            appName: "Mail",
            category: .email,
            style: .formal,
            windowTitle: nil,
            focusedFieldText: nil,
            isIDEChatPanel: false
        )
        let context = makeContext(appContext: appContext)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.contains("email"))
        XCTAssertTrue(messages.system.contains("paragraph breaks"))
    }

    func testCodeEditorContextHasTechnicalTerms() {
        let appContext = AppContext(
            bundleId: "com.microsoft.VSCode",
            appName: "VS Code",
            category: .codeEditor,
            style: .formal,
            windowTitle: nil,
            focusedFieldText: nil,
            isIDEChatPanel: false
        )
        let context = makeContext(appContext: appContext)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertTrue(messages.system.contains("technical terms"))
    }

    func testNoAppContextOmitsAppRules() {
        let context = makeContext(appContext: nil)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertFalse(messages.system.contains("@mentions"))
        XCTAssertFalse(messages.system.contains("paragraph breaks"))
    }

    // MARK: - Unknown Model Falls Back to Qwen Small

    func testUnknownModelIdFallsBackToSmallPrompt() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "nonexistent-model")
        XCTAssertTrue(messages.system.contains("Clean dictated speech"))
    }

    func testNilModelIdFallsBackToSmallPrompt() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: nil)
        XCTAssertTrue(messages.system.contains("Clean dictated speech"))
    }

    // MARK: - Medium Model Few-Shot Examples Per Cleanup Level

    func testMediumLightExamplesPreserveAllWords() {
        let context = makeContext(cleanupLevel: .light)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertTrue(messages.user.contains("<example>"))
        // Light examples keep fillers: "um probably" preserved in output
        XCTAssertTrue(messages.user.contains("um probably"))
    }

    func testMediumMediumExamplesShowFillerRemoval() {
        let context = makeContext(cleanupLevel: .medium)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        // Medium level has 3 examples — check for 3 <example> blocks
        XCTAssertTrue(messages.user.contains("<example>"))
        XCTAssertEqual(messages.user.components(separatedBy: "<example>").count - 1, 3, "Medium level should have 3 examples")
    }

    func testMediumHeavyExamplesShowAggressiveCleanup() {
        let context = makeContext(cleanupLevel: .heavy)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        // Heavy level has 2 examples
        XCTAssertTrue(messages.user.contains("<example>"))
        XCTAssertEqual(messages.user.components(separatedBy: "<example>").count - 1, 2, "Heavy level should have 2 examples")
    }

    // MARK: - Cross-Size Consistency

    func testAllSmallModelsGetSamePromptStructure() {
        let context = makeContext()
        let llama1b = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        let qwen1_5b = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-1.5b")
        // Both small models should use the same system prompt
        XCTAssertEqual(llama1b.system, qwen1_5b.system)
        // Both should use compact IN:/OUT: examples
        XCTAssertTrue(llama1b.user.contains("IN:"))
        XCTAssertTrue(qwen1_5b.user.contains("IN:"))
    }

    func testMediumModelsGetUnifiedPrompts() {
        let context = makeContext()
        let llama3b = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        let qwen3b = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        // Both medium models now get the SAME unified prompt
        XCTAssertEqual(llama3b.system, qwen3b.system)
        XCTAssertTrue(llama3b.user.contains("<example>"))
        XCTAssertTrue(qwen3b.user.contains("<example>"))
    }

    // MARK: - IDE Chat Panel Prompt

    func testIDEChatPanelToneHintIncludesFilePrefixInstruction() {
        let appCtx = AppContext(bundleId: "", appName: "Cursor", category: .codeEditor,
                                style: .formal, windowTitle: "Composer",
                                focusedFieldText: nil, isIDEChatPanel: true)
        let context = makeContext(appContext: appCtx)
        let (system, _) = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(system.contains("Prefix ALL filenames with @"))
    }

    func testNonIDEChatPanelDoesNotIncludeFilePrefixInstruction() {
        let appCtx = AppContext(bundleId: "", appName: "VS Code", category: .codeEditor,
                                style: .formal, windowTitle: nil,
                                focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let (system, _) = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertFalse(system.contains("Prefix ALL filenames"))
        XCTAssertTrue(system.contains("technical terms"))
    }

    // MARK: - App Context Rules (Rich Rules)

    func testWorkMessagingRulesInMediumModel() {
        let appCtx = AppContext(bundleId: "", appName: "Slack", category: .workMessaging,
                                style: .casual, windowTitle: nil,
                                focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let (system, _) = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(system.contains("@mentions"))
        XCTAssertTrue(system.contains("#channels"))
    }

    func testEmailRulesInMediumModel() {
        let appCtx = AppContext(bundleId: "", appName: "Mail", category: .email,
                                style: .formal, windowTitle: nil,
                                focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let (system, _) = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(system.contains("paragraph breaks"))
    }

    func testAIChatRulesInMediumModel() {
        let appCtx = AppContext(bundleId: "", appName: "ChatGPT", category: .aiChat,
                                style: .casual, windowTitle: nil,
                                focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let (system, _) = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(system.contains("code references"))
    }

    // MARK: - List Formatting Instruction

    func testQwenMediumSystemIncludesListInstruction() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.contains("explicitly enumerates"))
        // Must not trigger on multi-clause sentences
        XCTAssertFalse(messages.system.contains("lists or enumerates multiple things"))
    }

    func testLlamaMediumSystemIncludesListInstruction() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertTrue(messages.system.contains("explicitly enumerates"))
        XCTAssertFalse(messages.system.contains("lists or enumerates multiple things"))
    }

    func testSmallModelIncludesListInstruction() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        // Small model uses template-based system prompt — verify it contains cleanup instructions
        XCTAssertTrue(messages.system.contains("Clean dictated speech"))
        XCTAssertFalse(messages.system.contains("multiple items are listed"))
    }

    func testSmallModelUserMessageIncludesListExample() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        // Grocery list example removed — it caused Gemma to echo it instead of cleaning the transcript
        XCTAssertFalse(messages.user.contains("- Milk"))
        XCTAssertFalse(messages.user.contains("- Eggs"))
        // Basic IN/OUT format still present
        XCTAssertTrue(messages.user.contains("IN:"))
        XCTAssertTrue(messages.user.contains("OUT:"))
    }

    func testMediumModelIncludesListInstruction() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.contains("explicitly enumerates"))
    }

    func testLlamaMediumIncludesListInstructionInConstraints() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertTrue(messages.system.contains("explicitly enumerates"))
    }

    func testLlamaMediumUserMessageIncludesListExample() {
        let context = makeContext(cleanupLevel: .medium)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        // Medium cleanup has 3 examples in XML format
        XCTAssertEqual(messages.user.components(separatedBy: "<example>").count - 1, 3)
    }

    func testQwenMediumUserMessageIncludesListExample() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        // Medium cleanup (default level) has 3 examples in XML format
        XCTAssertEqual(messages.user.components(separatedBy: "<example>").count - 1, 3)
    }

    func testLlamaMediumLightUserMessageIncludesListExample() {
        let context = makeContext(cleanupLevel: .light)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        // Light examples have 3 examples in XML format
        XCTAssertEqual(messages.user.components(separatedBy: "<example>").count - 1, 3)
    }

    func testLlamaMediumHeavyUserMessageIncludesListExample() {
        let context = makeContext(cleanupLevel: .heavy)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        // Heavy examples have 2 examples in XML format
        XCTAssertEqual(messages.user.components(separatedBy: "<example>").count - 1, 2)
    }

    // MARK: - Small Model App Context Hints

    func testSmallModelEmailHint() {
        let appCtx = AppContext(bundleId: "", appName: "Mail", category: .email,
                                style: .formal, windowTitle: nil,
                                focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.contains("Professional"))
    }

    func testSmallModelIDEChatHint() {
        let appCtx = AppContext(bundleId: "", appName: "Cursor", category: .codeEditor,
                                style: .formal, windowTitle: "Composer",
                                focusedFieldText: nil, isIDEChatPanel: true)
        let context = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-1.5b")
        XCTAssertTrue(messages.system.contains("Prefix filenames with @"))
    }

    func testSmallModelPersonalMessagingHint() {
        let appCtx = AppContext(bundleId: "", appName: "Messages", category: .personalMessaging,
                                style: .veryCasual, windowTitle: nil,
                                focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.contains("Casual"))
    }

    func testSmallModelAIChatHint() {
        let appCtx = AppContext(bundleId: "", appName: "ChatGPT", category: .aiChat,
                                style: .casual, windowTitle: nil,
                                focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.contains("technical terms"))
    }

    func testSmallModelNoAppContextNoHint() {
        let context = makeContext(appContext: nil)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        // Without app context, should just have base prompt
        XCTAssertTrue(messages.system.contains("Clean dictated speech"))
        XCTAssertFalse(messages.system.contains("@mentions"))
    }

    // MARK: - Experimental Mode (Small → Medium Override)

    func testExperimentalModeSkips1BModels() {
        let context = makeContext(experimentalPrompts: true)
        // Llama 1B (< 800MB) can't follow detailed prompts — should stay on small prompts
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertFalse(messages.system.contains("RULES:"), "1B models should not get detailed system prompt even with experimental mode")
        XCTAssertTrue(messages.system.contains("Clean dictated speech"))
    }

    func testExperimentalModeSkips1BUserMessage() {
        let context = makeContext(experimentalPrompts: true)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertFalse(messages.user.contains("<example>"), "1B models should not get detailed examples even with experimental mode")
        XCTAssertTrue(messages.user.contains("IN:"), "1B models should get compact IN:/OUT: format")
    }

    func testExperimentalModeGivesQwenSmallDetailedPrompt() {
        let context = makeContext(experimentalPrompts: true)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-1.5b")
        XCTAssertTrue(messages.system.contains("You clean up dictated speech into readable text."))
        XCTAssertTrue(messages.user.contains("<example>"))
    }

    func testExperimentalModeIncludesFormality() {
        let context = makeContext(formality: .formal, experimentalPrompts: true)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-1.5b")
        XCTAssertTrue(messages.system.contains("Expand contractions"), "Experimental mode should enable formality for small Qwen models")
    }

    func testExperimentalModeDoesNotAffectMediumModels() {
        let context = makeContext(experimentalPrompts: true)
        let withExp = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        let withoutExp = CleanupPromptBuilder.buildMessages(rawText: "test", context: makeContext(experimentalPrompts: false), modelId: "llama-3.2-3b")
        XCTAssertEqual(withExp.system, withoutExp.system, "Experimental mode should not change medium model prompts")
        XCTAssertEqual(withExp.user, withoutExp.user)
    }

    func testExperimentalModeOffUsesSmallPrompt() {
        let context = makeContext(experimentalPrompts: false)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.contains("Clean dictated speech"), "Without experimental mode, small models should get minimal prompts")
    }

    // MARK: - Gemma Models

    func testGemmaGetsMinimalSystemPrompt() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "gemma-3-1b")
        XCTAssertEqual(messages.system, PromptTemplates.System.gemmaSystem)
    }

    func testGemmaMediumInstructionsInUserBlock() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "gemma-3-4b")
        XCTAssertEqual(messages.system, PromptTemplates.System.gemmaSystem)
        XCTAssertTrue(messages.user.contains("INSTRUCTIONS:"))
        XCTAssertTrue(messages.user.contains("You clean up dictated speech"))
    }

    func testGemmaSmallNoInstructionsInUserBlock() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "gemma-3-1b")
        XCTAssertFalse(messages.user.contains("INSTRUCTIONS:"))
    }

    func testGemmaUsesINOUTExampleFormat() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "gemma-3-4b")
        XCTAssertTrue(messages.user.contains("IN:"))
        XCTAssertTrue(messages.user.contains("OUT:"))
    }

    // MARK: - Example Selection Varies by Level

    func testMediumLightExamplesAreDifferentFromMediumMedium() {
        let lightCtx = makeContext(cleanupLevel: .light)
        let medCtx = makeContext(cleanupLevel: .medium)
        let lightMsgs = CleanupPromptBuilder.buildMessages(rawText: "test", context: lightCtx, modelId: "qwen-2.5-3b")
        let medMsgs = CleanupPromptBuilder.buildMessages(rawText: "test", context: medCtx, modelId: "qwen-2.5-3b")
        XCTAssertNotEqual(lightMsgs.user, medMsgs.user, "Different cleanup levels should produce different examples")
    }

    // MARK: - Echo-Safe Example Format

    func testMediumModelUsesXMLExampleFormat() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        // Must use XML tags, not EXAMPLE N: labels
        XCTAssertTrue(messages.user.contains("<example>"), "Medium model must use XML example tags")
        XCTAssertTrue(messages.user.contains("</example>"), "XML tags must be closed")
        XCTAssertFalse(messages.user.contains("EXAMPLE 1:"), "Old EXAMPLE N: format must be gone")
        XCTAssertFalse(messages.user.contains("EXAMPLE 2:"), "Old EXAMPLE N: format must be gone")
    }

    func testMediumModelExamplesUseLowercaseInOutLabels() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        // Must use lowercase "in:"/"out:", not "Input:"/"Output:" (avoids triggering sanitizeOutput)
        XCTAssertTrue(messages.user.contains("in:"), "Examples must use lowercase 'in:' label")
        XCTAssertTrue(messages.user.contains("out:"), "Examples must use lowercase 'out:' label")
        XCTAssertFalse(messages.user.contains("Input:"), "Must not use capitalized 'Input:' label")
        XCTAssertFalse(messages.user.contains("Output:"), "Must not use capitalized 'Output:' label in examples")
    }

    func testSmallModelDoesNotUseXMLFormat() {
        // Small models use IN:/OUT: format, not XML
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertFalse(messages.user.contains("<example>"))
        XCTAssertTrue(messages.user.contains("IN:"))
        XCTAssertTrue(messages.user.contains("OUT:"))
    }

    // MARK: - Prompt Repetition Technique (arxiv 2512.14982)

    func testMediumModelRepeatsTranscript() {
        let context = makeContext()
        let rawText = "um so I was thinking about the meeting"
        let messages = CleanupPromptBuilder.buildMessages(rawText: rawText, context: context, modelId: "qwen-2.5-3b")
        // Transcript should appear twice in the user prompt
        let occurrences = messages.user.components(separatedBy: rawText).count - 1
        XCTAssertEqual(occurrences, 2, "Medium model should repeat transcript twice for better instruction following")
    }

    func testLargeModelRepeatsTranscript() {
        let context = makeContext()
        let rawText = "um so I was thinking about the meeting"
        let messages = CleanupPromptBuilder.buildMessages(rawText: rawText, context: context, modelId: "qwen-2.5-7b")
        let occurrences = messages.user.components(separatedBy: rawText).count - 1
        XCTAssertEqual(occurrences, 2, "Large model should repeat transcript twice")
    }

    func testSmallModelDoesNotRepeatTranscript() {
        let context = makeContext()
        let rawText = "um so I was thinking about the meeting"
        let messages = CleanupPromptBuilder.buildMessages(rawText: rawText, context: context, modelId: "llama-3.2-1b")
        let occurrences = messages.user.components(separatedBy: rawText).count - 1
        XCTAssertEqual(occurrences, 1, "Small model should NOT repeat transcript")
    }

    // MARK: - UserPromptContext Parameter

    func testBuildMessagesAcceptsNilUserContext() {
        let context = makeContext()
        // Should not crash with nil userContext
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b", userContext: nil)
        XCTAssertFalse(messages.user.isEmpty)
    }

    // MARK: - Dictation Enhancement Instructions (Numbers, Abbreviations, Spoken Punctuation)

    func testMediumMediumHasNumberConversion() {
        let context = makeContext(cleanupLevel: .medium)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.contains("Numbers: convert spoken numbers to digits"))
    }

    func testMediumHeavyHasNumberConversion() {
        let context = makeContext(cleanupLevel: .heavy)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.contains("Numbers: convert spoken numbers to digits"))
    }

    func testMediumMediumHasSpokenPunctuation() {
        let context = makeContext(cleanupLevel: .medium)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.contains("new line"))
        XCTAssertTrue(messages.system.contains("new paragraph"))
    }

    func testMediumMediumHasAbbreviationExpansion() {
        let context = makeContext(cleanupLevel: .medium)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.contains("thx → thanks"))
        XCTAssertTrue(messages.system.contains("gonna → going to"))
    }

    func testLargeMediumHasNumberConversion() {
        let context = makeContext(cleanupLevel: .medium)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-7b")
        XCTAssertTrue(messages.system.contains("Numbers: convert spoken numbers to digits"))
    }

    func testLargeHeavyHasAbbreviationExpansion() {
        let context = makeContext(cleanupLevel: .heavy)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-7b")
        XCTAssertTrue(messages.system.contains("thx → thanks"))
    }

    func testSmallModelDoesNotHaveNumberConversion() {
        let context = makeContext(cleanupLevel: .medium)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertFalse(messages.system.contains("Numbers: convert spoken numbers"))
    }

    func testLightCleanupDoesNotHaveNumberConversion() {
        let context = makeContext(cleanupLevel: .light)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertFalse(messages.system.contains("Numbers: convert spoken numbers"))
    }

    // MARK: - Helpers

    private func makeContext(
        stylePrompt: String = "",
        formality: CleanupContext.Formality = .neutral,
        cleanupLevel: CleanupContext.CleanupLevel = .medium,
        appContext: AppContext? = nil,
        removeFillers: Bool = true,
        experimentalPrompts: Bool = false
    ) -> CleanupContext {
        CleanupContext(
            stylePrompt: stylePrompt,
            formality: formality,
            language: "en",
            appContext: appContext,
            cleanupLevel: cleanupLevel,
            removeFillers: removeFillers,
            experimentalPrompts: experimentalPrompts
        )
    }
}
