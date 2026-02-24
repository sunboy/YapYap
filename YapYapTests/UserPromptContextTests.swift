// UserPromptContextTests.swift
// YapYapTests
import XCTest
@testable import YapYap

final class UserPromptContextTests: XCTestCase {

    // MARK: - Empty Dictionary

    func testEmptyDictionaryProducesEmptyBlock() {
        let ctx = UserPromptContext(dictionaryEntries: [], editMemoryEntries: [])
        XCTAssertTrue(ctx.dictionaryBlock(modelSize: .small).isEmpty)
        XCTAssertTrue(ctx.dictionaryBlock(modelSize: .medium).isEmpty)
        XCTAssertTrue(ctx.dictionaryBlock(modelSize: .large).isEmpty)
    }

    func testEmptyEditMemoryProducesEmptyBlock() {
        let ctx = UserPromptContext(dictionaryEntries: [], editMemoryEntries: [])
        XCTAssertTrue(ctx.editMemoryBlock(modelSize: .small).isEmpty)
        XCTAssertTrue(ctx.editMemoryBlock(modelSize: .medium).isEmpty)
        XCTAssertTrue(ctx.editMemoryBlock(modelSize: .large).isEmpty)
    }

    // MARK: - Dictionary Formatting

    func testSmallModelDictionaryFormat() {
        let ctx = UserPromptContext(
            dictionaryEntries: [
                (spoken: "eat a", corrected: "ETA"),
                (spoken: "elm", corrected: "LLM"),
            ],
            editMemoryEntries: []
        )
        let block = ctx.dictionaryBlock(modelSize: .small)
        XCTAssertTrue(block.hasPrefix("WORDS:"))
        XCTAssertTrue(block.contains("eat a → ETA"))
        XCTAssertTrue(block.contains("elm → LLM"))
    }

    func testMediumModelDictionaryFormat() {
        let ctx = UserPromptContext(
            dictionaryEntries: [
                (spoken: "eat a", corrected: "ETA"),
                (spoken: "elm", corrected: "LLM"),
            ],
            editMemoryEntries: []
        )
        let block = ctx.dictionaryBlock(modelSize: .medium)
        XCTAssertTrue(block.hasPrefix("DICTIONARY"))
        XCTAssertTrue(block.contains("eat a → ETA"))
        XCTAssertTrue(block.contains("elm → LLM"))
    }

    func testLargeModelUsesMediumFormat() {
        let ctx = UserPromptContext(
            dictionaryEntries: [(spoken: "eat a", corrected: "ETA")],
            editMemoryEntries: []
        )
        let medium = ctx.dictionaryBlock(modelSize: .medium)
        let large = ctx.dictionaryBlock(modelSize: .large)
        XCTAssertEqual(medium, large)
    }

    // MARK: - Entry Count Limits

    func testSmallModelLimitsTo15Entries() {
        let entries = (0..<20).map { (spoken: "word\($0)", corrected: "WORD\($0)") }
        let ctx = UserPromptContext(dictionaryEntries: entries, editMemoryEntries: [])
        let block = ctx.dictionaryBlock(modelSize: .small)
        // Should contain word14 (15th entry, 0-indexed) but not word15
        XCTAssertTrue(block.contains("word14"))
        XCTAssertFalse(block.contains("word15"))
    }

    func testMediumModelLimitsTo30Entries() {
        let entries = (0..<35).map { (spoken: "word\($0)", corrected: "WORD\($0)") }
        let ctx = UserPromptContext(dictionaryEntries: entries, editMemoryEntries: [])
        let block = ctx.dictionaryBlock(modelSize: .medium)
        XCTAssertTrue(block.contains("word29"))
        XCTAssertFalse(block.contains("word30"))
    }

    // MARK: - Edit Memory

