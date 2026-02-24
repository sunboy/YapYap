// CommandModeTests.swift
// YapYapTests
import XCTest
@testable import YapYap

final class CommandModeTests: XCTestCase {

    // MARK: - Command Prefix Detection (Edit)

    func testDetectsMakeThis() {
        XCTAssertTrue(CommandMode.isCommand("Make this more professional"))
    }

    func testDetectsRewrite() {
        XCTAssertTrue(CommandMode.isCommand("Rewrite this as bullet points"))
    }

    func testDetectsShorten() {
        XCTAssertTrue(CommandMode.isCommand("Shorten this paragraph"))
    }

    func testDetectsSummarize() {
        XCTAssertTrue(CommandMode.isCommand("Summarize this email"))
    }

    func testDetectsExpand() {
        XCTAssertTrue(CommandMode.isCommand("Expand this into a full paragraph"))
    }

    func testDetectsTranslate() {
        XCTAssertTrue(CommandMode.isCommand("Translate this to Spanish"))
    }

    func testDetectsFixGrammar() {
        XCTAssertTrue(CommandMode.isCommand("Fix the grammar in this"))
    }

    func testDetectsMakeBulletPoints() {
        XCTAssertTrue(CommandMode.isCommand("Add bullet points to this list"))
    }

    func testDetectsSimplify() {
        XCTAssertTrue(CommandMode.isCommand("Simplify this explanation"))
    }

    // MARK: - New Edit Prefixes

    func testDetectsAddEmojis() {
        XCTAssertTrue(CommandMode.isCommand("add emojis to this"))
    }

    func testDetectsRemoveEmojis() {
        XCTAssertTrue(CommandMode.isCommand("remove emojis"))
    }

    func testDetectsMakeShorter() {
        XCTAssertTrue(CommandMode.isCommand("make shorter"))
    }

    func testDetectsMakeLonger() {
        XCTAssertTrue(CommandMode.isCommand("make longer"))
    }

    func testDetectsFixSpelling() {
        XCTAssertTrue(CommandMode.isCommand("fix spelling"))
    }

    func testDetectsFixPunctuation() {
        XCTAssertTrue(CommandMode.isCommand("fix punctuation"))
    }

    func testDetectsConvertToBulletPoints() {
        XCTAssertTrue(CommandMode.isCommand("convert to bullet points"))
    }

    func testDetectsConvertToList() {
        XCTAssertTrue(CommandMode.isCommand("convert to list"))
    }

    // MARK: - Write Mode Prefixes

    func testDetectsWrite() {
        XCTAssertTrue(CommandMode.isCommand("write an email declining a meeting"))
    }

    func testDetectsDraft() {
        XCTAssertTrue(CommandMode.isCommand("draft a response to the client"))
    }

    func testDetectsCompose() {
        XCTAssertTrue(CommandMode.isCommand("compose a thank you note"))
    }

    func testDetectsCreate() {
        XCTAssertTrue(CommandMode.isCommand("create a summary of the meeting"))
    }

    // MARK: - Non-Commands

    func testRegularTextNotCommand() {
        XCTAssertFalse(CommandMode.isCommand("Hello how are you"))
    }

    func testDictationNotCommand() {
        XCTAssertFalse(CommandMode.isCommand("I need to send an email to John about the meeting"))
    }

    func testPartialMatchNotCommand() {
        XCTAssertFalse(CommandMode.isCommand("I made this cake yesterday"))
    }

    // MARK: - Case Insensitivity

    func testCaseInsensitive() {
        XCTAssertTrue(CommandMode.isCommand("MAKE THIS more professional"))
        XCTAssertTrue(CommandMode.isCommand("make this more professional"))
        XCTAssertTrue(CommandMode.isCommand("Make This More Professional"))
    }

    // MARK: - Whitespace Handling

    func testTrimsWhitespace() {
        XCTAssertTrue(CommandMode.isCommand("  make this more professional  "))
    }

    // MARK: - Write Command Detection

    func testIsWriteCommandDetectsWritePrefixes() {
        XCTAssertTrue(CommandMode.isWriteCommand("write an email"))
        XCTAssertTrue(CommandMode.isWriteCommand("draft a response"))
        XCTAssertTrue(CommandMode.isWriteCommand("compose a message"))
        XCTAssertTrue(CommandMode.isWriteCommand("create a bullet list"))
    }

    func testIsWriteCommandRejectsEditPrefixes() {
        XCTAssertFalse(CommandMode.isWriteCommand("make this more formal"))
        XCTAssertFalse(CommandMode.isWriteCommand("fix grammar"))
        XCTAssertFalse(CommandMode.isWriteCommand("shorten this"))
        XCTAssertFalse(CommandMode.isWriteCommand("summarize"))
    }

    func testIsWriteCommandIsCaseInsensitive() {
        XCTAssertTrue(CommandMode.isWriteCommand("WRITE an email"))
        XCTAssertTrue(CommandMode.isWriteCommand("  Draft a note  "))
    }

    // MARK: - Edit Prompt Building

    func testBuildPromptContainsCommand() {
        let prompt = CommandMode.buildPrompt(command: "make it shorter", selectedText: "hello world")
        XCTAssertTrue(prompt.contains("make it shorter"))
    }

    func testBuildPromptContainsSelectedText() {
        let prompt = CommandMode.buildPrompt(command: "rewrite", selectedText: "The quick brown fox")
        XCTAssertTrue(prompt.contains("The quick brown fox"))
    }

    func testBuildPromptHasTextToEditMarker() {
        let prompt = CommandMode.buildPrompt(command: "simplify", selectedText: "text")
        XCTAssertTrue(prompt.contains("TEXT TO EDIT:"))
    }

    func testBuildPromptHasFormattingPreservationRule() {
        let prompt = CommandMode.buildPrompt(command: "test", selectedText: "test")
        XCTAssertTrue(prompt.contains("Preserve formatting"))
    }

    func testBuildPromptHasNoPreambleRule() {
        let prompt = CommandMode.buildPrompt(command: "test", selectedText: "test")
        XCTAssertTrue(prompt.contains("no explanations"))
        XCTAssertTrue(prompt.contains("no preamble"))
    }

    // MARK: - Write Prompt Building

    func testBuildWritePromptContainsInstruction() {
        let prompt = CommandMode.buildWritePrompt(instruction: "write an email declining a meeting")
        XCTAssertTrue(prompt.contains("INSTRUCTION: write an email declining a meeting"))
    }

    func testBuildWritePromptHasWritingAssistantRole() {
        let prompt = CommandMode.buildWritePrompt(instruction: "test")
        XCTAssertTrue(prompt.contains("writing assistant"))
    }

    func testBuildWritePromptHasNoPreambleRule() {
        let prompt = CommandMode.buildWritePrompt(instruction: "test")
        XCTAssertTrue(prompt.contains("no explanations"))
        XCTAssertTrue(prompt.contains("no preamble"))
    }

    func testBuildWritePromptDoesNotContainTextToEdit() {
        let prompt = CommandMode.buildWritePrompt(instruction: "write something")
        XCTAssertFalse(prompt.contains("TEXT TO EDIT"))
    }

    func testBuildWritePromptMentionsTone() {
        let prompt = CommandMode.buildWritePrompt(instruction: "test")
        XCTAssertTrue(prompt.contains("tone and formality"))
    }
}
