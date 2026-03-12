// MemoryPressureTests.swift
// YapYapTests — Tests for MemoryPressureLevel, LLMCleanupMetrics, and MachineProfile.availableMemoryMB
import XCTest
@testable import YapYap

final class MemoryPressureTests: XCTestCase {

    // MARK: - MemoryPressureLevel.from(genTokPerSec:)

    func testCriticalBelowFive() {
        XCTAssertEqual(MemoryPressureLevel.from(genTokPerSec: 0), .critical)
        XCTAssertEqual(MemoryPressureLevel.from(genTokPerSec: 1), .critical)
        XCTAssertEqual(MemoryPressureLevel.from(genTokPerSec: 4.9), .critical)
    }

    func testWarningBetweenFiveAndTwenty() {
        XCTAssertEqual(MemoryPressureLevel.from(genTokPerSec: 5), .warning)
        XCTAssertEqual(MemoryPressureLevel.from(genTokPerSec: 10), .warning)
        XCTAssertEqual(MemoryPressureLevel.from(genTokPerSec: 19.9), .warning)
    }

    func testNormalAtTwentyAndAbove() {
        XCTAssertEqual(MemoryPressureLevel.from(genTokPerSec: 20), .normal)
        XCTAssertEqual(MemoryPressureLevel.from(genTokPerSec: 100), .normal)
        XCTAssertEqual(MemoryPressureLevel.from(genTokPerSec: 500), .normal)
    }

    func testBoundaryAtExactlyFive() {
        // 5.0 is the first value that should NOT be critical
        XCTAssertNotEqual(MemoryPressureLevel.from(genTokPerSec: 5.0), .critical)
        XCTAssertEqual(MemoryPressureLevel.from(genTokPerSec: 5.0), .warning)
    }

    func testBoundaryAtExactlyTwenty() {
        // 20.0 is the first value that should NOT be warning
        XCTAssertNotEqual(MemoryPressureLevel.from(genTokPerSec: 20.0), .warning)
        XCTAssertEqual(MemoryPressureLevel.from(genTokPerSec: 20.0), .normal)
    }

    // MARK: - MemoryPressureLevel raw values

    func testRawValues() {
        XCTAssertEqual(MemoryPressureLevel.normal.rawValue, "normal")
        XCTAssertEqual(MemoryPressureLevel.warning.rawValue, "warning")
        XCTAssertEqual(MemoryPressureLevel.critical.rawValue, "critical")
        XCTAssertEqual(MemoryPressureLevel.unknown.rawValue, "unknown")
    }

    func testUnknownNotReturnedByFrom() {
        // .unknown is only used as a default — from() should never produce it
        for speed in [0.0, 1.0, 5.0, 10.0, 20.0, 100.0, 1000.0] {
            XCTAssertNotEqual(MemoryPressureLevel.from(genTokPerSec: speed), .unknown)
        }
    }

    // MARK: - LLMCleanupMetrics

    func testMetricsConstruction() {
        let metrics = LLMCleanupMetrics(
            prefillMs: 150,
            prefillTokPerSec: 300.0,
            genTokPerSec: 250.0,
            genTokenCount: 42,
            inputTokenCount: 128,
            promptCacheHit: true,
            memoryPressure: .normal
        )
        XCTAssertEqual(metrics.prefillMs, 150)
        XCTAssertEqual(metrics.prefillTokPerSec, 300.0)
        XCTAssertEqual(metrics.genTokPerSec, 250.0)
        XCTAssertEqual(metrics.genTokenCount, 42)
        XCTAssertEqual(metrics.inputTokenCount, 128)
        XCTAssertTrue(metrics.promptCacheHit)
        XCTAssertEqual(metrics.memoryPressure, .normal)
    }

    func testMetricsMemoryPressureConsistency() {
        // Verify that manually-set memoryPressure matches what from() would produce
        let slowMetrics = LLMCleanupMetrics(
            prefillMs: 11000,
            prefillTokPerSec: 10.0,
            genTokPerSec: 3.0,
            genTokenCount: 20,
            inputTokenCount: 200,
            promptCacheHit: false,
            memoryPressure: .from(genTokPerSec: 3.0)
        )
        XCTAssertEqual(slowMetrics.memoryPressure, .critical)

        let fastMetrics = LLMCleanupMetrics(
            prefillMs: 200,
            prefillTokPerSec: 500.0,
            genTokPerSec: 350.0,
            genTokenCount: 50,
            inputTokenCount: 100,
            promptCacheHit: true,
            memoryPressure: .from(genTokPerSec: 350.0)
        )
        XCTAssertEqual(fastMetrics.memoryPressure, .normal)
    }

    // MARK: - MachineProfile.availableMemoryMB

    func testAvailableMemoryMBReturnsPositive() {
        let mb = MachineProfile.availableMemoryMB()
        XCTAssertGreaterThan(mb, 0, "Should report some available memory on a running system")
    }

    func testAvailableMemoryMBIsReasonable() {
        let mb = MachineProfile.availableMemoryMB()
        let totalMB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))
        XCTAssertLessThanOrEqual(mb, totalMB, "Available memory should not exceed total physical RAM")
    }

    // MARK: - LLMEngine default extension

    func testDefaultMetricsIsNil() {
        // Engines that don't override lastCleanupMetrics should return nil
        let engine = MockLLMEngine()
        XCTAssertNil(engine.lastCleanupMetrics)
    }
}

// Minimal mock to test the default protocol extension
private class MockLLMEngine: LLMEngine {
    var isLoaded: Bool = false
    var modelId: String? = nil
    func loadModel(id: String, progressHandler: @escaping (Double) -> Void) async throws {}
    func unloadModel() {}
    func cleanup(rawText: String, context: CleanupContext) async throws -> String { rawText }
    func warmup() async {}
}
