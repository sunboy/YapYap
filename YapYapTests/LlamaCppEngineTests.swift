// LlamaCppEngineTests.swift
// YapYapTests — Tests for LlamaCppEngine (state, concurrency guard, error types)
import XCTest
@testable import YapYap

final class LlamaCppEngineTests: XCTestCase {

    // MARK: - Initial State

    func testInitialStateNotLoaded() {
        let engine = LlamaCppEngine()
        XCTAssertFalse(engine.isLoaded)
        XCTAssertNil(engine.modelId)
    }

    func testPromptModelIdDefaultsToNil() {
        let engine = LlamaCppEngine()
        XCTAssertNil(engine.promptModelId)
    }

    // MARK: - Protocol Conformance

    func testConformsToLLMEngine() {
        let engine = LlamaCppEngine()
        XCTAssertTrue(engine is LLMEngine)
    }

    func testIsClassType() {
        let engine: LLMEngine = LlamaCppEngine()
        XCTAssertNotNil(engine)
    }

    // MARK: - Unload

    func testUnloadResetsState() {
        let engine = LlamaCppEngine()
        engine.unloadModel()
        XCTAssertFalse(engine.isLoaded)
        XCTAssertNil(engine.modelId)
    }

    func testDoubleUnloadIsSafe() {
        let engine = LlamaCppEngine()
        engine.unloadModel()
        engine.unloadModel()
        XCTAssertFalse(engine.isLoaded)
    }

    // MARK: - Cleanup Without Load

    func testCleanupThrowsWhenNotLoaded() async {
        let engine = LlamaCppEngine()
        let context = CleanupContext(
            stylePrompt: "",
            formality: .neutral,
            language: "en",
            appContext: nil,
            cleanupLevel: .medium,
            removeFillers: true,
            experimentalPrompts: false
        )
        do {
            _ = try await engine.cleanup(rawText: "hello world", context: context)
            XCTFail("Expected cleanup to throw when not loaded")
        } catch {
            XCTAssertTrue(error is YapYapError)
        }
    }

    // MARK: - Warmup Without Load

    func testWarmupSafeWhenNotLoaded() async {
        let engine = LlamaCppEngine()
        // Should return immediately without crash
        await engine.warmup()
        XCTAssertFalse(engine.isLoaded)
    }

    // MARK: - Load With Invalid Model

    func testLoadFailsWithInvalidModelId() async {
        let engine = LlamaCppEngine()
        do {
            try await engine.loadModel(id: "nonexistent-model", progressHandler: { _ in })
            XCTFail("Expected load to throw for invalid model ID")
        } catch {
            XCTAssertTrue(error is YapYapError)
        }
    }

    // MARK: - Concurrent Warmup Safety

    func testConcurrentWarmupsDoNotCrash() async {
        // Even without a loaded model, verify multiple concurrent warmup calls
        // don't crash. The guard on isLoaded returns early, but this exercises
        // the code path and ensures no unexpected state corruption.
        let engine = LlamaCppEngine()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { await engine.warmup() }
            }
        }
        XCTAssertFalse(engine.isLoaded)
    }

    // MARK: - LlamaCppError

    func testModelLoadFailedDescription() {
        let error = LlamaCppError.modelLoadFailed("/path/to/model.gguf")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("/path/to/model.gguf"))
    }

    func testContextCreationFailedDescription() {
        let error = LlamaCppError.contextCreationFailed
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("context"))
    }

    func testTokenizationFailedDescription() {
        let error = LlamaCppError.tokenizationFailed
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("tokenize"))
    }

    func testDecodeFailedDescription() {
        let error = LlamaCppError.decodeFailed(-1)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("-1"))
    }

    func testSamplerInitFailedDescription() {
        let error = LlamaCppError.samplerInitFailed
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("sampler"))
    }

    func testDownloadFailedDescription() {
        let error = LlamaCppError.downloadFailed("https://example.com/model.gguf")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("example.com"))
    }

    func testAllErrorCasesHaveDescriptions() {
        let errors: [LlamaCppError] = [
            .modelLoadFailed("/tmp/test"),
            .contextCreationFailed,
            .tokenizationFailed,
            .decodeFailed(1),
            .samplerInitFailed,
            .downloadFailed("https://example.com"),
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Missing description for \(error)")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Empty description for \(error)")
        }
    }
}
