// PersonalDictionaryTests.swift
// YapYapTests
import XCTest
@testable import YapYap

final class PersonalDictionaryTests: XCTestCase {

    private func makeEntry(_ spoken: String, _ corrected: String, appName: String? = nil) -> CorrectionEntry {
        CorrectionEntry(
            spoken: spoken,
            corrected: corrected,
            dateAdded: Date(),
            hitCount: 0,
            isEnabled: true,
            source: .manual,
            appName: appName
        )
    }

    func testApplyCorrections() {
        let dict = PersonalDictionary()
        dict.entries = [
            "anthropick": makeEntry("anthropick", "Anthropic"),
            "kubernetees": makeEntry("kubernetees", "Kubernetes")
        ]

        let result = dict.applyCorrections(to: "I work at anthropick using kubernetees")
        XCTAssertTrue(result.contains("Anthropic"))
        XCTAssertTrue(result.contains("Kubernetes"))
        XCTAssertFalse(result.contains("anthropick"))
    }

    func testCaseInsensitiveCorrection() {
        let dict = PersonalDictionary()
        dict.entries = ["openai": makeEntry("openai", "OpenAI")]

        let result = dict.applyCorrections(to: "I use OpenAI products")
        XCTAssertTrue(result.contains("OpenAI"))
    }

    func testLearnCorrection() {
        let dict = PersonalDictionary()
        dict.learnCorrection(spoken: "Anthroapic", corrected: "Anthropic")
        XCTAssertEqual(dict.entries["anthroapic"]?.corrected, "Anthropic")
    }

    func testRemoveCorrection() {
        let dict = PersonalDictionary()
        dict.entries = ["test": makeEntry("test", "Test")]
        dict.removeCorrection(key: "test")
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
        dict.entries = ["at": makeEntry("at", "AT")]

        // "at" in "that" should NOT be replaced
        let result = dict.applyCorrections(to: "I think that is correct")
        XCTAssertTrue(result.contains("that"))
    }

    func testToggleCorrection() {
        let dict = PersonalDictionary()
        dict.entries = ["test": makeEntry("test", "Test")]

        dict.toggleCorrection(key: "test", enabled: false)
        XCTAssertEqual(dict.entries["test"]?.isEnabled, false)

        // Disabled entries should not apply corrections
        let result = dict.applyCorrections(to: "this is a test")
        XCTAssertTrue(result.contains("test"))
        XCTAssertFalse(result.contains("Test"))
    }

    func testAllEntriesSorted() {
        let dict = PersonalDictionary()
        let older = CorrectionEntry(spoken: "first", corrected: "First", dateAdded: Date(timeIntervalSinceNow: -100), hitCount: 0, isEnabled: true, source: .manual, appName: nil)
        let newer = CorrectionEntry(spoken: "second", corrected: "Second", dateAdded: Date(), hitCount: 0, isEnabled: true, source: .manual, appName: nil)
        dict.entries = ["first": older, "second": newer]

        let sorted = dict.allEntries
        XCTAssertEqual(sorted.first?.spoken, "second")
        XCTAssertEqual(sorted.last?.spoken, "first")
    }

    func testLearnCorrectionSource() {
        let dict = PersonalDictionary()
        dict.learnCorrection(spoken: "test", corrected: "Test", source: .autoLearned)
        XCTAssertEqual(dict.entries["test"]?.source, .autoLearned)
    }

    // MARK: - Per-App Dictionary Tests

    func testPerAppCorrection() {
        let dict = PersonalDictionary()
        dict.entries = [
            "typo::Slack": makeEntry("typo", "Corrected", appName: "Slack")
        ]

        // Should apply when active app matches
        let result = dict.applyCorrections(to: "fix this typo", activeAppName: "Slack")
        XCTAssertTrue(result.contains("Corrected"))
    }

    func testPerAppCorrectionSkippedForOtherApps() {
        let dict = PersonalDictionary()
        dict.entries = [
            "typo::Slack": makeEntry("typo", "Corrected", appName: "Slack")
        ]

        // Should NOT apply for different app
        let result = dict.applyCorrections(to: "fix this typo", activeAppName: "Mail")
        XCTAssertTrue(result.contains("typo"))
        XCTAssertFalse(result.contains("Corrected"))
    }

    func testGlobalAndPerAppCoexist() {
        let dict = PersonalDictionary()
        dict.entries = [
            "anthropick": makeEntry("anthropick", "Anthropic"),
            "kube::Xcode": makeEntry("kube", "Kubernetes", appName: "Xcode")
        ]

        // Global entry applies everywhere
        let r1 = dict.applyCorrections(to: "anthropick and kube", activeAppName: "Mail")
        XCTAssertTrue(r1.contains("Anthropic"))
        XCTAssertTrue(r1.contains("kube")) // Per-app entry should NOT apply

        // Both apply in matching app
        let r2 = dict.applyCorrections(to: "anthropick and kube", activeAppName: "Xcode")
        XCTAssertTrue(r2.contains("Anthropic"))
        XCTAssertTrue(r2.contains("Kubernetes"))
    }

    func testLearnPerAppCorrection() {
        let dict = PersonalDictionary()
        dict.learnCorrection(spoken: "test", corrected: "Test", source: .manual, appName: "Slack")
        XCTAssertNotNil(dict.entries["test::Slack"])
        XCTAssertEqual(dict.entries["test::Slack"]?.appName, "Slack")
    }

    func testEntriesForApp() {
        let dict = PersonalDictionary()
        dict.entries = [
            "a": makeEntry("a", "A"),
            "b::Slack": makeEntry("b", "B", appName: "Slack"),
            "c::Mail": makeEntry("c", "C", appName: "Mail")
        ]

        XCTAssertEqual(dict.entriesFor(app: "Slack").count, 1)
        XCTAssertEqual(dict.globalEntries.count, 1)
        XCTAssertEqual(dict.appsWithEntries.count, 2)
    }
}
