// MLXEngine.swift
// YapYap — MLX Swift LLM inference engine
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers
import Foundation
import Hub

class MLXEngine: LLMEngine {
    private var modelContext: ModelContext?
    private(set) var modelId: String?

    var isLoaded: Bool { modelContext != nil }

    func loadModel(id: String, progressHandler: @escaping (Double) -> Void) async throws {
        let config = ModelConfiguration(id: id)
        let factory = LLMModelFactory.shared

        // Load model using the factory
        modelContext = try await factory.load(
            hub: HubApi(),
            configuration: config
        ) { progress in
            progressHandler(progress.fractionCompleted)
        }

        self.modelId = id
    }

    func unloadModel() {
        modelContext = nil
        modelId = nil
    }

    func cleanup(rawText: String, context: CleanupContext) async throws -> String {
        guard let modelContext = modelContext else {
            throw YapYapError.modelNotLoaded
        }

        let prompt = CleanupPromptBuilder.buildPrompt(rawText: rawText, context: context)

        // Tokenize the prompt
        let encoding = modelContext.tokenizer.encode(text: prompt)
        let input = LMInput(tokens: MLXArray(encoding))

        // Generate parameters
        let parameters = GenerateParameters(
            maxTokens: 512,
            temperature: 0.3,
            topP: 0.9
        )

        // Generate output tokens using deprecated but functional API
        let didGenerate: ([Int]) -> GenerateDisposition = { tokens in
            // Continue generating tokens
            return .more
        }

        let result: GenerateResult = try generate(
            input: input,
            parameters: parameters,
            context: modelContext,
            didGenerate: didGenerate
        )

        // Return the final generated text, trimmed
        return result.output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}
