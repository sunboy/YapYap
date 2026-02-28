// InferenceFrameworkTests.swift
// YapYapTests — Tests for inference framework types, factory, and settings integration
import XCTest
@testable import YapYap

final class InferenceFrameworkTests: XCTestCase {

    // MARK: - LLMInferenceFramework Enum

    func testFrameworkRawValues() {
        XCTAssertEqual(LLMInferenceFramework.mlx.rawValue, "mlx")
        XCTAssertEqual(LLMInferenceFramework.ollama.rawValue, "ollama")
    }

    func testFrameworkFromRawValue() {
        XCTAssertEqual(LLMInferenceFramework(rawValue: "mlx"), .mlx)
        XCTAssertEqual(LLMInferenceFramework(rawValue: "ollama"), .ollama)
        XCTAssertNil(LLMInferenceFramework(rawValue: "invalid"))
    }

    func testFrameworkAllCases() {
        XCTAssertEqual(LLMInferenceFramework.allCases.count, 2)
        XCTAssertTrue(LLMInferenceFramework.allCases.contains(.mlx))
        XCTAssertTrue(LLMInferenceFramework.allCases.contains(.ollama))
    }

    func testFrameworkDisplayNames() {
        XCTAssertFalse(LLMInferenceFramework.mlx.displayName.isEmpty)
        XCTAssertFalse(LLMInferenceFramework.ollama.displayName.isEmpty)
        XCTAssertTrue(LLMInferenceFramework.mlx.displayName.contains("MLX"))
        XCTAssertTrue(LLMInferenceFramework.ollama.displayName.contains("Ollama"))
    }

    func testFrameworkDescriptions() {
        XCTAssertFalse(LLMInferenceFramework.mlx.description.isEmpty)
        XCTAssertFalse(LLMInferenceFramework.ollama.description.isEmpty)
    }

    func testFrameworkCodable() throws {
        let original = LLMInferenceFramework.ollama
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LLMInferenceFramework.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - LLMEngineFactory

    func testFactoryCreatesMLXEngine() {
        let engine = LLMEngineFactory.create(framework: .mlx)
        XCTAssertTrue(engine is MLXEngine)
        XCTAssertFalse(engine.isLoaded)
    }

    func testFactoryCreatesOllamaEngine() {
        let engine = LLMEngineFactory.create(framework: .ollama)
        XCTAssertTrue(engine is OllamaEngine)
        XCTAssertFalse(engine.isLoaded)
    }

    func testFactoryCreatesOllamaEngineWithCustomEndpoint() {
        let endpoint = "http://192.168.1.100:11434"
        let engine = LLMEngineFactory.create(framework: .ollama, ollamaEndpoint: endpoint)
        XCTAssertTrue(engine is OllamaEngine)
    }

    func testFactoryDefaultEndpoint() {
        // Create two engines — one with default, one with explicit default
        let engine1 = LLMEngineFactory.create(framework: .ollama)
        let engine2 = LLMEngineFactory.create(framework: .ollama, ollamaEndpoint: OllamaEngine.defaultEndpoint)
        // Both should be OllamaEngine instances
        XCTAssertTrue(engine1 is OllamaEngine)
        XCTAssertTrue(engine2 is OllamaEngine)
    }

    // MARK: - AppSettings Integration

    func testAppSettingsDefaultsMLXFramework() {
        let settings = AppSettings()
        XCTAssertEqual(settings.llmInferenceFramework, LLMInferenceFramework.mlx.rawValue)
    }

    func testAppSettingsOllamaEndpointDefault() {
        let settings = AppSettings()
        XCTAssertEqual(settings.ollamaEndpoint, OllamaEngine.defaultEndpoint)
    }

    func testAppSettingsOllamaModelNameDefault() {
        let settings = AppSettings()
        XCTAssertFalse(settings.ollamaModelName.isEmpty)
    }

    func testAppSettingsFrameworkSwitchable() {
        let settings = AppSettings()
        XCTAssertEqual(settings.llmInferenceFramework, "mlx")

        settings.llmInferenceFramework = LLMInferenceFramework.ollama.rawValue
        XCTAssertEqual(settings.llmInferenceFramework, "ollama")

        let framework = LLMInferenceFramework(rawValue: settings.llmInferenceFramework)
        XCTAssertEqual(framework, .ollama)
    }

    func testAppSettingsCustomOllamaConfig() {
        let settings = AppSettings(
            ollamaEndpoint: "http://10.0.0.5:11434",
            ollamaModelName: "llama3.2:3b"
        )
        XCTAssertEqual(settings.ollamaEndpoint, "http://10.0.0.5:11434")
        XCTAssertEqual(settings.ollamaModelName, "llama3.2:3b")
    }

    func testAppSettingsDefaultsUseMachineProfile() {
        let defaults = AppSettings.defaults()
        let profile = MachineProfile.detect()
        XCTAssertEqual(defaults.llmModelId, profile.recommendedMLXModelId)
        XCTAssertEqual(defaults.ollamaModelName, profile.recommendedOllamaModelName)
    }
}
