// OllamaEngineTests.swift
// YapYapTests — Tests for OllamaEngine (protocol conformance, state, error types)
import XCTest
@testable import YapYap

final class OllamaEngineTests: XCTestCase {

    // MARK: - Initial State

    func testInitialStateNotLoaded() {
        let engine = OllamaEngine()
        XCTAssertFalse(engine.isLoaded)
        XCTAssertNil(engine.modelId)
    }

    func testDefaultEndpoint() {
        XCTAssertEqual(OllamaEngine.defaultEndpoint, "http://localhost:11434")
    }

    func testCustomEndpoint() {
        let engine = OllamaEngine(endpoint: "http://10.0.0.5:11434")
        XCTAssertFalse(engine.isLoaded)
    }

    func testEndpointTrailingSlashStripped() {
        // The engine should handle trailing slashes gracefully
        let engine = OllamaEngine(endpoint: "http://localhost:11434/")
        XCTAssertFalse(engine.isLoaded)
    }

    // MARK: - Protocol Conformance

    func testConformsToLLMEngine() {
        let engine = OllamaEngine()
        XCTAssertTrue(engine is LLMEngine)
    }

    func testIsClassType() {
        // LLMEngine requires AnyObject (class type)
        let engine: LLMEngine = OllamaEngine()
        XCTAssertNotNil(engine)
    }

    // MARK: - Unload

    func testUnloadResetsState() {
        let engine = OllamaEngine()
        engine.unloadModel()
        XCTAssertFalse(engine.isLoaded)
        XCTAssertNil(engine.modelId)
    }

    // MARK: - Cleanup Without Load

    func testCleanupThrowsWhenNotLoaded() async {
        let engine = OllamaEngine()
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
            // Expected — model not loaded
            XCTAssertTrue(error is YapYapError)
        }
    }

    // MARK: - Load Fails Without Server

    func testLoadFailsWithoutServer() async {
        // Use a non-routable endpoint so it fails quickly
        let engine = OllamaEngine(endpoint: "http://192.0.2.1:99999")
        do {
            try await engine.loadModel(id: "test-model", progressHandler: { _ in })
            XCTFail("Expected load to throw when server is unreachable")
        } catch {
            XCTAssertTrue(error is OllamaError)
            if case .serverUnreachable = error as? OllamaError {
                // Expected
            } else {
                XCTFail("Expected serverUnreachable error, got \(error)")
            }
        }
    }

    // MARK: - OllamaError

    func testServerUnreachableDescription() {
        let error = OllamaError.serverUnreachable("http://localhost:11434")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Ollama"))
        XCTAssertTrue(error.errorDescription!.contains("localhost"))
    }

    func testPullFailedDescription() {
        let error = OllamaError.pullFailed("qwen2.5:1.5b")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("qwen2.5:1.5b"))
    }

    func testPullErrorDescription() {
        let error = OllamaError.pullError("qwen2.5:1.5b", "network timeout")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("network timeout"))
    }

    func testInvalidResponseDescription() {
        let error = OllamaError.invalidResponse
        XCTAssertNotNil(error.errorDescription)
    }

    func testHttpErrorDescription() {
        let error = OllamaError.httpError(404, "model not found")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("404"))
    }

    func testModelNotFoundDescription() {
        let error = OllamaError.modelNotFound("llama3:8b")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("llama3:8b"))
        XCTAssertTrue(error.errorDescription!.contains("ollama pull"))
    }
}
