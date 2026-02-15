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

    func testSmallModelSystemPromptIsUltraMinimal() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        // Small model prompt should be under 15 words
        let wordCount = messages.system.split(separator: " ").count
        XCTAssertLessThanOrEqual(wordCount, 15, "Small model system prompt should be ultra-minimal")
        XCTAssertTrue(messages.system.contains("Fix dictation"))
    }

    func testSmallModelUserMessageHasCompactExamples() {
        let context = makeContext()
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test input", context: context, modelId: "llama-3.2-1b")
        XCTAssertTrue(messages.user.contains("IN:"))
        XCTAssertTrue(messages.user.contains("OUT:"))
        XCTAssertTrue(messages.user.contains("Fix this:"))
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

    func testSmallModelOmitsAppContext() {
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
        XCTAssertFalse(messages.system.contains("Slack"), "Small models should not get app context")
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
        XCTAssertTrue(messages.user.contains("NOW CLEAN THIS TRANSCRIPT:"))
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
        XCTAssertTrue(messages.user.contains("NOW CLEAN THIS TRANSCRIPT:"))
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
        // Medium examples show "um" removal
        XCTAssertTrue(messages.user.contains("um so"))
        XCTAssertTrue(messages.user.contains("EXAMPLE 3:"))
    }

    func testLlamaMediumHeavyExamplesShowAggressiveCleanup() {
        let context = makeContext(cleanupLevel: .heavy)
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-3b")
        XCTAssertTrue(messages.user.contains("EXAMPLE 1:"))
        // Heavy has fewer examples (2 instead of 3) but more aggressive
        XCTAssertFalse(messages.user.contains("EXAMPLE 3:"))
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

    // MARK: - Helpers

    private func makeContext(
        stylePrompt: String = "",
        formality: CleanupContext.Formality = .neutral,
        cleanupLevel: CleanupContext.CleanupLevel = .medium,
        appContext: AppContext? = nil,
        removeFillers: Bool = true
    ) -> CleanupContext {
        CleanupContext(
            stylePrompt: stylePrompt,
            formality: formality,
            language: "en",
            appContext: appContext,
            cleanupLevel: cleanupLevel,
            removeFillers: removeFillers
        )
    }
}
