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

    /// Prompt cache: reuses KV state from the static prefix (system prompt + examples)
    /// across inference calls. Only the dynamic suffix (raw transcript) needs new prefill.
    /// Invalidated when app context, settings, or model changes.
    private var promptCache: [any KVCache]?
    private var promptCachePrefixTokenCount: Int = 0
    private var promptCachePrefixKey: String?

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

        // ~/Library/Application Support/YapYap/models/llm/
        // Application Support is never iCloud-synced, so large model weights are
        // never evicted. Without an explicit downloadBase, HubApi defaults to
        // ~/Documents/huggingface which iCloud can evict, causing stat() hangs.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let llmCacheURL = appSupport.appendingPathComponent("YapYap/models/llm")
        try? FileManager.default.createDirectory(at: llmCacheURL, withIntermediateDirectories: true)

        // HubApi with downloadBase stores models at {downloadBase}/models/{huggingFaceId}.
        // Only check the new App Support location — the legacy ~/Documents path may be
        // iCloud-evicted, where fileExists() returns true but contents cause stat() hangs.
        let localModelDir = llmCacheURL.appendingPathComponent("models/\(modelInfo.huggingFaceId)")
        let isLocallyAvailable = FileManager.default.fileExists(atPath: localModelDir.path)
        let hub = HubApi(downloadBase: llmCacheURL, useOfflineMode: isLocallyAvailable ? true : nil)
        NSLog("[MLXEngine] Model locally available: \(isLocallyAvailable) → \(isLocallyAvailable ? "offline mode (no HF network call)" : "online mode (will download)")")

        lmContext = try await factory.load(
            hub: hub,
            configuration: config
        ) { progress in
            progressHandler(progress.fractionCompleted)
        }

        self.modelId = id

        // Clear any stale prompt cache from a previously loaded model.
        // The old cache's KV arrays have wrong dimensions for the new model.
        promptCache = nil
        promptCachePrefixTokenCount = 0
        promptCachePrefixKey = nil

        // Set GPU cache limit to prevent Metal from freeing compute buffers between
        // inference calls. Without this, MLX deallocates Metal buffers after each
        // generate() and must reallocate them on the next call, adding latency.
        // 1GB is generous enough to hold model activations + KV cache for 1-3B models.
        let cacheBytes = 1024 * 1024 * 1024  // 1GB
        GPU.set(cacheLimit: cacheBytes)
        NSLog("[MLXEngine] GPU cache limit set to \(cacheBytes / 1024 / 1024)MB")

        NSLog("[MLXEngine] Model '\(id)' loaded successfully")
        await MainActor.run { DataManager.shared.markModelDownloaded(id) }
    }

    func unloadModel() {
        promptCache = nil
        promptCachePrefixTokenCount = 0
        promptCachePrefixKey = nil
        lmContext = nil
        modelId = nil
    }

    func warmup() async {
        guard let lmContext = lmContext else { return }
        do {
            // Use a realistic prompt size (~250 tokens) to force all model weights
            // into memory. A tiny "Hello" only touches a small subset of weights,
            // leaving the rest to be paged from disk on the first real inference.
            // Use Gemma format for warmup since Gemma 3 4B is the default model.
            // Gemma merges system content into the user block (no system role).
            let warmupPrompt = """
            <start_of_turn>user
            You are a text refinement tool. REPEAT the input text but fix grammar. \
            You are NOT an assistant. DO NOT answer questions.

            Clean this: um hello this is a warmup prompt to keep the model weights in memory<end_of_turn>
            <start_of_turn>model
            """
            let tokens = lmContext.tokenizer.encode(text: warmupPrompt)
            let input = LMInput(tokens: MLXArray(tokens))
            let parameters = GenerateParameters(maxTokens: 1)
            let cache = lmContext.model.newCache(parameters: nil)
            let startTime = Date()
            let stream: AsyncStream<Generation> = try generate(
                input: input,
                cache: cache,
                parameters: parameters,
                context: lmContext
            )
            for await _ in stream { break }
            let elapsed = Date().timeIntervalSince(startTime) * 1000
            NSLog("[MLXEngine] Keep-alive warmup complete (\(String(format: "%.0f", elapsed))ms, \(tokens.count) tokens)")
        } catch {
            NSLog("[MLXEngine] Keep-alive warmup failed: \(error)")
        }
    }

    func cleanup(rawText: String, context: CleanupContext) async throws -> String {
        guard let lmContext = lmContext else {
            throw YapYapError.modelNotLoaded
        }

        // Build prompt in parts: (system, userPrefix, userSuffix)
        // userPrefix = examples + instructions (static), userSuffix = rawText (dynamic)
        let parts = CleanupPromptBuilder.buildMessageParts(
            rawText: rawText, context: context,
            modelId: modelId
        )

        // Debug: log prompt content for echo bug diagnosis
        NSLog("[MLXEngine] System prompt (\(parts.system.count) chars): \"\(String(parts.system.prefix(200)))\"")
        NSLog("[MLXEngine] User prefix (\(parts.userPrefix.count) chars), suffix (\(parts.userSuffix.count) chars)")

        // Use model-family-specific inference parameters
        let modelInfo = modelId.flatMap { LLMModelRegistry.model(for: $0) }
        let family = modelInfo?.family ?? .qwen

        // Format prefix and suffix using model-specific chat template.
        // We use manual templates (same as the existing fallback path) because
        // applyChatTemplate returns a flat token array that can't be split for caching.
        let (templatePrefix, templateSuffix) = formatForTemplate(
            system: parts.system,
            userPrefix: parts.userPrefix,
            userSuffix: parts.userSuffix,
            family: family
        )

        // Encode prefix and suffix tokens separately.
        // The split is always at a newline boundary, so BPE produces identical
        // tokens regardless of whether prefix and suffix are encoded together or apart.
        // We validate this: if separate encoding differs from joint, fall back to joint.
        let prefixTokens = lmContext.tokenizer.encode(text: templatePrefix)
        let suffixTokens = lmContext.tokenizer.encode(text: templateSuffix)
        let jointTokens = lmContext.tokenizer.encode(text: templatePrefix + templateSuffix)
        let splitValid = (prefixTokens + suffixTokens == jointTokens)

        // Prompt caching: reuse KV state from the static prefix if it hasn't changed.
        // On cache hit, trim the saved cache to the prefix length and only prefill
        // the suffix (rawText). This skips ~1000 tokens of prefill for medium models.
        let cache: [any KVCache]
        let inputTokens: [Int]
        let totalTokenCount = jointTokens.count

        if !splitValid {
            // BPE boundary mismatch: separate encoding differs from joint.
            // This means a BPE merge spans the split point. Disable caching for safety.
            cache = lmContext.model.newCache(parameters: nil)
            inputTokens = jointTokens
            promptCache = nil
            NSLog("[MLXEngine] BPE boundary mismatch (split: %d, joint: %d) — caching disabled, full prefill %d tokens",
                  prefixTokens.count + suffixTokens.count, jointTokens.count, totalTokenCount)
        } else if let existingCache = promptCache,
                  promptCachePrefixKey == templatePrefix,
                  promptCachePrefixTokenCount == prefixTokens.count {
            // Cache hit: trim back to prefix length, feed only suffix tokens.
            // trim(_:) REMOVES n tokens from the cache (decrements offset by n).
            // We remove everything past the prefix: offset - prefixTokenCount tokens.
            var trimmed = true
            for c in existingCache {
                if c.isTrimmable {
                    let tokensToRemove = c.offset - promptCachePrefixTokenCount
                    if tokensToRemove > 0 {
                        c.trim(tokensToRemove)
                    }
                } else {
                    trimmed = false
                    break
                }
            }
            if trimmed {
                cache = existingCache
                inputTokens = suffixTokens
                NSLog("[MLXEngine] Prompt cache HIT — skipping %d prefix tokens, prefilling %d suffix tokens", prefixTokens.count, suffixTokens.count)
            } else {
                // Cache not trimmable, fall back to full prefill
                cache = lmContext.model.newCache(parameters: nil)
                inputTokens = jointTokens
                NSLog("[MLXEngine] Prompt cache not trimmable — full prefill %d tokens", totalTokenCount)
            }
        } else {
            // Cache miss: new prefix, full prefill
            cache = lmContext.model.newCache(parameters: nil)
            inputTokens = prefixTokens + suffixTokens
            NSLog("[MLXEngine] Prompt cache MISS — full prefill %d tokens (prefix: %d, suffix: %d)", totalTokenCount, prefixTokens.count, suffixTokens.count)
        }

        let input = LMInput(tokens: MLXArray(inputTokens))

        // Cap output tokens: cleanup output ≈ input length
        let userTokenCount = lmContext.tokenizer.encode(text: rawText).count
        let maxOutputTokens = max(32, min(userTokenCount * 2, 512))

        NSLog("[MLXEngine] Prompt: \(totalTokenCount) tokens, user: \(userTokenCount) tokens, maxOutput: \(maxOutputTokens), family: \(family.rawValue)")

        let parameters = GenerateParameters(
            maxTokens: maxOutputTokens,
            temperature: family.temperature,
            topP: family.topP,
            repetitionPenalty: family.repetitionPenalty,
            repetitionContextSize: family.repetitionContextSize
        )

        let startTime = Date()
        var firstTokenTime: Date?

        // Stop tokens that signal end of model response — truncate output here.
        // Gemma uses <end_of_turn>, others use <|im_end|>, <|eot_id|>, etc.
        let stopSequences = ["<end_of_turn>", "<|im_end|>", "<|eot_id|>", "<|end|>", "</s>", "</output>"]

        var outputText = ""
        var stopped = false
        let stream: AsyncStream<Generation> = try generate(
            input: input,
            cache: cache,
            parameters: parameters,
            context: lmContext
        )

        for await generation in stream {
            guard !stopped else { break }
            switch generation {
            case .chunk(let text):
                if firstTokenTime == nil {
                    firstTokenTime = Date()
                    let prefillMs = firstTokenTime!.timeIntervalSince(startTime) * 1000
                    NSLog("[MLXEngine] Prefill: \(String(format: "%.0f", prefillMs))ms (\(inputTokens.count) tokens, \(totalTokenCount) total)")
                }
                outputText += text
                for stop in stopSequences {
                    if let range = outputText.range(of: stop) {
                        outputText = String(outputText[..<range.lowerBound])
                        stopped = true
                        break
                    }
                }
            case .info(let info):
                let elapsed = Date().timeIntervalSince(startTime)
                let genMs = firstTokenTime.map { Date().timeIntervalSince($0) * 1000 } ?? 0
                NSLog("[MLXEngine] Generation: \(info.generationTokenCount) tokens in \(String(format: "%.0f", genMs))ms (\(String(format: "%.0f", info.tokensPerSecond)) tok/s), total \(String(format: "%.1f", elapsed))s")
            default:
                break
            }
        }

        // Save cache for next call. The cache now contains KV state for
        // prefix + suffix + generated tokens. On next call, we'll trim it
        // back to just the prefix if the prefix hasn't changed.
        // Only save when BPE split is valid — otherwise the cache can never be reused.
        if splitValid {
            promptCache = cache
            promptCachePrefixTokenCount = prefixTokens.count
            promptCachePrefixKey = templatePrefix
        }

        let result = Self.sanitizeOutput(outputText)
        NSLog("[MLXEngine] Cleanup result (\(result.count) chars): \"\(String(result.prefix(80)))...\"")
        return result
    }

    // MARK: - Template Formatting

    /// Formats system + user message parts into model-specific chat template strings.
    /// Returns (prefix, suffix) where the split is between the static prompt and the
    /// dynamic rawText portion. Uses the same templates as the existing fallback path.
    private func formatForTemplate(system: String, userPrefix: String, userSuffix: String, family: LLMModelFamily) -> (prefix: String, suffix: String) {
        switch family {
        case .llama:
            let systemBlock = system.isEmpty ? "" : "<|start_header_id|>system<|end_header_id|>\n\n\(system)<|eot_id|>"
            let prefix = "<|begin_of_text|>\(systemBlock)<|start_header_id|>user<|end_header_id|>\n\n\(userPrefix)"
            let suffix = "\(userSuffix)<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
            return (prefix, suffix)
        case .gemma:
            // Gemma: system already merged into userPrefix by CleanupPromptBuilder
            let prefix = "<start_of_turn>user\n\(userPrefix)"
            let suffix = "\(userSuffix)<end_of_turn>\n<start_of_turn>model\n"
            return (prefix, suffix)
        case .qwen:
            let systemBlock = system.isEmpty ? "" : "<|im_start|>system\n\(system)<|im_end|>\n"
            let prefix = "\(systemBlock)<|im_start|>user\n\(userPrefix)"
            let suffix = "\(userSuffix)<|im_end|>\n<|im_start|>assistant\n"
            return (prefix, suffix)
        }
    }

    // MARK: - Pre-compiled Sanitization Regexes

    /// Pre-compiled regex patterns for output sanitization.
    /// Compiled once at class load time, reused across all calls.
    private struct SanitizationRegexes {
        let specialTokens = [
            "<|endoftext|>", "<|im_end|>", "<|im_start|>",
            "<|eot_id|>", "<|end|>", "</s>", "<s>",
            "<|assistant|>", "<|user|>", "<|system|>",
            "</output>", "<output>", "<input>", "</input>"
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
                // Echo patterns: model emits few-shot example structure instead of cleaned text
                "(?i)^\\s*EXAMPLE\\s+\\d+\\s*:?\\s*",
                "(?i)^\\s*Input\\s*:\\s*",
                "(?i)^\\s*<example>\\s*",
                "(?i)^\\s*in\\s*:\\s*",
                "(?i)^\\s*out\\s*:\\s*",
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
