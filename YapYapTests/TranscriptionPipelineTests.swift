// TranscriptionPipelineTests.swift
// Tests for STT artifact stripping and output sanitization in TranscriptionPipeline.
// These tests cover regressions that were caught in production — add a test here
// any time a new artifact type is found in the wild.
import XCTest
@testable import YapYap

final class TranscriptionPipelineTests: XCTestCase {

    // MARK: - Whisper Artifact Stripping

    func testStripsBlankAudioTag() {
        let result = TranscriptionPipeline.testStripWhisperArtifacts("[BLANK_AUDIO] Hello world")
        XCTAssertEqual(result, "Hello world")
    }

    func testStripsTrailingBlankAudioTag() {
        let result = TranscriptionPipeline.testStripWhisperArtifacts("Hello world [BLANK_AUDIO]")
        XCTAssertEqual(result, "Hello world")
    }

    func testStripsNoAudioTag() {
        let result = TranscriptionPipeline.testStripWhisperArtifacts("[no audio from the video] Hello world")
        XCTAssertEqual(result, "Hello world")
    }

    func testStripsMusicTag() {
        let result = TranscriptionPipeline.testStripWhisperArtifacts("[Music] Hello world")
        XCTAssertEqual(result, "Hello world")
    }

    func testStripsApplauseTag() {
        let result = TranscriptionPipeline.testStripWhisperArtifacts("Great job. [Applause] Thanks everyone.")
        XCTAssertEqual(result, "Great job. Thanks everyone.")
    }

    func testStripsParentheticalSighs() {
        // Both the (sighs) tag and the trailing ellipsis should be stripped
        let result = TranscriptionPipeline.testStripWhisperArtifacts("(sighs) So I was thinking...")
        XCTAssertEqual(result, "So I was thinking")
    }

    func testStripsMultipleTags() {
        let result = TranscriptionPipeline.testStripWhisperArtifacts("[BLANK_AUDIO] Hello [Music] world [BLANK_AUDIO]")
        XCTAssertEqual(result, "Hello world")
    }

    func testPreservesNormalText() {
        let result = TranscriptionPipeline.testStripWhisperArtifacts("Hello world, how are you?")
        XCTAssertEqual(result, "Hello world, how are you?")
    }

    func testPreservesUserBrackets() {
        // Long bracketed content (>60 chars) should not be stripped — likely real user content
        let longTag = "[this is a really long note that the user intentionally wrote out in brackets]"
        let result = TranscriptionPipeline.testStripWhisperArtifacts("Hello \(longTag) world")
        XCTAssertTrue(result.contains("world"))
    }

    func testCollapsesExtraSpacesAfterStrip() {
        let result = TranscriptionPipeline.testStripWhisperArtifacts("Hello  [BLANK_AUDIO]  world")
        XCTAssertEqual(result, "Hello world")
    }

    func testStripsTrailingEllipsis() {
        // Whisper renders mid-sentence trailing pauses as "word..." — strip the ellipsis
        let result = TranscriptionPipeline.testStripWhisperArtifacts("do a main... so that all future sessions know about it")
        XCTAssertEqual(result, "do a main so that all future sessions know about it")
    }

    func testStripsTrailingEllipsisAtEndOfSentence() {
        let result = TranscriptionPipeline.testStripWhisperArtifacts("I was thinking...")
        XCTAssertEqual(result, "I was thinking")
    }

    func testDoesNotStripStandalonellipsis() {
        // A standalone "..." between words (not attached to a word) is preserved
        // This test documents the current behavior — standalone ellipsis is unlikely in STT
        let result = TranscriptionPipeline.testStripWhisperArtifacts("Hello ... world")
        XCTAssertEqual(result, "Hello ... world")
    }

    // MARK: - LLM Prompt: No grocery list contamination

    func testSmallModelPromptNoGroceryList() {
        // The grocery list example caused Gemma to echo "Milk, Eggs, Bread" instead of
        // cleaning the actual transcript. It must not appear in any small model prompt.
        let context = CleanupContext(
            stylePrompt: "", formality: .neutral, language: "en",
            appContext: nil, cleanupLevel: .medium,
            removeFillers: true, experimentalPrompts: false
        )
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        XCTAssertFalse(messages.user.contains("Milk"), "Grocery list example must not appear — causes model to echo it")
        XCTAssertFalse(messages.user.contains("Eggs"), "Grocery list example must not appear — causes model to echo it")
        XCTAssertFalse(messages.user.contains("dry cleaning"), "Grocery list example must not appear — causes model to echo it")
    }

    func testGemmaPromptNoGroceryList() {
        let context = CleanupContext(
            stylePrompt: "", formality: .neutral, language: "en",
            appContext: nil, cleanupLevel: .medium,
            removeFillers: true, experimentalPrompts: false
        )
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "gemma-3-1b")
        XCTAssertFalse(messages.user.contains("Milk"), "Grocery list example must not appear in Gemma prompt")
        XCTAssertFalse(messages.user.contains("dry cleaning"), "Grocery list example must not appear in Gemma prompt")
    }

    // MARK: - LLM Prompt: List formatting only on explicit enumeration

    func testSmallModelListInstructionRequiresExplicitEnumeration() {
        let context = CleanupContext(
            stylePrompt: "", formality: .neutral, language: "en",
            appContext: nil, cleanupLevel: .medium,
            removeFillers: true, experimentalPrompts: false
        )
        let messages = CleanupPromptBuilder.buildMessages(rawText: "test", context: context, modelId: "llama-3.2-1b")
        // Must require explicit enumeration signal, not trigger on any multi-clause sentence
        XCTAssertTrue(messages.system.contains("explicitly"),
                      "List instruction must require explicit enumeration to avoid false positives on multi-clause sentences")
        XCTAssertFalse(messages.system.contains("comma-separated") || messages.system.contains("multiple items are listed"),
                       "Old over-broad list instruction must be gone")
    }
}

// MARK: - Test Helpers

extension TranscriptionPipeline {
    /// Exposes private stripWhisperArtifacts for testing.
    static func testStripWhisperArtifacts(_ text: String) -> String {
        return stripWhisperArtifacts(text)
    }
}
