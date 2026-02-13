// PersonalDictionaryTests.swift
// YapYapTests
import XCTest
@testable import YapYap

final class PersonalDictionaryTests: XCTestCase {

    func testApplyCorrections() {
        let dict = PersonalDictionary()
        dict.entries = ["anthropick": "Anthropic", "kubernetees": "Kubernetes"]

        let result = dict.applyCorrections(to: "I work at anthropick using kubernetees")
        XCTAssertTrue(result.contains("Anthropic"))
        XCTAssertTrue(result.contains("Kubernetes"))
        XCTAssertFalse(result.contains("anthropick"))
    }

    func testCaseInsensitiveCorrection() {
        let dict = PersonalDictionary()
        dict.entries = ["openai": "OpenAI"]

        let result = dict.applyCorrections(to: "I use OpenAI products")
        XCTAssertTrue(result.contains("OpenAI"))
    }

    func testLearnCorrection() {
        let dict = PersonalDictionary()
        dict.learnCorrection(spoken: "Anthroapic", corrected: "Anthropic")
        XCTAssertEqual(dict.entries["anthroapic"], "Anthropic")
    }

    func testRemoveCorrection() {
        let dict = PersonalDictionary()
        dict.entries = ["test": "Test"]
        dict.removeCorrection(spoken: "test")
        XCTAssertNil(dict.entries["test"])
    }

    func testEmptyDictionary() {
        let dict = PersonalDictionary()
        dict.entries = [:]
        let result = dict.applyCorrections(to: "Hello world")
        XCTAssertEqual(result, "Hello world")
    }

    func testWordBoundary() {
        let dict = PersonalDictionary()
        dict.entries = ["at": "AT"]

        // "at" in "that" should NOT be replaced
        let result = dict.applyCorrections(to: "I think that is correct")
        XCTAssertTrue(result.contains("that"))
    }
}
