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

    /// Caches encoded prefix tokens to avoid re-encoding the static prefix each call.
    private var prefixTokenCache: (prefix: String, tokens: [Int])?
    /// Joint-encoded prefix slice stored for cache hit validation on the next call.
    private var promptCacheJointPrefixSlice: [Int]?


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

        // Clear any stale caches from a previously loaded model.
        // The old cache's KV arrays have wrong dimensions for the new model.
        promptCache = nil
        promptCachePrefixTokenCount = 0
        promptCachePrefixKey = nil
        prefixTokenCache = nil
        promptCacheJointPrefixSlice = nil

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
        prefixTokenCache = nil
        promptCacheJointPrefixSlice = nil
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

        let userContext = UserPromptContextManager.shared.context(
            for: context.appContext?.appName,
            transcript: rawText
        )

        // Use model-family-specific inference parameters
        let modelInfo = modelId.flatMap { LLMModelRegistry.model(for: $0) }
        let family = modelInfo?.family ?? .qwen

        let templatePrefix: String
        let templateSuffix: String

        if context.useV2Prompts {
            // V2: multi-turn chat-style messages
            let parts = CleanupPromptBuilderV2.buildMessageParts(
                rawText: rawText, context: context, userContext: userContext
            )
            (templatePrefix, templateSuffix) = formatMultiTurnTemplate(
                prefixMessages: parts.prefix,
                suffixMessage: parts.suffix,
                family: family
            )
            NSLog("[MLXEngine] V2 prompt: %d prefix messages, suffix: \"%@\"",
                  parts.prefix.count, String(parts.suffix.content.prefix(80)))
        } else {
            // V1: classic system + user message
            let parts = CleanupPromptBuilder.buildMessageParts(
                rawText: rawText, context: context,
                modelId: modelId, userContext: userContext
            )
            (templatePrefix, templateSuffix) = formatForTemplate(
                system: parts.system,
                userPrefix: parts.userPrefix,
                userSuffix: parts.userSuffix,
                family: family
            )
            NSLog("[MLXEngine] V1 prompt: system (%d chars), user prefix (%d chars), suffix (%d chars)",
                  parts.system.count, parts.userPrefix.count, parts.userSuffix.count)
        }

        // Encode prefix alone (cached) to know the split point, then tokenize
        // prefix+suffix JOINTLY so BPE merges at the boundary are always captured.
        // This eliminates the "BPE boundary mismatch" cache miss entirely.
        let prefixTokens: [Int]
        if let cached = prefixTokenCache, cached.prefix == templatePrefix {
            prefixTokens = cached.tokens
        } else {
            prefixTokens = lmContext.tokenizer.encode(text: templatePrefix)
            prefixTokenCache = (templatePrefix, prefixTokens)
        }

        let jointTokens = lmContext.tokenizer.encode(text: templatePrefix + templateSuffix)
        let splitPoint = min(prefixTokens.count, jointTokens.count)
        let jointPrefixSlice = Array(jointTokens[0..<splitPoint])
        let totalTokenCount = jointTokens.count

        NSLog("[MLXEngine] Joint encode: %d tokens (prefix: %d, suffix: %d) — prompt %.0f chars",
              jointTokens.count, splitPoint, jointTokens.count - splitPoint,
              Double(templatePrefix.count + templateSuffix.count))

        let cache: [any KVCache]
        let inputTokens: [Int]

        if let existingCache = promptCache,
           promptCachePrefixKey == templatePrefix,
           promptCachePrefixTokenCount == splitPoint,
           jointPrefixSlice == (promptCacheJointPrefixSlice ?? []) {
            // Cache hit — trim to prefix, prefill only suffix
            var trimmed = true
            for c in existingCache {
                if c.isTrimmable {
                    let tokensToRemove = c.offset - splitPoint
                    if tokensToRemove > 0 { c.trim(tokensToRemove) }
                } else { trimmed = false; break }
            }
            if trimmed {
                cache = existingCache
                inputTokens = Array(jointTokens[splitPoint...])
                NSLog("[MLXEngine] Prompt cache HIT — skipping %d prefix tokens, prefilling %d suffix tokens",
                      splitPoint, inputTokens.count)
            } else {
                cache = lmContext.model.newCache(parameters: nil)
                inputTokens = jointTokens
                NSLog("[MLXEngine] Prompt cache not trimmable — full prefill %d tokens", totalTokenCount)
            }
        } else {
            // Cache miss
            cache = lmContext.model.newCache(parameters: nil)
            inputTokens = jointTokens
            NSLog("[MLXEngine] Prompt cache MISS — full prefill %d tokens (prefix: %d)", totalTokenCount, splitPoint)
        }

        let input = LMInput(tokens: MLXArray(inputTokens))

        NSLog("[MLXEngine] Prompt: \(totalTokenCount) tokens, suffix: \(jointTokens.count - splitPoint) tokens, family: \(family.rawValue)")

        let parameters = GenerateParameters(
            maxTokens: nil,
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
        // Max stop-sequence length for O(1) tail scanning instead of O(n) full-string search
        let maxStopLen = stopSequences.map(\.count).max() ?? 0

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
                    let prefillTokPerSec = prefillMs > 0 ? Double(inputTokens.count) / (prefillMs / 1000) : 0
                    let prefillWarning = prefillTokPerSec < 50 ? " ⚠️ SLOW PREFILL" : ""
                    NSLog("[MLXEngine] Prefill: %.0fms (%d tokens, %.0f tok/s)%@",
                          prefillMs, inputTokens.count, prefillTokPerSec, prefillWarning)
                }
                outputText += text
                // Only scan the tail of outputText for stop sequences (O(1) per token)
                let tailStart = outputText.index(outputText.endIndex, offsetBy: -(maxStopLen + text.count), limitedBy: outputText.startIndex) ?? outputText.startIndex
                let tail = String(outputText[tailStart...])
                for stop in stopSequences {
                    if let range = tail.range(of: stop) {
                        // Convert tail range back to outputText range
                        let offset = outputText.distance(from: outputText.startIndex, to: tailStart)
                        let fullStart = outputText.index(outputText.startIndex, offsetBy: offset + tail.distance(from: tail.startIndex, to: range.lowerBound))
                        outputText = String(outputText[..<fullStart])
                        stopped = true
                        break
                    }
                }
            case .info(let info):
                let elapsed = Date().timeIntervalSince(startTime)
                let genMs = firstTokenTime.map { Date().timeIntervalSince($0) * 1000 } ?? 0
                let genTokPerSec = info.tokensPerSecond
                let memWarning = genTokPerSec < 5 ? " ⚠️ MEMORY PRESSURE — model likely swapped to disk" :
                                 genTokPerSec < 20 ? " ⚠️ SLOW — possible memory pressure" : ""
                NSLog("[MLXEngine] Generation: %d tokens in %.0fms (%.0f tok/s), total %.1fs%@",
                      info.generationTokenCount, genMs, genTokPerSec, elapsed, memWarning)
            default:
                break
            }
        }

        // Save cache for next call. The cache now contains KV state for
        // prefix + suffix + generated tokens. On next call, we'll trim it
        // back to just the prefix if the prefix hasn't changed.
        // Always save — BPE boundary no longer causes invalid cache state.
        promptCache = cache
        promptCachePrefixTokenCount = splitPoint
        promptCachePrefixKey = templatePrefix
        promptCacheJointPrefixSlice = jointPrefixSlice

        let result = LLMOutputSanitizer.sanitize(outputText)
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

    // MARK: - V2 Multi-Turn Template Formatting

    /// Formats multi-turn ChatMessages into model-specific template strings.
    /// Returns (prefix, suffix) where prefix contains all cacheable messages
    /// and suffix contains only the final user message + assistant response header.
    private func formatMultiTurnTemplate(
        prefixMessages: [ChatMessage],
        suffixMessage: ChatMessage,
        family: LLMModelFamily
    ) -> (prefix: String, suffix: String) {
        switch family {
        case .llama:
            return formatLlamaMultiTurn(prefixMessages: prefixMessages, suffixMessage: suffixMessage)
        case .qwen:
            return formatQwenMultiTurn(prefixMessages: prefixMessages, suffixMessage: suffixMessage)
        case .gemma:
            return formatGemmaMultiTurn(prefixMessages: prefixMessages, suffixMessage: suffixMessage)
        }
    }

    private func formatLlamaMultiTurn(prefixMessages: [ChatMessage], suffixMessage: ChatMessage) -> (prefix: String, suffix: String) {
        var prefix = "<|begin_of_text|>"
        for msg in prefixMessages {
            prefix += "<|start_header_id|>\(msg.role.rawValue)<|end_header_id|>\n\n\(msg.content)<|eot_id|>"
        }
        let suffix = "<|start_header_id|>user<|end_header_id|>\n\n\(suffixMessage.content)<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
        return (prefix, suffix)
    }

    private func formatQwenMultiTurn(prefixMessages: [ChatMessage], suffixMessage: ChatMessage) -> (prefix: String, suffix: String) {
        var prefix = ""
        for msg in prefixMessages {
            prefix += "<|im_start|>\(msg.role.rawValue)\n\(msg.content)<|im_end|>\n"
        }
        let suffix = "<|im_start|>user\n\(suffixMessage.content)<|im_end|>\n<|im_start|>assistant\n"
        return (prefix, suffix)
    }

    private func formatGemmaMultiTurn(prefixMessages: [ChatMessage], suffixMessage: ChatMessage) -> (prefix: String, suffix: String) {
        // Gemma doesn't support system role — merge system content into the first user turn.
        var prefix = ""
        var systemContent = ""
        var isFirstUser = true

        for msg in prefixMessages {
            switch msg.role {
            case .system:
                if systemContent.isEmpty {
                    systemContent = msg.content
                } else {
                    systemContent += "\n\n" + msg.content
                }
            case .user:
                if isFirstUser && !systemContent.isEmpty {
                    prefix += "<start_of_turn>user\n\(systemContent)\n\n\(msg.content)<end_of_turn>\n"
                    isFirstUser = false
                } else {
                    prefix += "<start_of_turn>user\n\(msg.content)<end_of_turn>\n"
                }
            case .assistant:
                prefix += "<start_of_turn>model\n\(msg.content)<end_of_turn>\n"
            }
        }

        // Suffix: final user message + model response header
        let userContent: String
        if isFirstUser && !systemContent.isEmpty {
            userContent = systemContent + "\n\n" + suffixMessage.content
        } else {
            userContent = suffixMessage.content
        }
        let suffix = "<start_of_turn>user\n\(userContent)<end_of_turn>\n<start_of_turn>model\n"
        return (prefix, suffix)
    }

}