    func testEditMemorySmallFormat() {
        let ctx = UserPromptContext(
            dictionaryEntries: [],
            editMemoryEntries: [
                (before: "I will", after: "I'll"),
                (before: "Hi", after: "Hey"),
            ]
        )
        let block = ctx.editMemoryBlock(modelSize: .small)
        XCTAssertTrue(block.hasPrefix("STYLE:"))
        XCTAssertTrue(block.contains("I will → I'll"))
    }

    func testEditMemoryMediumFormat() {
        let ctx = UserPromptContext(
            dictionaryEntries: [],
            editMemoryEntries: [
                (before: "I will", after: "I'll"),
            ]
        )
        let block = ctx.editMemoryBlock(modelSize: .medium)
        XCTAssertTrue(block.hasPrefix("STYLE RULES"))
        XCTAssertTrue(block.contains("\"I will\" → \"I'll\""))
    }

    func testEditMemoryLimitsSmallTo10() {
        let entries = (0..<15).map { (before: "before\($0)", after: "after\($0)") }
        let ctx = UserPromptContext(dictionaryEntries: [], editMemoryEntries: entries)
        let block = ctx.editMemoryBlock(modelSize: .small)
        XCTAssertTrue(block.contains("before9"))
        XCTAssertFalse(block.contains("before10"))
    }

    func testEditMemoryLimitsMediumTo20() {
        let entries = (0..<25).map { (before: "before\($0)", after: "after\($0)") }
        let ctx = UserPromptContext(dictionaryEntries: [], editMemoryEntries: entries)
        let block = ctx.editMemoryBlock(modelSize: .medium)
        XCTAssertTrue(block.contains("before19"))
        XCTAssertFalse(block.contains("before20"))
    }

    // MARK: - Integration with CleanupPromptBuilder

    func testDictionaryAppearsInUserMessage() {
        let ctx = UserPromptContext(
            dictionaryEntries: [(spoken: "eat a", corrected: "ETA")],
            editMemoryEntries: []
        )
        let cleanupCtx = CleanupContext(
            stylePrompt: "", formality: .neutral, language: "en",
            appContext: nil, cleanupLevel: .medium,
            removeFillers: true, experimentalPrompts: false
        )
        let messages = CleanupPromptBuilder.buildMessages(
            rawText: "test", context: cleanupCtx,
            modelId: "qwen-2.5-3b", userContext: ctx
        )
        XCTAssertTrue(messages.user.contains("DICTIONARY"))
        XCTAssertTrue(messages.user.contains("eat a → ETA"))
    }

    func testEmptyContextProducesNoExtraBlocks() {
        let ctx = UserPromptContext(dictionaryEntries: [], editMemoryEntries: [])
        let cleanupCtx = CleanupContext(
            stylePrompt: "", formality: .neutral, language: "en",
            appContext: nil, cleanupLevel: .medium,
            removeFillers: true, experimentalPrompts: false
        )
        let withCtx = CleanupPromptBuilder.buildMessages(
            rawText: "test", context: cleanupCtx,
            modelId: "qwen-2.5-3b", userContext: ctx
        )
        let withoutCtx = CleanupPromptBuilder.buildMessages(
            rawText: "test", context: cleanupCtx,
            modelId: "qwen-2.5-3b", userContext: nil
        )
        // Empty context should produce identical output to nil context
        XCTAssertEqual(withCtx.user, withoutCtx.user)
    }

    func testSmallModelDictionaryInUserMessage() {
        let ctx = UserPromptContext(
            dictionaryEntries: [(spoken: "elm", corrected: "LLM")],
            editMemoryEntries: []
        )
        let cleanupCtx = CleanupContext(
            stylePrompt: "", formality: .neutral, language: "en",
            appContext: nil, cleanupLevel: .medium,
            removeFillers: true, experimentalPrompts: false
        )
        let messages = CleanupPromptBuilder.buildMessages(
            rawText: "test", context: cleanupCtx,
            modelId: "qwen-2.5-1.5b", userContext: ctx
        )
        XCTAssertTrue(messages.user.contains("WORDS:"))
        XCTAssertTrue(messages.user.contains("elm → LLM"))
    }
}
