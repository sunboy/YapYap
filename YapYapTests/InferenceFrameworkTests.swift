// InferenceFrameworkTests.swift
// YapYapTests — Tests for inference framework types, factory, and settings integration
import XCTest
@testable import YapYap

final class InferenceFrameworkTests: XCTestCase {

    // MARK: - LLMInferenceFramework Enum

    func testFrameworkRawValues() {
        XCTAssertEqual(LLMInferenceFramework.mlx.rawValue, "mlx")
        XCTAssertEqual(LLMInferenceFramework.llamacpp.rawValue, "llamacpp")
        XCTAssertEqual(LLMInferenceFramework.ollama.rawValue, "ollama")
    }

    func testFrameworkFromRawValue() {
        XCTAssertEqual(LLMInferenceFramework(rawValue: "mlx"), .mlx)
        XCTAssertEqual(LLMInferenceFramework(rawValue: "llamacpp"), .llamacpp)
        XCTAssertEqual(LLMInferenceFramework(rawValue: "ollama"), .ollama)
        XCTAssertNil(LLMInferenceFramework(rawValue: "invalid"))
    }

    func testFrameworkAllCases() {
        XCTAssertEqual(LLMInferenceFramework.allCases.count, 3)
        XCTAssertTrue(LLMInferenceFramework.allCases.contains(.mlx))
        XCTAssertTrue(LLMInferenceFramework.allCases.contains(.llamacpp))
        XCTAssertTrue(LLMInferenceFramework.allCases.contains(.ollama))
    }

    func testFrameworkDisplayNames() {
        XCTAssertFalse(LLMInferenceFramework.mlx.displayName.isEmpty)
        XCTAssertFalse(LLMInferenceFramework.llamacpp.displayName.isEmpty)
        XCTAssertFalse(LLMInferenceFramework.ollama.displayName.isEmpty)
        XCTAssertTrue(LLMInferenceFramework.mlx.displayName.contains("MLX"))
        XCTAssertTrue(LLMInferenceFramework.llamacpp.displayName.contains("llama"))
        XCTAssertTrue(LLMInferenceFramework.ollama.displayName.contains("Ollama"))
    }

    func testFrameworkDescriptions() {
        XCTAssertFalse(LLMInferenceFramework.mlx.description.isEmpty)
        XCTAssertFalse(LLMInferenceFramework.llamacpp.description.isEmpty)
        XCTAssertFalse(LLMInferenceFramework.ollama.description.isEmpty)
    }

    func testFrameworkModelTypeFlags() {
        XCTAssertTrue(LLMInferenceFramework.mlx.usesMLXModels)
        XCTAssertFalse(LLMInferenceFramework.mlx.usesGGUFModels)
        XCTAssertFalse(LLMInferenceFramework.mlx.usesOllamaModels)

        XCTAssertFalse(LLMInferenceFramework.llamacpp.usesMLXModels)
        XCTAssertTrue(LLMInferenceFramework.llamacpp.usesGGUFModels)
        XCTAssertFalse(LLMInferenceFramework.llamacpp.usesOllamaModels)

        XCTAssertFalse(LLMInferenceFramework.ollama.usesMLXModels)
        XCTAssertFalse(LLMInferenceFramework.ollama.usesGGUFModels)
        XCTAssertTrue(LLMInferenceFramework.ollama.usesOllamaModels)
    }

    func testFrameworkCodable() throws {
        for framework in LLMInferenceFramework.allCases {
            let data = try JSONEncoder().encode(framework)
            let decoded = try JSONDecoder().decode(LLMInferenceFramework.self, from: data)
            XCTAssertEqual(framework, decoded)
        }
    }

    // MARK: - LLMEngineFactory

    func testFactoryCreatesMLXEngine() {
        let engine = LLMEngineFactory.create(framework: .mlx)
        XCTAssertTrue(engine is MLXEngine)
        XCTAssertFalse(engine.isLoaded)
    }

    func testFactoryCreatesLlamaCppEngine() {
        let engine = LLMEngineFactory.create(framework: .llamacpp)
        XCTAssertTrue(engine is LlamaCppEngine)
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

    // MARK: - GGUFModelRegistry

    func testGGUFRegistryHasModels() {
        XCTAssertFalse(GGUFModelRegistry.allModels.isEmpty)
    }

    func testGGUFRegistryHasRecommendedModel() {
        let recommended = GGUFModelRegistry.recommendedModel
        XCTAssertTrue(recommended.isRecommended)
    }

    func testGGUFRegistryModelLookup() {
        for model in GGUFModelRegistry.allModels {
            XCTAssertNotNil(GGUFModelRegistry.model(for: model.id))
        }
        XCTAssertNil(GGUFModelRegistry.model(for: "nonexistent"))
    }

    func testGGUFModelsHaveMLXEquivalents() {
        for model in GGUFModelRegistry.allModels {
            XCTAssertNotNil(
                LLMModelRegistry.model(for: model.mlxEquivalentId),
                "GGUF model \(model.id) has no MLX equivalent \(model.mlxEquivalentId)"
            )
        }
    }

    func testGGUFModelsHaveValidDownloadURLs() {
        for model in GGUFModelRegistry.allModels {
            let url = model.downloadURL
            XCTAssertTrue(url.absoluteString.contains("huggingface.co"), "Invalid URL for \(model.id)")
            XCTAssertTrue(url.absoluteString.hasSuffix(".gguf"), "URL should end with .gguf for \(model.id)")
        }
    }

    func testGGUFModelIdsArePrefixed() {
        for model in GGUFModelRegistry.allModels {
            XCTAssertTrue(model.id.hasPrefix("gguf-"), "GGUF model ID \(model.id) should start with 'gguf-'")
        }
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

    func testAppSettingsLlamaCppModelIdDefault() {
        let settings = AppSettings()
        XCTAssertFalse(settings.llamacppModelId.isEmpty)
        XCTAssertTrue(settings.llamacppModelId.hasPrefix("gguf-"))
    }

    func testAppSettingsFrameworkSwitchable() {
        let settings = AppSettings()
        XCTAssertEqual(settings.llmInferenceFramework, "mlx")

        settings.llmInferenceFramework = LLMInferenceFramework.llamacpp.rawValue
        XCTAssertEqual(settings.llmInferenceFramework, "llamacpp")

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
        XCTAssertEqual(defaults.llamacppModelId, profile.recommendedGGUFModelId)
    }
}
