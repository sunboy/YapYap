// VADConfigTests.swift
// YapYapTests
import XCTest
@testable import YapYap

final class VADConfigTests: XCTestCase {

    func testDefaultConfig() {
        let config = VADConfig.default
        XCTAssertEqual(config.threshold, 0.35)
        XCTAssertEqual(config.minSpeechDurationMs, 200)
        XCTAssertEqual(config.minSilenceDurationMs, 300)
        XCTAssertEqual(config.speechPadMs, 100)
        XCTAssertEqual(config.maxSpeechDurationS, 30)
    }

    func testNoisyPreset() {
        let config = VADConfig.noisyPreset
        XCTAssertGreaterThan(config.threshold, VADConfig.default.threshold)
        XCTAssertGreaterThan(config.minSpeechDurationMs, VADConfig.default.minSpeechDurationMs)
    }

    func testQuietPreset() {
        let config = VADConfig.quietPreset
        XCTAssertLessThan(config.threshold, VADConfig.default.threshold)
        XCTAssertLessThan(config.minSpeechDurationMs, VADConfig.default.minSpeechDurationMs)
    }

    func testNoisyHasHigherThresholdThanQuiet() {
        XCTAssertGreaterThan(VADConfig.noisyPreset.threshold, VADConfig.quietPreset.threshold)
    }
}
