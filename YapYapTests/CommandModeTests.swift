// CommandModeTests.swift
// YapYapTests
import XCTest
@testable import YapYap

final class CommandModeTests: XCTestCase {

    // MARK: - Command Detection

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

    // MARK: - Prompt Building

    func testBuildPromptContainsCommand() {
        let prompt = CommandMode.buildPrompt(command: "make it shorter", selectedText: "hello world")
        XCTAssertTrue(prompt.contains("make it shorter"))
    }

    func testBuildPromptContainsSelectedText() {
        let prompt = CommandMode.buildPrompt(command: "rewrite", selectedText: "The quick brown fox")
        XCTAssertTrue(prompt.contains("The quick brown fox"))
    }

    func testBuildPromptContainsTransformMarker() {
        let prompt = CommandMode.buildPrompt(command: "simplify", selectedText: "text")
        XCTAssertTrue(prompt.contains("TRANSFORMED TEXT:"))
    }
}
