// MLXEngine.swift
// YapYap — MLX Swift LLM inference engine
import MLX
import MLXLM
import Foundation

class MLXEngine: LLMEngine {
    private var model: LLMModel?
    private var tokenizer: Tokenizer?
    private(set) var modelId: String?

    var isLoaded: Bool { model != nil }

    func loadModel(id: String, progressHandler: @escaping (Double) -> Void) async throws {
        let config = ModelConfiguration(id: id)
        let (loadedModel, loadedTokenizer) = try await MLXLM.load(configuration: config) { progress in
            progressHandler(progress.fractionCompleted)
        }
        self.model = loadedModel
        self.tokenizer = loadedTokenizer
        self.modelId = id
    }

    func unloadModel() {
        model = nil
        tokenizer = nil
        modelId = nil
    }

    func cleanup(rawText: String, context: CleanupContext) async throws -> String {
        guard let model = model, let tokenizer = tokenizer else {
            throw YapYapError.modelNotLoaded
        }

        let prompt = CleanupPromptBuilder.buildPrompt(rawText: rawText, context: context)

        let result = try await MLXLM.generate(
            model: model,
            tokenizer: tokenizer,
            prompt: prompt,
            parameters: .init(temperature: 0.3, topP: 0.9, maxTokens: 512)
        )

        // Strip any preamble the model might add
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
