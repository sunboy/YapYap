// DataModelTests.swift
// YapYapTests — Test SwiftData model initialization and defaults
import XCTest
@testable import YapYap

final class DataModelTests: XCTestCase {

    // MARK: - AppSettings Defaults

    func testAppSettingsDefaults() {
        let settings = AppSettings()
        XCTAssertFalse(settings.sttModelId.isEmpty)
        XCTAssertFalse(settings.llmModelId.isEmpty)
        XCTAssertEqual(settings.formality, "neutral")
        XCTAssertEqual(settings.cleanupLevel, "medium")
        XCTAssertEqual(settings.language, "en")
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertTrue(settings.showFloatingBar)
        XCTAssertTrue(settings.autoPaste)
        XCTAssertTrue(settings.copyToClipboard)
        XCTAssertFalse(settings.notifyOnComplete)
        XCTAssertTrue(settings.soundFeedback)
        XCTAssertTrue(settings.hapticFeedback)
        XCTAssertTrue(settings.gpuAcceleration)
        XCTAssertTrue(settings.autoDownloadModels)
        XCTAssertEqual(settings.historyLimit, 100)
    }

    // MARK: - Transcription

    func testTranscriptionInit() {
        let t = Transcription(
            rawText: "hello um world",
            cleanedText: "Hello world",
            durationSeconds: 2.5,
            wordCount: 2,
            sttModel: "whisper-large-v3-turbo",
            llmModel: "qwen-2.5-3b",
            sourceApp: "Mail",
            language: "en"
        )
        XCTAssertEqual(t.rawText, "hello um world")
        XCTAssertEqual(t.cleanedText, "Hello world")
        XCTAssertEqual(t.durationSeconds, 2.5)
        XCTAssertEqual(t.wordCount, 2)
        XCTAssertEqual(t.sttModel, "whisper-large-v3-turbo")
        XCTAssertEqual(t.llmModel, "qwen-2.5-3b")
        XCTAssertEqual(t.sourceApp, "Mail")
        XCTAssertNotNil(t.id)
        XCTAssertNotNil(t.timestamp)
    }

    // MARK: - CustomDictionaryEntry

    func testCustomDictionaryEntry() {
        let entry = CustomDictionaryEntry(original: "anthropick", replacement: "Anthropic")
        XCTAssertEqual(entry.original, "anthropick")
        XCTAssertEqual(entry.replacement, "Anthropic")
        XCTAssertTrue(entry.isEnabled)
    }

    // MARK: - DailyStats

    func testDailyStatsInit() {
        let stats = DailyStats()
        XCTAssertEqual(stats.transcriptionCount, 0)
        XCTAssertEqual(stats.wordCount, 0)
        XCTAssertEqual(stats.totalDurationSeconds, 0)
        XCTAssertNotNil(stats.date)
    }

    // MARK: - PowerModeRule

    func testPowerModeRuleInit() {
        let rule = PowerModeRule(
            appBundleId: "com.apple.mail",
            stylePrompt: "Professional tone",
            formality: "formal",
            cleanupLevel: "medium"
        )
        XCTAssertEqual(rule.appBundleId, "com.apple.mail")
        XCTAssertEqual(rule.formality, "formal")
        XCTAssertTrue(rule.isEnabled)
    }
}
