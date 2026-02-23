// CorrectionDifferTests.swift
// YapYapTests
import XCTest
@testable import YapYap

final class CorrectionDifferTests: XCTestCase {

    // MARK: - Substitution Detection

    func testSimpleSubstitution() {
        let candidates = CorrectionDiffer.diff(
            original: "I work at anthropick",
            corrected: "I work at Anthropic"
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.original, "anthropick")
        XCTAssertEqual(candidates.first?.corrected, "Anthropic")
    }

    func testMultipleSubstitutions() {
        let candidates = CorrectionDiffer.diff(
            original: "I use kubernetees at anthropick",
            corrected: "I use Kubernetes at Anthropic"
        )
        XCTAssertEqual(candidates.count, 2)

        let originals = Set(candidates.map { $0.original })
        XCTAssertTrue(originals.contains("kubernetees"))
        XCTAssertTrue(originals.contains("anthropick"))
    }

    // MARK: - Insertions and Deletions Ignored

    func testInsertionIgnored() {
        // User added "really" — this is not a correction
        let candidates = CorrectionDiffer.diff(
            original: "I like coding",
            corrected: "I really like coding"
        )
        // Should not produce substitutions for the insertion
        for candidate in candidates {
            XCTAssertNotEqual(candidate.original, "like")
        }
    }

    func testDeletionIgnored() {
        // User removed "basically" — this is not a word correction
        let candidates = CorrectionDiffer.diff(
            original: "I basically like coding",
            corrected: "I like coding"
        )
        // Should not produce substitutions for the deletion
        XCTAssertTrue(candidates.isEmpty)
    }

    // MARK: - Common Word Filter

    func testCommonWordRephrasing() {
        // "there" → "their" are both common words — likely rephrasing, not STT error
        let candidates = CorrectionDiffer.diff(
            original: "I put it there",
            corrected: "I put it here"
        )
        XCTAssertTrue(candidates.isEmpty, "Common word substitutions should be filtered out")
    }

    // MARK: - Proper Noun Acceptance

    func testProperNounCorrection() {
        let candidates = CorrectionDiffer.diff(
            original: "I visited paris last year",
            corrected: "I visited Paris last year"
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.original, "paris")
        XCTAssertEqual(candidates.first?.corrected, "Paris")
    }

    // MARK: - Apostrophe Handling

    func testApostropheAddition() {
        let candidates = CorrectionDiffer.diff(
            original: "I cant do that",
            corrected: "I can't do that"
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.original, "cant")
        XCTAssertEqual(candidates.first?.corrected, "can't")
    }

    func testDontApostrophe() {
        let candidates = CorrectionDiffer.diff(
            original: "I dont know",
            corrected: "I don't know"
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.original, "dont")
        XCTAssertEqual(candidates.first?.corrected, "don't")
    }

    // MARK: - Too Different Filter

    func testTooDistantWordsFiltered() {
        // "elephant" → "Kubernetes" are way too different to be an STT error
        let candidates = CorrectionDiffer.diff(
            original: "I deployed to elephant",
            corrected: "I deployed to Kubernetes"
        )
        XCTAssertTrue(candidates.isEmpty, "Words with >60% Levenshtein distance should be filtered")
    }

    // MARK: - Identical Strings

    func testIdenticalStrings() {
        let candidates = CorrectionDiffer.diff(
            original: "Hello world",
            corrected: "Hello world"
        )
        XCTAssertTrue(candidates.isEmpty)
    }

    // MARK: - Empty Strings

    func testEmptyOriginal() {
        let candidates = CorrectionDiffer.diff(original: "", corrected: "Hello")
        XCTAssertTrue(candidates.isEmpty)
    }

    func testEmptyCorrected() {
        let candidates = CorrectionDiffer.diff(original: "Hello", corrected: "")
        XCTAssertTrue(candidates.isEmpty)
    }

    // MARK: - Levenshtein Distance

    func testLevenshteinIdentical() {
        XCTAssertEqual(CorrectionDiffer.levenshteinDistance("test", "test"), 0)
    }

    func testLevenshteinOneEdit() {
        XCTAssertEqual(CorrectionDiffer.levenshteinDistance("cat", "car"), 1)
    }

    func testLevenshteinCompletely() {
        XCTAssertEqual(CorrectionDiffer.levenshteinDistance("abc", "xyz"), 3)
    }

    func testLevenshteinEmpty() {
        XCTAssertEqual(CorrectionDiffer.levenshteinDistance("", "hello"), 5)
        XCTAssertEqual(CorrectionDiffer.levenshteinDistance("hello", ""), 5)
    }
}
