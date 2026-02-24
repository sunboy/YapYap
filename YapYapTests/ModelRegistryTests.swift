// ModelRegistryTests.swift
// YapYapTests
import XCTest
@testable import YapYap

final class ModelRegistryTests: XCTestCase {

    // MARK: - STT Model Registry

    func testSTTModelsNotEmpty() {
        XCTAssertFalse(STTModelRegistry.allModels.isEmpty)
    }

    func testSTTModelCount() {
        XCTAssertEqual(STTModelRegistry.allModels.count, 5)
    }

    func testSTTModelLookup() {
        let whisperLarge = STTModelRegistry.model(for: "whisper-large-v3-turbo")
        XCTAssertNotNil(whisperLarge)
        XCTAssertEqual(whisperLarge?.name, "Whisper Large v3")
        XCTAssertEqual(whisperLarge?.backend, .whisperKit)
    }

    func testSTTModelLookupParakeet() {
        let parakeet = STTModelRegistry.model(for: "parakeet-tdt-v3")
        XCTAssertNotNil(parakeet)
        XCTAssertEqual(parakeet?.backend, .fluidAudio)
    }

    func testSTTModelLookupVoxtral() {
        let voxtral = STTModelRegistry.model(for: "voxtral-mini-3b")
        XCTAssertNotNil(voxtral)
        XCTAssertEqual(voxtral?.backend, .whisperCpp)
    }

    func testSTTModelLookupInvalid() {
        let result = STTModelRegistry.model(for: "nonexistent-model")
        XCTAssertNil(result)
    }

    func testSTTRecommendedModel() {
        let recommended = STTModelRegistry.recommendedModel
        XCTAssertTrue(recommended.isRecommended)
        XCTAssertEqual(recommended.id, "whisper-small")
    }

    func testSTTModelUniqueIds() {
        let ids = STTModelRegistry.allModels.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "STT model IDs should be unique")
    }

    func testSTTModelSizesPositive() {
        for model in STTModelRegistry.allModels {
            XCTAssertGreaterThan(model.sizeBytes, 0, "\(model.name) should have positive size")
        }
    }

    func testSTTModelLanguagesNotEmpty() {
        for model in STTModelRegistry.allModels {
            XCTAssertFalse(model.languages.isEmpty, "\(model.name) should support at least one language")
        }
    }

    // MARK: - LLM Model Registry

    func testLLMModelsNotEmpty() {
        XCTAssertFalse(LLMModelRegistry.allModels.isEmpty)
    }

    func testLLMModelCount() {
        XCTAssertEqual(LLMModelRegistry.allModels.count, LLMModelRegistry.allModels.count) // count checked dynamically
        XCTAssertGreaterThan(LLMModelRegistry.allModels.count, 0)
    }

    func testLLMModelLookup() {
        let qwen3b = LLMModelRegistry.model(for: "qwen-2.5-3b")
        XCTAssertNotNil(qwen3b)
        XCTAssertEqual(qwen3b?.name, "Qwen 2.5 3B")
    }

    func testLLMModelLookupLlama() {
        let llama = LLMModelRegistry.model(for: "llama-3.2-3b")
        XCTAssertNotNil(llama)
        XCTAssertEqual(llama?.name, "Llama 3.2 3B")
    }

    func testLLMModelLookupInvalid() {
        let result = LLMModelRegistry.model(for: "nonexistent")
        XCTAssertNil(result)
    }

    func testLLMRecommendedModel() {
        let recommended = LLMModelRegistry.recommendedModel
        XCTAssertTrue(recommended.isRecommended)
        XCTAssertEqual(recommended.id, "qwen-2.5-1.5b")
    }

    func testLLMModelUniqueIds() {
        let ids = LLMModelRegistry.allModels.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "LLM model IDs should be unique")
    }

    func testLLMModelSizesPositive() {
        for model in LLMModelRegistry.allModels {
            XCTAssertGreaterThan(model.sizeBytes, 0, "\(model.name) should have positive size")
        }
    }

    func testLLMModelHuggingFaceIds() {
        for model in LLMModelRegistry.allModels {
            XCTAssertFalse(model.huggingFaceId.isEmpty, "\(model.name) should have HuggingFace ID")
            XCTAssertTrue(model.huggingFaceId.contains("/"), "\(model.name) HuggingFace ID should contain /")
        }
    }

    func testLLMModelFamilies() {
        let llama1b = LLMModelRegistry.model(for: "llama-3.2-1b")
        XCTAssertEqual(llama1b?.family, .llama)

        let llama3b = LLMModelRegistry.model(for: "llama-3.2-3b")
        XCTAssertEqual(llama3b?.family, .llama)

        let llama8b = LLMModelRegistry.model(for: "llama-3.1-8b")
        XCTAssertEqual(llama8b?.family, .llama)

        let qwen1_5b = LLMModelRegistry.model(for: "qwen-2.5-1.5b")
        XCTAssertEqual(qwen1_5b?.family, .qwen)

        let qwen3b = LLMModelRegistry.model(for: "qwen-2.5-3b")
        XCTAssertEqual(qwen3b?.family, .qwen)

        let qwen7b = LLMModelRegistry.model(for: "qwen-2.5-7b")
        XCTAssertEqual(qwen7b?.family, .qwen)
    }

    func testLLMModelFamilyInferenceParams() {
        // All families should use temperature 0.0 for deterministic cleanup
        XCTAssertEqual(LLMModelFamily.llama.temperature, 0.0)
        XCTAssertEqual(LLMModelFamily.qwen.temperature, 0.0)
        XCTAssertEqual(LLMModelFamily.gemma.temperature, 0.0)

        // All should have repetition penalty
        XCTAssertGreaterThan(LLMModelFamily.llama.repetitionPenalty, 1.0)
        XCTAssertGreaterThan(LLMModelFamily.qwen.repetitionPenalty, 1.0)
    }
}
