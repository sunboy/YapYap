// CleanupPromptBuilderTests.swift
// YapYapTests
import XCTest
@testable import YapYap

final class CleanupPromptBuilderTests: XCTestCase {

    // MARK: - Default Behavior (nil modelId → Qwen small)

    func testDefaultPromptUsesSmallQwenStyle() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "hello world", context: context)
        // Default resolves to (.qwen, .small) — ultra-minimal prompt
        XCTAssertTrue(messages.system.contains("Fix dictation"))
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
        // Small model prompt should be concise (under 65 words including list hint and self-correction rule)
        let wordCount = messages.system.split(separator: " ").count
        XCTAssertLessThanOrEqual(wordCount, 65, "Small model system prompt should be concise")
        XCTAssertTrue(messages.system.contains("Fix dictation"))
    }

    func testSmallModelUserMessageHasCompactExamples() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test input", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.user.contains("IN:"))
        XCTAssertTrue(messages.user.contains("OUT:"))
        XCTAssertTrue(messages.user.contains("Reply with only the fixed text"))
    }

    func testSmallModelUserMessageEndsWithRawText() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "my test input", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.user.hasSuffix("my test input"))
    }

    func testQwen1_5BAlsoUsesSmallPrompt() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-1.5b")
        XCTAssertTrue(messages.system.contains("Fix dictation"))
    }

    func testSmallModelOmitsFormality() {
        let context = makeContext(formality: .casual)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertFalse(messages.system.contains("casual"), "Small models should not get formality instructions")
    }

    func testSmallModelIncludesConciseAppContextHint() {
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
        // Small models now get concise app context hints (not the app name, but the category hint)
        XCTAssertTrue(messages.system.contains("@mentions"), "Small models should get concise work messaging hint")
    }

    func testSmallModelOmitsStylePrompt() {
        let context = makeContext(stylePrompt: "Be concise and direct")
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-1.5b")
        XCTAssertFalse(messages.system.contains("Be concise and direct"), "Small models should not get custom style prompts")
    }

    // MARK: - Medium Model Prompts (3B+: Llama 3B, Qwen 3B/7B)

    func testLlama3BUsesDetailedPrompt() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertTrue(messages.system.contains("speech-to-text cleanup engine"))
        XCTAssertTrue(messages.system.contains("STRICT CONSTRAINTS"))
    }

    func testLlama3BUserHasDetailedExamples() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertTrue(messages.user.contains("EXAMPLE 1:"))
        XCTAssertTrue(messages.user.contains("Transcript:"))
    }

    // MARK: - Qwen Medium Model Prompts

    func testQwenMediumSystemPromptHasRules() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.contains("You clean up speech-to-text transcripts."))
    }

    func testQwenMediumUserMessageHasExamples() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.user.contains("EXAMPLE 1:"))
        XCTAssertTrue(messages.user.contains("Transcript:"))
    }

    func testQwenMediumIncludesCustomStylePrompt() {
        let context = makeContext(stylePrompt: "Be concise and direct")
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.contains("Be concise and direct"))
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
        XCTAssertTrue(messages.system.lowercased().contains("clarity"))
    }

    // MARK: - Cleanup Levels (Small Models)

    func testSmallModelLightCleanupOmitsFillers() {
        let context = makeContext(cleanupLevel: .light)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.contains("Fix dictation"))
        XCTAssertFalse(messages.system.contains("filler"), "Light cleanup on small model should not mention fillers")
    }

    func testSmallModelMediumCleanupMentionsFillers() {
        let context = makeContext(cleanupLevel: .medium)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.contains("filler"))
    }

    func testSmallModelHeavyCleanupMentionsClarity() {
        let context = makeContext(cleanupLevel: .heavy)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.lowercased().contains("clarity"))
    }

    // MARK: - Formality (Medium Models)

    func testCasualFormalityInQwenMedium() {
        let context = makeContext(formality: .casual)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.lowercased().contains("casual"))
    }

    func testFormalFormalityInQwenMedium() {
        let context = makeContext(formality: .formal)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.system.lowercased().contains("formal"))
    }

    func testNeutralFormalityOmitsExtraInstruction() {
        let context = makeContext(formality: .neutral)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertFalse(messages.system.contains("Tone: casual"))
        XCTAssertFalse(messages.system.contains("Tone: formal"))
    }

    // MARK: - App Context (Medium Models)

    func testAppContextInjectedInLlamaMedium() {
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
        XCTAssertTrue(messages.system.contains("Slack"))
        XCTAssertTrue(messages.system.contains("work messaging"))
    }

    func testAppContextInjectedInQwenMedium() {
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
        XCTAssertTrue(messages.system.contains("Mail"))
        XCTAssertTrue(messages.system.contains("email"))
    }

    func testCodeEditorContextKeepsTechnicalTerms() {
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

    func testNoAppContextOmitsAppLine() {
        let context = makeContext(appContext: nil)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertFalse(messages.system.contains("App:"))
    }

    // MARK: - Unknown Model Falls Back to Qwen Small

    func testUnknownModelIdFallsBackToSmallPrompt() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "nonexistent-model")
        // Unknown models fall back to (.qwen, .small) — ultra-minimal
        XCTAssertTrue(messages.system.contains("Fix dictation"))
    }

    func testNilModelIdFallsBackToSmallPrompt() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: nil)
        XCTAssertTrue(messages.system.contains("Fix dictation"))
    }

    // MARK: - Llama Medium Few-Shot Examples Per Cleanup Level

    func testLlamaMediumLightExamplesPreserveAllWords() {
        let context = makeContext(cleanupLevel: .light)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        // Light examples should NOT show filler removal
        XCTAssertTrue(messages.user.contains("EXAMPLE 1:"))
        XCTAssertFalse(messages.user.contains("um so"))
    }

    func testLlamaMediumExamplesShowFillerRemoval() {
        let context = makeContext(cleanupLevel: .medium)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        // Medium examples show "um" removal + list example
        XCTAssertTrue(messages.user.contains("um so"))
        XCTAssertTrue(messages.user.contains("EXAMPLE 3:"))
        XCTAssertTrue(messages.user.contains("EXAMPLE 4:"))
    }

    func testLlamaMediumHeavyExamplesShowAggressiveCleanup() {
        let context = makeContext(cleanupLevel: .heavy)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertTrue(messages.user.contains("EXAMPLE 1:"))
        // Heavy has 3 examples (2 prose + 1 list) but no EXAMPLE 4
        XCTAssertTrue(messages.user.contains("EXAMPLE 3:"))
        XCTAssertFalse(messages.user.contains("EXAMPLE 4:"))
    }

    // MARK: - Cross-Size Consistency

    func testAllSmallModelsGetSamePromptStructure() {
        let context = makeContext()
        let llama1b = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        let qwen1_5b = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-1.5b")
        // Both small models should use ultra-minimal prompts
        XCTAssertTrue(llama1b.system.contains("Fix dictation"))
        XCTAssertTrue(qwen1_5b.system.contains("Fix dictation"))
        // Both should use compact IN:/OUT: examples
        XCTAssertTrue(llama1b.user.contains("IN:"))
        XCTAssertTrue(qwen1_5b.user.contains("IN:"))
    }

    func testMediumModelsGetDetailedPrompts() {
        let context = makeContext()
        let llama3b = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        let qwen3b = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        // Both medium models should get detailed prompts
        XCTAssertTrue(llama3b.user.contains("EXAMPLE 1:"))
        XCTAssertTrue(qwen3b.user.contains("EXAMPLE 1:"))
        // But with family-specific system prompts
        XCTAssertTrue(llama3b.system.contains("speech-to-text cleanup engine"))
        XCTAssertTrue(qwen3b.system.contains("You clean up speech-to-text transcripts."))
    }

    // MARK: - IDE Chat Panel Prompt

    func testIDEChatPanelToneHintIncludesFilePrefixInstruction() {
        let appCtx = AppContext(bundleId: "", appName: "Cursor", category: .codeEditor,
                                style: .formal, windowTitle: "Composer",
                                focusedFieldText: nil, isIDEChatPanel: true)
        let context = makeContext(appContext: appCtx)
        let (system, _) = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(system.contains("prefix filenames with @"))
    }

    func testNonIDEChatPanelDoesNotIncludeFilePrefixInstruction() {
        let appCtx = AppContext(bundleId: "", appName: "VS Code", category: .codeEditor,
                                style: .formal, windowTitle: nil,
                                focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let (system, _) = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertFalse(system.contains("prefix filenames with @"))
        XCTAssertTrue(system.contains("code editor"))
    }

    // MARK: - Updated Tone Hints

    func testWorkMessagingToneHintIncludesSlack() {
        let appCtx = AppContext(bundleId: "", appName: "Slack", category: .workMessaging,
                                style: .casual, windowTitle: nil,
                                focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let (system, _) = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(system.contains("Slack/Teams"))
        XCTAssertTrue(system.contains("@mentions"))
        XCTAssertTrue(system.contains("#channels"))
    }

    func testEmailToneHintIncludesParagraphStructure() {
        let appCtx = AppContext(bundleId: "", appName: "Mail", category: .email,
                                style: .formal, windowTitle: nil,
                                focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let (system, _) = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(system.contains("paragraph structure"))
    }

    func testAIChatToneHintIncludesCodeReferences() {
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
        XCTAssertTrue(messages.system.contains("explicitly"))
        // Old over-broad wording removed — no longer triggers on any multi-clause sentence
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
        XCTAssertTrue(messages.user.contains("EXAMPLE 4:"))
        XCTAssertTrue(messages.user.contains("1. An iOS app"))
    }

    func testQwenMediumUserMessageIncludesListExample() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-3b")
        XCTAssertTrue(messages.user.contains("EXAMPLE 4:"))
        XCTAssertTrue(messages.user.contains("1. An iOS app"))
    }

    func testLlamaMediumLightUserMessageIncludesListExample() {
        let context = makeContext(cleanupLevel: .light)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertTrue(messages.user.contains("EXAMPLE 3:"))
        XCTAssertTrue(messages.user.contains("- Pick up groceries"))
    }

    func testLlamaMediumHeavyUserMessageIncludesListExample() {
        let context = makeContext(cleanupLevel: .heavy)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertTrue(messages.user.contains("EXAMPLE 3:"))
        XCTAssertTrue(messages.user.contains("1. Fix the auth bug"))
    }

    // MARK: - Small Model App Context Hints

    func testSmallModelEmailHint() {
        let appCtx = AppContext(bundleId: "", appName: "Mail", category: .email,
                                style: .formal, windowTitle: nil,
                                focusedFieldText: nil, isIDEChatPanel: false)
        let context = makeContext(appContext: appCtx)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.system.contains("proper sentences"))
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
        XCTAssertTrue(messages.system.contains("casual"))
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
        // Without app context, should just have base prompt + list hint
        XCTAssertTrue(messages.system.contains("Fix dictation"))
        XCTAssertTrue(messages.system.contains("explicitly"))
        XCTAssertFalse(messages.system.contains("@mentions"))
        XCTAssertFalse(messages.system.contains("proper sentences"))
    }

    // MARK: - Experimental Mode (Small → Medium Override)

    func testExperimentalModeSkips1BModels() {
        let context = makeContext(experimentalPrompts: true)
        // Llama 1B (< 800MB) can't follow detailed prompts — should stay on small prompts
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertFalse(messages.system.contains("speech-to-text cleanup engine"), "1B models should not get detailed system prompt even with experimental mode")
        XCTAssertFalse(messages.system.contains("STRICT CONSTRAINTS"))
        XCTAssertTrue(messages.system.contains("Fix dictation errors"))
    }

    func testExperimentalModeSkips1BUserMessage() {
        let context = makeContext(experimentalPrompts: true)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertFalse(messages.user.contains("EXAMPLE 1:"), "1B models should not get detailed examples even with experimental mode")
        XCTAssertTrue(messages.user.contains("IN:"), "1B models should get compact IN:/OUT: format")
    }

    func testExperimentalModeGivesQwenSmallDetailedPrompt() {
        let context = makeContext(experimentalPrompts: true)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-1.5b")
        XCTAssertTrue(messages.system.contains("You clean up speech-to-text transcripts."))
        XCTAssertTrue(messages.user.contains("EXAMPLE 1:"))
    }

    func testExperimentalModeIncludesFormality() {
        let context = makeContext(formality: .formal, experimentalPrompts: true)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-1.5b")
        XCTAssertTrue(messages.system.contains("formal"), "Experimental mode should enable formality for small Qwen models")
    }

    func testExperimentalModeIncludesStylePrompt() {
        let context = makeContext(stylePrompt: "Be concise", experimentalPrompts: true)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "qwen-2.5-1.5b")
        XCTAssertTrue(messages.system.contains("Be concise"), "Experimental mode should enable custom style for small models")
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
        XCTAssertTrue(messages.system.contains("Fix dictation"), "Without experimental mode, small models should get minimal prompts")
        XCTAssertFalse(messages.system.contains("STRICT CONSTRAINTS"))
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
