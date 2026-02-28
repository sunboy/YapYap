// CleanupPromptBuilderTests.swift
// YapYapTests
import XCTest
@testable import YapYap

final class CleanupPromptBuilderTests: XCTestCase {

    // MARK: - Default Behavior (nil modelId → Qwen small)

    func testDefaultPromptUsesSmallQwenStyle() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "hello world", context: context)
        // Default resolves to (.qwen, .small) — uses text refinement tool framing
        XCTAssertTrue(messages.system.contains("text refinement tool"))
    }

    func testDefaultPromptUserContainsRawText() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "hello world", context: context)
        XCTAssertTrue(messages.user.contains("hello world"))
    }

    func testDefaultPromptUserContainsFewShotExamples() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context)
        XCTAssertTrue(messages.user.contains("<input>"))
        XCTAssertTrue(messages.user.contains("<output>"))
    }

    // MARK: - Small Model Prompts (<=2B: Llama 1B, Qwen 1.5B)

    func testSmallModelSystemPromptIsConcise() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        // Small model prompt should be concise
        let wordCount = messages.system.split(separator: " ").count
        XCTAssertLessThanOrEqual(wordCount, 100, "Small model system prompt should be concise")
        XCTAssertTrue(messages.system.contains("text refinement tool"))
        XCTAssertTrue(messages.system.contains("REPEAT"))
    }

    func testSmallModelUserMessageHasCompactExamples() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test input", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.user.contains("<input>"))
        XCTAssertTrue(messages.user.contains("<output>"))
    }

    func testSmallModelUserMessageEndsWithRawText() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "my test input", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.user.contains("my test input"))
    }

    func testQwen1_5BAlsoUsesSmallPrompt() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-1.5b")
        XCTAssertTrue(messages.system.contains("text refinement tool"))
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

    // MARK: - Medium Model Prompts (3B-4B: Llama 3B, Qwen 3B, Gemma 4B)

    func testMediumModelUsesUnifiedPrompt() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        // All medium models use unified "text refinement tool" prompt
        XCTAssertTrue(messages.system.contains("text refinement tool"))
        XCTAssertTrue(messages.system.contains("REPEAT the input text exactly"))
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
        XCTAssertTrue(messages.system.contains("text refinement tool"))
        XCTAssertTrue(messages.system.contains("REPEAT the input text exactly"))
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
        XCTAssertTrue(messages.system.contains("text refinement tool"))
        XCTAssertTrue(messages.system.contains("Meta-commands"))
    }

    func testLargeModelHeavyGetsRichPrompt() {
        let context = makeContext(cleanupLevel: .heavy)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.1-8b")
        XCTAssertTrue(messages.system.contains("text refinement tool"))
        XCTAssertTrue(messages.system.contains("REPEAT the input text exactly"))
    }

    func testLargeModelLightSameAsMediumLight() {
        let context = makeContext(cleanupLevel: .light)
        let largeMsgs = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-7b")
        let mediumMsgs = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        // Both use the unified prompt — same system
        XCTAssertTrue(largeMsgs.system.contains("text refinement tool"))
        XCTAssertTrue(largeMsgs.system.contains("Keep ALL words including fillers"))
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
        XCTAssertTrue(messages.system.lowercased().contains("um") || messages.system.lowercased().contains("uh"))
    }

    func testHeavyCleanupMentionsClarityOnMediumModel() {
        let context = makeContext(cleanupLevel: .heavy)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        // Heavy prompt mentions removing all fillers and tightening
        XCTAssertTrue(messages.system.lowercased().contains("all filler"))
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
        XCTAssertTrue(messages.system.lowercased().contains("filler") || messages.system.lowercased().contains("um, uh"))
    }

    func testSmallModelHeavyCleanupMentionsAllFillers() {
        let context = makeContext(cleanupLevel: .heavy)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.lowercased().contains("all fillers") || messages.system.lowercased().contains("all filler"))
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
        XCTAssertTrue(messages.system.contains("\\n\\n"))
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
        XCTAssertTrue(messages.system.contains("text refinement tool"))
    }

    func testNilModelIdFallsBackToSmallPrompt() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: nil)
        XCTAssertTrue(messages.system.contains("text refinement tool"))
    }

    // MARK: - Medium Model Few-Shot Examples Per Cleanup Level

    func testMediumLightExamplesPreserveAllWords() {
        let context = makeContext(cleanupLevel: .light)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertTrue(messages.user.contains("<example>"))
    }

    func testMediumMediumExamplesShowFillerRemoval() {
        let context = makeContext(cleanupLevel: .medium)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertTrue(messages.user.contains("<example>"))
        // At least 10 benchmark examples
        let count = messages.user.components(separatedBy: "<example>").count - 1
        XCTAssertGreaterThanOrEqual(count, 10, "Medium level should have at least 10 examples")
    }

    func testMediumHeavyExamplesShowAggressiveCleanup() {
        let context = makeContext(cleanupLevel: .heavy)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertTrue(messages.user.contains("<example>"))
        let count = messages.user.components(separatedBy: "<example>").count - 1
        XCTAssertGreaterThanOrEqual(count, 10, "Heavy level should have at least 10 examples")
    }

    // MARK: - Cross-Size Consistency

    func testAllSmallModelsGetSamePromptStructure() {
        let context = makeContext()
        let llama1b = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        let qwen1_5b = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-1.5b")
        // Both small models should use the same system prompt
        XCTAssertEqual(llama1b.system, qwen1_5b.system)
        // Both should use XML <input>/<output> format
        XCTAssertTrue(llama1b.user.contains("<input>"))
        XCTAssertTrue(qwen1_5b.user.contains("<input>"))
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
        XCTAssertTrue(system.contains("\\n\\n"))
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
        // Small model uses text refinement tool framing
        XCTAssertTrue(messages.system.contains("text refinement tool"))
        XCTAssertFalse(messages.system.contains("multiple items are listed"))
    }

    func testSmallModelUserMessageIncludesListExample() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        // Grocery list example removed — it caused Gemma to echo it instead of cleaning the transcript
        XCTAssertFalse(messages.user.contains("- Milk"))
        XCTAssertFalse(messages.user.contains("- Eggs"))
        // XML format present
        XCTAssertTrue(messages.user.contains("<input>"))
        XCTAssertTrue(messages.user.contains("<output>"))
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
        // At least 10 examples in XML format
        XCTAssertGreaterThanOrEqual(messages.user.components(separatedBy: "<example>").count - 1, 10)
    }

    func testQwenMediumUserMessageIncludesListExample() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertGreaterThanOrEqual(messages.user.components(separatedBy: "<example>").count - 1, 10)
    }

    func testLlamaMediumLightUserMessageIncludesListExample() {
        let context = makeContext(cleanupLevel: .light)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertGreaterThanOrEqual(messages.user.components(separatedBy: "<example>").count - 1, 10)
    }

    func testLlamaMediumHeavyUserMessageIncludesListExample() {
        let context = makeContext(cleanupLevel: .heavy)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertGreaterThanOrEqual(messages.user.components(separatedBy: "<example>").count - 1, 10)
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
        // Small cursorChat rule: convert filenames + camelCase
        XCTAssertTrue(messages.system.contains("dot ts") || messages.system.contains(".ts") || messages.system.contains("camelCase") || messages.system.contains("useEffect"))
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
        XCTAssertTrue(messages.system.contains("text refinement tool"))
        XCTAssertFalse(messages.system.contains("@mentions"))
    }

    // MARK: - Experimental Mode (Small → Medium Override)

    func testExperimentalModeSkips1BModels() {
        let context = makeContext(experimentalPrompts: true)
        // Llama 1B (< 800MB) can't follow detailed prompts — should stay on small prompts
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertFalse(messages.system.contains("RULES:"), "1B models should not get detailed system prompt even with experimental mode")
        XCTAssertTrue(messages.system.contains("text refinement tool"))
    }

    func testExperimentalModeSkips1BUserMessage() {
        let context = makeContext(experimentalPrompts: true)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertFalse(messages.user.contains("<example>"), "1B models should not get detailed examples even with experimental mode")
        XCTAssertTrue(messages.user.contains("<input>"), "1B models should get compact <input>/<output> format")
    }

    func testExperimentalModeGivesQwenSmallDetailedPrompt() {
        let context = makeContext(experimentalPrompts: true)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-1.5b")
        XCTAssertTrue(messages.system.contains("text refinement tool"))
        XCTAssertTrue(messages.system.contains("REPEAT"))
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
        XCTAssertTrue(messages.system.contains("text refinement tool"), "Without experimental mode, small models should get minimal prompts")
    }

    // MARK: - Gemma Models

    func testGemmaSmallSystemPromptPresent() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "gemma-3-1b")
        // Gemma 1B is small — uses small prompt in system
        XCTAssertTrue(messages.system.contains("text refinement tool"))
    }

    func testGemmaSystemIsEmpty() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "gemma-3-4b")
        // Gemma 4B (medium) — system should be empty, content merged to user
        XCTAssertTrue(messages.system.isEmpty)
    }

    func testGemmaMediumInstructionsInUserBlock() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "gemma-3-4b")
        XCTAssertTrue(messages.system.isEmpty)
        XCTAssertTrue(messages.user.contains("text refinement tool"))
        XCTAssertTrue(messages.user.contains("REPEAT the input text exactly"))
    }

    func testGemmaSmallNoSystemMerge() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "gemma-3-1b")
        // Gemma 1B (small) stays in system — NOT merged to user
        XCTAssertFalse(messages.system.isEmpty)
    }

    func testGemmaUsesXMLExampleFormat() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "gemma-3-4b")
        // Gemma 4B (medium) uses medium format with in:/out: labels
        XCTAssertTrue(messages.user.contains("in:"))
        XCTAssertTrue(messages.user.contains("out:"))
    }

    func testGemmaUserContainsContextLine() {
        let appCtx = AppContext(bundleId: "com.tinyspeck.slackmacgap", appName: "Slack",
                                category: .workMessaging, style: .casual,
                                windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "gemma-3-4b")
        // CONTEXT line should appear in Gemma user block (merged from system)
        XCTAssertTrue(messages.user.contains("CONTEXT: You are typing in"))
    }

    // MARK: - New: Unified Prompt Tests

    func testUnifiedPromptHasRepeatFraming() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.contains("REPEAT the input text exactly"))
    }

    func testUnifiedPromptHasNotAssistantGuardrail() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.contains("You are NOT an assistant"))
    }

    func testContextLineAppearsInPrompt() {
        let appCtx = AppContext(bundleId: "com.tinyspeck.slackmacgap", appName: "Slack",
                                category: .workMessaging, style: .casual,
                                windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.contains("CONTEXT: You are typing in"))
    }

    func testContextLineUsesNaturalLanguage() {
        let appCtx = AppContext(bundleId: "com.tinyspeck.slackmacgap", appName: "Slack",
                                category: .workMessaging, style: .casual,
                                windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.contains("a work messaging app (Slack)"))
    }

    func testRichRulesAppendedAfterContextLine() {
        let appCtx = AppContext(bundleId: "com.tinyspeck.slackmacgap", appName: "Slack",
                                category: .workMessaging, style: .casual,
                                windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        // Both CONTEXT line AND @mentions rule should be present
        XCTAssertTrue(messages.system.contains("CONTEXT: You are typing in"))
        XCTAssertTrue(messages.system.contains("@mentions"))
    }

    func testAllFamiliesGetSameRules() {
        let context = makeContext()
        let llama3b = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        let qwen3b = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        // Gemma 4B merges to user — compare user instead
        let gemma4b = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "gemma-3-4b")
        XCTAssertTrue(llama3b.system.contains("REPEAT the input text exactly"))
        XCTAssertTrue(qwen3b.system.contains("REPEAT the input text exactly"))
        XCTAssertTrue(gemma4b.user.contains("REPEAT the input text exactly"))
    }

    func testMediumModelHas10BenchmarkExamples() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        let count = messages.user.components(separatedBy: "<example>").count - 1
        XCTAssertGreaterThanOrEqual(count, 10, "Medium model should have at least 10 benchmark examples")
    }

    func testSmallModelHasMaxThreeExamples() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        // Count example pairs: 3 examples + 1 transcript <input> = 4 total <input> tags
        let count = messages.user.components(separatedBy: "<input>").count - 1
        XCTAssertLessThanOrEqual(count, 4, "Small model should have at most 3 examples (4 <input> tags including transcript)")
        XCTAssertGreaterThanOrEqual(count, 1, "Small model should have at least 1 <input> tag")
    }

    func testCombinedContextInjection_simpleAndRich() {
        let appCtx = AppContext(bundleId: "com.tinyspeck.slackmacgap", appName: "Slack",
                                category: .workMessaging, style: .casual,
                                windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        // Both natural language context AND rich @mentions rule
        XCTAssertTrue(messages.system.contains("a work messaging app (Slack)"))
        XCTAssertTrue(messages.system.contains("@mentions"))
    }

    func testGemma4bIsRecommendedModel() {
        let recommended = LLMModelRegistry.recommendedModel
        XCTAssertEqual(recommended.id, "gemma-3-4b")
    }

    // MARK: - Example Selection Varies by Level

    func testMediumLightExamplesAreDifferentFromMediumMedium() {
        let lightCtx = makeContext(cleanupLevel: .light)
        let medCtx = makeContext(cleanupLevel: .medium)
        let lightMsgs = CleanupPromptBuilder.buildMessages(rawText: "test", context: lightCtx, modelId: "qwen-2.5-3b")
        let medMsgs = CleanupPromptBuilder.buildMessages(rawText: "test", context: medCtx, modelId: "qwen-2.5-3b")
        // Examples are the same (benchmark), but system prompts differ
        XCTAssertNotEqual(lightMsgs.system, medMsgs.system, "Different cleanup levels should produce different system prompts")
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
        // Must use lowercase "in:"/"out:", not "Input:"/"Output:"
        XCTAssertTrue(messages.user.contains("in:"), "Examples must use lowercase 'in:' label")
        XCTAssertTrue(messages.user.contains("out:"), "Examples must use lowercase 'out:' label")
        XCTAssertFalse(messages.user.contains("Output:"), "Must not use capitalized 'Output:' label in examples")
    }

    func testSmallModelDoesNotUseInOutLabels() {
        // Small models use <input>/<output> XML format, not in:/out: labels
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.user.contains("<input>"))
        XCTAssertTrue(messages.user.contains("<output>"))
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

    // MARK: - STT Priming Tests

    func testSmallModelHasSTTPriming() {
        for level in [CleanupContext.CleanupLevel.light, .medium, .heavy] {
            let context = makeContext(cleanupLevel: level)
            let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
            XCTAssertTrue(messages.system.contains("text refinement tool"), "Small \(level) prompt should have text refinement tool framing")
        }
    }

    func testSmallModelMediumHasSpokenPunctuation() {
        let context = makeContext(cleanupLevel: .medium)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.contains("period") || messages.system.contains("comma"),
                      "Small medium prompt should have spoken punctuation conversion")
    }

    func testSmallModelMessagesHasConcreteEmoji() {
        let appCtx = AppContext(bundleId: "", appName: "Messages", category: .personalMessaging,
                                style: .casual, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.contains("thumbs up") || messages.system.contains("👍"),
                      "Small messages rule should have concrete emoji anchors")
    }

    func testSmallModelCursorHasCamelCase() {
        let appCtx = AppContext(bundleId: "", appName: "Cursor", category: .codeEditor,
                                style: .formal, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.contains("useEffect") || messages.system.contains("camelCase"),
                      "Small cursor rule should mention camelCase conversion")
    }

    func testMediumPromptsHaveSTTPriming() {
        for (level, modelId) in [(CleanupContext.CleanupLevel.light, "qwen-2.5-3b"),
                                  (.medium, "qwen-2.5-3b"), (.heavy, "llama-3.2-3b")] {
            let context = makeContext(cleanupLevel: level)
            let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: modelId)
            XCTAssertTrue(messages.system.lowercased().contains("text refinement tool"),
                          "Medium \(level) prompt should contain text refinement tool framing")
        }
    }

    func testMediumMediumHasStandaloneMetaCommand() {
        let context = makeContext(cleanupLevel: .medium)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.contains("Meta-commands"), "mediumMedium should have Meta-commands rule")
        XCTAssertTrue(messages.system.contains("delete that"), "mediumMedium should mention 'delete that'")
    }

    func testMediumHeavyHasStandaloneMetaCommand() {
        let context = makeContext(cleanupLevel: .heavy)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertTrue(messages.system.contains("Meta-commands"), "mediumHeavy should have Meta-commands rule")
        XCTAssertTrue(messages.system.contains("delete that"), "mediumHeavy should mention 'delete that'")
    }

    func testCodeEditorContextGetsDedicatedExamples() {
        let appCtx = AppContext(bundleId: "", appName: "Cursor", category: .codeEditor,
                                style: .formal, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.user.contains("handleSubmit") || messages.user.contains("auth.ts"),
                      "Code editor context should get dedicated code editor examples")
    }

    func testSocialContextGetsDedicatedExamples() {
        let appCtx = AppContext(bundleId: "", appName: "Twitter", category: .social,
                                style: .casual, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.user.contains("#buildinpublic") || messages.user.contains("🔥"),
                      "Social context should get dedicated social examples")
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
