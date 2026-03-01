// BenchmarkLLMRunner.swift
// YapYapBench — Wraps MLX generate for raw output + structured metrics
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers
import Foundation
import Hub

/// Metrics from a single LLM run.
struct LLMRunMetrics {
    let rawOutput: String
    let sanitizedOutput: String
    let promptTokens: Int
    let generationTokens: Int
    let prefillMs: Int
    let generationMs: Int
    let totalMs: Int
    let tokensPerSecond: Double
}

/// Wraps MLX inference to capture raw output and timing metrics that MLXEngine.cleanup() doesn't expose.
class BenchmarkLLMRunner {
    private var lmContext: ModelContext?
    private(set) var modelId: String?

    var isLoaded: Bool { lmContext != nil }


    // MARK: - Model Loading

    func loadModel(id: String, progressHandler: @escaping (Double) -> Void) async throws {
        guard let modelInfo = LLMModelRegistry.model(for: id) else {
            throw BenchError.invalidModel("Unknown LLM model: \(id)")
        }

        let config = ModelConfiguration(id: modelInfo.huggingFaceId)
        let factory = LLMModelFactory.shared

        lmContext = try await factory.load(
            hub: HubApi(),
            configuration: config
        ) { progress in
            progressHandler(progress.fractionCompleted)
        }

        self.modelId = id
    }

    func unloadModel() {
        lmContext = nil
        modelId = nil
    }

    // MARK: - Inference with Metrics

    /// Run LLM cleanup and return raw output + structured metrics.
    func run(rawText: String, context: CleanupContext) async throws -> LLMRunMetrics {
        guard let lmContext = lmContext, let modelId = modelId else {
            throw BenchError.llmFailed("Model not loaded")
        }

        let messages = CleanupPromptBuilder.buildMessages(rawText: rawText, context: context, modelId: modelId)

        // Apply chat template
        // Omit system role when empty (Gemma merges system into user block)
        var chatMessages: [[String: String]] = []
        if !messages.system.isEmpty {
            chatMessages.append(["role": "system", "content": messages.system])
        }
        chatMessages.append(["role": "user", "content": messages.user])

        let encoding: [Int]
        do {
            encoding = try lmContext.tokenizer.applyChatTemplate(messages: chatMessages)
        } catch {
            let fallbackModelInfo = LLMModelRegistry.model(for: modelId)
            let fallbackPrompt: String
            if fallbackModelInfo?.family == .llama {
                fallbackPrompt = "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(messages.system)<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n\(messages.user)<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
            } else if fallbackModelInfo?.family == .gemma {
                // Gemma format (system already merged into user by CleanupPromptBuilder)
                fallbackPrompt = "<start_of_turn>user\n\(messages.user)<end_of_turn>\n<start_of_turn>model\n"
            } else {
                // Qwen/ChatML format (default)
                let systemBlock = messages.system.isEmpty ? "" : "<|im_start|>system\n\(messages.system)<|im_end|>\n"
                fallbackPrompt = "\(systemBlock)<|im_start|>user\n\(messages.user)<|im_end|>\n<|im_start|>assistant\n"
            }
            encoding = lmContext.tokenizer.encode(text: fallbackPrompt)
        }

        let input = LMInput(tokens: MLXArray(encoding))

        let userTokenCount = lmContext.tokenizer.encode(text: rawText).count
        let maxOutputTokens = max(32, min(userTokenCount * 2, 512))

        let modelInfo = LLMModelRegistry.model(for: modelId)
        let family = modelInfo?.family ?? .qwen

        let parameters = GenerateParameters(
            maxTokens: maxOutputTokens,
            temperature: family.temperature,
            topP: family.topP,
            repetitionPenalty: family.repetitionPenalty,
            repetitionContextSize: family.repetitionContextSize
        )

        let startTime = Date()
        var firstTokenTime: Date?
        var outputText = ""
        var generationTokenCount = 0
        var finalTokPerSec = 0.0

        let stream: AsyncStream<Generation> = try generate(
            input: input,
            parameters: parameters,
            context: lmContext
        )

        for await generation in stream {
            switch generation {
            case .chunk(let text):
                if firstTokenTime == nil {
                    firstTokenTime = Date()
                }
                outputText += text
                generationTokenCount += 1
            case .info(let info):
                generationTokenCount = info.generationTokenCount
                finalTokPerSec = info.tokensPerSecond
            default:
                break
            }
        }

        let endTime = Date()
        let prefillMs = Int((firstTokenTime ?? endTime).timeIntervalSince(startTime) * 1000)
        let generationMs = Int(endTime.timeIntervalSince(firstTokenTime ?? endTime) * 1000)
        let totalMs = Int(endTime.timeIntervalSince(startTime) * 1000)

        let sanitized = LLMOutputSanitizer.sanitize(outputText)

        return LLMRunMetrics(
            rawOutput: outputText,
            sanitizedOutput: sanitized,
            promptTokens: encoding.count,
            generationTokens: generationTokenCount,
            prefillMs: prefillMs,
            generationMs: generationMs,
            totalMs: totalMs,
            tokensPerSecond: finalTokPerSec
        )
    }

    /// Get the prompt that would be sent (for recording in results).
    func getPrompt(rawText: String, context: CleanupContext) -> (system: String, user: String) {
        CleanupPromptBuilder.buildMessages(rawText: rawText, context: context, modelId: modelId)
    }

}
