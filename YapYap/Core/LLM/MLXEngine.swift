// MLXEngine.swift
// YapYap — MLX Swift LLM inference engine
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers
import Foundation
import Hub

class MLXEngine: LLMEngine {
    // Use explicit module qualification to avoid SwiftData.ModelContext collision
    private var lmContext: MLXLMCommon.ModelContext?
    private(set) var modelId: String?

    /// Pre-compiled regex patterns for output sanitization (compiled once, reused)
    private static let sanitizationRegexes = SanitizationRegexes()

    /// Matches lines starting with list markers: "1. ", "2) ", "- ", "* ", "• "
    private static let listMarkerRegex = try! NSRegularExpression(pattern: "^(\\d+[.)]\\s|[-•*]\\s)")

    var isLoaded: Bool { lmContext != nil }

    func loadModel(id: String, progressHandler: @escaping (Double) -> Void) async throws {
        guard let modelInfo = LLMModelRegistry.model(for: id) else {
            throw YapYapError.modelNotLoaded
        }

        NSLog("[MLXEngine] Loading model '\(id)' from HuggingFace repo: \(modelInfo.huggingFaceId)")

        let config = ModelConfiguration(id: modelInfo.huggingFaceId)
        let factory = LLMModelFactory.shared

        lmContext = try await factory.load(
            hub: HubApi(),
            configuration: config
        ) { progress in
            progressHandler(progress.fractionCompleted)
        }

        self.modelId = id
        NSLog("[MLXEngine] Model '\(id)' loaded successfully")
    }

    func unloadModel() {
        lmContext = nil
        modelId = nil
    }

    func warmup() async {
        guard let lmContext = lmContext else { return }
        do {
            let tokens = lmContext.tokenizer.encode(text: "Hello")
            let input = LMInput(tokens: MLXArray(tokens))
            let parameters = GenerateParameters(maxTokens: 1)
            let stream: AsyncStream<Generation> = try generate(
                input: input,
                parameters: parameters,
                context: lmContext
            )
            for await _ in stream { break }
            NSLog("[MLXEngine] Keep-alive warmup complete")
        } catch {
            NSLog("[MLXEngine] Keep-alive warmup failed: \(error)")
        }
    }

