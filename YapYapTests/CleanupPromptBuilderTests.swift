// CleanupPromptBuilderTests.swift
// YapYapTests
import XCTest
@testable import YapYap

final class CleanupPromptBuilderTests: XCTestCase {

    // MARK: - Full Prompt Build

    func testBuildPromptContainsRawText() {
        let context = makeContext()
        let prompt = CleanupPromptBuilder.buildPrompt(rawText: "hello world", context: context)
        XCTAssertTrue(prompt.contains("hello world"))
    }

    func testBuildPromptContainsCleanedTextMarker() {
        let context = makeContext()
        let prompt = CleanupPromptBuilder.buildPrompt(rawText: "test", context: context)
        XCTAssertTrue(prompt.contains("Cleaned text:"))
    }

    func testBuildPromptIncludesCustomStylePrompt() {
        let context = makeContext(stylePrompt: "Be concise and direct")
        let prompt = CleanupPromptBuilder.buildPrompt(rawText: "test", context: context)
        XCTAssertTrue(prompt.contains("Be concise and direct"))
    }

    func testBuildPromptIncludesSystemRole() {
        let context = makeContext()
        let prompt = CleanupPromptBuilder.buildPrompt(rawText: "test", context: context)
        XCTAssertTrue(prompt.contains("writing assistant"))
        XCTAssertTrue(prompt.contains("voice transcriptions"))
    }

    // MARK: - Formality Instructions

    func testCasualFormality() {
        let instruction = CleanupPromptBuilder.buildFormalityInstruction(.casual)
        XCTAssertTrue(instruction.lowercased().contains("casual"))
        XCTAssertTrue(instruction.lowercased().contains("contractions"))
    }

    func testNeutralFormality() {
        let instruction = CleanupPromptBuilder.buildFormalityInstruction(.neutral)
        XCTAssertTrue(instruction.lowercased().contains("professional") || instruction.lowercased().contains("everyday"))
    }

    func testFormalFormality() {
        let instruction = CleanupPromptBuilder.buildFormalityInstruction(.formal)
        XCTAssertTrue(instruction.lowercased().contains("formal"))
        XCTAssertTrue(instruction.lowercased().contains("no contractions") || instruction.lowercased().contains("polished"))
    }

    // MARK: - Cleanup Level Instructions

    func testLightCleanup() {
        let instruction = CleanupPromptBuilder.buildCleanupInstruction(.light)
        XCTAssertTrue(instruction.lowercased().contains("grammar"))
        XCTAssertTrue(instruction.lowercased().contains("exact words") || instruction.lowercased().contains("keep"))
    }

    func testMediumCleanup() {
        let instruction = CleanupPromptBuilder.buildCleanupInstruction(.medium)
        XCTAssertTrue(instruction.lowercased().contains("clarity") || instruction.lowercased().contains("restructure"))
    }

    func testHeavyCleanup() {
        let instruction = CleanupPromptBuilder.buildCleanupInstruction(.heavy)
        XCTAssertTrue(instruction.lowercased().contains("rewrite") || instruction.lowercased().contains("polish"))
    }

    // MARK: - Filler Removal Instructions

    func testFillerRemovalOff() {
        let context = makeContext(removeFillers: false)
        let instruction = CleanupPromptBuilder.buildFillerRemovalInstruction(context)
        XCTAssertTrue(instruction.lowercased().contains("preserve") || instruction.lowercased().contains("verbatim"))
    }

    func testFillerRemovalLightLevel() {
        let context = makeContext(cleanupLevel: .light, removeFillers: true)
        let instruction = CleanupPromptBuilder.buildFillerRemovalInstruction(context)
        XCTAssertTrue(instruction.lowercased().contains("um") || instruction.lowercased().contains("hesitation"))
    }

    func testFillerRemovalMediumLevel() {
        let context = makeContext(cleanupLevel: .medium, removeFillers: true)
        let instruction = CleanupPromptBuilder.buildFillerRemovalInstruction(context)
        XCTAssertTrue(instruction.lowercased().contains("self-correction") || instruction.lowercased().contains("filler"))
    }

    func testFillerRemovalHeavyLevel() {
        let context = makeContext(cleanupLevel: .heavy, removeFillers: true)
        let instruction = CleanupPromptBuilder.buildFillerRemovalInstruction(context)
        XCTAssertTrue(instruction.lowercased().contains("all") || instruction.lowercased().contains("paragraph"))
    }

    // MARK: - Style Instructions

    func testVeryCasualStyle() {
        let instruction = CleanupPromptBuilder.buildStyleInstruction(.veryCasual)
        XCTAssertTrue(instruction.lowercased().contains("no capitalization") || instruction.lowercased().contains("no trailing"))
    }

    func testCasualStyle() {
        let instruction = CleanupPromptBuilder.buildStyleInstruction(.casual)
        XCTAssertTrue(instruction.lowercased().contains("casual") || instruction.lowercased().contains("conversational"))
    }

    func testExcitedStyle() {
        let instruction = CleanupPromptBuilder.buildStyleInstruction(.excited)
        XCTAssertTrue(instruction.lowercased().contains("exclamation") || instruction.lowercased().contains("excited"))
    }

    func testFormalStyle() {
        let instruction = CleanupPromptBuilder.buildStyleInstruction(.formal)
        XCTAssertTrue(instruction.lowercased().contains("formal") || instruction.lowercased().contains("professional"))
    }

    // MARK: - App Formatting Instructions

    func testPersonalMessagingFormatting() {
        let ctx = AppContext(bundleId: "", appName: "Messages", category: .personalMessaging, style: .casual, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let instruction = CleanupPromptBuilder.buildAppFormattingInstruction(ctx)
        XCTAssertTrue(instruction.lowercased().contains("messaging") || instruction.lowercased().contains("conversational"))
    }

    func testEmailFormatting() {
        let ctx = AppContext(bundleId: "", appName: "Mail", category: .email, style: .formal, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let instruction = CleanupPromptBuilder.buildAppFormattingInstruction(ctx)
        XCTAssertTrue(instruction.lowercased().contains("email") || instruction.lowercased().contains("paragraph"))
    }

    func testIDEChatFormatting() {
        let ctx = AppContext(bundleId: "", appName: "Cursor", category: .codeEditor, style: .formal, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: true)
        let instruction = CleanupPromptBuilder.buildAppFormattingInstruction(ctx)
        XCTAssertTrue(instruction.lowercased().contains("backtick") || instruction.lowercased().contains("@filename"))
    }

    func testCodeEditorFormatting() {
        let ctx = AppContext(bundleId: "", appName: "VS Code", category: .codeEditor, style: .formal, windowTitle: nil, focusedFieldText: nil, isIDEChatPanel: false)
        let instruction = CleanupPromptBuilder.buildAppFormattingInstruction(ctx)
        XCTAssertTrue(instruction.lowercased().contains("code") || instruction.lowercased().contains("technical"))
    }

    // MARK: - Helpers

    private func makeContext(
        stylePrompt: String = "",
        formality: CleanupContext.Formality = .neutral,
        cleanupLevel: CleanupContext.CleanupLevel = .medium,
        removeFillers: Bool = true
    ) -> CleanupContext {
        CleanupContext(
            stylePrompt: stylePrompt,
            formality: formality,
            language: "en",
            appContext: nil,
            cleanupLevel: cleanupLevel,
            removeFillers: removeFillers
        )
    }
}
