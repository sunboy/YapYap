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

    // MARK: - Pre-compiled sanitization (mirrors MLXEngine)

    private static let specialTokens = [
        "<|endoftext|>", "<|im_end|>", "<|im_start|>",
        "<|eot_id|>", "<|end|>", "</s>", "<s>",
        "<|assistant|>", "<|user|>", "<|system|>"
    ]

    private static let preambleRegexes: [NSRegularExpression] = {
        let patterns = [
            "(?i)^\\s*(the\\s+)?cleaned\\s+(text|version)\\s*(is)?\\s*:?\\s*",
            "(?i)^\\s*here\\s+(is|are)\\s+(the\\s+)?.*?:\\s*",
            "(?i)^\\s*here'?s\\s+the\\s+.*?:\\s*",
            "(?i)^\\s*(cleaned|corrected|fixed)\\s+(text|version)\\s*:?\\s*",
            "(?i)^\\s*output\\s*:\\s*",
            "(?i)^\\s*result\\s*:\\s*",
            "(?i)^\\s*(I'?d\\s+love\\s+to|sure[,!.]?|of\\s+course[,!.]?|certainly[,!.]?|absolutely[,!.]?)\\s+.*?[:\\.!]\\s*",
            "(?i)^\\s*I'?m\\s+sorry.*$",
            "(?i)^\\s*I\\s+cannot\\s+.*$",
            "(?i)^\\s*I\\s+can'?t\\s+provide.*$",
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    private static let trailingRegexes: [NSRegularExpression] = {
        let patterns = [
            "(?i)\\s*no\\s+further\\s+(changes|edits|modifications)\\s+(are\\s+)?(required|needed|necessary).*$",
            "(?i)\\s*\\(no\\s+changes.*?\\)\\s*$",
            "(?i)\\s*I('ve|\\s+have)\\s+cleaned\\s+up.*$",
            "(?i)\\s*note:.*$",
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    private static let listMarkerRegex = try! NSRegularExpression(pattern: "^(\\d+[.)]\\s|[-•*]\\s)")

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

        let sanitized = Self.sanitizeOutput(outputText)

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

    // MARK: - Sanitization (mirrors MLXEngine.sanitizeOutput)

    private static func sanitizeOutput(_ text: String) -> String {
        var cleaned = text

        for token in specialTokens {
            cleaned = cleaned.replacingOccurrences(of: token, with: "")
        }

        for regex in preambleRegexes {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }

        for regex in trailingRegexes {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }

        if cleaned.contains("```") {
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        }

        let lines = cleaned.components(separatedBy: "\n")
        let commentLines = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        if commentLines.count > lines.count / 2 && lines.count > 2 {
            return ""
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("`") && cleaned.hasSuffix("`") && cleaned.count > 2 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count > 2 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }

        let splitLines = cleaned.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let listLineCount = splitLines.filter { line in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            return listMarkerRegex.firstMatch(in: line, range: range) != nil
        }.count

        if listLineCount >= 2 {
            cleaned = splitLines.joined(separator: "\n")
        } else {
            cleaned = splitLines.joined(separator: " ")
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
