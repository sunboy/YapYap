// FillerFilterTests.swift
// YapYapTests
import XCTest
@testable import YapYap

final class FillerFilterTests: XCTestCase {

    // MARK: - Basic Hesitation Removal

    func testRemovesUm() {
        let result = FillerFilter.removeFillers(from: "I um think we should go")
        XCTAssertEqual(result, "I think we should go")
    }

    func testRemovesUh() {
        let result = FillerFilter.removeFillers(from: "So uh what do you think")
        XCTAssertEqual(result, "So what do you think")
    }

    func testRemovesAh() {
        let result = FillerFilter.removeFillers(from: "Ah I see what you mean")
        XCTAssertEqual(result, "I see what you mean")
    }

    func testRemovesEr() {
        let result = FillerFilter.removeFillers(from: "The er meeting is tomorrow")
        XCTAssertEqual(result, "The meeting is tomorrow")
    }

    func testRemovesHmm() {
        let result = FillerFilter.removeFillers(from: "Hmm let me think about that")
        XCTAssertEqual(result, "let me think about that")
    }

    func testRemovesMultipleHesitations() {
        let result = FillerFilter.removeFillers(from: "Um well uh I think ah maybe")
        XCTAssertFalse(result.contains("Um"))
        XCTAssertFalse(result.lowercased().contains("uh"))
        XCTAssertFalse(result.lowercased().contains(" ah "))
    }

    func testRemovesHesitationsWithCommas() {
        let result = FillerFilter.removeFillers(from: "I think, um, we should go")
        XCTAssertFalse(result.lowercased().contains("um"))
    }

    func testRemovesHesitationsWithPeriods() {
        let result = FillerFilter.removeFillers(from: "Um. Let me think")
        XCTAssertFalse(result.lowercased().contains("um"))
    }

    // MARK: - Does NOT Remove Parts of Words

    func testPreservesUmbrella() {
        let result = FillerFilter.removeFillers(from: "Bring an umbrella today")
        XCTAssertTrue(result.contains("umbrella"))
    }

    func testPreservesHummer() {
        let result = FillerFilter.removeFillers(from: "I saw a hummer on the road")
        XCTAssertTrue(result.contains("hummer"))
    }

    func testPreservesUmber() {
        let result = FillerFilter.removeFillers(from: "The color umber is beautiful")
        XCTAssertTrue(result.contains("umber"))
    }

    // MARK: - Aggressive Mode

    func testAggressiveRemovesYouKnow() {
        let result = FillerFilter.removeFillers(from: "I think, you know, it's good", aggressive: true)
        XCTAssertFalse(result.contains("you know"))
    }

    func testAggressiveRemovesIMean() {
        let result = FillerFilter.removeFillers(from: "I mean the project is going well", aggressive: true)
        XCTAssertFalse(result.lowercased().contains("i mean"))
    }

    func testAggressiveRemovesBasically() {
        let result = FillerFilter.removeFillers(from: "It's basically done", aggressive: true)
        XCTAssertFalse(result.lowercased().contains("basically"))
    }

    func testAggressiveRemovesSortOf() {
        let result = FillerFilter.removeFillers(from: "It's sort of working", aggressive: true)
        XCTAssertFalse(result.lowercased().contains("sort of"))
    }

    func testAggressiveRemovesLiterally() {
        let result = FillerFilter.removeFillers(from: "It literally just happened", aggressive: true)
        XCTAssertFalse(result.lowercased().contains("literally"))
    }

    // MARK: - Non-Aggressive Does NOT Remove Extended Fillers

    func testNonAggressiveKeepsYouKnow() {
        let result = FillerFilter.removeFillers(from: "I think, you know, it's good", aggressive: false)
        XCTAssertTrue(result.contains("you know"))
    }

    func testNonAggressiveKeepsBasically() {
        let result = FillerFilter.removeFillers(from: "It's basically done", aggressive: false)
        XCTAssertTrue(result.contains("basically"))
    }

    // MARK: - Edge Cases

    func testEmptyString() {
        let result = FillerFilter.removeFillers(from: "")
        XCTAssertEqual(result, "")
    }

    func testStringWithOnlyFillers() {
        let result = FillerFilter.removeFillers(from: "um uh ah")
        XCTAssertEqual(result, "")
    }

    func testCleansUpDoubleSpaces() {
        let result = FillerFilter.removeFillers(from: "I um think uh yes")
        XCTAssertFalse(result.contains("  "))
    }

    func testTrimsWhitespace() {
        let result = FillerFilter.removeFillers(from: " um hello ")
        XCTAssertEqual(result, "hello")
    }

    func testCaseInsensitive() {
        let result = FillerFilter.removeFillers(from: "UM I think UH yes")
        XCTAssertFalse(result.contains("UM"))
        XCTAssertFalse(result.contains("UH"))
    }
}