    func cleanup(rawText: String, context: CleanupContext) async throws -> String {
        guard let lmContext = lmContext else {
            throw YapYapError.modelNotLoaded
        }

        let messages = CleanupPromptBuilder.buildMessages(rawText: rawText, context: context, modelId: modelId)

        // Use the tokenizer's chat template for correct model-specific formatting
        // This handles Llama vs Qwen vs other model template differences automatically
        let chatMessages: [[String: String]] = [
            ["role": "system", "content": messages.system],
            ["role": "user", "content": messages.user]
        ]

        let encoding: [Int]
        do {
            encoding = try lmContext.tokenizer.applyChatTemplate(messages: chatMessages)
        } catch {
            // Fallback: manual template if applyChatTemplate fails.
            // Use model-family-specific token format to avoid garbage output.
            NSLog("[MLXEngine] applyChatTemplate failed: \(error), using manual template")
            let fallbackModelInfo = modelId.flatMap { LLMModelRegistry.model(for: $0) }
            let fallbackPrompt: String
            if fallbackModelInfo?.family == .llama {
                // Llama 3.x format
                fallbackPrompt = "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(messages.system)<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n\(messages.user)<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
            } else {
                // Qwen/ChatML format (default)
                fallbackPrompt = "<|im_start|>system\n\(messages.system)<|im_end|>\n<|im_start|>user\n\(messages.user)<|im_end|>\n<|im_start|>assistant\n"
            }
            encoding = lmContext.tokenizer.encode(text: fallbackPrompt)
        }

        let input = LMInput(tokens: MLXArray(encoding))

        // Cap output tokens: cleanup output ≈ input length
        let userTokenCount = lmContext.tokenizer.encode(text: rawText).count
        let maxOutputTokens = max(32, min(userTokenCount * 2, 512))

        // Use model-family-specific inference parameters
        let modelInfo = modelId.flatMap { LLMModelRegistry.model(for: $0) }
        let family = modelInfo?.family ?? .qwen

        // Use library default prefillStepSize (512). Our prompts are 150-250 tokens,
        // and the prefill processes them in chunks of this size. Larger steps allow
        // better GPU utilization on Apple Silicon.
        NSLog("[MLXEngine] Prompt: \(encoding.count) tokens, user: \(userTokenCount) tokens, maxOutput: \(maxOutputTokens), family: \(family.rawValue)")

        let parameters = GenerateParameters(
            maxTokens: maxOutputTokens,
            temperature: family.temperature,
            topP: family.topP,
            repetitionPenalty: family.repetitionPenalty,
            repetitionContextSize: family.repetitionContextSize
        )

        let startTime = Date()
        var firstTokenTime: Date?

        // Use the AsyncStream-based generate API
        var outputText = ""
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
                    let prefillMs = firstTokenTime!.timeIntervalSince(startTime) * 1000
                    NSLog("[MLXEngine] Prefill: \(String(format: "%.0f", prefillMs))ms (\(encoding.count) prompt tokens)")
                }
                outputText += text
            case .info(let info):
                let elapsed = Date().timeIntervalSince(startTime)
                let genMs = firstTokenTime.map { Date().timeIntervalSince($0) * 1000 } ?? 0
                NSLog("[MLXEngine] Generation: \(info.generationTokenCount) tokens in \(String(format: "%.0f", genMs))ms (\(String(format: "%.0f", info.tokensPerSecond)) tok/s), total \(String(format: "%.1f", elapsed))s")
            default:
                break
            }
        }

        let result = Self.sanitizeOutput(outputText)
        NSLog("[MLXEngine] Cleanup result (\(result.count) chars): \"\(String(result.prefix(80)))...\"")
        return result
    }

    // MARK: - Pre-compiled Sanitization Regexes

    /// Pre-compiled regex patterns for output sanitization.
    /// Compiled once at class load time, reused across all calls.
    private struct SanitizationRegexes {
        let specialTokens = [
            "<|endoftext|>", "<|im_end|>", "<|im_start|>",
            "<|eot_id|>", "<|end|>", "</s>", "<s>",
            "<|assistant|>", "<|user|>", "<|system|>"
        ]

        let preambleRegexes: [NSRegularExpression]
        let trailingRegexes: [NSRegularExpression]
        let codeLanguageRegex: NSRegularExpression?

        init() {
            let preamblePatterns = [
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

            let trailingPatterns = [
                "(?i)\\s*no\\s+further\\s+(changes|edits|modifications)\\s+(are\\s+)?(required|needed|necessary).*$",
                "(?i)\\s*\\(no\\s+changes.*?\\)\\s*$",
                "(?i)\\s*I('ve|\\s+have)\\s+cleaned\\s+up.*$",
                "(?i)\\s*note:.*$",
            ]

            let codeLanguages = ["python", "swift", "javascript", "typescript", "bash", "shell", "ruby", "java", "go", "rust", "cpp", "c\\+\\+", "html", "css", "sql"]
            let langPattern = "(?i)^\\s*(" + codeLanguages.joined(separator: "|") + ")\\s*\\n"

            preambleRegexes = preamblePatterns.compactMap { try? NSRegularExpression(pattern: $0) }
            trailingRegexes = trailingPatterns.compactMap { try? NSRegularExpression(pattern: $0) }
            codeLanguageRegex = try? NSRegularExpression(pattern: langPattern)
        }
    }

    /// Strip LLM artifacts: special tokens, meta-commentary, labels, etc.
    /// Uses pre-compiled regex patterns for performance.
    private static func sanitizeOutput(_ text: String) -> String {
        var cleaned = text
        let regexes = sanitizationRegexes

        // Remove special tokens
        for token in regexes.specialTokens {
            cleaned = cleaned.replacingOccurrences(of: token, with: "")
        }

        // Remove common LLM preambles/labels
        for regex in regexes.preambleRegexes {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }

        // Remove trailing meta-commentary
        for regex in regexes.trailingRegexes {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }

        // Remove markdown code fences if the LLM wrapped its output
        if cleaned.contains("```") {
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        }

        // Remove leading code language identifiers
        if let regex = regexes.codeLanguageRegex {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }

        // Strip lines that are just code comments if output looks like generated code
        let lines = cleaned.components(separatedBy: "\n")
        let commentLines = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        if commentLines.count > lines.count / 2 && lines.count > 2 {
            // More than half the lines are comments — LLM generated code, not cleanup
            return ""
        }

        // Remove wrapping single backticks
        cleaned = cleaned.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if cleaned.hasPrefix("`") && cleaned.hasSuffix("`") && cleaned.count > 2 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }

        // Remove quotes if the LLM quoted the entire output
        cleaned = cleaned.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count > 2 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }

        // Collapse newlines into spaces, EXCEPT when the LLM produced an intentional
        // list (2+ lines starting with numbered/bulleted markers like "1.", "-", "*").
        let splitLines = cleaned.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let listLineCount = splitLines.filter { line in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            return listMarkerRegex.firstMatch(in: line, range: range) != nil
        }.count

        if listLineCount >= 2 {
            // Preserve newlines — this is an intentional list from the LLM
            cleaned = splitLines.joined(separator: "\n")
        } else {
            // Collapse newlines — prose that the LLM split unnecessarily
            cleaned = splitLines.joined(separator: " ")
        }

        return cleaned.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}
